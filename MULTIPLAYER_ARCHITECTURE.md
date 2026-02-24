# Multiplayer Blackjack Architecture (Cloud Functions)

This document describes the multiplayer blackjack design with **Firebase Cloud Functions as the game authority**. Functions read and write directly to the Realtime Database (`table` and `game`). Clients only send intentions (ready, bet, hit, stand, double) and observe state.

---

## 1. Who owns what

| Layer | Writes game state | Writes table (seats, balances) |
|-------|--------------------|-------------------------------|
| **Cloud Functions** | ✅ Yes — phase, deck, hands, dealer, currentTurn | ✅ Yes — balance updates, ready flags (when advancing) |
| **Clients** | ❌ No | ✅ Limited — join seat, set displayName, set **ready** (or via callable), place **bet** (via callable) |

**Yes: Cloud Functions directly read and write both:**

- **`mp_blackjack/table`** — seats (playerId, displayName, balance, chipColorName, hands, **ready**). Functions write here for: balance updates (payouts), and optionally clearing **ready** when a new hand starts.
- **`mp_blackjack/game`** — phase, deck, deckIndex, dealerCards, playerHands, currentTurn, handNumber, **phaseResumeAt** (for pacing). Functions are the **only** writer of `game` during play (deck, cards, phase transitions).

Clients never write to `game` (no deck, no phase, no hands). They call **callable** functions (setReady, placeBet, playerAction, maybe startDeal / startNextHand) and observe both paths.

---

## 2. Firebase paths (data model)

### Table — `mp_blackjack/table`

Persistent table and seating. Clients write: join, leave, displayName. Functions write: balance (on payout), ready (optional, or ready is client-written and function only reads it).

```text
mp_blackjack/table/
  seats/
    0/
      playerId: string | null
      displayName: string
      balance: number
      chipColorName: string
      ready: boolean        // true when player has tapped "Ready" for this round
      hands: [ { bet: number }, ... ]   // optional; can also live under game
    1/ ...
```

### Game — `mp_blackjack/game`

Ephemeral per-hand state. **Only Cloud Functions write here** during a hand (except possibly a single “request deal” or “start next hand” flag that a function consumes and clears).

```text
mp_blackjack/game/
  phase: "waiting_for_ready" | "betting" | "dealing" | "player_actions" | "dealer_turn" | "resolving" | "game_over" | "between_hands"
  phaseResumeAt: number     // Firebase server timestamp (ms) when phase can advance (e.g. end of 3s break)
  handNumber: number
  deckSeed: number
  deck: [ { rank: string, suit: string }, ... ]
  deckIndex: number
  dealerCards: [ { rank, suit }, ... ]
  dealerHoleRevealed: boolean
  playerHands: {
    "0": [ { cards: [...], bet: number, stood: boolean, doubled: boolean, busted: boolean }, ... ],
    "1": [ ... ],
    ...
  }
  currentTurn: { seatIndex: number, handIndex: number } | null
```

- **phaseResumeAt**: Used to control pacing. When `phase === "between_hands"` and server time ≥ `phaseResumeAt`, a function advances to `betting`. Optional for other phases (e.g. “deal in 3s”).
- **ready**: Can live under `table/seats/i/ready`. Function reads “all seated players ready?” to decide when to move from `waiting_for_ready` to `betting` (or you use a callable “startGame” that requires all ready and then advances).

---

## 3. Game loop (state machine)

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
    │  (show results; optional short delay in client)
    ▼
between_hands
    │  phaseResumeAt = now + 3000
    │  (scheduled function or callable after 3s advances to betting)
    ▼
betting  (next hand)
```

### How fast the game advances (pacing)

- **When the game starts (ready-up)**  
  - Phase: `waiting_for_ready`.  
  - Each player taps “Ready” → client calls **setReady()** (callable) which sets `table/seats/{seatIndex}/ready = true`.  
  - When to advance:  
    - **Option A:** A “Start game” button (host or any player) calls **startGame()**. Function checks that all seated players have `ready === true`, then sets `game.phase = "betting"` and clears `ready` for the next round.  
    - **Option B:** A DB trigger on `table/seats` that runs when any `ready` changes: if all seated players are ready, function sets phase to `betting` and clears ready.  
  - So “how fast” is: as soon as all have readied and (in Option A) someone taps Start.

- **3-second break between hands**  
  - When leaving `resolving`, the function sets `phase = "between_hands"` and `phaseResumeAt = Date.now() + 3000` (or Firebase server timestamp + 3s).  
  - **Advancement:**  
    - **Option A (scheduled function):** A function runs every 2–5 seconds (Cloud Scheduler), reads all tables (or only those in `between_hands`), and for each where `phaseResumeAt <= now` sets `phase = "betting"` and clears `ready` for the next round.  
    - **Option B (client):** After 3 seconds the client shows “Bet now” and calls **startNextHand()**. Function checks `phase === "between_hands"` and optionally that `phaseResumeAt` has passed, then sets `phase = "betting"`.  
  - So the “speed” is fixed: 3 seconds of break, then betting starts (either by scheduler or by client after 3s).

- **Betting and dealing**  
  - Betting phase has no automatic timer in this design; players place bets and someone (or a “Deal” button) calls **startDeal()** when ready. So “how fast” is player-driven. You could add a “deal in 30s” by setting `phaseResumeAt` and having the same scheduled function advance to `dealing` and call the deal logic.

- **Player actions / dealer**  
  - Advance as soon as the callable returns (no artificial delay). You can add optional delays only in the client (e.g. animate dealer card every 0.5s by having the function write one card at a time and client animating on each update).

---

## 4. Deck creation (in a Cloud Function)

Deck creation happens **inside a Cloud Function** when a hand starts (e.g. in **startDeal** or when transitioning to `dealing`).

1. Generate a random **seed** (e.g. `Math.floor(Math.random() * 0x7FFFFFFF)` or use a seed from Admin SDK).
2. Build an ordered 52-card array (e.g. ranks `["A","2",...,"K"]`, suits `["hearts","clubs","diamonds","spades"]`).
3. Shuffle **deterministically** with that seed (e.g. seeded PRNG; same seed ⇒ same order).
4. Write to **`mp_blackjack/game`**:
   - `deckSeed`
   - `deck`: shuffled array of `{ rank, suit }`
   - `deckIndex`: 0
   - `phase`: `"dealing"`
   - Then same function (or next step) deals initial cards: two to each active seat, two to dealer (one hidden), updates `playerHands` and `dealerCards`, increments `deckIndex`, sets `phase = "player_actions"` and `currentTurn` to first active seat.

Only the function writes `deck` and `deckSeed`; clients only read. Players “see” the deck only via cards appearing in `dealerCards` and `playerHands` as the function adds them.

**Example (Node/TypeScript):**

```typescript
function createShuffledDeck(seed: number): { rank: string; suit: string }[] {
  const suits = ["hearts", "clubs", "diamonds", "spades"];
  const ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
  const cards: { rank: string; suit: string }[] = [];
  for (const suit of suits) for (const rank of ranks) cards.push({ rank, suit });
  // Seeded shuffle (e.g. use a small seeded RNG library)
  const rng = seededRandom(seed);
  for (let i = cards.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [cards[i], cards[j]] = [cards[j], cards[i]];
  }
  return cards;
}

// In startDeal (or similar):
const seed = Math.floor(Math.random() * 0x7FFFFFFF);
const deck = createShuffledDeck(seed);
await gameRef.update({
  phase: "dealing",
  deckSeed: seed,
  deck,
  deckIndex: 0,
});
// Then deal initial cards (see below) and set phase to "player_actions".
```

---

## 5. How players take action (hit, stand, double)

All actions go through **callable** Cloud Functions. The function reads `mp_blackjack/game` (and if needed `mp_blackjack/table`), validates, updates **game** (and **table** for balance on double), then returns. Clients observe `game` and `table` and update the UI.

- **setReady**  
  - Callable: `setReady({ seatIndex })`.  
  - Function: ensure the seat belongs to the caller (e.g. by playerId in context), then set `table/seats/{seatIndex}/ready = true`. Optionally check “all ready” and advance phase (or rely on startGame).

- **placeBet**  
  - Callable: `placeBet({ seatIndex, amount })`.  
  - Function: check `phase === "betting"`, seat has enough balance, then deduct from `table/seats/{seatIndex}/balance` and set the bet for that hand in `game.playerHands["seatIndex"]` (or keep bets only under table; your choice). Write to **table** (balance) and **game** (bets/hands).

- **playerAction**  
  - Callable: `playerAction({ seatIndex, handIndex, action })` with `action in ["hit","stand","double"]`.  
  - Function:  
    - Read `game`. Check `phase === "player_actions"` and `currentTurn.seatIndex === seatIndex`, `currentTurn.handIndex === handIndex`.  
    - **Hit:** Take `game.deck[game.deckIndex]`, append to `game.playerHands[seatIndex][handIndex].cards`, increment `deckIndex`. If total > 21, set `busted: true` and advance turn.  
    - **Stand:** Set that hand’s `stood: true`, advance turn.  
    - **Double:** Deduct same bet from `table/seats/{seatIndex}/balance`, double the hand’s bet, deal one card, set `doubled: true`, advance turn.  
  - If all hands for all players are done (stood/busted/doubled), set `phase = "dealer_turn"` and either return (and have client or trigger call **runDealer**) or call runDealer inside the same function.  
  - All writes go to **game** (and **table** for balance on double). No client writes to `game`.

So: **Cloud Functions react to the callable invocations** by validating and then **directly manipulating and writing** both `game` and (when needed) `table`.

---

## 6. Individual payouts (not whole table at once)

Payouts are computed **per seat** and written **per seat** so each player’s balance updates as soon as their result is written. The function still runs in one go (no literal “loop” over time), but the **writes** are per seat.

**In the resolving function (e.g. runDealer + resolve, or a dedicated resolvePayouts):**

1. Compute dealer total and whether dealer busted.
2. For **each** seat that had a bet:
   - Compute win/loss for each of their hands (push/win/loss, blackjack pay 3:2, etc.).
   - New balance = current `table/seats/{seatIndex}/balance` + total payout for that seat.
   - Write **only that seat’s balance**: `table/seats/{seatIndex}/balance = newBalance`.
3. Then set `game.phase = "game_over"` and `game.handNumber += 1`, and optionally clear `game.playerHands` / dealer cards for the next hand, or leave them for display until the next deal.
4. Then set `game.phase = "between_hands"` and `game.phaseResumeAt = now + 3000`.

Clients observe `table/seats/{theirSeatIndex}/balance`. Each seat sees its own balance change as soon as the function writes it; you’re not “paying the whole table at once” in a single atomic blob—you’re doing one write per seat (or a multi-path update in one commit if you prefer). Function still runs once; the “individual” part is **per-seat balance writes**, not one global payout event.

**Example (conceptual):**

```typescript
const seats = await tableRef.child("seats").once("value");
const game = (await gameRef.once("value")).val();
const dealerTotal = computeTotal(game.dealerCards);
const dealerBusted = dealerTotal > 21;

for (const seatIndex of Object.keys(game.playerHands || {})) {
  const hands = game.playerHands[seatIndex];
  let payout = 0;
  for (const hand of hands) {
    const result = resolveHand(hand, dealerTotal, dealerBusted);
    payout += result; // positive win, negative loss, 0 push
  }
  const seatRef = tableRef.child("seats").child(seatIndex);
  const snap = await seatRef.once("value");
  const currentBalance = snap.val()?.balance ?? 0;
  await seatRef.child("balance").set(currentBalance + payout);
}
await gameRef.update({ phase: "game_over" });
// then set between_hands and phaseResumeAt
```

---

## 7. Controlling how fast the game advances (summary)

| Moment | How it’s controlled |
|--------|---------------------|
| **Start: ready-up** | Players call **setReady**; when all ready, **startGame** (or trigger) sets phase to `betting`. Speed = when everyone readies + one Start. |
| **After each hand: 3s break** | Function sets `phase = "between_hands"` and `phaseResumeAt = now + 3000`. A **scheduled function** (every few seconds) checks `phaseResumeAt <= now` and sets `phase = "betting"`; or after 3s the **client** calls **startNextHand()** to advance. Speed = 3 seconds. |
| **Betting → dealing** | When “Deal” is pressed (callable **startDeal**). Optional: auto-deal after N seconds by setting `phaseResumeAt` and same scheduler advancing phase and calling deal logic. |
| **Player actions / dealer** | Advance as soon as callables return; no server-side delay. Optional client-side animation delays. |

So: **Cloud Functions** own phase transitions and **directly write** `game` (and when needed `table`). **Pacing** is via `phaseResumeAt` plus either a **scheduled function** that advances phases when time is up, or **client callables** (startGame, startNextHand, startDeal) that the function validates and then advances.

---

## 8. Example: list of Cloud Functions

| Function | Trigger | What it does | Writes |
|----------|---------|--------------|--------|
| **setReady** | Callable | Sets `table/seats/{i}/ready = true` | `table` |
| **startGame** | Callable | Requires all seated ready; sets `game.phase = "betting"`, clears ready | `game`, `table` |
| **placeBet** | Callable | Deducts balance, sets bet for seat in game | `table`, `game` |
| **startDeal** | Callable | Creates deck, deals, sets `player_actions` + `currentTurn` | `game` |
| **playerAction** | Callable | Hit/stand/double; updates hand, deckIndex, currentTurn; if all done → dealer_turn | `game`, `table` (double) |
| **runDealer** | Callable (or trigger on phase) | Dealer draws to 17+; then resolve payouts per seat; set game_over → between_hands, phaseResumeAt | `game`, `table` (balances) |
| **advancePhase** | Scheduled (e.g. every 5s) or Callable | If `phase === "between_hands"` and `phaseResumeAt <= now`, set `phase = "betting"`, clear ready | `game`, `table` |

---

## 9. Summary

- **Game loop** is implemented **on top of Firebase Cloud Functions**: callables for player actions and phase starters, optional scheduled function for “after 3s break” and optional auto-deal.
- **Deck creation** happens inside a function (startDeal): seeded shuffle, write `deck` + `deckSeed` + `deckIndex` to `game`; only the function writes the deck.
- **Players take action** by calling **setReady**, **placeBet**, **playerAction**; functions **directly read and write** both `mp_blackjack/table` and `mp_blackjack/game`.
- **Pacing:** Ready-up is “when all ready + Start”; 3-second break between hands is `phaseResumeAt` + scheduled function (or client) advancing to betting; betting/dealing is on “Deal” (or optional timer).
- **Payouts** are **per seat**: the resolving function writes each seat’s new balance to `table/seats/{i}/balance` individually so each player is paid out on their own balance update.

All of this works with Cloud Functions as the single authority that **directly manipulates and writes** both the **table** and the **game** in Firebase.
