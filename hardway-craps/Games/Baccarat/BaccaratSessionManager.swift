//
//  BaccaratSessionManager.swift
//  hardway-craps
//

import Foundation

protocol BaccaratSessionManagerDelegate: BaseSessionManagerDelegate {
    func metricsDidUpdate(metrics: BaccaratGameplayMetrics)
    func handCountDidChange(count: Int)
}

final class BaccaratSessionManager: BaseSessionManager {

    weak var delegate: BaccaratSessionManagerDelegate?

    private(set) var handCount: Int = 0
    private(set) var lastBalanceBeforeHand: Int
    private(set) var baccaratMetrics: BaccaratGameplayMetrics

    // MARK: - Initialization

    override init(startingBalance: Int = 200, resumingSession: GameSession? = nil) {
        self.lastBalanceBeforeHand = startingBalance

        if let resuming = resumingSession {
            self.handCount = resuming.handCount ?? 0
            self.baccaratMetrics = resuming.baccaratMetrics ?? BaccaratGameplayMetrics()
            self.baccaratMetrics.lastBalanceBeforeHand = resuming.endingBalance
            self.lastBalanceBeforeHand = resuming.endingBalance
        } else {
            self.baccaratMetrics = BaccaratGameplayMetrics()
            self.baccaratMetrics.lastBalanceBeforeHand = startingBalance
        }

        super.init(startingBalance: startingBalance, resumingSession: resumingSession)
    }

    // MARK: - BaseSessionManager Overrides

    override var eventCount: Int { handCount }
    override var hasGameplay: Bool { handCount > 0 || baccaratMetrics.totalBetAmount > 0 }

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
            blackjackMetrics: nil,
            gameType: .baccarat,
            baccaratMetrics: baccaratMetrics,
            crapsDiceOutcomeHistogram: nil
        )
    }

    override func resetGameSpecificState() {
        handCount = 0
        baccaratMetrics = BaccaratGameplayMetrics()
    }

    override func onSessionStarted() {
        handCount = 0
        baccaratMetrics = BaccaratGameplayMetrics()
        baccaratMetrics.lastBalanceBeforeHand = startingBalance
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

    // MARK: - Baccarat-Specific Methods

    func updateLastBalanceBeforeHand(_ balance: Int) {
        lastBalanceBeforeHand = balance
    }

    func incrementHandCount() {
        handCount += 1
        delegate?.handCountDidChange(count: handCount)
    }

    func trackBet(amount: Int, isBankerBet: Bool) {
        let betPercent = Double(amount) / Double(max(currentBalance + amount, 1))

        if currentBalance < lastBalanceBeforeHand {
            baccaratMetrics.betsAfterLossCount += 1
        }

        if isBankerBet {
            baccaratMetrics.bankerBetCount += 1
            baccaratMetrics.totalBankerBetAmount += amount
        } else {
            baccaratMetrics.playerBetCount += 1
            baccaratMetrics.totalPlayerBetAmount += amount
        }

        if amount > baccaratMetrics.largestBetAmount {
            baccaratMetrics.largestBetAmount = amount
            baccaratMetrics.largestBetPercent = betPercent
        }

        delegate?.metricsDidUpdate(metrics: baccaratMetrics)
    }

    func updateConcurrentBets(count: Int) {
        if count > baccaratMetrics.maxConcurrentBets {
            baccaratMetrics.maxConcurrentBets = count
            delegate?.metricsDidUpdate(metrics: baccaratMetrics)
        }
    }

    func recordHandResult(_ result: BaccaratHandRecord.Result, isNatural: Bool = false, hasPair: Bool = false) {
        baccaratMetrics.handHistory.append(
            BaccaratHandRecord(result: result, isNatural: isNatural, hasPair: hasPair)
        )
    }

    func recordBankerWin() {
        baccaratMetrics.bankerWins += 1
        delegate?.metricsDidUpdate(metrics: baccaratMetrics)
    }

    func recordPlayerWin() {
        baccaratMetrics.playerWins += 1
        delegate?.metricsDidUpdate(metrics: baccaratMetrics)
    }

    func recordTie() {
        baccaratMetrics.ties += 1
        delegate?.metricsDidUpdate(metrics: baccaratMetrics)
    }

    func recordNatural() {
        baccaratMetrics.naturals += 1
        delegate?.metricsDidUpdate(metrics: baccaratMetrics)
    }

    override func trackATMVisit(amount: Int) {
        baccaratMetrics.atmVisitsCount += 1
        baccaratMetrics.totalATMAmount += amount
        super.trackATMVisit(amount: amount)
        delegate?.metricsDidUpdate(metrics: baccaratMetrics)
    }
}
