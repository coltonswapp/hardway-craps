import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
}

private func testStandardVariant() {
    let standard = StandardCrapsVariantRules()
    let game = CrapsGame(rules: standard)

    expect(game.processRoll(7) == .passLineWin, "standard come-out 7 should win")
    expect(game.processRoll(2) == .passLineLoss, "standard come-out 2 should lose")

    let pointGame = CrapsGame(rules: standard)
    expect(pointGame.processRoll(6) == .pointEstablished(6), "standard 6 establishes point")
    expect(pointGame.processRoll(6) == .pointMade, "standard point made should win")

    expect(standard.comeBetComeOutAction(for: 11) == .win, "standard come bet 11 should win")
    expect(standard.comeBetComeOutAction(for: 12) == .lose, "standard come bet 12 should lose")
    expect(standard.orderedPointNumbers == [4, 5, 6, 8, 9, 10], "standard ordered point domain")
}

private func testCraplessVariant() {
    let crapless = CraplessCrapsVariantRules()
    let game = CrapsGame(rules: crapless)

    expect(game.processRoll(7) == .passLineWin, "crapless come-out 7 should win")
    expect(game.processRoll(2) == .pointEstablished(2), "crapless come-out 2 should establish point")
    expect(game.processRoll(2) == .pointMade, "crapless point 2 made should win")

    expect(crapless.comeBetComeOutAction(for: 12) == .establishPoint, "crapless come bet 12 should travel")
    expect(crapless.dontPassComeOutAction(for: 7) == .lose, "crapless don't pass should lose on 7")
    expect(crapless.pointNumbers.contains(2) && crapless.pointNumbers.contains(12), "crapless point domain includes 2 and 12")
    expect(crapless.orderedPointNumbers == [2, 3, 4, 5, 6, 8, 9, 10, 11, 12], "crapless ordered point domain")
    expect(crapless.passLineOddsMultiplier(for: 2) == 6.0, "crapless true odds for point 2")
    expect(crapless.dontPassOddsMultiplier(for: 12) == (1.0 / 6.0), "crapless lay odds for point 12")
}

private func testParities() {
    let standard = StandardCrapsVariantRules()
    let crapless = CraplessCrapsVariantRules()

    // Shared truths that should not regress between variants.
    expect(standard.passLinePointEvent(for: 7, pointNumber: 8) == .sevenOut, "standard seven-out in point phase")
    expect(crapless.passLinePointEvent(for: 7, pointNumber: 11) == .sevenOut, "crapless seven-out in point phase")
    expect(standard.fieldPayoutMultiplier(for: 12) == 3.0, "standard field 12 payout")
    expect(crapless.fieldPayoutMultiplier(for: 12) == 3.0, "crapless field 12 payout")
}

@main
struct CrapsRulesSmokeTestsRunner {
    static func main() {
        testStandardVariant()
        testCraplessVariant()
        testParities()
        print("Craps rules smoke tests passed.")
    }
}
