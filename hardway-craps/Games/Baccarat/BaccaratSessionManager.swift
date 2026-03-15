//
//  BaccaratSessionManager.swift
//  hardway-craps
//
//  Created by Claude Code on 3/10/26.
//

import Foundation

/// Delegate protocol for baccarat session events
protocol BaccaratSessionManagerDelegate: AnyObject {
    func sessionDidStart(id: String)
    func sessionWasSaved(session: GameSession)
    func metricsDidUpdate(metrics: BaccaratGameplayMetrics)
    func balanceDidChange(from oldBalance: Int, to newBalance: Int)
    func handCountDidChange(count: Int)
}

/// Manages session lifecycle, metrics collection, and persistence for Baccarat
final class BaccaratSessionManager {

    // MARK: - Properties

    weak var delegate: BaccaratSessionManagerDelegate?

    private(set) var sessionId: String?
    private(set) var sessionStartTime: Date?
    private(set) var accumulatedPlayTime: TimeInterval = 0
    private(set) var currentPeriodStartTime: Date?
    private(set) var handCount: Int = 0
    private(set) var balanceHistory: [Int] = []
    private(set) var betSizeHistory: [Int] = []
    private(set) var atmVisitIndices: [Int] = []
    private(set) var lastBalanceBeforeHand: Int
    private(set) var hasBeenSaved: Bool = false
    private(set) var baccaratMetrics: BaccaratGameplayMetrics

    private let startingBalance: Int
    private var pendingBetSizeSnapshot: Int = 0

    var currentBalance: Int {
        didSet {
            if oldValue != currentBalance {
                delegate?.balanceDidChange(from: oldValue, to: currentBalance)
            }
        }
    }

    // MARK: - Initialization

    init(startingBalance: Int = 200, resumingSession: GameSession? = nil) {
        self.startingBalance = startingBalance
        self.currentBalance = startingBalance
        self.lastBalanceBeforeHand = startingBalance

        if let resuming = resumingSession {
            self.sessionId = resuming.id
            self.sessionStartTime = resuming.date
            self.accumulatedPlayTime = resuming.duration
            self.currentPeriodStartTime = Date()
            self.handCount = resuming.handCount ?? 0
            self.baccaratMetrics = resuming.baccaratMetrics ?? BaccaratGameplayMetrics()
            self.baccaratMetrics.lastBalanceBeforeHand = resuming.endingBalance
            self.balanceHistory = resuming.balanceHistory ?? [resuming.endingBalance]
            self.betSizeHistory = resuming.betSizeHistory ?? []
            self.atmVisitIndices = resuming.atmVisitIndices ?? []
            self.lastBalanceBeforeHand = resuming.endingBalance
            self.currentBalance = resuming.endingBalance
            self.hasBeenSaved = false
        } else {
            self.baccaratMetrics = BaccaratGameplayMetrics()
            self.baccaratMetrics.lastBalanceBeforeHand = startingBalance
            self.balanceHistory = [startingBalance]
            self.betSizeHistory = []
            self.atmVisitIndices = []
        }
    }

    // MARK: - Public Methods

    func startSession() {
        guard sessionId == nil else { return }

        sessionId = UUID().uuidString
        sessionStartTime = Date()
        accumulatedPlayTime = 0
        currentPeriodStartTime = Date()
        handCount = 0
        baccaratMetrics = BaccaratGameplayMetrics()
        baccaratMetrics.lastBalanceBeforeHand = startingBalance
        balanceHistory = [startingBalance]
        betSizeHistory = []
        atmVisitIndices = []
        lastBalanceBeforeHand = startingBalance
        hasBeenSaved = false

        if let id = sessionId {
            delegate?.sessionDidStart(id: id)
        }
    }

    func pauseSessionTimer() {
        guard let periodStart = currentPeriodStartTime else { return }
        let currentPeriodDuration = Date().timeIntervalSince(periodStart)
        accumulatedPlayTime += currentPeriodDuration
        currentPeriodStartTime = nil
    }

    func resumeSessionTimer() {
        guard hasActiveSession() else { return }
        currentPeriodStartTime = Date()
    }

    func recordBalanceSnapshot() {
        balanceHistory.append(currentBalance)
        betSizeHistory.append(pendingBetSizeSnapshot)
    }

    func snapshotBetSize(_ betSize: Int) {
        pendingBetSizeSnapshot = betSize
    }

    func updateLastBalanceBeforeHand(_ balance: Int) {
        lastBalanceBeforeHand = balance
    }

    func incrementHandCount() {
        handCount += 1
        delegate?.handCountDidChange(count: handCount)
    }

    func trackBet(amount: Int, isBankerBet: Bool) {
        let betPercent = Double(amount) / Double(max(currentBalance + amount, 1))

        // Check for loss chasing
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

    /// Record a hand result for Big Road history persistence
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

    func trackATMVisit() {
        baccaratMetrics.atmVisitsCount += 1
        atmVisitIndices.append(balanceHistory.count - 1)
        delegate?.metricsDidUpdate(metrics: baccaratMetrics)
    }

    func updateSession() {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return }
        guard handCount > 0 || baccaratMetrics.totalBetAmount > 0 else { return }

        var duration = accumulatedPlayTime
        if let periodStart = currentPeriodStartTime {
            duration += Date().timeIntervalSince(periodStart)
        }

        let endingBalance = currentBalance
        finalizeBalanceHistory()

        let session = GameSession(
            id: sessionId,
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
            baccaratMetrics: baccaratMetrics
        )

        SessionPersistenceManager.shared.saveSession(session)
    }

    func saveCurrentSession() -> GameSession? {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return nil }
        if hasBeenSaved { return nil }
        guard handCount > 0 || baccaratMetrics.totalBetAmount > 0 else { return nil }

        var duration = accumulatedPlayTime
        if let periodStart = currentPeriodStartTime {
            duration += Date().timeIntervalSince(periodStart)
        }

        let endingBalance = currentBalance
        finalizeBalanceHistory()

        let session = GameSession(
            id: sessionId,
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
            baccaratMetrics: baccaratMetrics
        )

        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        delegate?.sessionWasSaved(session: session)
        return session
    }

    @discardableResult
    func saveCurrentSessionForced() -> GameSession? {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return nil }
        guard handCount > 0 || baccaratMetrics.totalBetAmount > 0 else { return nil }

        var duration = accumulatedPlayTime
        if let periodStart = currentPeriodStartTime {
            duration += Date().timeIntervalSince(periodStart)
        }

        let endingBalance = currentBalance
        finalizeBalanceHistory()

        let session = GameSession(
            id: sessionId,
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
            baccaratMetrics: baccaratMetrics
        )

        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        delegate?.sessionWasSaved(session: session)
        return session
    }

    func currentSessionSnapshot() -> GameSession? {
        guard let sessionId = sessionId, let startTime = sessionStartTime else { return nil }

        var duration = accumulatedPlayTime
        if let periodStart = currentPeriodStartTime {
            duration += Date().timeIntervalSince(periodStart)
        }

        let endingBalance = currentBalance

        var balanceSnapshot = balanceHistory
        var betSnapshot = betSizeHistory

        if handCount == 0 {
            balanceSnapshot = [endingBalance]
            betSnapshot = [0]
        } else {
            if balanceSnapshot.isEmpty {
                balanceSnapshot = [startingBalance, endingBalance]
            } else if balanceSnapshot.last != endingBalance {
                balanceSnapshot.append(endingBalance)
            }

            if betSnapshot.isEmpty {
                betSnapshot = Array(repeating: 0, count: balanceSnapshot.count)
            } else if betSnapshot.count < balanceSnapshot.count {
                let lastBet = betSnapshot.last ?? 0
                betSnapshot.append(contentsOf: Array(repeating: lastBet, count: balanceSnapshot.count - betSnapshot.count))
            } else if betSnapshot.count > balanceSnapshot.count {
                betSnapshot = Array(betSnapshot.prefix(balanceSnapshot.count))
            }
        }

        return GameSession(
            id: sessionId,
            date: startTime,
            duration: duration,
            startingBalance: startingBalance,
            endingBalance: endingBalance,
            rollCount: nil,
            gameplayMetrics: nil,
            sevensRolled: nil,
            pointsHit: nil,
            balanceHistory: balanceSnapshot,
            betSizeHistory: betSnapshot,
            atmVisitIndices: atmVisitIndices,
            handCount: handCount,
            blackjackMetrics: nil,
            gameType: .baccarat,
            baccaratMetrics: baccaratMetrics
        )
    }

    func hasActiveSession() -> Bool {
        return sessionId != nil && sessionStartTime != nil
    }

    // MARK: - Private Methods

    private func finalizeBalanceHistory() {
        if handCount == 0 {
            balanceHistory = [currentBalance]
            betSizeHistory = [0]
            return
        }

        if balanceHistory.isEmpty {
            balanceHistory = [startingBalance, currentBalance]
        }

        if balanceHistory.last != currentBalance {
            balanceHistory.append(currentBalance)
        }

        if betSizeHistory.isEmpty {
            betSizeHistory = Array(repeating: 0, count: balanceHistory.count)
        } else if betSizeHistory.count < balanceHistory.count {
            let lastBetSize = betSizeHistory.last ?? 0
            betSizeHistory.append(contentsOf: Array(repeating: lastBetSize, count: balanceHistory.count - betSizeHistory.count))
        } else if betSizeHistory.count > balanceHistory.count {
            betSizeHistory = Array(betSizeHistory.prefix(balanceHistory.count))
        }
    }
}
