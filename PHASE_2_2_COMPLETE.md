# Phase 2.2 Complete: CrapsPassLineManager

## Summary

Successfully completed Phase 2.2 of the Craps refactoring plan by creating and integrating `CrapsPassLineManager`.

## What Was Created

### CrapsPassLineManager.swift (147 lines)

**Location**: `hardway-craps/Games/Craps/CrapsPassLineManager.swift`

**Components**:
- `PassLineWinResult` struct - Win calculation result with bet, winnings, and multiplier
- `CrapsPassLineManagerDelegate` protocol - Delegate pattern for pass line events
- `CrapsPassLineManager` class - Manager implementation for pass line logic

**Responsibilities**:
- Calculate odds multipliers for different point numbers
- Determine when odds should be enabled (point phase + pass line bet)
- Calculate pass line payouts (1:1)
- Calculate odds payouts (point-based: 2:1, 3:2, 6:5)
- Process win/loss events and notify delegate
- Update control states (enabled/disabled, hidden/visible)

**Key Methods**:
- `calculateOddsMultiplier(for:)` - Get multiplier for point (4,10: 2x, 5,9: 1.5x, 6,8: 1.2x)
- `shouldEnableOdds(isPointPhase:hasPassLineBet:)` - Determine if odds should be enabled
- `calculatePassLinePayout(betAmount:)` - Calculate 1:1 payout
- `calculateOddsPayout(betAmount:point:)` - Calculate point-based payout
- `processPassLineWin(betAmount:)` - Process win and notify delegate
- `processPassLineOddsWin(betAmount:point:)` - Process odds win with multiplier
- `processPassLineLoss(betAmount:)` - Process loss and notify delegate
- `processPassLineOddsLoss(betAmount:)` - Process odds loss and notify delegate
- `updateControlStates(...)` - Update pass line and odds control states

**Delegate Protocol**:
```swift
protocol CrapsPassLineManagerDelegate: AnyObject {
    func passLineWinProcessed(originalBet: Int, winnings: Int)
    func passLineOddsWinProcessed(originalBet: Int, winnings: Int, point: Int, multiplier: Double)
    func passLineLossProcessed(lostAmount: Int)
    func passLineOddsLossProcessed(lostAmount: Int)
}
```

**PassLineWinResult**:
```swift
struct PassLineWinResult {
    let originalBet: Int
    let winnings: Int
    let oddsMultiplier: Double
}
```

## Integration Changes

### CrapsGameplayViewController.swift

**Added**:
- `private var passLineManager: CrapsPassLineManager!` - Manager instance
- Manager initialization in `setupManagers()`
- Delegate extension: `CrapsPassLineManagerDelegate`
- Manager calls in win/loss methods

**Modified**:
- `updatePassLineOddsVisibility()` - Delegates to manager's `updateControlStates()`
- `handlePassLineWin()` - Uses manager to process win and get result
- `handlePassLineOddsWin()` - Uses manager to calculate multiplier and process win
- `handlePassLineLoss()` - Uses manager to process loss
- `handlePassLineOddsLoss()` - Uses manager to process odds loss

**Removed Logic**:
- Inline odds multiplier calculation (switch statement)
- Inline control state management logic
- Direct betting control updates

**Animation Logic Preserved**:
- All animation code remains in ViewController (UI responsibility)
- Manager provides calculations, ViewController handles animations
- Clean separation: business logic vs presentation

## Line Counts

| Component | Before | After | Change |
|-----------|--------|-------|--------|
| CrapsGameplayViewController.swift | 1,922 | 1,941 | +19 lines |
| **New Files** | | | |
| CrapsPassLineManager.swift | - | 147 | +147 lines |

**Note**: ViewController grew by 19 lines due to:
- Manager property and initialization (+3 lines)
- Delegate extension implementation (+14 lines)
- Additional method calls in integration (+2 lines)

This is expected and acceptable - the business logic is now isolated and testable.

### Cumulative Progress (Phases 1.1 + 1.2 + 1.3 + 2.2)

| Metric | Value |
|--------|-------|
| **Original ViewController** | 2,071 lines |
| **Current ViewController** | 1,941 lines |
| **Total Reduction** | 130 lines (-6%) |
| | |
| **Managers Created** | 4 managers |
| CrapsSettingsManager | 154 lines |
| CrapsSessionManager | 391 lines |
| CrapsGameStateManager | 178 lines |
| CrapsPassLineManager | 147 lines |
| **Total Extracted** | 870 lines |
| | |
| **Net Code** | 2,811 lines total |
| **Net Growth** | +740 lines |

## Benefits Achieved

### 1. Single Responsibility
Pass line and odds logic is now isolated:
- ViewController no longer calculates odds multipliers
- Control state management delegated
- Payout calculations centralized
- Clean separation: calculations vs animations

### 2. Testability
`CrapsPassLineManager` can be unit tested:
```swift
func testOddsMultiplier() {
    let manager = CrapsPassLineManager()
    XCTAssertEqual(manager.calculateOddsMultiplier(for: 4), 2.0)
    XCTAssertEqual(manager.calculateOddsMultiplier(for: 5), 1.5)
    XCTAssertEqual(manager.calculateOddsMultiplier(for: 6), 1.2)
}

func testOddsPayout() {
    let manager = CrapsPassLineManager()
    let result = manager.calculateOddsPayout(betAmount: 10, point: 4)
    XCTAssertEqual(result.winnings, 20) // 2:1 odds
    XCTAssertEqual(result.oddsMultiplier, 2.0)
}

func testShouldEnableOdds() {
    let manager = CrapsPassLineManager()
    XCTAssertTrue(manager.shouldEnableOdds(isPointPhase: true, hasPassLineBet: true))
    XCTAssertFalse(manager.shouldEnableOdds(isPointPhase: false, hasPassLineBet: true))
    XCTAssertFalse(manager.shouldEnableOdds(isPointPhase: true, hasPassLineBet: false))
}
```

### 3. Clear Separation
Business logic vs presentation:
- **Manager**: Calculations, rules, logic
- **ViewController**: Animations, UI updates, user interaction

Example in `handlePassLineOddsWin()`:
```swift
// Manager handles business logic
let result = passLineManager.processPassLineOddsWin(betAmount: capturedBetAmount, point: pointNumber)

// ViewController handles animations
animateWinnings(for: passLineOddsControl, odds: result.oddsMultiplier)
animateBetCollection(for: passLineOddsControl)
```

### 4. Maintainability
Changes to pass line logic are localized:
- Need to change odds multipliers? → Update manager only
- Need different payout rules? → Update manager only
- Need to add new bet types? → Extend manager

### 5. Reusability
Manager can be used elsewhere:
- Payout calculator screens
- Game simulations
- Testing tools
- Analytics

## Pattern Consistency

This implementation follows the same delegation pattern as all previous managers:
- **Phase 1.1**: CrapsSettingsManager
- **Phase 1.2**: CrapsSessionManager
- **Phase 1.3**: CrapsGameStateManager
- **Phase 2.2**: CrapsPassLineManager (current)

Consistent approach:
- Protocol-based delegation
- Manager initializes in `setupManagers()`
- ViewController sets itself as delegate
- Manager provides calculations/logic
- ViewController handles UI/animations
- Clean separation of concerns

## Key Implementation Details

### Odds Multiplier Calculation

Centralized in manager:
```swift
func calculateOddsMultiplier(for point: Int) -> Double {
    switch point {
    case 4, 10: return 2.0  // 2:1 odds
    case 5, 9: return 1.5   // 3:2 odds
    case 6, 8: return 1.2   // 6:5 odds
    default: return 1.0
    }
}
```

This was previously duplicated in multiple places in the ViewController.

### Control State Management

Manager determines what should be enabled:
```swift
func updateControlStates(
    isPointPhase: Bool,
    hasPassLineBet: Bool,
    passLineControl: PlainControl,
    oddsControl: PlainControl
) {
    let isEnabled = shouldEnableOdds(isPointPhase: isPointPhase, hasPassLineBet: hasPassLineBet)
    passLineControl.setBetRemovalDisabled(isPointPhase)
    oddsControl.setBetRemovalDisabled(!isEnabled)
    oddsControl.isEnabled = isEnabled
    oddsControl.isHidden = false
}
```

ViewController just calls this with current state - manager handles the logic.

### Win/Loss Processing

Manager processes event and returns result:
```swift
// In ViewController:
let result = passLineManager.processPassLineOddsWin(betAmount: capturedBetAmount, point: pointNumber)
// Use result.oddsMultiplier for animation
animateWinnings(for: passLineOddsControl, odds: result.oddsMultiplier)
```

Manager notifies delegate and returns calculation result for immediate use.

## Why ViewController Grew

The +19 lines is due to integration overhead:
1. **Manager property** (+1 line)
2. **Manager initialization** (+3 lines in setupManagers)
3. **Delegate extension** (+14 lines with 4 methods)
4. **Additional method calls** (+1-2 lines per method)

This is **expected and beneficial**:
- Infrastructure for delegation pattern
- Clear separation of concerns
- Testable business logic
- Maintainable architecture

The actual business logic (switch statements, calculations, state management) was extracted - that's the goal!

## Next Steps

Continue with **Phase 2.3: CrapsSpecialBetsManager** (~200 lines)

This will extract:
- Hardway bet evaluation (4 hard ways)
- Horn bet evaluation (4 horn bets)
- Field bet evaluation
- Payout calculations for each
- Win/loss detection logic

---

**Completed by**: Claude Code (Anthropic)
**Date**: January 28, 2026
**Branch**: refactor/crapsgameplay
**Phase**: 2.2 - CrapsPassLineManager

**Cumulative Progress**:
- Phase 1.1: CrapsSettingsManager ✅ (154 lines)
- Phase 1.2: CrapsSessionManager ✅ (391 lines)
- Phase 1.3: CrapsGameStateManager ✅ (178 lines)
- Phase 2.2: CrapsPassLineManager ✅ (147 lines)
- ViewController: 2,071 → 1,941 lines (130 lines / -6%)
- Total managers: 4 (870 lines extracted)
- Foundation + Pass Line complete!
