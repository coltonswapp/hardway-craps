# Single-Player Blackjack: Hand-by-Hand UX Refactor

## Context

The single-player blackjack flow has drifted behind the multiplayer version. Today SP lets the user tap the page-control dots to jump between split hands "willy nilly" at any time, with only flat session-level flags tracking hand progress and a hard cap of one split (2 hands total). The MP version we just shipped has a much cleaner UX: sequential play per hand, a visible active-hand turn indicator, per-hand state tracking, auto-advance on bust/21, and up to 4 hands via re-splitting.

This refactor brings that hand-by-hand UX to SP while keeping the existing visual skin — we're staying on the current `PlayerHandView`/`BlackjackHandView` + scroll container layout rather than swapping to `PlayerSeat`/`CompactPlayerHandView`. What changes is the **state model, turn progression, and action routing**, not the card look.

**Goals**
- Each hand carries its own state; the session no longer conflates "player" flags with "hand" flags.
- Split hands play sequentially — hand 0 to completion, then auto-advance to hand 1, etc.
- Support up to 4 hands via re-splitting pairs (DAS stays allowed per hand).
- Visible active-hand indicator replaces the interactive page control.
- No behavioral regressions: double, surrender, insurance, bust, blackjack, settlement, animations all still work.

**Non-goals**
- No redesign of card rendering or bet controls.
- No changes to dealer logic, rule settings, or bonus bets.
- No changes to `BlackjackSessionManager`'s public shape beyond what per-hand metrics require.

---

## Approach

### 1. Introduce a `PlayerHand` state type (per-hand model)

Replace the scattered SP flags (`hasPlayerHit`, `hasPlayerStood`, `hasPlayerDoubled`, `playerBusted` at the session level, plus the 2-element `SplitHandState` array) with a single per-hand value type that every hand — primary or split — uses uniformly.

Add to `hardway-craps/Games/Blackjack/BlackjackGameStateManager.swift`:

```swift
struct PlayerHand {
    let handIndex: Int
    var bet: Int
    var hasHit: Bool = false
    var hasStood: Bool = false
    var hasDoubled: Bool = false
    var hasSurrendered: Bool = false
    var busted: Bool = false
    var isFromSplit: Bool = false
    var isBlackjack: Bool = false   // natural 21 on initial 2 cards
    var doubleDownCardIndex: Int? = nil

    var isComplete: Bool { hasStood || busted || hasSurrendered || hasDoubled }
}
```

The manager replaces `splitHandStates: [SplitHandState]` with `playerHands: [PlayerHand]` (always length ≥ 1, initialized to a single `PlayerHand(handIndex: 0, ...)` at the start of each deal). `isSplit` becomes a computed `playerHands.count > 1`. `activeHandIndex` stays.

Keep the existing delegate surface mostly intact — `splitStateDidChange(isSplit:activeHandIndex:)` still fires, `playerActionStateDidChange()` still fires whenever the active hand mutates. Legacy readers (`hasPlayerHit`, `hasPlayerStood`, `hasPlayerDoubled`, `playerBusted`) become computed properties that read from `playerHands[activeHandIndex]`, so existing call sites in the VC keep compiling while we migrate.

### 2. Strict sequential turn progression

Remove free hand switching. The page control stays as a **read-only indicator** (keep it, but set `isUserInteractionEnabled = false` and unbind the `.valueChanged` target). `handsScrollView.isScrollEnabled` stays off; hand switching is strictly programmatic.

Add a single `advanceToNextHandOrDealer()` method on the VC that:
1. Checks if `playerHands[activeHandIndex].isComplete`.
2. Finds the next `!isComplete` hand index (scanning forward from active+1).
3. If found: calls `switchFocusToHand(nextIndex)` + deals the required second card for a just-split hand that only has 1 card.
4. If no more hands: `setGamePhase(.dealerTurn)`.

This method is the single exit point from every player action (hit→bust, hit→21, stand, double, surrender, split-completion). It replaces the ad-hoc `checkSplitHandsCompletion()` (`BlackjackGameplayViewController.swift:1362-1390`) and the scattered inline transitions to dealer turn.

### 3. Generalize split to support up to 4 hands

Current SP caps at 2 hands (`canPlayerSplit` returns false once `isSplit` is true — `BlackjackGameStateManager.swift:209`). Lift this to `playerHands.count < 4` and allow splitting on any 2-card hand of matching rank, including freshly-split hands.

Updates needed:
- `BlackjackGameStateManager.canPlayerSplit(...)` — change guard to `playerHands.count < 4`.
- `BlackjackGameStateManager.initializeSplitState()` — rename to `appendSplitHand(fromHandIndex:bet:)` that inserts a new `PlayerHand` right after the source hand and returns the new index.
- `BlackjackGameplayViewController.playerSplitTapped()` (line 1423) — generalize from "create second `PlayerHandView`" to "insert a new `PlayerHandView` into `handsContentStackView` at the correct position, transfer one card from the source hand, deal a new card to the source hand, then focus stays on the source hand index until it's played out."
- The page control `numberOfPages` is now bound to `playerHands.count` (update in `splitStateDidChange`).
- Layout: `playerHandWidthConstraint` (line 529) — when count > 1, each hand gets `splitHandWidth` (280). Already works for 2; verify the scroll view content size accommodates 3-4 hands by updating `setupPlayerHandView` constraints to size the content stack to `splitHandWidth * count + spacing * (count-1)`.

Splitting aces still follows the existing one-card-per-ace rule (look at current split flow — if it has this today, preserve; if not, this isn't in scope).

### 4. Active hand visual indicator

The page control becomes a passive active-hand indicator (dot highlight moves with `activeHandIndex`). Keep it visible whenever `playerHands.count > 1`.

Additionally, add a lightweight highlight on the **active `PlayerHandView`** itself — a 1pt border or a subtle glow/scale — by adding `setActive(_ active: Bool, animated: Bool)` to `PlayerHandView.swift`. Call it from `switchFocusToHand(_:)` so the old active hand deactivates and the new one activates. This is the SP equivalent of MP's yellow turn-indicator dot, adapted to SP's larger card layout.

### 5. Action routing always goes through active hand

Audit every `@objc` action handler in `BlackjackGameplayViewController.swift`:
- `playerHitTapped` (line 1272)
- `playerStandTapped` (line 1392)
- `playerDoubleTapped` (line 1650)
- `playerSplitTapped` (line 1423)
- `playerSurrenderTapped` (wherever it lives)
- Tap-to-hit on `playerHandView.onTap` (line 485) and the corresponding `canTap` (line 494)

Each handler resolves the **active `PlayerHandView`** and the **active `PlayerHand` state** via helpers:

```swift
private var activePlayerHand: PlayerHand { gameStateManager.playerHands[activeHandIndex] }
private var activeHandView: PlayerHandView { /* playerHandView if index 0, else splitHandViews[index - 1] */ }
```

`splitHandView` (single-value optional, line ~186) becomes `splitHandViews: [PlayerHandView]` (array). Every place that reads `splitHandView` gets updated to index into the array.

After any mutating action, call `gameStateManager.updatePlayerHand(at: activeHandIndex) { $0.hasHit = true }` (similar for stood/doubled/busted), then call `advanceToNextHandOrDealer()` if the hand is now complete.

### 6. Per-hand settlement

`endSplitGame()` (`BlackjackGameplayViewController.swift:2010-2139`) already iterates both hands and settles each. Generalize its loop from `[playerHandView, splitHandView!]` to `[playerHandView] + splitHandViews` and iterate `playerHands` in parallel. Each hand evaluates independently against the dealer's final total. The summary message logic (lines 2039-2048) extends to 3/4 hands — just tally wins/losses/pushes and format accordingly, e.g. "2 win, 1 lose, 1 push."

`sessionManager.recordWin/recordLoss/recordPush` already gets called per hand, so metrics just follow the new loop bounds naturally.

### 7. Cleanup

- `cleanupSplitHand()` (`BlackjackGameplayViewController.swift:2141-2169`) — generalize to remove **all** extra split hand views (not just one), restore single-hand layout.
- `resetSplitState()` on the state manager resets `playerHands` to `[PlayerHand(handIndex: 0, bet: currentBet)]`.
- New-hand flow in the ready tap / deal start path must initialize `playerHands` before any cards are dealt.

---

## Critical files to modify

| File | Change |
|---|---|
| `hardway-craps/Games/Blackjack/BlackjackGameStateManager.swift` | Add `PlayerHand` struct; replace `splitHandStates` with `playerHands`; keep legacy computed accessors; generalize split APIs; relax 4-hand cap. |
| `hardway-craps/Games/Blackjack/BlackjackGameplayViewController.swift` | Main work lives here. Replace `splitHandView: PlayerHandView?` with `splitHandViews: [PlayerHandView]`. Route all actions through active hand. Add `advanceToNextHandOrDealer()`. Remove interactive page control handler; make page control indicator-only. Generalize split creation, layout width, and settlement loop. |
| `hardway-craps/Games/Blackjack/PlayerHandView.swift` | Add `setActive(_:animated:)` for active-hand highlight. |
| `hardway-craps/Games/Blackjack/BlackjackSessionManager.swift` | Verify `recordWin/Loss/Push` are tolerant of being called 3-4× per deal; no structural change expected. |

Key existing utilities to **reuse**:
- `BlackjackGameStateManager.calculateHandTotal/isBusted/isBlackjack/canPlayerSplit` — keep as-is, take `[Card]` arg already.
- `ChipAnimationHelper.animateWinnings/animateBetCollection/animateChipsAway` — per-hand animations already parameterized by bet control.
- `PlayerHandView` card animation, bet control closures, tap handling — unchanged.
- `handsContentStackView` horizontal stack already supports N arranged subviews.

---

## Verification plan

Run the app in the iOS simulator, play SP blackjack, and walk through each scenario:

1. **No split, normal play** — bet, deal, hit, stand; confirm no regression on single-hand flow. Check bust, 21, blackjack, push, dealer win paths.
2. **Single split (2 hands)** — get a pair, split, play hand 0 through (hit/stand/bust/double), confirm focus auto-advances to hand 1, confirm dealer turn runs only after both hands complete. Try standing on hand 0, try busting on hand 0, try doubling on hand 0.
3. **Re-split to 3 hands** — split once, then on a freshly split hand that's another pair, split again. Confirm a third `PlayerHandView` is inserted between the existing hands at the right index, focus stays on the original hand until done, then advances through each.
4. **Re-split to 4 hands (max)** — confirm split button disables at 4 hands.
5. **Double on split hand** — confirm each hand doubles independently, balance deducts correctly, auto-stand + auto-advance fires.
6. **Page control** — confirm dots are visible, match hand count, highlight the active hand, but are **not tappable** (tap doesn't switch hands).
7. **Active hand highlight** — confirm `PlayerHandView` active state is visually distinct and updates as focus advances.
8. **Settlement** — mixed outcomes across 3-4 hands (some win, some lose, some push); confirm per-hand payout animations and summary message are correct.
9. **New deal cleanup** — confirm all extra split views are removed and layout returns to single-hand mode.
10. **Metrics** — check `BlackjackSessionManager` stats after a few multi-hand rounds; wins/losses/pushes should equal total hand outcomes, not total deals.

No automated tests exist for this flow (per the existing repo layout), so verification is manual in the simulator.
