# BlackjackGameplayViewController Refactoring Summary

## Overview

Successfully refactored the massive 3,883-line `BlackjackGameplayViewController.swift` by extracting business logic into focused, single-responsibility managers following the delegation pattern.

## Results

### Before Refactoring
- **BlackjackGameplayViewController.swift**: 3,883 lines
- Single massive class handling all game logic
- Difficult to maintain, test, and understand

### After Refactoring
- **BlackjackGameplayViewController.swift**: 3,524 lines (9.2% reduction)
- **5 Manager Classes**: 1,336 lines of extracted logic
- **Total Code**: 4,860 lines (managers + view controller)

### Code Distribution
- **BlackjackSettingsManager**: 278 lines - Settings persistence and coordination
- **BlackjackDeckManager**: 258 lines - Deck operations, shuffling, card counting
- **BlackjackSessionManager**: 403 lines - Session lifecycle, metrics, balance tracking
- **BlackjackGameStateManager**: 276 lines - Game phases, player actions, split state
- **BlackjackBetManager**: 121 lines - Betting logic and rebet functionality

## Architecture Pattern

All managers follow a consistent **protocol-based delegation pattern**:

```swift
protocol ManagerDelegate: AnyObject {
    func eventDidOccur(...)
}

final class Manager {
    weak var delegate: ManagerDelegate?
    private(set) var state: State

    func performAction() {
        // Update state
        delegate?.eventDidOccur(...)
    }
}
```

The ViewController:
- Initializes managers in `setupManagers()`
- Sets itself as delegate for all managers
- Uses computed properties for backward compatibility
- Delegates business logic to appropriate managers

## Extracted Managers

### 1. BlackjackSettingsManager
**Purpose**: Manages all game settings persistence and coordination

**Responsibilities**:
- Load/save settings from UserDefaults
- Track display preferences (show totals, deck count, card count)
- Manage deck configuration (count, penetration, fixed hand types)
- Handle rebet settings and selected side bets
- Notify delegate of setting changes

**Key Methods**:
- `loadSettings()` - Load from UserDefaults
- `updateSettings(_:)` - Update and persist settings
- `toggleTotals()`, `setDeckCount(_:)` - Individual setting updates

**Delegate Protocol**:
```swift
protocol BlackjackSettingsManagerDelegate: AnyObject {
    func settingsDidChange(_ settings: BlackjackSettings)
}
```

### 2. BlackjackDeckManager
**Purpose**: Handles all deck operations, shuffling, and card counting

**Responsibilities**:
- Create and shuffle multiple decks (1, 2, 4, or 6 decks)
- Draw cards from deck with automatic reshuffling
- Insert and track cut card position for realistic casino play
- Implement Hi-Lo card counting system (running count + true count)
- Support fixed hand types for testing bonus bets

**Key Methods**:
- `createAndShuffleDeck()` - Initialize new shuffled deck
- `drawCard()` - Draw card with automatic reshuffle when needed
- `updateCardCount(for:)` - Update running/true count
- `dealFixedHand(type:)` - Deal specific hands for testing

**Delegate Protocol**:
```swift
protocol BlackjackDeckManagerDelegate: AnyObject {
    func deckWasShuffled(cardCount: Int)
    func cutCardWasReached()
    func cardCountDidUpdate(running: Int, trueCount: Int)
    func deckCountDidChange(remaining: Int)
}
```

**Card Counting**: Implements Hi-Lo system with true count calculation based on decks remaining.

### 3. BlackjackSessionManager
**Purpose**: Manages session lifecycle, metrics collection, and persistence

**Responsibilities**:
- Track session ID, start time, and accumulated play time
- Pause/resume timer for app backgrounding
- Record balance history and bet size snapshots
- Collect detailed gameplay metrics (wins, losses, pushes, doubles, blackjacks)
- Track bonus bet wins by type (Perfect Pairs, Royal Match, etc.)
- Save/resume sessions for backward compatibility
- Detect loss chasing behavior

**Key Methods**:
- `startSession()` - Initialize new session
- `pauseSessionTimer()` / `resumeSessionTimer()` - Handle app lifecycle
- `trackBet(amount:isMainBet:)` - Record bet placement
- `recordWin(isBlackjack:)` - Track hand outcomes
- `saveCurrentSession()` - Persist to SessionPersistenceManager
- `currentSessionSnapshot()` - Get live session for display

**Delegate Protocol**:
```swift
protocol BlackjackSessionManagerDelegate: AnyObject {
    func sessionDidStart(id: String)
    func sessionWasSaved(session: GameSession)
    func metricsDidUpdate(metrics: BlackjackGameplayMetrics)
    func balanceDidChange(from: Int, to: Int)
    func handCountDidChange(count: Int)
}
```

**Backward Compatibility**: Supports resuming existing sessions from GameSession objects.

### 4. BlackjackGameStateManager
**Purpose**: Manages game phase, player actions, and hand states

**Responsibilities**:
- Track current game phase (waiting for bet, player turn, dealer turn, etc.)
- Manage player action state (has hit, stood, doubled)
- Handle split hand state tracking for multiple hands
- Provide game state queries (can split, is blackjack, calculate total)
- Track insurance state and availability

**Key Methods**:
- `setGamePhase(_:)` - Update current phase
- `resetToWaitingForBet()` - Reset all state for new hand
- `setPlayerHit()` / `setPlayerStood()` / `setPlayerDoubled()` - Record actions
- `initializeSplitState()` - Start split hands
- `updateSplitHandState(index:...)` - Update individual split hand
- `calculateHandTotal(cards:)` - Compute hand value with Ace logic
- `isBlackjack(cards:)` - Check for natural 21

**Delegate Protocol**:
```swift
protocol BlackjackGameStateManagerDelegate: AnyObject {
    func gamePhaseDidChange(from: GamePhase, to: GamePhase)
    func playerActionStateDidChange()
    func splitStateDidChange(isSplit: Bool, activeHandIndex: Int)
}
```

**Split State Management**: Tracks individual state for each split hand (hasHit, hasStood, hasDoubled, busted).

### 5. BlackjackBetManager
**Purpose**: Manages betting logic and rebet functionality

**Responsibilities**:
- Track rebet settings (enabled, amount)
- Learn player's preferred bet amount (tracks 3 consecutive same bets)
- Validate bet placement against balance
- Check if bonus bets can be placed in current game phase
- Calculate smart rebet amounts (only when appropriate)

**Key Methods**:
- `trackBetForRebet(amount:)` - Learn preferred bet amount
- `calculateRebetAmount(currentBetAmount:balance:)` - Smart rebet logic
- `canPlaceBet(amount:currentBalance:)` - Validate bet
- `canPlaceBonusBet(gamePhase:)` - Check bonus bet timing
- `updateRebetSettings(enabled:amount:)` - Sync with settings

**Delegate Protocol**:
```swift
protocol BlackjackBetManagerDelegate: AnyObject {
    func rebetAmountDidUpdate(amount: Int)
    func betWasPlaced(amount: Int, isMainBet: Bool)
    func betWasRemoved(amount: Int)
}
```

**Smart Rebet**: Automatically detects when rebet should NOT be applied (e.g., bet already on table from winning).

## Benefits of Refactoring

### 1. Single Responsibility
Each manager has one clear purpose and encapsulates related logic:
- **Settings** → BlackjackSettingsManager
- **Deck Operations** → BlackjackDeckManager
- **Session Tracking** → BlackjackSessionManager
- **Game State** → BlackjackGameStateManager
- **Betting Logic** → BlackjackBetManager

### 2. Testability
Managers can now be unit tested independently:
```swift
func testCardCounting() {
    let manager = BlackjackDeckManager(deckCount: 1)
    let card = BlackjackHandView.Card(rank: .five, suit: .hearts)
    manager.updateCardCount(for: card)
    XCTAssertEqual(manager.runningCount, 1) // Low card = +1
}
```

### 3. Reusability
Managers can be reused in other contexts:
- Use BlackjackDeckManager in a different game mode
- Use BlackjackSessionManager for analytics dashboard
- Use BlackjackGameStateManager for game replays

### 4. Maintainability
Changes are now localized:
- Adding new bet validation? → Update BlackjackBetManager only
- Changing card counting algorithm? → Update BlackjackDeckManager only
- Adding new metrics? → Update BlackjackSessionManager only

### 5. Backward Compatibility
Computed properties in ViewController ensure existing code still works:
```swift
private var hasPlayerHit: Bool { gameStateManager.hasPlayerHit }
private var runningCount: Int { deckManager.runningCount }
```

## Integration Pattern

### Manager Setup
```swift
private func setupManagers() {
    // Initialize managers in dependency order
    settingsManager = BlackjackSettingsManager()
    settingsManager.delegate = self

    deckManager = BlackjackDeckManager(
        deckCount: settingsManager.currentSettings.deckCount,
        deckPenetration: settingsManager.currentSettings.deckPenetration
    )
    deckManager.delegate = self

    // ... other managers
}
```

### Delegate Implementation
```swift
extension BlackjackGameplayViewController: BlackjackSessionManagerDelegate {
    func sessionDidStart(id: String) {
        // Handle session start
    }

    func metricsDidUpdate(metrics: BlackjackGameplayMetrics) {
        // Update UI with new metrics
    }
}
```

## Remaining Code in ViewController

The ViewController (3,524 lines) still handles:
- **UI Management**: View lifecycle, layout, constraints
- **Animation Coordination**: Card dealing, chip movements, win/loss animations
- **User Interaction**: Tap handlers, button actions, gesture recognizers
- **View Coordination**: Dealer hand, player hand(s), split hands, bonus bets
- **Game Flow**: Orchestrating managers to implement complete game logic
- **Bonus Bet Evaluation**: Checking Perfect Pairs, Royal Match, etc.
- **Dealer AI**: Dealer turn logic (hit on 16 or less, stand on 17+)

These responsibilities are appropriate for a ViewController as they require tight coupling with UIKit and view hierarchy.

## Migration Notes

### For Future Refactoring
If further extraction is desired, consider:
1. **BlackjackAnimationCoordinator** - Extract animation sequences
2. **BlackjackBonusBetEvaluator** - Already exists as separate class
3. **BlackjackResultCalculator** - Extract win/loss/push determination logic

### Testing Strategy
1. Unit test each manager independently
2. Integration test manager interactions
3. UI test complete game flows
4. Regression test all existing gameplay scenarios

## Commit History

1. **Phase 1.1**: BlackjackSettingsManager (~286 lines)
2. **Phase 1.2**: BlackjackDeckManager (~270 lines)
3. **Phase 1.3**: BlackjackSessionManager (~408 lines)
4. **Phase 2.1**: BlackjackGameStateManager (~273 lines)
5. **Phase 2.2**: BlackjackBetManager (~126 lines)

Each phase was committed atomically with:
- Manager creation
- ViewController integration
- Delegate implementation
- Backward compatibility via computed properties

## Conclusion

This refactoring successfully reduced the ViewController from 3,883 to 3,524 lines (9.2% reduction) while extracting 1,336 lines of business logic into focused, testable, reusable managers. The codebase is now significantly more maintainable and follows SOLID principles.

The remaining ViewController code is appropriate for a UIViewController as it handles UI, animations, and view coordination—responsibilities that benefit from tight coupling with UIKit.

---

**Refactored by**: Claude Code (Anthropic)
**Date**: January 26, 2026
**Branch**: refactor/blackjack-view-controller
