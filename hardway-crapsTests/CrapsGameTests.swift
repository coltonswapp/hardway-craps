import XCTest
@testable import hardway_craps

final class CrapsGameTests: XCTestCase {

    // MARK: - Standard Craps: Come-Out Roll

    func testStandard_comeOut7_passLineWin() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        XCTAssertEqual(game.processRoll(7), .passLineWin)
        XCTAssertFalse(game.isPointPhase)
    }

    func testStandard_comeOut11_passLineWin() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        XCTAssertEqual(game.processRoll(11), .passLineWin)
    }

    func testStandard_comeOut2_passLineLoss() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        XCTAssertEqual(game.processRoll(2), .passLineLoss)
    }

    func testStandard_comeOut3_passLineLoss() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        XCTAssertEqual(game.processRoll(3), .passLineLoss)
    }

    func testStandard_comeOut12_passLineLoss() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        XCTAssertEqual(game.processRoll(12), .passLineLoss)
    }

    func testStandard_comeOutPointNumbers_establishPoint() {
        for point in [4, 5, 6, 8, 9, 10] {
            let game = CrapsGame(rules: StandardCrapsVariantRules())
            XCTAssertEqual(game.processRoll(point), .pointEstablished(point), "Rolling \(point) should establish point")
            XCTAssertTrue(game.isPointPhase)
            XCTAssertEqual(game.currentPoint, point)
        }
    }

    // MARK: - Standard Craps: Point Phase

    func testStandard_pointMade() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        _ = game.processRoll(8) // establish point
        XCTAssertEqual(game.processRoll(8), .pointMade)
        XCTAssertFalse(game.isPointPhase, "Game should return to come-out after point made")
    }

    func testStandard_sevenOut() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        _ = game.processRoll(4) // establish point on 4
        XCTAssertEqual(game.processRoll(7), .sevenOut)
        XCTAssertFalse(game.isPointPhase, "Game should return to come-out after seven-out")
    }

    func testStandard_pointPhase_irrelevantRoll_noEvent() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        _ = game.processRoll(6) // establish 6
        XCTAssertEqual(game.processRoll(5), .none, "Rolling a non-point, non-7 number should be .none")
        XCTAssertTrue(game.isPointPhase)
        XCTAssertEqual(game.currentPoint, 6)
    }

    func testStandard_multipleRollsBeforePointMade() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        _ = game.processRoll(9) // establish 9
        XCTAssertEqual(game.processRoll(4), .none)
        XCTAssertEqual(game.processRoll(8), .none)
        XCTAssertEqual(game.processRoll(11), .none)
        XCTAssertEqual(game.processRoll(3), .none)
        XCTAssertEqual(game.processRoll(9), .pointMade)
    }

    // MARK: - Standard Craps: Full Game Sequence

    func testStandard_fullSequence_establishPointThenWin() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        let passLineManager = CrapsPassLineManager()
        passLineManager.rules = StandardCrapsVariantRules()
        let bet = 10

        XCTAssertEqual(game.processRoll(6), .pointEstablished(6))
        XCTAssertEqual(game.processRoll(6), .pointMade)
        XCTAssertFalse(game.isPointPhase)

        let payout = passLineManager.calculatePassLinePayout(betAmount: bet)
        XCTAssertEqual(payout.originalBet, 10)
        XCTAssertEqual(payout.winnings, 10, "Pass line is 1:1")
    }

    func testStandard_fullSequence_establishPointThenSevenOut() {
        let game = CrapsGame(rules: StandardCrapsVariantRules())
        let bet = 10

        XCTAssertEqual(game.processRoll(4), .pointEstablished(4))
        XCTAssertEqual(game.processRoll(5), .none)
        XCTAssertEqual(game.processRoll(7), .sevenOut)

        // Player loses the $10 pass line bet
        XCTAssertFalse(game.isPointPhase)
        _ = bet // bet is lost, balance decreases by bet amount
    }

    // MARK: - Crapless Craps: Come-Out Roll

    func testCrapless_comeOut7_passLineWin() {
        let game = CrapsGame(rules: CraplessCrapsVariantRules())
        XCTAssertEqual(game.processRoll(7), .passLineWin)
    }

    func testCrapless_comeOut2_establishesPoint() {
        let game = CrapsGame(rules: CraplessCrapsVariantRules())
        XCTAssertEqual(game.processRoll(2), .pointEstablished(2))
        XCTAssertEqual(game.currentPoint, 2)
    }

    func testCrapless_comeOut3_establishesPoint() {
        let game = CrapsGame(rules: CraplessCrapsVariantRules())
        XCTAssertEqual(game.processRoll(3), .pointEstablished(3))
    }

    func testCrapless_comeOut11_establishesPoint() {
        let game = CrapsGame(rules: CraplessCrapsVariantRules())
        XCTAssertEqual(game.processRoll(11), .pointEstablished(11))
    }

    func testCrapless_comeOut12_establishesPoint() {
        let game = CrapsGame(rules: CraplessCrapsVariantRules())
        XCTAssertEqual(game.processRoll(12), .pointEstablished(12))
    }

    func testCrapless_allPointNumbers() {
        let rules = CraplessCrapsVariantRules()
        for point in [2, 3, 4, 5, 6, 8, 9, 10, 11, 12] {
            let game = CrapsGame(rules: rules)
            XCTAssertEqual(game.processRoll(point), .pointEstablished(point))
        }
    }

    func testCrapless_pointMadeOn2() {
        let game = CrapsGame(rules: CraplessCrapsVariantRules())
        _ = game.processRoll(2)
        XCTAssertEqual(game.processRoll(2), .pointMade)
    }

    func testCrapless_sevenOutOnPoint12() {
        let game = CrapsGame(rules: CraplessCrapsVariantRules())
        _ = game.processRoll(12)
        XCTAssertEqual(game.processRoll(7), .sevenOut)
    }

    // MARK: - Rule Switching

    func testUpdateRules_invalidPointResetsPhase() {
        let game = CrapsGame(rules: CraplessCrapsVariantRules())
        _ = game.processRoll(3) // point = 3, valid in crapless
        XCTAssertEqual(game.currentPoint, 3)

        game.updateRules(StandardCrapsVariantRules()) // 3 is not a valid point in standard
        XCTAssertFalse(game.isPointPhase, "Should reset to come-out when point is invalid in new rules")
    }

    func testUpdateRules_validPointKeepsPhase() {
        let game = CrapsGame(rules: CraplessCrapsVariantRules())
        _ = game.processRoll(6) // point = 6, valid in both variants
        XCTAssertEqual(game.currentPoint, 6)

        game.updateRules(StandardCrapsVariantRules())
        XCTAssertTrue(game.isPointPhase, "Point 6 is valid in standard too")
        XCTAssertEqual(game.currentPoint, 6)
    }

    // MARK: - Factory

    func testFactory_standardVariant() {
        let rules = CrapsVariantRulesFactory.makeRules(for: .standard)
        XCTAssertEqual(rules.variant, .standard)
    }

    func testFactory_craplessVariant() {
        let rules = CrapsVariantRulesFactory.makeRules(for: .crapless)
        XCTAssertEqual(rules.variant, .crapless)
    }

    // MARK: - CrapsGameStateManager Delegate Notifications

    func testGameStateManager_pointEstablished_notifiesDelegate() {
        let manager = CrapsGameStateManager(variant: .standard)
        let spy = GameStateManagerDelegateSpy()
        manager.delegate = spy

        _ = manager.processRoll(8)
        XCTAssertEqual(spy.pointsEstablished, [8])
        XCTAssertEqual(spy.phaseChanges.count, 1)
    }

    func testGameStateManager_sevenOut_notifiesDelegate() {
        let manager = CrapsGameStateManager(variant: .standard)
        let spy = GameStateManagerDelegateSpy()
        manager.delegate = spy

        _ = manager.processRoll(4) // establish
        _ = manager.processRoll(7) // seven out
        XCTAssertEqual(spy.sevenOutCount, 1)
    }

    func testGameStateManager_pointMade_notifiesDelegate() {
        let manager = CrapsGameStateManager(variant: .standard)
        let spy = GameStateManagerDelegateSpy()
        manager.delegate = spy

        _ = manager.processRoll(10) // establish
        _ = manager.processRoll(10) // point made
        XCTAssertEqual(spy.pointsMade, [10])
    }
}
