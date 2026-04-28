import XCTest
@testable import hardway_craps

final class CrapsRollOutcomePolicyTests: XCTestCase {

    // MARK: - shouldApplyRebet

    func testRebet_passLineWin_alwaysTrue() {
        XCTAssertTrue(CrapsRollOutcomePolicy.shouldApplyRebet(
            event: .passLineWin,
            passLineBetAmountBeforeOutcome: 0,
            dontPassBetAmountBeforeOutcome: 0,
            dontPassDidLose: false,
            didDontPassWin: false,
            currentDontPassBetAmount: 0
        ))
    }

    func testRebet_passLineLoss_alwaysTrue() {
        XCTAssertTrue(CrapsRollOutcomePolicy.shouldApplyRebet(
            event: .passLineLoss,
            passLineBetAmountBeforeOutcome: 0,
            dontPassBetAmountBeforeOutcome: 0,
            dontPassDidLose: false,
            didDontPassWin: false,
            currentDontPassBetAmount: 0
        ))
    }

    func testRebet_pointMade_withPassLineBet_true() {
        XCTAssertTrue(CrapsRollOutcomePolicy.shouldApplyRebet(
            event: .pointMade,
            passLineBetAmountBeforeOutcome: 10,
            dontPassBetAmountBeforeOutcome: 0,
            dontPassDidLose: false,
            didDontPassWin: false,
            currentDontPassBetAmount: 0
        ))
    }

    func testRebet_pointMade_noBets_false() {
        XCTAssertFalse(CrapsRollOutcomePolicy.shouldApplyRebet(
            event: .pointMade,
            passLineBetAmountBeforeOutcome: 0,
            dontPassBetAmountBeforeOutcome: 0,
            dontPassDidLose: false,
            didDontPassWin: false,
            currentDontPassBetAmount: 0
        ))
    }

    func testRebet_sevenOut_withPassLineBet_true() {
        XCTAssertTrue(CrapsRollOutcomePolicy.shouldApplyRebet(
            event: .sevenOut,
            passLineBetAmountBeforeOutcome: 10,
            dontPassBetAmountBeforeOutcome: 0,
            dontPassDidLose: false,
            didDontPassWin: false,
            currentDontPassBetAmount: 0
        ))
    }

    func testRebet_sevenOut_withDontPassWin_true() {
        XCTAssertTrue(CrapsRollOutcomePolicy.shouldApplyRebet(
            event: .sevenOut,
            passLineBetAmountBeforeOutcome: 0,
            dontPassBetAmountBeforeOutcome: 10,
            dontPassDidLose: false,
            didDontPassWin: true,
            currentDontPassBetAmount: 0
        ))
    }

    func testRebet_pointEstablished_noDontPassOutcome_false() {
        XCTAssertFalse(CrapsRollOutcomePolicy.shouldApplyRebet(
            event: .pointEstablished(6),
            passLineBetAmountBeforeOutcome: 10,
            dontPassBetAmountBeforeOutcome: 0,
            dontPassDidLose: false,
            didDontPassWin: false,
            currentDontPassBetAmount: 0
        ))
    }

    func testRebet_pointEstablished_dontPassDidLose_true() {
        XCTAssertTrue(CrapsRollOutcomePolicy.shouldApplyRebet(
            event: .pointEstablished(6),
            passLineBetAmountBeforeOutcome: 10,
            dontPassBetAmountBeforeOutcome: 0,
            dontPassDidLose: true,
            didDontPassWin: false,
            currentDontPassBetAmount: 10
        ))
    }

    func testRebet_none_noOutcome_false() {
        XCTAssertFalse(CrapsRollOutcomePolicy.shouldApplyRebet(
            event: .none,
            passLineBetAmountBeforeOutcome: 10,
            dontPassBetAmountBeforeOutcome: 0,
            dontPassDidLose: false,
            didDontPassWin: false,
            currentDontPassBetAmount: 0
        ))
    }

    // MARK: - rollingStateUpdateDelay

    func testDelay_withWinningBets_usesWinDelay() {
        let delay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: .pointMade, hasWinningBets: true, dontPassDidLose: false, applySpeedMultiplier: false
        )
        XCTAssertEqual(delay, 1.875, accuracy: 0.001)
    }

    func testDelay_sevenOut_noWins() {
        let delay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: .sevenOut, hasWinningBets: false, dontPassDidLose: false, applySpeedMultiplier: false
        )
        XCTAssertEqual(delay, 2.0, accuracy: 0.001)
    }

    func testDelay_passLineLoss_noWins() {
        let delay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: .passLineLoss, hasWinningBets: false, dontPassDidLose: false, applySpeedMultiplier: false
        )
        XCTAssertEqual(delay, 2.0, accuracy: 0.001)
    }

    func testDelay_pointMade_noDontPassLoss() {
        let delay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: .pointMade, hasWinningBets: false, dontPassDidLose: false, applySpeedMultiplier: false
        )
        XCTAssertEqual(delay, 1.5, accuracy: 0.001)
    }

    func testDelay_pointMade_withDontPassLoss() {
        let delay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: .pointMade, hasWinningBets: false, dontPassDidLose: true, applySpeedMultiplier: false
        )
        XCTAssertEqual(delay, 2.0, accuracy: 0.001)
    }

    func testDelay_passLineWin_noDontPassLoss_fast() {
        let delay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: .passLineWin, hasWinningBets: false, dontPassDidLose: false, applySpeedMultiplier: false
        )
        XCTAssertEqual(delay, 0.1, accuracy: 0.001)
    }

    func testDelay_passLineWin_withDontPassLoss() {
        let delay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: .passLineWin, hasWinningBets: false, dontPassDidLose: true, applySpeedMultiplier: false
        )
        XCTAssertEqual(delay, 2.0, accuracy: 0.001)
    }

    func testDelay_pointEstablished_fast() {
        let delay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: .pointEstablished(6), hasWinningBets: false, dontPassDidLose: false, applySpeedMultiplier: false
        )
        XCTAssertEqual(delay, 0.1, accuracy: 0.001)
    }

    func testDelay_none_fast() {
        let delay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: .none, hasWinningBets: false, dontPassDidLose: false, applySpeedMultiplier: false
        )
        XCTAssertEqual(delay, 0.1, accuracy: 0.001)
    }
}
