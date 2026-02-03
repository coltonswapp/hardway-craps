# CrapsGameplayViewController Refactoring Plan

## Overview

Refactor the 2,071-line `CrapsGameplayViewController.swift` by extracting business logic into focused, single-responsibility managers following the delegation pattern successfully used in the Blackjack refactoring.

## Goals

### Before Refactoring
- **CrapsGameplayViewController.swift**: 2,071 lines
- Single class handling all game logic, session tracking, bet management, and UI
- Difficult to maintain, test, and extend

### After Refactoring (Projected)
- **CrapsGameplayViewController.swift**: ~1,200 lines (42% reduction)
- **6-7 Manager Classes**: ~900 lines of extracted logic
- **Total Code**: ~2,100 lines (managers + view controller)
- Improved testability, maintainability, and code organization

## Architecture Pattern

All managers will follow the **protocol-based delegation pattern** used in Blackjack:

```swift
protocol CrapsManagerDelegate: AnyObject {
    func eventDidOccur(...)
}

final class CrapsManager {
    weak var delegate: CrapsManagerDelegate?
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

---

## Proposed Managers

### 1. CrapsSessionManager (~250 lines)

**Purpose**: Manages session lifecycle, metrics collection, and persistence

**Responsibilities**:
- Track session ID, start time, and accumulated play time
- Pause/resume timer for app backgrounding
- Record balance history and bet size snapshots
- Collect detailed gameplay metrics (rolls, sevens, points hit)
- Track bet metrics by type (pass line, odds, place, hardway, horn, field)
- Detect loss chasing behavior
- Save/resume sessions for backward compatibility

**Key Properties**:
```swift
private(set) var sessionId: String?
private(set) var sessionStartTime: Date?
private(set) var accumulatedPlayTime: TimeInterval
private var currentPeriodStartTime: Date?
private(set) var rollCount: Int
private(set) var sevensRolled: Int
private(set) var pointsHit: Int
private(set) var balanceHistory: [Int]
private(set) var betSizeHistory: [Int]
private(set) var gameplayMetrics: GameplayMetrics
```

**Key Methods**:
- `startSession()` - Initialize new session
- `pauseSessionTimer()` / `resumeSessionTimer()` - Handle app lifecycle
- `trackRoll()` - Increment roll count
- `trackSeven()` - Track sevens rolled
- `trackPoint()` - Track points made
- `recordBalanceSnapshot(balance:betSize:)` - Track balance changes
- `saveCurrentSession()` - Persist to SessionPersistenceManager
- `endSession()` - Finalize and save session
- `currentSessionSnapshot() -> GameSession` - Get live session

**Delegate Protocol**:
```swift
protocol CrapsSessionManagerDelegate: AnyObject {
    func sessionDidStart(id: String)
    func sessionWasSaved(session: GameSession)
    func metricsDidUpdate(metrics: GameplayMetrics)
    func rollCountDidChange(count: Int)
    func sevenWasRolled(total: Int)
    func pointWasMade(number: Int)
}
```

**Extracted From**:
- Lines 12-24 (session tracking properties)
- Lines 157-196 (pause/resume timer)
- Lines 219-233 (startSession)
- Lines 235-261 (balance history)
- Lines 361-470 (session persistence)

---

### 2. CrapsGameStateManager (~200 lines)

**Purpose**: Manages game phase, rolling state, and game events

**Responsibilities**:
- Track game phase (come out vs point phase)
- Manage rolling state (enabled/disabled based on bets)
- Coordinate with `CrapsGame` for roll processing
- Handle roll result events
- Notify delegates of phase changes
- Manage point tracking

**Key Properties**:
```swift
private var game: CrapsGame
private(set) var isRollingEnabled: Bool
private var rollingStateWorkItem: DispatchWorkItem?
```

**Key Methods**:
- `setGamePhase(_ phase: CrapsGame.Phase)` - Update phase
- `updateRollingState(hasPassLineBet:)` - Control roll button
- `processRoll(_ total: Int) -> GameEvent` - Handle roll via CrapsGame
- `handleRollResult(event:diceTotal:)` - Process game events
- `resetToWaitingForBet()` - Reset state for new hand
- `currentPoint() -> Int?` - Get current point number
- `isPointPhase() -> Bool` - Check if in point phase

**Delegate Protocol**:
```swift
protocol CrapsGameStateManagerDelegate: AnyObject {
    func gamePhaseDidChange(from: CrapsGame.Phase, to: CrapsGame.Phase)
    func rollingStateDidChange(enabled: Bool)
    func rollWasProcessed(event: GameEvent, total: Int)
    func pointWasEstablished(number: Int)
    func pointWasMade(number: Int)
    func sevenOut()
}
```

**Extracted From**:
- Line 50 (CrapsGame instance)
- Lines 1286-1402 (updateRollingState, handleRollResult)
- Lines 872-913 (rolling state work item management)

---

### 3. CrapsBetManager (~200 lines)

**Purpose**: Manages bet tracking, metrics, and balance coordination

**Responsibilities**:
- Track bets by type (pass line, odds, place, hardway, horn, field)
- Update gameplay metrics for each bet type
- Track concurrent bets across all controls
- Validate bets against balance
- Coordinate balance updates on bet placement/removal
- Track loss chasing behavior
- Track largest bet metrics

**Key Properties**:
```swift
private(set) var pendingBetSizeSnapshot: Int
private(set) var lastBalanceBeforeRoll: Int
```

**Key Methods**:
- `trackBet(amount:type:currentBalance:)` - Record bet placement
- `updateConcurrentBets(controlsWithBets:)` - Count active bets
- `canPlaceBet(amount:currentBalance:) -> Bool` - Validate bet
- `getAllActiveBets(from controls:) -> [(BetType, Int)]` - Collect all bets
- `setPendingBetSizeSnapshot(_ amount:)` - Track bet size before roll
- `updateLastBalance(_ balance:)` - Track balance before roll

**Delegate Protocol**:
```swift
protocol CrapsBetManagerDelegate: AnyObject {
    func betWasTracked(type: BetType, amount: Int)
    func concurrentBetsDidUpdate(count: Int)
    func lossChaseDetected(betCount: Int)
    func largestBetUpdated(amount: Int, percent: Double)
}
```

**BetType Enum**:
```swift
enum BetType {
    case passLine
    case odds
    case place
    case hardway
    case horn
    case field
}
```

**Extracted From**:
- Lines 21, 23 (bet tracking properties)
- Lines 263-359 (trackBet, updateConcurrentBets)
- Lines 1227-1231 (getAllBettingControls)

---

### 4. CrapsPassLineManager (~150 lines)

**Purpose**: Handles pass line and odds bet logic

**Responsibilities**:
- Calculate odds multipliers based on point number
- Determine pass line and odds visibility state
- Handle pass line win/loss animations
- Handle odds win/loss animations
- Calculate payouts for both pass line and odds

**Key Properties**:
```swift
// No state needed - stateless calculations
```

**Key Methods**:
- `calculateOddsMultiplier(for point: Int) -> Double` - Get odds multiplier (6,8: 1.2x, 5,9: 1.5x, 4,10: 2x)
- `shouldShowOdds(gamePhase: CrapsGame.Phase) -> Bool` - Determine odds visibility
- `calculatePassLinePayout(betAmount: Int) -> Int` - 1:1 payout
- `calculateOddsPayout(betAmount: Int, point: Int) -> Int` - Point-based payout
- `processPassLineWin(betAmount:) -> WinResult` - Handle pass line win
- `processPassLineOddsWin(betAmount:point:) -> WinResult` - Handle odds win
- `processPassLineLoss(betAmount:) -> LossResult` - Handle pass line loss
- `processPassLineOddsLoss(betAmount:) -> LossResult` - Handle odds loss

**Delegate Protocol**:
```swift
protocol CrapsPassLineManagerDelegate: AnyObject {
    func passLineWinProcessed(payout: Int, originalBet: Int)
    func passLineOddsWinProcessed(payout: Int, originalBet: Int, point: Int)
    func passLineLossProcessed(lostAmount: Int)
    func passLineOddsLossProcessed(lostAmount: Int)
}
```

**Extracted From**:
- Lines 1511-1571 (handlePassLineWin)
- Lines 1620-1667 (handlePassLineOddsWin)
- Lines 1573-1618 (handlePassLineLoss)
- Lines 1669-1690 (handlePassLineOddsLoss)
- Lines 614-740 (updatePassLineOddsVisibility, odds calculations)

---

### 5. CrapsSpecialBetsManager (~200 lines)

**Purpose**: Manages hardway, horn, and field bets logic

**Responsibilities**:
- Evaluate hardway wins (4 specific combinations)
- Detect hardway losses (7 rolled, or soft way hit)
- Evaluate horn bets (2, 3, 11, 12)
- Calculate horn payouts (30:1, 15:1, 7:1, etc.)
- Evaluate field bets (2-12 with special payouts)
- Calculate field payouts (1:1 or 2:1)

**Key Methods**:
- `evaluateHardwayBets(diceTotal:dice1:dice2:) -> [HardwayResult]`
- `isHardway(total:dice1:dice2:) -> Bool`
- `evaluateHornBets(diceTotal:) -> [HornResult]`
- `getHornBetName(for total: Int) -> String`
- `calculateHornPayout(betAmount:diceTotal:) -> Int`
- `evaluateFieldBet(diceTotal:betAmount:) -> FieldResult`
- `isFieldNumber(_ total: Int) -> Bool`
- `calculateFieldPayout(betAmount:diceTotal:) -> Int`

**Delegate Protocol**:
```swift
protocol CrapsSpecialBetsManagerDelegate: AnyObject {
    func hardwayWinEvaluated(total: Int, payout: Int)
    func hardwayLossEvaluated(total: Int)
    func hornWinEvaluated(hornType: String, payout: Int)
    func hornLossEvaluated()
    func fieldWinEvaluated(payout: Int, isDouble: Bool)
    func fieldLossEvaluated()
}
```

**Result Types**:
```swift
struct HardwayResult {
    let total: Int
    let isWin: Bool
    let payout: Int?
}

struct HornResult {
    let hornType: String // "Horn 2", "Horn 3", etc.
    let payout: Int
}

struct FieldResult {
    let isWin: Bool
    let payout: Int
    let isDoublePayout: Bool // 2:1 for 2 and 12
}
```

**Extracted From**:
- Lines 1692-1757 (handleHardwayBets)
- Lines 1759-1823 (handleHardwayLoss)
- Lines 1825-1857 (handleHornBets, getHornBetName)
- Lines 1887-1917 (field bet logic in handleOtherBets)
- Lines 742-773 (field bet setup)

---

### 6. CrapsSettingsManager (~80 lines)

**Purpose**: Manages game settings persistence and playstyle display

**Responsibilities**:
- Load/save settings from UserDefaults
- Track display preferences (show playstyle)
- Calculate current playstyle based on metrics
- Notify delegate of setting changes

**Key Properties**:
```swift
private(set) var showPlaystyle: Bool
```

**Key Methods**:
- `loadSettings()` - Load from UserDefaults
- `togglePlaystyle()` - Toggle playstyle display
- `savePlaystyleSetting(_ enabled: Bool)` - Persist setting
- `calculatePlaystyle(metrics:) -> String` - Determine playstyle (Conservative, Aggressive, etc.)

**Delegate Protocol**:
```swift
protocol CrapsSettingsManagerDelegate: AnyObject {
    func playstyleSettingDidChange(enabled: Bool)
    func playstyleDidUpdate(style: String)
}
```

**Extracted From**:
- Lines 48, 147-152 (showPlaystyle settings)
- Lines 1071-1175 (calculateCurrentPlaystyle, playstyle logic)

---

### 7. CrapsAnimationManager (~150 lines) - *Optional*

**Purpose**: Consolidate chip animations and coordinate timing

**Responsibilities**:
- Animate winnings from bet to balance
- Animate bet collection (return original bet)
- Animate chips away (losing bets)
- Coordinate animation timing and delays
- Use existing `ChipAnimationHelper` patterns

**Key Methods**:
- `animateWinnings(from control:to balanceView:amount:odds:completion:)`
- `animateBetCollection(from control:to balanceView:amount:completion:)`
- `animateChipsAway(from control:amount:completion:)`
- `coordinateMultipleWins(animations:completion:)`

**Delegate Protocol**:
```swift
protocol CrapsAnimationManagerDelegate: AnyObject {
    func animationDidComplete(type: AnimationType)
    func allAnimationsDidComplete()
}
```

**Extracted From**:
- Lines 1463-1509 (animateWinnings)
- Lines 1233-1277 (animateBetCollection)
- Lines 1710-1717, 1756-1765, 1825-1833, 1868-1879 (various animations)

**Note**: This is optional as animation logic is tightly coupled with UI. Could start without this and add later if needed.

---

## Implementation Phases

### Phase 1: Foundation Managers
**Goal**: Extract core business logic independent of other managers

#### Phase 1.1: CrapsSettingsManager (~80 lines)
- Create `CrapsSettingsManager.swift`
- Extract settings persistence
- Extract playstyle calculation
- Integrate with ViewController
- Add delegate protocol
- Add backward compatibility computed properties

#### Phase 1.2: CrapsSessionManager (~250 lines)
- Create `CrapsSessionManager.swift`
- Extract session lifecycle methods
- Extract metrics tracking
- Extract balance history management
- Extract app lifecycle handling
- Integrate with ViewController
- Add delegate protocol

#### Phase 1.3: CrapsGameStateManager (~200 lines)
- Create `CrapsGameStateManager.swift`
- Extract game phase management
- Extract rolling state logic
- Coordinate with existing `CrapsGame`
- Integrate with ViewController
- Add delegate protocol

---

### Phase 2: Bet & Payout Managers
**Goal**: Extract bet tracking and specialized payout logic

#### Phase 2.1: CrapsBetManager (~200 lines)
- Create `CrapsBetManager.swift`
- Extract bet tracking by type
- Extract concurrent bet counting
- Extract loss chasing detection
- Integrate with ViewController
- Add delegate protocol

#### Phase 2.2: CrapsPassLineManager (~150 lines)
- Create `CrapsPassLineManager.swift`
- Extract pass line win/loss logic
- Extract odds calculations
- Extract odds visibility logic
- Integrate with ViewController
- Add delegate protocol

#### Phase 2.3: CrapsSpecialBetsManager (~200 lines)
- Create `CrapsSpecialBetsManager.swift`
- Extract hardway logic
- Extract horn logic
- Extract field logic
- Integrate with ViewController
- Add delegate protocol

---

### Phase 3: Optional Refinements
**Goal**: Further cleanup and polish

#### Phase 3.1: CrapsAnimationManager (~150 lines) - *Optional*
- Create `CrapsAnimationManager.swift`
- Extract chip animations
- Coordinate animation timing
- Integrate with ViewController

#### Phase 3.2: Code Cleanup
- Remove duplicate code
- Simplify ViewController UI setup
- Add comprehensive comments
- Update documentation

---

## Benefits of Refactoring

### 1. Single Responsibility
Each manager has one clear purpose:
- **Settings** → CrapsSettingsManager
- **Session Tracking** → CrapsSessionManager
- **Game State** → CrapsGameStateManager
- **Bet Tracking** → CrapsBetManager
- **Pass Line Logic** → CrapsPassLineManager
- **Special Bets** → CrapsSpecialBetsManager

### 2. Testability
Managers can be unit tested independently:
```swift
func testHardwayWin() {
    let manager = CrapsSpecialBetsManager()
    let results = manager.evaluateHardwayBets(diceTotal: 8, dice1: 4, dice2: 4)
    XCTAssertTrue(results.first?.isWin == true)
    XCTAssertEqual(results.first?.total, 8)
}
```

### 3. Reusability
Managers can be reused in other contexts:
- Use CrapsSessionManager for analytics dashboard
- Use CrapsSpecialBetsManager for payout calculators
- Use CrapsGameStateManager for game replays

### 4. Maintainability
Changes are now localized:
- Adding new bet validation? → Update CrapsBetManager only
- Changing payout odds? → Update specific manager only
- Adding new metrics? → Update CrapsSessionManager only

### 5. Backward Compatibility
Computed properties in ViewController ensure existing code still works:
```swift
private var sessionId: String? { sessionManager.sessionId }
private var rollCount: Int { sessionManager.rollCount }
private var isRollingEnabled: Bool { gameStateManager.isRollingEnabled }
```

---

## Integration Pattern

### Manager Setup
```swift
private func setupManagers() {
    // Initialize managers in dependency order
    settingsManager = CrapsSettingsManager()
    settingsManager.delegate = self
    settingsManager.loadSettings()

    sessionManager = CrapsSessionManager()
    sessionManager.delegate = self

    gameStateManager = CrapsGameStateManager()
    gameStateManager.delegate = self

    betManager = CrapsBetManager()
    betManager.delegate = self

    passLineManager = CrapsPassLineManager()
    passLineManager.delegate = self

    specialBetsManager = CrapsSpecialBetsManager()
    specialBetsManager.delegate = self
}
```

### Delegate Implementation
```swift
extension CrapsGameplayViewController: CrapsSessionManagerDelegate {
    func sessionDidStart(id: String) {
        // Handle session start
    }

    func metricsDidUpdate(metrics: GameplayMetrics) {
        // Update UI with new metrics
    }

    func rollCountDidChange(count: Int) {
        // Update roll count display
    }
}
```

---

## Remaining Code in ViewController

The ViewController (~1,200 lines) will still handle:
- **UI Management**: View lifecycle, layout, constraints
- **Animation Coordination**: Chip movements, win/loss animations
- **User Interaction**: Tap handlers, button actions, gesture recognizers
- **View Coordination**: Pass line, odds, point stack, hardway, horn, field views
- **Game Flow**: Orchestrating managers to implement complete game logic
- **Dice Rolling UI**: FlipDiceContainer coordination and visual feedback

These responsibilities are appropriate for a ViewController as they require tight coupling with UIKit and view hierarchy.

---

## Key Differences from Blackjack Refactoring

1. **More Complex Bet Types**: Craps has 6+ bet types vs Blackjack's single hand betting
2. **No Deck Manager**: Craps uses dice (simple random), no equivalent to BlackjackDeckManager
3. **Stateless Payout Logic**: Most craps payouts are calculation-based, not state-based
4. **Phase Dependency**: Many bets depend on game phase (come out vs point)
5. **Concurrent Bets**: Craps allows multiple simultaneous bets (pass line + odds + hardways)
6. **Animation Complexity**: Multiple simultaneous win/loss animations for different bet types

---

## Success Metrics

- ✅ Reduce ViewController from 2,071 to ~1,200 lines (42% reduction)
- ✅ Extract ~900 lines into 6 focused managers
- ✅ Each manager has clear, testable responsibilities
- ✅ All existing functionality preserved
- ✅ Backward compatibility via computed properties
- ✅ Improved code maintainability and testability
- ✅ Follow SOLID principles

---

## Migration Notes

### Testing Strategy
1. Unit test each manager independently
2. Integration test manager interactions
3. UI test complete game flows
4. Regression test all bet types and payouts

### Potential Future Managers
If further extraction is desired:
1. **CrapsPointBetManager** - Separate place bet logic from special bets
2. **CrapsAnimationCoordinator** - If animation complexity increases
3. **CrapsPayoutCalculator** - Centralized payout logic across all bet types

---

**Created by**: Claude Code (Anthropic)
**Date**: January 28, 2026
**Branch**: refactor/crapsgameplay
**Based on**: Blackjack refactoring pattern (REFACTORING_SUMMARY.md)
