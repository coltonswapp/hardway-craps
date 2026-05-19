import XCTest
@testable import hardway_craps

final class CrapsPassLineManagerTests: XCTestCase {

    private var manager: CrapsPassLineManager!
    private var spy: PassLineManagerDelegateSpy!

    override func setUp() {
        super.setUp()
        manager = CrapsPassLineManager()
        manager.rules = StandardCrapsVariantRules()
        spy = PassLineManagerDelegateSpy()
        manager.delegate = spy
    }

    // MARK: - Pass Line Payout (1:1)

    func testPassLinePayout_10bet() {
        let result = manager.calculatePassLinePayout(betAmount: 10)
        XCTAssertEqual(result.originalBet, 10)
        XCTAssertEqual(result.winnings, 10)
        XCTAssertEqual(result.oddsMultiplier, 1.0)
    }

    func testPassLinePayout_25bet() {
        let result = manager.calculatePassLinePayout(betAmount: 25)
        XCTAssertEqual(result.originalBet, 25)
        XCTAssertEqual(result.winnings, 25)
    }

    func testPassLinePayout_zeroBet() {
        let result = manager.calculatePassLinePayout(betAmount: 0)
        XCTAssertEqual(result.winnings, 0)
    }

    // MARK: - Pass Line Odds Payouts (True Odds)

    func testOddsPayout_point4_10bet() {
        // 2:1 odds → $10 bet wins $20 profit, total return $30
        let result = manager.calculateOddsPayout(betAmount: 10, point: 4)
        XCTAssertEqual(result.originalBet, 10)
        XCTAssertEqual(result.winnings, 30) // 10 + (10 * 2.0)
        XCTAssertEqual(result.oddsMultiplier, 2.0)
    }

    func testOddsPayout_point10_10bet() {
        let result = manager.calculateOddsPayout(betAmount: 10, point: 10)
        XCTAssertEqual(result.winnings, 30)
    }

    func testOddsPayout_point5_10bet() {
        // 3:2 odds → $10 bet wins $15 profit, total return $25
        let result = manager.calculateOddsPayout(betAmount: 10, point: 5)
        XCTAssertEqual(result.winnings, 25) // 10 + (10 * 1.5)
        XCTAssertEqual(result.oddsMultiplier, 1.5)
    }

    func testOddsPayout_point9_20bet() {
        let result = manager.calculateOddsPayout(betAmount: 20, point: 9)
        XCTAssertEqual(result.winnings, 50) // 20 + (20 * 1.5)
    }

    func testOddsPayout_point6_10bet() {
        // 6:5 odds → $10 bet wins $12 profit, total return $22
        let result = manager.calculateOddsPayout(betAmount: 10, point: 6)
        XCTAssertEqual(result.winnings, 22) // 10 + (10 * 1.2)
        XCTAssertEqual(result.oddsMultiplier, 1.2)
    }

    func testOddsPayout_point8_25bet() {
        let result = manager.calculateOddsPayout(betAmount: 25, point: 8)
        XCTAssertEqual(result.winnings, 55) // 25 + (25 * 1.2)
    }

    // MARK: - Don't Pass Odds Payouts (Lay Odds)

    func testDontPassOddsPayout_point4_10bet() {
        // Lay 1:2 → $10 bet wins $5 profit, total $15
        let result = manager.calculateDontPassOddsPayout(betAmount: 10, point: 4)
        XCTAssertEqual(result.originalBet, 10)
        XCTAssertEqual(result.winnings, 15) // 10 + (10 * 0.5)
        XCTAssertEqual(result.oddsMultiplier, 0.5)
    }

    func testDontPassOddsPayout_point5_30bet() {
        // Lay 2:3 → $30 bet wins $20 profit, total $50
        let result = manager.calculateDontPassOddsPayout(betAmount: 30, point: 5)
        XCTAssertEqual(result.winnings, 50) // 30 + Int(30 * 2/3) = 30 + 20
    }

    func testDontPassOddsPayout_point6_30bet() {
        // Lay 5:6 → $30 bet wins $25 profit, total $55
        let result = manager.calculateDontPassOddsPayout(betAmount: 30, point: 6)
        XCTAssertEqual(result.winnings, 55) // 30 + Int(30 * 5/6) = 30 + 25
    }

    // MARK: - Process Methods (Delegate Notifications)

    func testProcessPassLineWin_notifiesDelegate() {
        let result = manager.processPassLineWin(betAmount: 10)
        XCTAssertEqual(result.winnings, 10)
        XCTAssertEqual(spy.passLineWins.count, 1)
        XCTAssertEqual(spy.passLineWins.first?.originalBet, 10)
        XCTAssertEqual(spy.passLineWins.first?.winnings, 10)
    }

    func testProcessPassLineOddsWin_notifiesDelegate() {
        let result = manager.processPassLineOddsWin(betAmount: 10, point: 4)
        XCTAssertEqual(result.winnings, 30)
        XCTAssertEqual(spy.passLineOddsWins.count, 1)
        XCTAssertEqual(spy.passLineOddsWins.first?.point, 4)
        XCTAssertEqual(spy.passLineOddsWins.first?.multiplier, 2.0)
    }

    func testProcessPassLineLoss_notifiesDelegate() {
        manager.processPassLineLoss(betAmount: 15)
        XCTAssertEqual(spy.passLineLosses, [15])
    }

    func testProcessPassLineOddsLoss_notifiesDelegate() {
        manager.processPassLineOddsLoss(betAmount: 20)
        XCTAssertEqual(spy.passLineOddsLosses, [20])
    }

    // MARK: - shouldEnableOdds

    func testShouldEnableOdds_pointPhaseWithBet_true() {
        XCTAssertTrue(manager.shouldEnableOdds(isPointPhase: true, hasPassLineBet: true))
    }

    func testShouldEnableOdds_comeOutPhase_false() {
        XCTAssertFalse(manager.shouldEnableOdds(isPointPhase: false, hasPassLineBet: true))
    }

    func testShouldEnableOdds_noBet_false() {
        XCTAssertFalse(manager.shouldEnableOdds(isPointPhase: true, hasPassLineBet: false))
    }

    // MARK: - Crapless Variant Odds

    func testCrapless_oddsPayout_point2() {
        manager.rules = CraplessCrapsVariantRules()
        // 6:1 odds → $10 bet wins $60 profit, total return $70
        let result = manager.calculateOddsPayout(betAmount: 10, point: 2)
        XCTAssertEqual(result.winnings, 70)
        XCTAssertEqual(result.oddsMultiplier, 6.0)
    }

    func testCrapless_dontPassOddsPayout_point2() {
        manager.rules = CraplessCrapsVariantRules()
        // Lay 1:6 → $60 bet wins $10 profit, total $70
        let result = manager.calculateDontPassOddsPayout(betAmount: 60, point: 2)
        XCTAssertEqual(result.winnings, 70) // 60 + Int(60 * 1/6) = 60 + 10
    }
}
