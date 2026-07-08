//
//  CrapsSessionManager.swift
//  hardway-craps
//

import Foundation

protocol CrapsSessionManagerDelegate: BaseSessionManagerDelegate {
    func metricsDidUpdate(metrics: GameplayMetrics)
    func rollCountDidChange(count: Int)
    func sevenWasRolled(total: Int)
    func pointWasMade(number: Int)
}

final class CrapsSessionManager: BaseSessionManager {

    weak var delegate: CrapsSessionManagerDelegate?

    private(set) var rollCount: Int = 0
    private(set) var sevensRolled: Int = 0
    private(set) var pointsHit: Int = 0
    private(set) var gameplayMetrics: GameplayMetrics
    private(set) var lastBalanceBeforeRoll: Int

    private var diceOutcomeHistogram: [Int]
    private let gameType: GameType

    private static let histogramLength = 11

    private static func normalizedHistogram(from stored: [Int]?) -> [Int] {
        var bins = Array(repeating: 0, count: histogramLength)
        guard let stored else { return bins }
        for i in 0..<min(stored.count, histogramLength) {
            bins[i] = stored[i]
        }
        return bins
    }

    // MARK: - Initialization

    init(startingBalance: Int = 200, resumingSession: GameSession? = nil, gameType: GameType = .craps) {
        self.gameType = gameType
        self.lastBalanceBeforeRoll = startingBalance
        self.diceOutcomeHistogram = Self.normalizedHistogram(from: resumingSession?.crapsDiceOutcomeHistogram)

        if let resuming = resumingSession {
            self.rollCount = resuming.rollCount ?? 0
            self.sevensRolled = resuming.sevensRolled ?? 0
            self.pointsHit = resuming.pointsHit ?? 0
            self.gameplayMetrics = resuming.gameplayMetrics ?? GameplayMetrics()
            self.gameplayMetrics.lastBalanceBeforeRoll = resuming.endingBalance
            self.lastBalanceBeforeRoll = resuming.endingBalance
        } else {
            self.gameplayMetrics = GameplayMetrics()
            self.gameplayMetrics.lastBalanceBeforeRoll = startingBalance
        }

        super.init(startingBalance: startingBalance, resumingSession: resumingSession)
    }

    // MARK: - BaseSessionManager Overrides

    override var eventCount: Int { rollCount }
    override var hasGameplay: Bool { rollCount > 0 || gameplayMetrics.totalBetAmount > 0 }

    override func buildGameSession(id: String, startTime: Date, duration: TimeInterval, endingBalance: Int) -> GameSession {
        GameSession(
            id: id,
            date: startTime,
            duration: duration,
            startingBalance: startingBalance,
            endingBalance: endingBalance,
            rollCount: rollCount,
            gameplayMetrics: gameplayMetrics,
            sevensRolled: sevensRolled,
            pointsHit: pointsHit,
            balanceHistory: balanceHistory,
            betSizeHistory: betSizeHistory,
            atmVisitIndices: atmVisitIndices,
            handCount: nil,
            blackjackMetrics: nil,
            gameType: gameType,
            baccaratMetrics: nil,
            crapsDiceOutcomeHistogram: diceOutcomeHistogram
        )
    }

    override func resetGameSpecificState() {
        rollCount = 0
        sevensRolled = 0
        pointsHit = 0
        gameplayMetrics = GameplayMetrics()
        diceOutcomeHistogram = Array(repeating: 0, count: Self.histogramLength)
    }

    override func onSessionStarted() {
        rollCount = 0
        sevensRolled = 0
        pointsHit = 0
        gameplayMetrics = GameplayMetrics()
        gameplayMetrics.lastBalanceBeforeRoll = startingBalance
        lastBalanceBeforeRoll = startingBalance
        diceOutcomeHistogram = Array(repeating: 0, count: Self.histogramLength)
    }

    override func balanceDidChange(from oldBalance: Int, to newBalance: Int) {
        delegate?.balanceDidChange(from: oldBalance, to: newBalance)
    }

    override func notifySessionSaved(_ session: GameSession) {
        delegate?.sessionWasSaved(session: session)
    }

    override func notifySessionStarted(id: String) {
        delegate?.sessionDidStart(id: id)
    }

    // MARK: - Craps-Specific Methods

    func updateLastBalanceBeforeRoll(_ balance: Int) {
        lastBalanceBeforeRoll = balance
        gameplayMetrics.lastBalanceBeforeRoll = balance
    }

    func incrementRollCount() {
        rollCount += 1
        delegate?.rollCountDidChange(count: rollCount)
    }

    func recordDiceOutcome(total: Int) {
        guard (2...12).contains(total) else { return }
        diceOutcomeHistogram[total - 2] += 1
    }

    func diceHistogramSnapshot() -> [Int] {
        diceOutcomeHistogram
    }

    func trackSevenRolled() {
        sevensRolled += 1
        delegate?.sevenWasRolled(total: sevensRolled)
    }

    func trackPointMade(number: Int) {
        pointsHit += 1
        delegate?.pointWasMade(number: number)
    }

    override func trackATMVisit(amount: Int) {
        gameplayMetrics.atmVisitsCount += 1
        gameplayMetrics.totalATMAmount += amount
        super.trackATMVisit(amount: amount)
        delegate?.metricsDidUpdate(metrics: gameplayMetrics)
    }

    func trackBet(amount: Int, type: BetType) {
        let betPercent = Double(amount) / Double(max(currentBalance + amount, 1)) * 100.0

        if currentBalance < lastBalanceBeforeRoll {
            gameplayMetrics.betsAfterLossCount += 1
        }

        switch type {
        case .passLine:
            gameplayMetrics.passLineBetCount += 1
            gameplayMetrics.totalPassLineAmount += amount
        case .odds:
            gameplayMetrics.oddsBetCount += 1
            gameplayMetrics.totalOddsAmount += amount
        case .place:
            gameplayMetrics.placeBetCount += 1
            gameplayMetrics.totalPlaceAmount += amount
        case .hardway:
            gameplayMetrics.hardwayBetCount += 1
            gameplayMetrics.totalHardwayAmount += amount
        case .horn:
            gameplayMetrics.hornBetCount += 1
            gameplayMetrics.totalHornAmount += amount
        case .field:
            gameplayMetrics.fieldBetCount += 1
            gameplayMetrics.totalFieldAmount += amount
        case .dontPass:
            gameplayMetrics.dontPassBetCount += 1
            gameplayMetrics.totalDontPassAmount += amount
        case .comeBet:
            gameplayMetrics.comeBetCount += 1
            gameplayMetrics.totalComeBetAmount += amount
        case .lay:
            gameplayMetrics.layBetCount += 1
            gameplayMetrics.totalLayAmount += amount
        case .cAndE, .anySeven:
            break
        }

        if amount > gameplayMetrics.largestBetAmount {
            gameplayMetrics.largestBetAmount = amount
            gameplayMetrics.largestBetPercent = betPercent
        }

        delegate?.metricsDidUpdate(metrics: gameplayMetrics)
    }

    func updateConcurrentBets(count: Int) {
        if count > gameplayMetrics.maxConcurrentBets {
            gameplayMetrics.maxConcurrentBets = count
            delegate?.metricsDidUpdate(metrics: gameplayMetrics)
        }
    }
}

// MARK: - BetType Enum

enum BetType {
    case passLine
    case odds
    case place
    case hardway
    case horn
    case field
    case dontPass
    case comeBet
    case lay
    case cAndE
    case anySeven
}
