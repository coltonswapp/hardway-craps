import Foundation
@testable import hardway_craps

// MARK: - Pass Line Manager Delegate Spy

final class PassLineManagerDelegateSpy: CrapsPassLineManagerDelegate {

    struct WinCall {
        let originalBet: Int
        let winnings: Int
    }

    struct OddsWinCall {
        let originalBet: Int
        let winnings: Int
        let point: Int
        let multiplier: Double
    }

    var passLineWins: [WinCall] = []
    var passLineOddsWins: [OddsWinCall] = []
    var passLineLosses: [Int] = []
    var passLineOddsLosses: [Int] = []

    func passLineWinProcessed(originalBet: Int, winnings: Int) {
        passLineWins.append(WinCall(originalBet: originalBet, winnings: winnings))
    }

    func passLineOddsWinProcessed(originalBet: Int, winnings: Int, point: Int, multiplier: Double) {
        passLineOddsWins.append(OddsWinCall(originalBet: originalBet, winnings: winnings, point: point, multiplier: multiplier))
    }

    func passLineLossProcessed(lostAmount: Int) {
        passLineLosses.append(lostAmount)
    }

    func passLineOddsLossProcessed(lostAmount: Int) {
        passLineOddsLosses.append(lostAmount)
    }
}

// MARK: - Special Bets Manager Delegate Spy

final class SpecialBetsDelegateSpy: CrapsSpecialBetsManagerDelegate {

    struct HardwayWinCall {
        let total: Int
        let betAmount: Int
        let multiplier: Double
        let winAmount: Int
    }

    struct HardwayLossCall {
        let total: Int
        let betAmount: Int
        let isSoftWay: Bool
    }

    struct HornWinCall {
        let hornName: String
        let betAmount: Int
        let multiplier: Double
        let winAmount: Int
    }

    struct FieldWinCall {
        let total: Int
        let betAmount: Int
        let multiplier: Double
        let winAmount: Int
    }

    struct DontPassWinCall {
        let total: Int
        let betAmount: Int
        let multiplier: Double
        let winAmount: Int
        let isPointPhase: Bool
    }

    struct DontPassPushCall {
        let total: Int
        let betAmount: Int
    }

    struct MakeEmWinCall {
        let betName: String
        let betAmount: Int
        let multiplier: Double
        let winAmount: Int
    }

    struct MakeEmHitCall {
        let betName: String
        let number: Int
    }

    var hardwayWins: [HardwayWinCall] = []
    var hardwayLosses: [HardwayLossCall] = []
    var hornWins: [HornWinCall] = []
    var fieldWins: [FieldWinCall] = []
    var dontPassWins: [DontPassWinCall] = []
    var dontPassPushes: [DontPassPushCall] = []
    var makeEmWins: [MakeEmWinCall] = []
    var makeEmHits: [MakeEmHitCall] = []

    func hardwayWinEvaluated(total: Int, betAmount: Int, multiplier: Double, winAmount: Int) {
        hardwayWins.append(HardwayWinCall(total: total, betAmount: betAmount, multiplier: multiplier, winAmount: winAmount))
    }

    func hardwayLossEvaluated(total: Int, betAmount: Int, isSoftWay: Bool) {
        hardwayLosses.append(HardwayLossCall(total: total, betAmount: betAmount, isSoftWay: isSoftWay))
    }

    func hornWinEvaluated(hornName: String, betAmount: Int, multiplier: Double, winAmount: Int) {
        hornWins.append(HornWinCall(hornName: hornName, betAmount: betAmount, multiplier: multiplier, winAmount: winAmount))
    }

    func fieldWinEvaluated(total: Int, betAmount: Int, multiplier: Double, winAmount: Int) {
        fieldWins.append(FieldWinCall(total: total, betAmount: betAmount, multiplier: multiplier, winAmount: winAmount))
    }

    func dontPassWinEvaluated(total: Int, betAmount: Int, multiplier: Double, winAmount: Int, isPointPhase: Bool) {
        dontPassWins.append(DontPassWinCall(total: total, betAmount: betAmount, multiplier: multiplier, winAmount: winAmount, isPointPhase: isPointPhase))
    }

    func dontPassPushEvaluated(total: Int, betAmount: Int) {
        dontPassPushes.append(DontPassPushCall(total: total, betAmount: betAmount))
    }

    func makeEmWinEvaluated(betName: String, betAmount: Int, multiplier: Double, winAmount: Int) {
        makeEmWins.append(MakeEmWinCall(betName: betName, betAmount: betAmount, multiplier: multiplier, winAmount: winAmount))
    }

    func makeEmNumberHit(betName: String, number: Int) {
        makeEmHits.append(MakeEmHitCall(betName: betName, number: number))
    }
}

// MARK: - Game State Manager Delegate Spy

final class GameStateManagerDelegateSpy: CrapsGameStateManagerDelegate {

    struct PhaseChangeCall {
        let from: CrapsGame.Phase
        let to: CrapsGame.Phase
    }

    var phaseChanges: [PhaseChangeCall] = []
    var rollingStateChanges: [Bool] = []
    var pointsEstablished: [Int] = []
    var pointsMade: [Int] = []
    var sevenOutCount = 0

    func gamePhaseDidChange(from: CrapsGame.Phase, to: CrapsGame.Phase) {
        phaseChanges.append(PhaseChangeCall(from: from, to: to))
    }

    func rollingStateDidChange(enabled: Bool) {
        rollingStateChanges.append(enabled)
    }

    func pointWasEstablished(number: Int) {
        pointsEstablished.append(number)
    }

    func pointWasMade(number: Int) {
        pointsMade.append(number)
    }

    func sevenOut() {
        sevenOutCount += 1
    }
}
