import XCTest
@testable import hardway_craps

final class CrapsRollOutcomePolicyTests: XCTestCase {

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
