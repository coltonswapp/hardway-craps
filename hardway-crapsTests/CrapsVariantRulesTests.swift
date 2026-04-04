import XCTest
@testable import hardway_craps

final class CrapsVariantRulesTests: XCTestCase {

    // MARK: - Standard: Point Numbers

    func testStandard_pointNumbers() {
        let rules = StandardCrapsVariantRules()
        XCTAssertEqual(rules.pointNumbers, [4, 5, 6, 8, 9, 10])
        XCTAssertEqual(rules.orderedPointNumbers, [4, 5, 6, 8, 9, 10])
    }

    // MARK: - Standard: Pass Line Come-Out Events

    func testStandard_passLineComeOut_allTotals() {
        let rules = StandardCrapsVariantRules()
        let expected: [Int: GameEvent] = [
            2: .passLineLoss, 3: .passLineLoss, 12: .passLineLoss,
            7: .passLineWin, 11: .passLineWin,
            4: .pointEstablished(4), 5: .pointEstablished(5), 6: .pointEstablished(6),
            8: .pointEstablished(8), 9: .pointEstablished(9), 10: .pointEstablished(10),
        ]
        for (total, event) in expected {
            XCTAssertEqual(rules.passLineComeOutEvent(for: total), event, "Total \(total)")
        }
    }

    // MARK: - Standard: Come Bet Actions

    func testStandard_comeBetComeOut() {
        let rules = StandardCrapsVariantRules()
        XCTAssertEqual(rules.comeBetComeOutAction(for: 7), .win)
        XCTAssertEqual(rules.comeBetComeOutAction(for: 11), .win)
        XCTAssertEqual(rules.comeBetComeOutAction(for: 2), .lose)
        XCTAssertEqual(rules.comeBetComeOutAction(for: 3), .lose)
        XCTAssertEqual(rules.comeBetComeOutAction(for: 12), .lose)
        XCTAssertEqual(rules.comeBetComeOutAction(for: 6), .establishPoint)
    }

    // MARK: - Standard: Don't Pass Come-Out Actions

    func testStandard_dontPassComeOut() {
        let rules = StandardCrapsVariantRules()
        XCTAssertEqual(rules.dontPassComeOutAction(for: 2), .win)
        XCTAssertEqual(rules.dontPassComeOutAction(for: 3), .win)
        XCTAssertEqual(rules.dontPassComeOutAction(for: 12), .push)
        XCTAssertEqual(rules.dontPassComeOutAction(for: 7), .lose)
        XCTAssertEqual(rules.dontPassComeOutAction(for: 11), .lose)
        XCTAssertEqual(rules.dontPassComeOutAction(for: 8), .establishPoint)
    }

    // MARK: - Standard: Field Payout Multipliers

    func testStandard_fieldPayoutMultipliers() {
        let rules = StandardCrapsVariantRules()
        XCTAssertEqual(rules.fieldPayoutMultiplier(for: 12), 3.0)
        XCTAssertEqual(rules.fieldPayoutMultiplier(for: 2), 2.0)
        XCTAssertEqual(rules.fieldPayoutMultiplier(for: 3), 1.0)
        XCTAssertEqual(rules.fieldPayoutMultiplier(for: 4), 1.0)
        XCTAssertEqual(rules.fieldPayoutMultiplier(for: 9), 1.0)
        XCTAssertEqual(rules.fieldPayoutMultiplier(for: 10), 1.0)
        XCTAssertEqual(rules.fieldPayoutMultiplier(for: 11), 1.0)
        XCTAssertNil(rules.fieldPayoutMultiplier(for: 5))
        XCTAssertNil(rules.fieldPayoutMultiplier(for: 6))
        XCTAssertNil(rules.fieldPayoutMultiplier(for: 7))
        XCTAssertNil(rules.fieldPayoutMultiplier(for: 8))
    }

    // MARK: - Standard: Pass Line Odds Multipliers (True Odds)

    func testStandard_passLineOddsMultipliers() {
        let rules = StandardCrapsVariantRules()
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 4), 2.0)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 10), 2.0)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 5), 1.5)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 9), 1.5)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 6), 1.2)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 8), 1.2)
    }

    // MARK: - Standard: Don't Pass Odds Multipliers (Lay Odds)

    func testStandard_dontPassOddsMultipliers() {
        let rules = StandardCrapsVariantRules()
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 4), 0.5)
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 10), 0.5)
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 5), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 9), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 6), 5.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 8), 5.0 / 6.0, accuracy: 0.0001)
    }

    // MARK: - Standard: Max Odds Multipliers

    func testStandard_maxOddsMultipliers() {
        let rules = StandardCrapsVariantRules()
        XCTAssertEqual(rules.maxOddsMultiplier(for: 4), 3)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 10), 3)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 5), 4)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 9), 4)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 6), 5)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 8), 5)
    }

    // MARK: - Crapless: Point Numbers

    func testCrapless_pointNumbers() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.pointNumbers, [2, 3, 4, 5, 6, 8, 9, 10, 11, 12])
        XCTAssertEqual(rules.orderedPointNumbers, [2, 3, 4, 5, 6, 8, 9, 10, 11, 12])
    }

    // MARK: - Crapless: Come-Out Events

    func testCrapless_passLineComeOut_7Wins() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.passLineComeOutEvent(for: 7), .passLineWin)
    }

    func testCrapless_passLineComeOut_allOthersEstablishPoint() {
        let rules = CraplessCrapsVariantRules()
        for total in [2, 3, 4, 5, 6, 8, 9, 10, 11, 12] {
            XCTAssertEqual(rules.passLineComeOutEvent(for: total), .pointEstablished(total), "Total \(total)")
        }
    }

    // MARK: - Crapless: Come Bet Actions

    func testCrapless_comeBet_7Wins() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.comeBetComeOutAction(for: 7), .win)
    }

    func testCrapless_comeBet_12EstablishesPoint() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.comeBetComeOutAction(for: 12), .establishPoint)
    }

    // MARK: - Crapless: Don't Pass Actions

    func testCrapless_dontPass_7Loses() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.dontPassComeOutAction(for: 7), .lose)
    }

    func testCrapless_dontPass_pointEstablishes() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.dontPassComeOutAction(for: 2), .establishPoint)
        XCTAssertEqual(rules.dontPassComeOutAction(for: 12), .establishPoint)
    }

    // MARK: - Crapless: Odds Multipliers

    func testCrapless_passLineOddsMultipliers() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 2), 6.0)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 12), 6.0)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 3), 3.0)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 11), 3.0)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 4), 2.0)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 10), 2.0)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 5), 1.5)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 9), 1.5)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 6), 1.2)
        XCTAssertEqual(rules.passLineOddsMultiplier(for: 8), 1.2)
    }

    func testCrapless_dontPassOddsMultipliers() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 2), 1.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 12), 1.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 3), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 11), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 4), 0.5)
        XCTAssertEqual(rules.dontPassOddsMultiplier(for: 10), 0.5)
    }

    func testCrapless_maxOddsMultipliers() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.maxOddsMultiplier(for: 2), 6)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 12), 6)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 3), 5)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 11), 5)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 4), 3)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 10), 3)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 5), 4)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 9), 4)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 6), 5)
        XCTAssertEqual(rules.maxOddsMultiplier(for: 8), 5)
    }

    // MARK: - Crapless: Field (same as standard)

    func testCrapless_fieldPayoutMultipliers() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.fieldPayoutMultiplier(for: 12), 3.0)
        XCTAssertEqual(rules.fieldPayoutMultiplier(for: 2), 2.0)
        XCTAssertEqual(rules.fieldPayoutMultiplier(for: 3), 1.0)
        XCTAssertNil(rules.fieldPayoutMultiplier(for: 7))
    }

    // MARK: - Point Phase (both variants share the same logic)

    func testStandard_passLinePointEvent_pointMade() {
        let rules = StandardCrapsVariantRules()
        XCTAssertEqual(rules.passLinePointEvent(for: 6, pointNumber: 6), .pointMade)
    }

    func testStandard_passLinePointEvent_sevenOut() {
        let rules = StandardCrapsVariantRules()
        XCTAssertEqual(rules.passLinePointEvent(for: 7, pointNumber: 6), .sevenOut)
    }

    func testStandard_passLinePointEvent_noAction() {
        let rules = StandardCrapsVariantRules()
        XCTAssertEqual(rules.passLinePointEvent(for: 5, pointNumber: 6), .none)
    }

    func testCrapless_passLinePointEvent_pointMadeOnExtreme() {
        let rules = CraplessCrapsVariantRules()
        XCTAssertEqual(rules.passLinePointEvent(for: 2, pointNumber: 2), .pointMade)
        XCTAssertEqual(rules.passLinePointEvent(for: 12, pointNumber: 12), .pointMade)
    }
}
