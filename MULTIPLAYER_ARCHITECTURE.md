# Multiplayer Blackjack Architecture (Cloud Functions)

This document describes the multiplayer blackjack design with **Firebase Cloud Functions as the game authority**. Functions read and write directly to the Realtime Database. **Multiple tables** are supported; each table has a **4-digit invite code** that is appended to the table path. Players join by code; table **settings** (bonus bets, decks per shoe, deck penetration, etc.) have defaults and can be changed per table.

---

## 1. Multiple tables and invite codes

- There are **multiple tables**. Each table is identified by a **4-digit invite code** (e.g. `"2847"`).
- The **table path** is **`mp_blackjack/table/{code}`** — the code is appended to the path. All data for that table (seats, settings, game) lives under this path.
- The **invite code is generated when the table is created** (see **Table creation** below). It must be unique.
- **Players join with the code**: they enter the 4 digits (or open a link with the code), and the client uses the path `mp_blackjack/table/{code}` to join, observe, and call callables for that table.
- All callables take a **`tableCode`** (or `code`) argument so the function knows which table to read and write.

**Example:** Code `2847` → path `mp_blackjack/table/2847` → seats at `mp_blackjack/table/2847/seats`, game at `mp_blackjack/table/2847/game`, settings at `mp_blackjack/table/2847/settings`.

---

## 2. Who owns what

| Layer | Writes game state | Writes table (seats, balances, settings) |
|-------|--------------------|------------------------------------------|
| **Cloud Functions** | ✅ Yes — phase, deck, hands, dealer, currentTurn (per table) | ✅ Yes — balance updates, ready flags; create table + settings |
| **Clients** | ❌ No | ✅ Limited — join seat (with path from code), set displayName, set **ready**, place **bet**; create table (callable returns code) |

**Cloud Functions directly read and write both**, **per table** (using `tableCode`):

- **`mp_blackjack/table/{code}`** — seats, **settings**, and (under a child) game. Functions write: balance updates (payouts), ready when advancing, and when creating the table (seats + settings).
- **`mp_blackjack/table/{code}/game`** — phase, **deckSeed**, deckIndex, dealerCards, currentTurn, handNumber, **phaseResumeAt**. The deck is **not** stored; it is derived deterministically from `deckSeed` + `settings.deckCount`. Functions are the **only** writer of `game` during play.

Clients never write to `game`. They call **callables** with **tableCode** (setReady, placeBet, playerAction, startDeal, startGame, startNextHand) and observe `table/{code}` and `table/{code}/game`.

---

## 3. Firebase paths (data model)

All paths below are **under** `mp_blackjack/table/{code}` where `{code}` is the 4-digit invite code.

### Table (seats + metadata) — `mp_blackjack/table/{code}`

Persistent table and seating. Clients write: join, leave, displayName (using the path derived from the code). Functions write: balance (on payout), ready (when advancing).

```text
mp_blackjack/table/{code}/
  inviteCode: string        // "2847" — same as {code}, stored for convenience
  createdAt: number         // server timestamp
  seats/
    0/
      playerId: string | null
      displayName: string
      balance: number
      chipColorName: string
      ready: boolean
      hands: [ { bet: number, cards: [ { rank: string, suit: string }, ... ], stood: boolean, doubled: boolean, busted: boolean, playerId: string }, ... ]
    1/ ...
  settings/                 // see Table settings below
```

### Table settings — `mp_blackjack/table/{code}/settings`

**Defaults** are applied when the table is created; they can be **changed** (e.g. by host or before the first hand). Used by Cloud Functions for deck creation and bonus bet availability.

```text
mp_blackjack/table/{code}/settings/
  bonusBetsEnabled: boolean    // default true
  deckCount: number            // decks per shoe; default 1 (e.g. 1, 2, 4, 6)
  deckPenetration: number      // 0–1 or -1 for random; default e.g. 0.75
  // optional: cutCardPosition, specific bonus toggles, etc.
```

- **bonusBetsEnabled**: Whether side bets (e.g. perfect pair, 21+3) are offered.
- **deckCount**: Number of 52-card decks in the shoe (1, 2, 4, or 6). Function builds a deck of `52 * deckCount` cards when starting a hand.
- **deckPenetration**: Fraction of the shoe before reshuffle (e.g. 0.75 = 75%), or -1 for “random” penetration. Function places cut card (or equivalent) when creating the deck.

Only the **table creator** (or a dedicated **updateTableSettings** callable with permission check) should write `settings`; all callables **read** `settings` when they need it (e.g. startDeal reads `deckCount` and `deckPenetration`).

### Game — `mp_blackjack/table/{code}/game`

Ephemeral per-hand state for **this table**. Only Cloud Functions write here during a hand.

```text
mp_blackjack/table/{code}/game/
  phase: "waiting_for_ready" | "betting" | "dealing" | "player_actions" | "dealer_turn" | "resolving" | "game_over" | "between_hands"
  phaseResumeAt: number
  handNumber: number
  deckSeed: number
  deckIndex: number
  // deck is NOT stored; same seed + settings.deckCount => same order via createShuffledDeck(seed, deckCount)
  dealerCards: [ ... ]
  dealerHoleRevealed: boolean
  currentTurn: { seatIndex: number, handIndex: number } | null
```

**Note:** Player hands (with cards) are now stored in `seats/{seatIndex}/hands`, not in `game/playerHands`. This eliminates duplication and simplifies the data model.

- **phaseResumeAt**: When `phase === "between_hands"` and server time ≥ `phaseResumeAt`, the scheduler (or startNextHand) advances to `betting`.
- **ready**: Under `table/{code}/seats/i/ready`. Function reads “all seated players ready?” to move from `waiting_for_ready` to `betting`.

### Table creation and code generation

- **Creating a table:** A client calls a callable **createTable(options?)**. Options can include initial settings overrides (e.g. `{ deckCount: 2, bonusBetsEnabled: false }`).
- **Code generation** happens in the Cloud Function:
  1. Generate a random 4-digit code (e.g. `1000 + Math.floor(Math.random() * 9000)`), or use a pool and mark as used.
  2. Check that **`mp_blackjack/table/{code}`** does not exist (or that the code is not in use). If it exists, retry with a new code (with a limit).
  3. Create the table: write `mp_blackjack/table/{code}` with `inviteCode`, `createdAt`, `seats` (empty or default empty seats), and **settings** (merge defaults with options). Optionally set `game.phase = "waiting_for_ready"`.
  4. Return **{ tableCode: "2847" }** (or the chosen code) to the client so they can show “Invite code: 2847” and navigate to that table.
- **Defaults** for settings (used if not overridden): e.g. `bonusBetsEnabled: true`, `deckCount: 1`, `deckPenetration: 0.75`.

---

## 4. Game loop (state machine)

The “game loop” is a **state machine** driven by Cloud Functions. Each transition is triggered by a callable or a scheduled check; there is no long-running loop.

```
waiting_for_ready
    │  (all players ready → callable or trigger advances)
    ▼
betting
    │  (deal requested / timer → startHand callable)
    ▼
dealing
    │  (function creates deck, deals, sets currentTurn)
    ▼
player_actions
    │  (playerAction callable: hit / stand / double; function advances turn or phase)
    ▼
dealer_turn
    │  (runDealer callable or trigger runs dealer to completion)
    ▼
resolving
    │  (function pays out each seat individually, then sets phase)
    ▼
game_over
    │  (show results)
    ▼
between_hands
    │  (host taps "Next hand" → startNextHand advances to betting)
    ▼
betting  (next hand)
```

### How fast the game advances (pacing)

- **When the game starts (ready-up)**  
  - Phase: `waiting_for_ready`.  
  - Each player taps “Ready” → client calls **setReady({ tableCode, seatIndex })**. Function sets `table/{tableCode}/seats/{seatIndex}/ready = true`.  
  - When to advance: **startGame({ tableCode })** (or a trigger). Function checks all seated players at that table have `ready === true`, then sets `table/{tableCode}/game.phase = "betting"` and clears `ready`.  
  - Speed: as soon as all have readied and someone taps Start.

- **Between hands (host-controlled)**  
  - When leaving `resolving`, the function sets `table/{tableCode}/game.phase = "between_hands"`.  
  - **Host** = first player at the table (lowest seat index that is occupied). Only the host can advance to the next hand.  
  - **Advancement:** The host taps “Next hand” (or similar). Client calls **startNextHand({ tableCode, playerId })**. Function verifies that `playerId` belongs to the host seat; if so, sets `phase = "betting"` and clears `ready`. No scheduled function; the host controls when betting starts again.

- **Betting and dealing**  
  - Betting phase has no automatic timer in this design; players place bets and someone (or a “Deal” button) calls **startDeal()** when ready. So “how fast” is player-driven. You could add a “deal in 30s” by setting `phaseResumeAt` and having the same scheduled function advance to `dealing` and call the deal logic.

- **Player actions / dealer**  
  - Advance as soon as the callable returns (no artificial delay). You can add optional delays only in the client (e.g. animate dealer card every 0.5s by having the function write one card at a time and client animating on each update).

---

## 5. Deck creation (in a Cloud Function)

Deck creation happens **inside a Cloud Function** when a hand starts, in **startDeal({ tableCode })**. The function uses **table settings** for deck size and penetration.

1. Read **`table/{tableCode}/settings`**: `deckCount` (e.g. 1, 2, 4, 6), `deckPenetration` (e.g. 0.75 or -1 for random).
2. Generate a random **seed**.
3. Build an ordered deck of **52 × deckCount** cards (same ranks/suits repeated).
4. Shuffle **deterministically** with that seed. Optionally insert a cut card based on **deckPenetration** (or mark penetration in state for later reshuffle).
5. Write to **`table/{tableCode}/game`**:
   - `deckSeed`, `deckIndex: 0`, `phase: "dealing"` (the full deck is **not** stored; it is derived from `deckSeed` + `settings.deckCount` whenever a card is needed).
   - Then deal initial cards: two to each active seat, two to dealer (one hidden), update hands in seats and `dealerCards`, set `phase = "player_actions"` and `currentTurn` to first active seat.

Only the function writes `deckSeed` and `deckIndex`. The deck order is deterministic: same seed + deckCount ⇒ same deck. Players “see” the deck via cards in `dealerCards` and in seat hands.

**Example (Node/TypeScript):**

```typescript
function createShuffledDeck(seed: number, deckCount: number): { rank: string; suit: string }[] {
  const suits = ["hearts", "clubs", "diamonds", "spades"];
  const ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
  const cards: { rank: string; suit: string }[] = [];
  for (let d = 0; d < deckCount; d++)
    for (const suit of suits) for (const rank of ranks) cards.push({ rank, suit });
  const rng = seededRandom(seed);
  for (let i = cards.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [cards[i], cards[j]] = [cards[j], cards[i]];
  }
  return cards;
}

// In startDeal({ tableCode }):
const settings = (await admin.database().ref(`mp_blackjack/table/${tableCode}/settings`).once("value")).val();
const deckCount = settings?.deckCount ?? 1;
const seed = Math.floor(Math.random() * 0x7FFFFFFF);
const deck = createShuffledDeck(seed, deckCount);
const gameRef = admin.database().ref(`mp_blackjack/table/${tableCode}/game`);
await gameRef.update({
  phase: "dealing",
  deckSeed: seed,
  deckIndex: 0,
});
// Deck is not stored; playerAction/runDealer derive it via createShuffledDeck(seed, settings.deckCount).
// Then deal initial cards and set phase to "player_actions".
```

---

## 6. How players take action (hit, stand, double)

All actions go through **callable** Cloud Functions and include **tableCode**. The function reads `table/{tableCode}/game` and `table/{tableCode}/seats` (and settings if needed), validates, updates **game** and **table** for that code, then returns. Clients observe `table/{tableCode}` and `table/{tableCode}/game` and update the UI.

- **setReady**  
  - Callable: `setReady({ tableCode, seatIndex })`.  
  - Function: ensure the seat belongs to the caller, then set `table/{tableCode}/seats/{seatIndex}/ready = true`. Optionally check “all ready” and advance phase (or rely on startGame).

- **placeBet**  
  - Callable: `placeBet({ tableCode, seatIndex, amount })`.  
  - Function: check `phase === "betting"`, seat has enough balance, then deduct from `table/{tableCode}/seats/{seatIndex}/balance` and set the bet in `table/{tableCode}/game.playerHands[seatIndex]`. Write **table** (balance) and **game** (bets/hands).

- **playerAction**  
  - Callable: `playerAction({ tableCode, seatIndex, handIndex, action })` with `action in ["hit","stand","double"]`.  
  - Function:  
    - Read `table/{tableCode}/game`. Check `phase === "player_actions"` and `currentTurn` matches.  
    - **Hit:** Derive deck from `createShuffledDeck(game.deckSeed, settings.deckCount)`, take `deck[game.deckIndex]`, append to the hand, increment `deckIndex`. If total > 21, set `busted: true` and advance turn.  
    - **Stand:** Set that hand’s `stood: true`, advance turn.  
    - **Double:** Deduct same bet from `table/{tableCode}/seats/{seatIndex}/balance`, double the hand’s bet, deal one card, set `doubled: true`, advance turn.  
  - If all players are done, set `phase = "dealer_turn"` and run dealer (same function or separate).  
  - All writes go to **table/{tableCode}/game** (and **table/{tableCode}/seats** for balance on double).

So: **Cloud Functions** take **tableCode** and **directly read/write** `table/{tableCode}` and `table/{tableCode}/game`.

---

## 7. Individual payouts (not whole table at once)

Payouts are computed **per seat** and written **per seat** so each player’s balance updates as soon as their result is written. The function still runs once per table; the “individual” part is **per-seat balance writes**.

**In the resolving function (e.g. runDealer + resolve) for a given `tableCode`:**

1. Compute dealer total and whether dealer busted.
2. For **each** seat that had a bet:
   - Compute win/loss for each of their hands (push/win/loss, blackjack pay 3:2, etc.).
   - New balance = current `table/{tableCode}/seats/{seatIndex}/balance` + total payout for that seat.
   - Write **only that seat’s balance**: `table/{tableCode}/seats/{seatIndex}/balance = newBalance`.
3. Set `table/{tableCode}/game.phase = "game_over"`, `handNumber += 1`.
4. Set `phase = "between_hands"` and `phaseResumeAt = now + 3000`.

Clients observe `table/{tableCode}/seats/{theirSeatIndex}/balance`. Each seat sees its own balance change when it’s written.

**Example (conceptual):**

```typescript
const tableRef = admin.database().ref(`mp_blackjack/table/${tableCode}`);
const gameRef = tableRef.child("game");
const game = (await gameRef.once("value")).val();
const dealerTotal = computeTotal(game.dealerCards);
const dealerBusted = dealerTotal > 21;

for (const seatIndex of Object.keys(game.playerHands || {})) {
  const hands = game.playerHands[seatIndex];
  let payout = 0;
  for (const hand of hands) payout += resolveHand(hand, dealerTotal, dealerBusted);
  const seatRef = tableRef.child("seats").child(seatIndex);
  const currentBalance = (await seatRef.once("value")).val()?.balance ?? 0;
  await seatRef.child("balance").set(currentBalance + payout);
}
await gameRef.update({ phase: "game_over" });
await gameRef.update({ phase: "between_hands", phaseResumeAt: Date.now() + 3000 });
```

---

## 8. Controlling how fast the game advances (summary)

| Moment | How it’s controlled |
|--------|---------------------|
| **Start: ready-up** | Players call **setReady**; when all ready, **startGame** (or trigger) sets phase to `betting`. Speed = when everyone readies + one Start. |
| **After each hand: 3s break** | Function sets `phase = "between_hands"` and `phaseResumeAt = now + 3000`. A **scheduled function** (every few seconds) checks `phaseResumeAt <= now` and sets `phase = "betting"`; or after 3s the **client** calls **startNextHand()** to advance. Speed = 3 seconds. |
| **Betting → dealing** | When “Deal” is pressed (callable **startDeal**). Optional: auto-deal after N seconds by setting `phaseResumeAt` and same scheduler advancing phase and calling deal logic. |
| **Player actions / dealer** | Advance as soon as callables return; no server-side delay. Optional client-side animation delays. |

So: **Cloud Functions** own phase transitions **per table** and write `table/{code}/game` and `table/{code}/seats`. **Pacing** is via **client callables**: startGame (when all ready), startDeal (when players want to deal), **startNextHand (host only**, to move from between_hands to betting).

---

## 9. Example: list of Cloud Functions

All callables take **tableCode** (except **createTable** and **advancePhase** scheduler). Paths are `mp_blackjack/table/{tableCode}/...`.

| Function | Trigger | What it does | Writes |
|----------|---------|--------------|--------|
| **createTable** | Callable | Generates unique 4-digit code, creates `table/{code}` + seats + **settings** (defaults + options), returns `{ tableCode }` | `table/{code}`, `table/{code}/settings` |
| **updateTableSettings** | Callable | Updates `table/{tableCode}/settings` (e.g. bonusBetsEnabled, deckCount, deckPenetration); permission check (e.g. creator/host only) | `table/{code}/settings` |
| **setReady** | Callable | Sets `table/{code}/seats/{i}/ready = true` | `table/{code}` |
| **startGame** | Callable | Requires all seated ready; sets `game.phase = "betting"`, clears ready | `table/{code}/game`, `table/{code}/seats` |
| **placeBet** | Callable | Deducts balance, sets bet in game (uses settings for bonus bets if enabled) | `table/{code}/seats`, `table/{code}/game` |
| **startDeal** | Callable | Reads **settings** (deckCount, deckPenetration); creates deck, deals, sets `player_actions` + `currentTurn` | `table/{code}/game` |
| **playerAction** | Callable | Hit/stand/double; updates hand, deckIndex, currentTurn; if all done → dealer_turn | `table/{code}/game`, `table/{code}/seats` (double) |
| **runDealer** | Callable | Dealer draws to 17+; resolve payouts per seat; set game_over → between_hands, phaseResumeAt | `table/{code}/game`, `table/{code}/seats` |
| **startNextHand** | Callable (**host only**) | Caller must be host (first seat). If `phase === "between_hands"`, set `phase = "betting"`, clear ready | `table/{code}/game`, `table/{code}/seats` |

---

## 10. Summary

- **Multiple tables:** Each table has a **4-digit invite code**; path is **`mp_blackjack/table/{code}`**. Code is **generated when the table is created** (callable **createTable**); players **join with the code** and use that path for all calls and observers.
- **Table settings:** Stored at **`table/{code}/settings`** with **defaults** (e.g. bonusBetsEnabled, deckCount, deckPenetration). Defaults are applied at creation; they can be **changed** via **updateTableSettings** (e.g. host only). **startDeal** and other logic read settings for deck size and bonus bets.
- **Game loop** is implemented with Cloud Functions: callables take **tableCode** and read/write **table/{code}** and **table/{code}/game**.
- **Deck creation** uses **settings.deckCount** and **settings.deckPenetration**; the function writes only **deckSeed** and **deckIndex** to **table/{code}/game**. The deck order is derived deterministically from seed + deckCount (no per-card storage).
- **Pacing:** Ready-up → startGame; between hands → **host** calls **startNextHand** when ready (no scheduled function).
- **Payouts** are per seat: function writes each seat’s balance under **table/{code}/seats/{i}/balance** individually.

Cloud Functions **directly manipulate and write** both the **table** (seats, settings) and the **game** (phase, deckSeed, deckIndex, dealerCards, currentTurn, etc.) **per table**, using the invite code in the path.
