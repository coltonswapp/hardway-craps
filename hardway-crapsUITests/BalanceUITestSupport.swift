import XCTest

/// Helpers for gameplay UI tests: balance, chip selector, and bet controls (`PlainControl` / bet chips).
enum BalanceUITestSupport {

  // MARK: - Chip selector (`ChipSelector`, identifiers `chipDrag.<value>`)

  /// The chip denomination control in the selector strip (`ProgrammaticChipView` / `UIControl`).
  static func chipDenomination(in app: XCUIApplication, value: Int) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "chipDrag.\(value)").firstMatch
  }

  /// Asserts the given denomination is the active chip (requires `.selected` on `ProgrammaticChipView`).
  static func assertSelectedChipDenomination(
    _ value: Int,
    in app: XCUIApplication,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let chip = chipDenomination(in: app, value: value)
    XCTAssertTrue(chip.waitForExistence(timeout: timeout), "Chip $\(value) should exist", file: file, line: line)
    XCTAssertTrue(chip.isSelected, "Expected $\(value) chip selected in chip selector", file: file, line: line)
  }

  // MARK: - Bet controls (`PlainControl` uses `line|odds`; bet chips use plain amount)

  /// Parses `accessibilityValue` from a pass/don’t-pass style control: `"\(line)"` or `"\(line)|\(odds)"`.
  static func readLineBetAndOdds(from control: XCUIElement) -> (line: Int, odds: Int) {
    let raw = control.value as? String ?? ""
    let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map {
      String($0).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let line = Int(parts[0]) ?? 0
    let odds = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
    return (line, odds)
  }

  /// Reads a single bet amount from a bet chip (`SmallBetChip` / place chip `pointPlaceBetChip.<n>`).
  static func readBetChipAmount(from element: XCUIElement) -> Int {
    let raw = element.value as? String ?? ""
    return Int(raw) ?? 0
  }

  /// Asserts line and optional odds on a `PlainControl` (e.g. `passLineControl`).
  static func assertLineAndOdds(
    on control: XCUIElement,
    expectedLine: Int,
    expectedOdds: Int = 0,
    step: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let got = readLineBetAndOdds(from: control)
    let prefix = step.isEmpty ? "" : "[\(step)] "
    XCTAssertEqual(
      got.line, expectedLine,
      "\(prefix)Expected line bet \(expectedLine), got \(got.line) (full value: \(control.value as? String ?? ""))",
      file: file, line: line)
    XCTAssertEqual(
      got.odds, expectedOdds,
      "\(prefix)Expected odds \(expectedOdds), got \(got.odds) (full value: \(control.value as? String ?? ""))",
      file: file, line: line)
  }

  /// Asserts the amount shown on a bet chip element.
  static func assertBetChipAmount(
    on element: XCUIElement,
    expected: Int,
    step: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let got = readBetChipAmount(from: element)
    let prefix = step.isEmpty ? "" : "[\(step)] "
    XCTAssertEqual(
      got, expected,
      "\(prefix)Expected bet chip \(expected), got \(got)",
      file: file, line: line)
  }

  /// Reads the total at-risk amount from `CurrentBetView` (`accessibilityIdentifier` `"currentBetView"`).
  static func readCurrentBet(from element: XCUIElement) -> Int {
    let raw = element.value as? String ?? ""
    return Int(raw) ?? 0
  }

  /// Polls until `currentBetView`’s value equals `target` (e.g. after table clears on seven-out).
  @discardableResult
  static func waitForCurrentBet(
    equals target: Int,
    in element: XCUIElement,
    timeout: TimeInterval = 10
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if readCurrentBet(from: element) == target { return true }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return readCurrentBet(from: element) == target
  }

  /// Reads the numeric balance from a `BalanceView` (`accessibilityIdentifier` `"balanceView"`).
  static func readBalance(from element: XCUIElement) -> Int {
    let raw = element.value as? String ?? ""
    return Int(raw) ?? 0
  }

  /// After an action that may update balance asynchronously, polls until the reading is unchanged for
  /// `stableInterval`, or `timeout` elapses (returns last read).
  static func waitForSettledBalance(
    in element: XCUIElement, stableInterval: TimeInterval = 0.25, timeout: TimeInterval = 10
  ) -> Int {
    var previous = readBalance(from: element)
    var stableStart = Date()
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
      let v = readBalance(from: element)
      if v != previous {
        previous = v
        stableStart = Date()
      } else if Date().timeIntervalSince(stableStart) >= stableInterval {
        return v
      }
    }
    return readBalance(from: element)
  }

  /// Runs `afterAction`, then polls until balance equals `before + expectingDelta` (or fails).
  static func assertBalanceNetChange(
    in element: XCUIElement,
    expectingDelta: Int,
    step: String,
    timeout: TimeInterval = 10,
    file: StaticString = #filePath,
    line: UInt = #line,
    afterAction: @escaping () -> Void
  ) {
    let before = readBalance(from: element)
    let target = before + expectingDelta

    XCTContext.runActivity(named: step) { _ in
      afterAction()

      guard pollUntilBalance(equals: target, in: element, timeout: timeout) else {
        let after = readBalance(from: element)
        let observed = after - before
        XCTFail(
          """
          [\(step)] Wrong balance net change. before=\(before), after=\(after), observed Δ=\(observed), expected Δ=\(expectingDelta) (target \(target))
          """, file: file, line: line)
        return
      }

      let after = readBalance(from: element)
      XCTAssertEqual(
        after, target,
        "[\(step)] before=\(before), after=\(after), observed Δ=\(after - before), expected Δ=\(expectingDelta)",
        file: file, line: line)
    }
  }

  /// Runs `afterAction`, then polls until balance equals `expected` (absolute).
  static func assertBalanceEquals(
    in element: XCUIElement,
    expected: Int,
    step: String,
    timeout: TimeInterval = 10,
    file: StaticString = #filePath,
    line: UInt = #line,
    afterAction: @escaping () -> Void
  ) {
    XCTContext.runActivity(named: step) { _ in
      afterAction()

      guard pollUntilBalance(equals: expected, in: element, timeout: timeout) else {
        let after = readBalance(from: element)
        XCTFail(
          """
          [\(step)] Wrong balance. expected=\(expected), got=\(after)
          """, file: file, line: line)
        return
      }

      let after = readBalance(from: element)
      XCTAssertEqual(
        after, expected,
        "[\(step)] expected=\(expected), got=\(after)",
        file: file, line: line)
    }
  }

  private static func pollUntilBalance(
    equals target: Int, in element: XCUIElement, timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if readBalance(from: element) == target { return true }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return readBalance(from: element) == target
  }
}
