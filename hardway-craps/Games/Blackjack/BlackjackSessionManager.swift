//
//  BlackjackSessionManager.swift
//  hardway-craps
//

import Foundation

protocol BlackjackSessionManagerDelegate: BaseSessionManagerDelegate {
    func metricsDidUpdate(metrics: BlackjackGameplayMetrics)
    func handCountDidChange(count: Int)
}

final class BlackjackSessionManager: BaseSessionManager {

    weak var delegate: BlackjackSessionManagerDelegate?

    private(set) var handCount: Int = 0
    private(set) var lastBalanceBeforeHand: Int
    private(set) var blackjackMetrics: BlackjackGameplayMetrics

    // MARK: - Initialization

    override init(startingBalance: Int = 200, resumingSession: GameSession? = nil) {
        self.lastBalanceBeforeHand = startingBalance

        if let resuming = resumingSession {
            self.handCount = resuming.handCount ?? 0
            self.blackjackMetrics = resuming.blackjackMetrics ?? BlackjackGameplayMetrics()
            self.blackjackMetrics.lastBalanceBeforeHand = resuming.endingBalance
            self.lastBalanceBeforeHand = resuming.endingBalance
        } else {
            self.blackjackMetrics = BlackjackGameplayMetrics()
            self.blackjackMetrics.lastBalanceBeforeHand = startingBalance
        }

        super.init(startingBalance: startingBalance, resumingSession: resumingSession)
    }

    // MARK: - BaseSessionManager Overrides

    override var eventCount: Int { handCount }
    override var hasGameplay: Bool { handCount > 0 || blackjackMetrics.totalBetAmount > 0 }

    override func buildGameSession(id: String, startTime: Date, duration: TimeInterval, endingBalance: Int) -> GameSession {
        GameSession(
            id: id,
            date: startTime,
            duration: duration,
            startingBalance: startingBalance,
            endingBalance: endingBalance,
            rollCount: nil,
            gameplayMetrics: nil,
            sevensRolled: nil,
            pointsHit: nil,
            balanceHistory: balanceHistory,
            betSizeHistory: betSizeHistory,
            atmVisitIndices: atmVisitIndices,
            handCount: handCount,
            blackjackMetrics: blackjackMetrics,
            gameType: .blackjack,
            baccaratMetrics: nil,
            crapsDiceOutcomeHistogram: nil
        )
    }

    override func resetGameSpecificState() {
        handCount = 0
        blackjackMetrics = BlackjackGameplayMetrics()
    }

    override func onSessionStarted() {
        handCount = 0
        blackjackMetrics = BlackjackGameplayMetrics()
        blackjackMetrics.lastBalanceBeforeHand = startingBalance
        lastBalanceBeforeHand = startingBalance
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

    // MARK: - Blackjack-Specific Methods

    func updateLastBalanceBeforeHand(_ balance: Int) {
        lastBalanceBeforeHand = balance
    }

    func incrementHandCount() {
        handCount += 1
        delegate?.handCountDidChange(count: handCount)
    }

    func trackBet(amount: Int, isMainBet: Bool) {
        let betPercent = Double(amount) / Double(max(currentBalance + amount, 1))

        if currentBalance < lastBalanceBeforeHand {
            blackjackMetrics.betsAfterLossCount += 1
        }

        if isMainBet {
            blackjackMetrics.mainBetCount += 1
            blackjackMetrics.totalMainBetAmount += amount
        } else {
            blackjackMetrics.bonusBetCount += 1
            blackjackMetrics.totalBonusBetAmount += amount
        }

        if amount > blackjackMetrics.largestBetAmount {
            blackjackMetrics.largestBetAmount = amount
            blackjackMetrics.largestBetPercent = betPercent
        }

        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    func updateConcurrentBets(count: Int) {
        if count > blackjackMetrics.maxConcurrentBets {
            blackjackMetrics.maxConcurrentBets = count
            delegate?.metricsDidUpdate(metrics: blackjackMetrics)
        }
    }

    func recordWin(isBlackjack: Bool = false) {
        blackjackMetrics.wins += 1
        if isBlackjack {
            blackjackMetrics.blackjacksHit += 1
        }
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    func recordLoss() {
        blackjackMetrics.losses += 1
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    func recordPush() {
        blackjackMetrics.pushes += 1
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    func recordDoubleDown() {
        blackjackMetrics.doublesDown += 1
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    func recordBonusWin(amount: Int, type: String) {
        blackjackMetrics.bonusesWon += 1
        blackjackMetrics.totalBonusWinnings += amount

        switch type {
        case "Perfect Pairs":
            blackjackMetrics.perfectPairsWon += 1
        case "Royal Match":
            blackjackMetrics.royalMatchesWon += 1
        default:
            break
        }

        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    func updateBonusMetrics(perfectPairs: Int = 0, coloredPairs: Int = 0, mixedPairs: Int = 0,
                            royalMatches: Int = 0, suitedMatches: Int = 0) {
        blackjackMetrics.perfectPairsWon += perfectPairs
        blackjackMetrics.coloredPairsWon += coloredPairs
        blackjackMetrics.mixedPairsWon += mixedPairs
        blackjackMetrics.royalMatchesWon += royalMatches
        blackjackMetrics.suitedMatchesWon += suitedMatches
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    override func trackATMVisit(amount: Int) {
        blackjackMetrics.atmVisitsCount += 1
        blackjackMetrics.totalATMAmount += amount
        super.trackATMVisit(amount: amount)
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }
}
