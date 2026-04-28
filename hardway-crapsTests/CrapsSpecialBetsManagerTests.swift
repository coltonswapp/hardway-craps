import XCTest
@testable import hardway_craps

final class CrapsSpecialBetsManagerTests: XCTestCase {

    private var manager: CrapsSpecialBetsManager!
    private var spy: SpecialBetsDelegateSpy!

    override func setUp() {
        super.setUp()
        manager = CrapsSpecialBetsManager()
        manager.rules = StandardCrapsVariantRules()
        spy = SpecialBetsDelegateSpy()
        manager.delegate = spy
    }

    // MARK: - Hardway: isHardway

    func testIsHardway_sameDice_true() {
        XCTAssertTrue(manager.isHardway(die1: 3, die2: 3))
        XCTAssertTrue(manager.isHardway(die1: 4, die2: 4))
    }

    func testIsHardway_differentDice_false() {
        XCTAssertFalse(manager.isHardway(die1: 2, die2: 4))
    }

    // MARK: - Hardway: evaluateHardwayBet

    func testHardway_hard6Win_9to1() {
        let result = manager.evaluateHardwayBet(die1: 3, die2: 3, hardwayDieValue: 3, betAmount: 10, oddsString: "9:1")
        XCTAssertTrue(result.isWin)
        XCTAssertFalse(result.isSoftWayLoss)
        XCTAssertEqual(result.winAmount, 100) // 10 * 10.0
        XCTAssertEqual(result.oddsMultiplier, 10.0)
        XCTAssertEqual(spy.hardwayWins.count, 1)
    }

    func testHardway_hard8Win_9to1() {
        let result = manager.evaluateHardwayBet(die1: 4, die2: 4, hardwayDieValue: 4, betAmount: 5, oddsString: "9:1")
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 50) // 5 * 10.0
    }

    func testHardway_hard4Win_7to1() {
        let result = manager.evaluateHardwayBet(die1: 2, die2: 2, hardwayDieValue: 2, betAmount: 10, oddsString: "7:1")
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 80) // 10 * 8.0
        XCTAssertEqual(result.oddsMultiplier, 8.0)
    }

    func testHardway_hard10Win_7to1() {
        let result = manager.evaluateHardwayBet(die1: 5, die2: 5, hardwayDieValue: 5, betAmount: 10, oddsString: "7:1")
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 80)
    }

    func testHardway_softWayLoss() {
        // Rolled 4+2=6 but hardway 6 requires 3+3
        let result = manager.evaluateHardwayBet(die1: 4, die2: 2, hardwayDieValue: 3, betAmount: 10, oddsString: "9:1")
        XCTAssertFalse(result.isWin)
        XCTAssertTrue(result.isSoftWayLoss)
        XCTAssertNil(result.winAmount)
        XCTAssertEqual(spy.hardwayLosses.count, 1)
        XCTAssertTrue(spy.hardwayLosses.first!.isSoftWay)
    }

    func testHardway_noAction() {
        // Rolled 5+1=6 but hardway is for 4 (2+2=4)
        let result = manager.evaluateHardwayBet(die1: 5, die2: 1, hardwayDieValue: 2, betAmount: 10, oddsString: "7:1")
        XCTAssertFalse(result.isWin)
        XCTAssertFalse(result.isSoftWayLoss)
    }

    // MARK: - Horn Bets

    func testHornBet_snakeEyes_30to1() {
        let result = manager.evaluateHornBet(die1: 1, die2: 1, hornDieValue1: 1, hornDieValue2: 1, betAmount: 10, oddsString: "30:1")
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 310) // 10 * 31.0
        XCTAssertEqual(result.hornName, "Snake Eyes")
        XCTAssertEqual(spy.hornWins.count, 1)
    }

    func testHornBet_boxcars_30to1() {
        let result = manager.evaluateHornBet(die1: 6, die2: 6, hornDieValue1: 6, hornDieValue2: 6, betAmount: 5, oddsString: "30:1")
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 155) // 5 * 31.0
        XCTAssertEqual(result.hornName, "Boxcars")
    }

    func testHornBet_aceDeuce_15to1() {
        let result = manager.evaluateHornBet(die1: 1, die2: 2, hornDieValue1: 1, hornDieValue2: 2, betAmount: 10, oddsString: "15:1")
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 160) // 10 * 16.0
        XCTAssertEqual(result.hornName, "Ace-Deuce")
    }

    func testHornBet_reversedDiceOrder_stillWins() {
        let result = manager.evaluateHornBet(die1: 2, die2: 1, hornDieValue1: 1, hornDieValue2: 2, betAmount: 10, oddsString: "15:1")
        XCTAssertTrue(result.isWin)
    }

    func testHornBet_noMatch_loses() {
        let result = manager.evaluateHornBet(die1: 3, die2: 4, hornDieValue1: 1, hornDieValue2: 1, betAmount: 10, oddsString: "30:1")
        XCTAssertFalse(result.isWin)
        XCTAssertNil(result.winAmount)
    }

    // MARK: - Horn Bet Names

    func testHornBetName_snakeEyes() {
        XCTAssertEqual(manager.getHornBetName(dieValue1: 1, dieValue2: 1), "Snake Eyes")
    }

    func testHornBetName_boxcars() {
        XCTAssertEqual(manager.getHornBetName(dieValue1: 6, dieValue2: 6), "Boxcars")
    }

    func testHornBetName_aceDeuce() {
        XCTAssertEqual(manager.getHornBetName(dieValue1: 1, dieValue2: 2), "Ace-Deuce")
    }

    func testHornBetName_fiveSix() {
        XCTAssertEqual(manager.getHornBetName(dieValue1: 5, dieValue2: 6), "Five-Six")
    }

    func testHornBetName_generic() {
        XCTAssertEqual(manager.getHornBetName(dieValue1: 3, dieValue2: 3), "Horn Bet")
    }

    // MARK: - Any Horn

    func testAnyHorn_snakeEyes_quarterBetAt31x() {
        let result = manager.evaluateAnyHornBet(die1: 1, die2: 1, betAmount: 40)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isWin)
        // quarterBet = 40/4 = 10, winAmount = 10 * 31 = 310
        XCTAssertEqual(result!.winAmount, 310)
        XCTAssertEqual(result!.hornName, "Snake Eyes")
    }

    func testAnyHorn_boxcars_quarterBetAt31x() {
        let result = manager.evaluateAnyHornBet(die1: 6, die2: 6, betAmount: 20)
        XCTAssertNotNil(result)
        // quarterBet = 20/4 = 5, winAmount = 5 * 31 = 155
        XCTAssertEqual(result!.winAmount, 155)
    }

    func testAnyHorn_aceDeuce_quarterBetAt16x() {
        let result = manager.evaluateAnyHornBet(die1: 1, die2: 2, betAmount: 40)
        XCTAssertNotNil(result)
        // quarterBet = 40/4 = 10, winAmount = 10 * 16 = 160
        XCTAssertEqual(result!.winAmount, 160)
        XCTAssertEqual(result!.hornName, "Ace-Deuce")
    }

    func testAnyHorn_eleven_quarterBetAt16x() {
        let result = manager.evaluateAnyHornBet(die1: 5, die2: 6, betAmount: 40)
        XCTAssertNotNil(result)
        // quarterBet = 40/4 = 10, winAmount = 10 * 16 = 160
        XCTAssertEqual(result!.winAmount, 160)
        XCTAssertEqual(result!.hornName, "Eleven")
    }

    func testAnyHorn_nonHornNumber_returnsNil() {
        let result = manager.evaluateAnyHornBet(die1: 3, die2: 4, betAmount: 40)
        XCTAssertNil(result)
    }

    // MARK: - C & E: Craps Zone

    func testCAndECrapsZone_crapsNumber_wins() {
        for total in [2, 3, 12] {
            let result = manager.evaluateCAndECrapsZone(total: total, betAmount: 10)
            XCTAssertTrue(result.isWin, "Total \(total) should win craps zone")
            XCTAssertEqual(result.profitDisplayAmount, 70, "7:1 profit on $10 for total \(total)")
            XCTAssertEqual(result.totalReturn, 80) // 10 + 70
        }
    }

    func testCAndECrapsZone_nonCraps_loses() {
        let result = manager.evaluateCAndECrapsZone(total: 7, betAmount: 10)
        XCTAssertFalse(result.isWin)
        XCTAssertEqual(result.totalReturn, 0)
    }

    func testCAndECrapsZone_zeroBet() {
        let result = manager.evaluateCAndECrapsZone(total: 2, betAmount: 0)
        XCTAssertFalse(result.isWin)
    }

    // MARK: - C & E: Eleven Zone

    func testCAndEElevenZone_eleven_wins() {
        let result = manager.evaluateCAndEElevenZone(total: 11, betAmount: 10)
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.profitDisplayAmount, 150) // 15:1 profit
        XCTAssertEqual(result.totalReturn, 160) // 10 + 150
    }

    func testCAndEElevenZone_notEleven_loses() {
        let result = manager.evaluateCAndEElevenZone(total: 7, betAmount: 10)
        XCTAssertFalse(result.isWin)
    }

    // MARK: - C & E: Middle Split Zone

    func testCAndEMiddleSplit_crapsNumber_halfOnCraps() {
        // $10 bet → craps stake = 5, eleven stake = 5
        // Craps wins: totalReturn = 8 * 5 = 40, profit = 40 - 10 = 30
        let result = manager.evaluateCAndEMiddleSplitZone(total: 2, betAmount: 10)
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.totalReturn, 40)
        XCTAssertEqual(result.profitDisplayAmount, 30)
    }

    func testCAndEMiddleSplit_eleven_halfOnEleven() {
        // $10 bet → craps stake = 5, eleven stake = 5
        // Eleven wins: totalReturn = 16 * 5 = 80, profit = 80 - 10 = 70
        let result = manager.evaluateCAndEMiddleSplitZone(total: 11, betAmount: 10)
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.totalReturn, 80)
        XCTAssertEqual(result.profitDisplayAmount, 70)
    }

    func testCAndEMiddleSplit_otherNumber_loses() {
        let result = manager.evaluateCAndEMiddleSplitZone(total: 7, betAmount: 10)
        XCTAssertFalse(result.isWin)
        XCTAssertEqual(result.totalReturn, 0)
    }

    func testCAndEMiddleSplit_zeroBet() {
        let result = manager.evaluateCAndEMiddleSplitZone(total: 2, betAmount: 0)
        XCTAssertFalse(result.isWin)
    }

    // MARK: - Field Bets

    func testIsFieldNumber() {
        let fieldNumbers = [2, 3, 4, 9, 10, 11, 12]
        let nonFieldNumbers = [5, 6, 7, 8]
        for n in fieldNumbers {
            XCTAssertTrue(manager.isFieldNumber(n), "\(n) should be a field number")
        }
        for n in nonFieldNumbers {
            XCTAssertFalse(manager.isFieldNumber(n), "\(n) should not be a field number")
        }
    }

    func testFieldBet_12_pays3x() {
        let result = manager.evaluateFieldBet(total: 12, betAmount: 10)
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 30) // 10 * 3.0
        XCTAssertEqual(result.oddsMultiplier, 3.0)
        XCTAssertEqual(spy.fieldWins.count, 1)
    }

    func testFieldBet_2_pays2x() {
        let result = manager.evaluateFieldBet(total: 2, betAmount: 10)
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 20) // 10 * 2.0
        XCTAssertEqual(result.oddsMultiplier, 2.0)
    }

    func testFieldBet_3_pays1x() {
        let result = manager.evaluateFieldBet(total: 3, betAmount: 10)
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 10)
    }

    func testFieldBet_9_pays1x() {
        let result = manager.evaluateFieldBet(total: 9, betAmount: 25)
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 25)
    }

    func testFieldBet_7_loses() {
        let result = manager.evaluateFieldBet(total: 7, betAmount: 10)
        XCTAssertFalse(result.isWin)
        XCTAssertEqual(result.winAmount, 0)
    }

    func testFieldBet_6_loses() {
        let result = manager.evaluateFieldBet(total: 6, betAmount: 10)
        XCTAssertFalse(result.isWin)
    }

    func testCalculateFieldPayout_convenienceMethod() {
        XCTAssertEqual(manager.calculateFieldPayout(total: 12, betAmount: 10), 30)
        XCTAssertEqual(manager.calculateFieldPayout(total: 7, betAmount: 10), 0)
    }

    // MARK: - Don't Pass: Come-Out

    func testDontPass_comeOut_2_wins() {
        let result = manager.evaluateDontPassComeOutRoll(total: 2, betAmount: 10)
        XCTAssertTrue(result.isWin)
        XCTAssertFalse(result.isPush)
        XCTAssertEqual(result.winAmount, 10) // 1:1
        XCTAssertEqual(spy.dontPassWins.count, 1)
    }

    func testDontPass_comeOut_3_wins() {
        let result = manager.evaluateDontPassComeOutRoll(total: 3, betAmount: 10)
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 10)
    }

    func testDontPass_comeOut_12_push() {
        let result = manager.evaluateDontPassComeOutRoll(total: 12, betAmount: 10)
        XCTAssertFalse(result.isWin)
        XCTAssertTrue(result.isPush)
        XCTAssertEqual(result.winAmount, 0)
        XCTAssertEqual(spy.dontPassPushes.count, 1)
    }

    func testDontPass_comeOut_7_loses() {
        let result = manager.evaluateDontPassComeOutRoll(total: 7, betAmount: 10)
        XCTAssertFalse(result.isWin)
        XCTAssertFalse(result.isPush)
        XCTAssertEqual(result.winAmount, 0)
    }

    func testDontPass_comeOut_11_loses() {
        let result = manager.evaluateDontPassComeOutRoll(total: 11, betAmount: 10)
        XCTAssertFalse(result.isWin)
        XCTAssertFalse(result.isPush)
    }

    func testDontPass_comeOut_pointNumber_noAction() {
        let result = manager.evaluateDontPassComeOutRoll(total: 6, betAmount: 10)
        XCTAssertFalse(result.isWin)
        XCTAssertFalse(result.isPush)
        XCTAssertEqual(result.winAmount, 0)
    }

    // MARK: - Don't Pass: Point Phase

    func testDontPass_pointPhase_7_wins() {
        let result = manager.evaluateDontPassPointPhase(total: 7, point: 6, betAmount: 10)
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 10)
        XCTAssertEqual(spy.dontPassWins.count, 1)
        XCTAssertTrue(spy.dontPassWins.first!.isPointPhase)
    }

    func testDontPass_pointPhase_pointHit_loses() {
        let result = manager.evaluateDontPassPointPhase(total: 6, point: 6, betAmount: 10)
        XCTAssertFalse(result.isWin)
        XCTAssertEqual(result.winAmount, 0)
    }

    func testDontPass_pointPhase_otherNumber_noAction() {
        let result = manager.evaluateDontPassPointPhase(total: 5, point: 6, betAmount: 10)
        XCTAssertFalse(result.isWin)
        XCTAssertEqual(result.winAmount, 0)
    }

    // MARK: - Make Em Bets

    func testMakeEm_newNumberHit_progressTracked() {
        let result = manager.evaluateMakeEmBet(
            total: 4, betName: "Small", targetNumbers: [4, 5, 6],
            hitNumbers: [], betAmount: 10, oddsString: "34:1"
        )
        XCTAssertFalse(result.isWin)
        XCTAssertTrue(result.isNewNumber)
        XCTAssertEqual(result.hitNumbers, [4])
        XCTAssertEqual(spy.makeEmHits.count, 1)
    }

    func testMakeEm_duplicateNumber_notNew() {
        let result = manager.evaluateMakeEmBet(
            total: 4, betName: "Small", targetNumbers: [4, 5, 6],
            hitNumbers: [4], betAmount: 10, oddsString: "34:1"
        )
        XCTAssertFalse(result.isWin)
        XCTAssertFalse(result.isNewNumber)
    }

    func testMakeEm_allNumbersHit_wins_34to1() {
        let result = manager.evaluateMakeEmBet(
            total: 6, betName: "Small", targetNumbers: [4, 5, 6],
            hitNumbers: [4, 5], betAmount: 10, oddsString: "34:1"
        )
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 350) // 10 * 35.0
        XCTAssertEqual(result.oddsMultiplier, 35.0)
        XCTAssertEqual(spy.makeEmWins.count, 1)
    }

    func testMakeEm_allNumbersHit_wins_175to1() {
        let result = manager.evaluateMakeEmBet(
            total: 10, betName: "All", targetNumbers: [4, 5, 6, 8, 9, 10],
            hitNumbers: [4, 5, 6, 8, 9], betAmount: 10, oddsString: "175:1"
        )
        XCTAssertTrue(result.isWin)
        XCTAssertEqual(result.winAmount, 1760) // 10 * 176.0
    }

    func testMakeEm_irrelevantRoll_noAction() {
        let result = manager.evaluateMakeEmBet(
            total: 7, betName: "Small", targetNumbers: [4, 5, 6],
            hitNumbers: [4], betAmount: 10, oddsString: "34:1"
        )
        XCTAssertFalse(result.isWin)
        XCTAssertFalse(result.isNewNumber)
        XCTAssertEqual(result.hitNumbers, [4])
    }
}
