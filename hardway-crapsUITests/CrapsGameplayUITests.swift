import XCTest

final class CrapsGameplayUITests: XCTestCase {

    /// Do not persist sessions or log craps start analytics — keeps UI test runs out of real session history.
    private static let disableSessionRecordingArg = "-UITestDisableSessionRecording"

    private var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [Self.disableSessionRecordingArg]
        app.launch()
    }
    
    /// Example recorded flow with deterministic dice: relaunch with a fixed roll queue, then target
    /// place boxes by `accessibilityIdentifier` (`pointControl.<n>`) instead of unlabeled `staticTexts`.
    @MainActor
    func testPointEstablishBetSixBetEightHitPoint() throws {
        app.terminate()
        // Establish point as 9, 2 rolls, then hit point
        app.launchArguments = [
            Self.disableSessionRecordingArg,
            "-UITestFixedDiceTotals", "9, 6, 8, 9",
        ]
        app.launch()
        
        app.staticTexts.matching(identifier: "New Game").element(boundBy: 0).tap()
        
        let balanceView = app.otherElements["balanceView"]
        XCTAssertTrue(balanceView.waitForExistence(timeout: 3), "Balance view should be visible")

        let startingBalance = BalanceUITestSupport.readBalance(from: balanceView)
        XCTAssertGreaterThan(startingBalance, 0, "Starting balance should be positive")
        
        let passLine = app.otherElements["passLineControl"]
        XCTAssertTrue(passLine.waitForExistence(timeout: 5))
        passLine.tap()
        passLine.tap()
        let (lineBet, _) = BalanceUITestSupport.readLineBetAndOdds(from: passLine)
        XCTAssertGreaterThan(lineBet, 0, "Pass line should show a non-zero line bet after two chip taps")
        
        rollDice()  // Expecting 9
        _ = BalanceUITestSupport.waitForSettledBalance(in: balanceView)
        
        passLine.tap()
        passLine.tap()
        let (lineAfterPoint, oddsBet) = BalanceUITestSupport.readLineBetAndOdds(from: passLine)
        XCTAssertEqual(
            lineAfterPoint, lineBet,
            "Adding odds should not change the pass line amount (value: \(passLine.value as? String ?? ""))")
        XCTAssertGreaterThan(oddsBet, 0, "Two taps should add non-zero free odds")
        
        let placeSixZone = Self.pointPlaceZone(in: app, pointNumber: 6)
        placeSixZone.tap()
        placeSixZone.tap()
        
        let placeEightZone = Self.pointPlaceZone(in: app, pointNumber: 8)
        placeEightZone.tap()
        placeEightZone.tap()

        let placeSixChip = Self.placeBetChip(in: app, pointNumber: 6)
        let placeEightChip = Self.placeBetChip(in: app, pointNumber: 8)
        XCTAssertTrue(placeSixChip.waitForExistence(timeout: 3))
        XCTAssertTrue(placeEightChip.waitForExistence(timeout: 3))
        let placeSixAmount = BalanceUITestSupport.readBetChipAmount(from: placeSixChip)
        let placeEightAmount = BalanceUITestSupport.readBetChipAmount(from: placeEightChip)
        XCTAssertGreaterThan(placeSixAmount, 0, "Place 6 should show a bet")
        XCTAssertGreaterThan(placeEightAmount, 0, "Place 8 should show a bet")
        
        let expectedPlaceSixPay = CrapsUITestPayoutExpectations.placeBetProfitCreditedToBalance(
            placeBet: placeSixAmount, pointNumber: 6)
        BalanceUITestSupport.assertBalanceNetChange(
            in: balanceView, expectingDelta: expectedPlaceSixPay, step: "Roll 6 — place 6 pays"
        ) {
            self.rollDice()
        }
        
        let expectedPlaceEightPay = CrapsUITestPayoutExpectations.placeBetProfitCreditedToBalance(
            placeBet: placeEightAmount, pointNumber: 8)
        BalanceUITestSupport.assertBalanceNetChange(
            in: balanceView, expectingDelta: expectedPlaceEightPay, step: "Roll 8 — place 8 pays"
        ) {
            self.rollDice()
        }
        
        let expectedPassHit = CrapsUITestPayoutExpectations.balanceDeltaPassLineHitPoint(
            lineBet: lineAfterPoint, oddsBet: oddsBet, point: 9)
        BalanceUITestSupport.assertBalanceNetChange(
            in: balanceView, expectingDelta: expectedPassHit, step: "Roll 9 — pass + odds win"
        ) {
            self.rollDice()
        }
    }
    
    /// Set point 9, add pass + odds + place 6/8, then roll 7: table clears so **current bet** returns to $0.
    func testPassLineSetPlaceBetSevenOut() {
        app.terminate()
        // Establish point as 9, 2 rolls, then hit point
        app.launchArguments = [
            Self.disableSessionRecordingArg,
            "-UITestFixedDiceTotals", "9, 7",
        ]
        app.launch()
        
        app.staticTexts.matching(identifier: "New Game").element(boundBy: 0).tap()
        
        let balanceView = app.otherElements["balanceView"]
        XCTAssertTrue(balanceView.waitForExistence(timeout: 3), "Balance view should be visible")

        BalanceUITestSupport.assertSelectedChipDenomination(5, in: app)

        let startingBalance = BalanceUITestSupport.readBalance(from: balanceView)
        XCTAssertGreaterThan(startingBalance, 0, "Starting balance should be positive")
        
        let passLine = app.otherElements["passLineControl"]
        XCTAssertTrue(passLine.waitForExistence(timeout: 5))
        passLine.tap()
        passLine.tap()
        BalanceUITestSupport.assertLineAndOdds(
            on: passLine, expectedLine: 10, step: "Pass line should be $10 after two taps at $5 chip")
        
        rollDice()  // Expecting 9
        _ = BalanceUITestSupport.waitForSettledBalance(in: balanceView)
        
        // Add $10 odds (two taps at $5)
        passLine.tap()
        passLine.tap()
        BalanceUITestSupport.assertLineAndOdds(
            on: passLine, expectedLine: 10, expectedOdds: 10, step: "Pass + $10 odds")
        
        let placeSixZone = Self.pointPlaceZone(in: app, pointNumber: 6)
        placeSixZone.tap()
        placeSixZone.tap()
        
        let placeEightZone = Self.pointPlaceZone(in: app, pointNumber: 8)
        placeEightZone.tap()
        placeEightZone.tap()

        let placeSixChip = Self.placeBetChip(in: app, pointNumber: 6)
        let placeEightChip = Self.placeBetChip(in: app, pointNumber: 8)
        XCTAssertTrue(placeSixChip.waitForExistence(timeout: 3))
        XCTAssertTrue(placeEightChip.waitForExistence(timeout: 3))
        BalanceUITestSupport.assertBetChipAmount(on: placeSixChip, expected: 10, step: "Place 6")
        BalanceUITestSupport.assertBetChipAmount(on: placeEightChip, expected: 10, step: "Place 8")

        let currentBetView = app.otherElements["currentBetView"]
        XCTAssertTrue(currentBetView.waitForExistence(timeout: 3), "Current bet readout should be visible")
        XCTAssertEqual(
            BalanceUITestSupport.readCurrentBet(from: currentBetView), 40,
            "Pass $10 + odds $10 + place 6/8 $10 each → $40 at risk before rolling 7")

        rollDice()  // Expecting 7 — lose pass/odds/place; table clears

        XCTAssertTrue(
            BalanceUITestSupport.waitForCurrentBet(equals: 0, in: currentBetView),
            "Current bet should return to $0 after seven-out (animations may delay readout)")
        XCTAssertEqual(
            BalanceUITestSupport.readCurrentBet(from: currentBetView), 0,
            "Seven-out should clear all table bets")
    }
    
    private func rollDice() {
        let diceControl = app.otherElements["flipDiceContainer"]
        XCTAssertTrue(diceControl.waitForExistence(timeout: 3), "Dice container should be visible")
        diceControl.tap()
    }
    
    /// Continuous touch path for `UIPanGestureRecognizer` (chip drag). Nudge offsets if a drop fails.
    private func dragFromTo(
        from: XCUIElement,
        fromOffset: CGVector,
        to: XCUIElement,
        toOffset: CGVector
    ) {
        let start = from.coordinate(withNormalizedOffset: fromOffset)
        let end = to.coordinate(withNormalizedOffset: toOffset)
        start.press(forDuration: 0.25, thenDragTo: end)
    }
    
    /// `PointControl` exposes the place `betView` as `pointPlaceBetChip.<pointNumber>` for UI tests.
    private static func placeBetChip(in app: XCUIApplication, pointNumber: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "pointPlaceBetChip.\(pointNumber)")
            .firstMatch
    }
    
    /// Lower “place” sub-zone of a point box (not the top lay stripe). Avoids `pointControl.<n>` taps that can hit lay.
    private static func pointPlaceZone(in app: XCUIApplication, pointNumber: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "pointControlPlaceZone.\(pointNumber)")
            .firstMatch
    }
}
