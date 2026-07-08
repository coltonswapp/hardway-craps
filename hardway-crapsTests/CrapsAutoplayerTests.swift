import XCTest
@testable import hardway_craps

final class CrapsAutoplayerTests: XCTestCase {

  func testPresetProfilePreservesKind() {
    let gambler = CrapsAutoplayerProfile.preset(.gambler)
    XCTAssertEqual(gambler.kind, .gambler)
    XCTAssertGreaterThan(gambler.oddsTakeProbability, CrapsAutoplayerProfile.preset(.conservative).oddsTakeProbability)
  }

  func testRandomProfileUsesKnownKind() {
    let p = CrapsAutoplayerProfile.random()
    XCTAssertTrue(CrapsAutoplayerProfileKind.allCases.contains(p.kind))
  }

  func testTableSnapshotEquality() {
    let a = CrapsTableSnapshot(
      phase: .comeOut,
      balance: 100,
      betsAreOn: true,
      selectedChipValue: 5,
      passLineBet: 5,
      passLineOdds: 0,
      fieldBet: 0,
      hardwaysEnabled: true,
      makeEmEnabled: true,
      hornEnabled: true,
      variant: .standard,
      rollingGateOpen: true,
      isDiceRolling: false,
      canRoll: true
    )
    let b = a
    XCTAssertEqual(a, b)
  }
}
