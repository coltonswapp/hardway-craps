//
//  BlackjackSessionManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/26/26.
//

import Foundation

/// Delegate protocol for session-related events
protocol BlackjackSessionManagerDelegate: AnyObject {
    func sessionDidStart(id: String)
    func sessionWasSaved(session: GameSession)
    func metricsDidUpdate(metrics: BlackjackGameplayMetrics)
    func balanceDidChange(from oldBalance: Int, to newBalance: Int)
    func handCountDidChange(count: Int)
}

/// Manages session lifecycle, metrics collection, and persistence
final class BlackjackSessionManager {

    // MARK: - Properties

    weak var delegate: BlackjackSessionManagerDelegate?

    private(set) var sessionId: String?
    private(set) var sessionStartTime: Date?
    private(set) var accumulatedPlayTime: TimeInterval = 0
    private(set) var currentPeriodStartTime: Date?
    private(set) var handCount: Int = 0
    private(set) var balanceHistory: [Int] = []
    private(set) var betSizeHistory: [Int] = []
    private(set) var lastBalanceBeforeHand: Int
    private(set) var hasBeenSaved: Bool = false
    private(set) var blackjackMetrics: BlackjackGameplayMetrics

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
            // Resume existing session
            self.sessionId = resuming.id
            self.sessionStartTime = resuming.date
            self.accumulatedPlayTime = resuming.duration
            self.currentPeriodStartTime = Date() // Start tracking active time from now
            self.handCount = resuming.handCount ?? 0
            self.blackjackMetrics = resuming.blackjackMetrics ?? BlackjackGameplayMetrics()
            self.blackjackMetrics.lastBalanceBeforeHand = resuming.endingBalance
            self.balanceHistory = resuming.balanceHistory ?? [resuming.endingBalance]
            self.betSizeHistory = resuming.betSizeHistory ?? []
            self.lastBalanceBeforeHand = resuming.endingBalance
            self.currentBalance = resuming.endingBalance
            self.hasBeenSaved = false
        } else {
            // Start new session
            self.blackjackMetrics = BlackjackGameplayMetrics()
            self.blackjackMetrics.lastBalanceBeforeHand = startingBalance
            self.balanceHistory = [startingBalance]
            self.betSizeHistory = []
        }
    }

    // MARK: - Public Methods

    /// Start a new session
    func startSession() {
        guard sessionId == nil else { return } // Already started

        sessionId = UUID().uuidString
        sessionStartTime = Date()
        accumulatedPlayTime = 0
        currentPeriodStartTime = Date()
        handCount = 0
        blackjackMetrics = BlackjackGameplayMetrics()
        blackjackMetrics.lastBalanceBeforeHand = startingBalance
        balanceHistory = [startingBalance]
        betSizeHistory = []
        lastBalanceBeforeHand = startingBalance
        hasBeenSaved = false

        if let id = sessionId {
            delegate?.sessionDidStart(id: id)
        }
    }

    /// Pause the session timer (when app backgrounds)
    func pauseSessionTimer() {
        guard let periodStart = currentPeriodStartTime else { return }

        // Add the current active period to accumulated time
        let currentPeriodDuration = Date().timeIntervalSince(periodStart)
        accumulatedPlayTime += currentPeriodDuration

        // Clear the current period start
        currentPeriodStartTime = nil
    }

    /// Resume the session timer (when app becomes active)
    func resumeSessionTimer() {
        guard hasActiveSession() else { return }

        // Start a new active period
        currentPeriodStartTime = Date()
    }

    /// Record a balance snapshot after a hand completes
    func recordBalanceSnapshot() {
        balanceHistory.append(currentBalance)
        betSizeHistory.append(pendingBetSizeSnapshot)
    }

    /// Snapshot the bet size before dealing
    func snapshotBetSize(_ betSize: Int) {
        pendingBetSizeSnapshot = betSize
    }

    /// Update last balance before hand starts
    func updateLastBalanceBeforeHand(_ balance: Int) {
        lastBalanceBeforeHand = balance
    }

    /// Increment hand count
    func incrementHandCount() {
        handCount += 1
        delegate?.handCountDidChange(count: handCount)
    }

    /// Track a bet placed
    func trackBet(amount: Int, isMainBet: Bool) {
        let betPercent = Double(amount) / Double(max(currentBalance + amount, 1))

        // Check for loss chasing: if placing bet after a loss
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

        // Track largest bet
        if amount > blackjackMetrics.largestBetAmount {
            blackjackMetrics.largestBetAmount = amount
            blackjackMetrics.largestBetPercent = betPercent
        }

        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    /// Update concurrent bet count
    func updateConcurrentBets(count: Int) {
        if count > blackjackMetrics.maxConcurrentBets {
            blackjackMetrics.maxConcurrentBets = count
            delegate?.metricsDidUpdate(metrics: blackjackMetrics)
        }
    }

    /// Record a win
    func recordWin(isBlackjack: Bool = false) {
        blackjackMetrics.wins += 1
        if isBlackjack {
            blackjackMetrics.blackjacksHit += 1
        }
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    /// Record a loss
    func recordLoss() {
        blackjackMetrics.losses += 1
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    /// Record a push
    func recordPush() {
        blackjackMetrics.pushes += 1
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    /// Record a double down
    func recordDoubleDown() {
        blackjackMetrics.doublesDown += 1
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    /// Record a bonus bet win
    func recordBonusWin(amount: Int, type: String) {
        blackjackMetrics.bonusesWon += 1
        blackjackMetrics.totalBonusWinnings += amount

        // Update specific bonus metrics
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

    /// Update detailed bonus metrics from evaluator
    func updateBonusMetrics(perfectPairs: Int = 0, coloredPairs: Int = 0, mixedPairs: Int = 0,
                            royalMatches: Int = 0, suitedMatches: Int = 0) {
        blackjackMetrics.perfectPairsWon += perfectPairs
        blackjackMetrics.coloredPairsWon += coloredPairs
        blackjackMetrics.mixedPairsWon += mixedPairs
        blackjackMetrics.royalMatchesWon += royalMatches
        blackjackMetrics.suitedMatchesWon += suitedMatches
        delegate?.metricsDidUpdate(metrics: blackjackMetrics)
    }

    /// Save the current session
    func saveCurrentSession() -> GameSession? {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return nil }

        // If already saved (e.g., on background), don't save again unless explicitly ending
        if hasBeenSaved {
            return nil
        }

        // Only save session if there was actual gameplay (bets placed or hands played)
        guard handCount > 0 || blackjackMetrics.totalBetAmount > 0 else {
            return nil
        }

        // Calculate total duration: accumulated time + current active period (if any)
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
            atmVisitIndices: nil,  // ATM visits not implemented for Blackjack yet
            handCount: handCount,
            blackjackMetrics: blackjackMetrics
        )

        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        delegate?.sessionWasSaved(session: session)
        return session
    }

    /// Force save the current session (for explicit end session)
    func saveCurrentSessionForced() -> GameSession? {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return nil }

        // Only save session if there was actual gameplay
        guard handCount > 0 || blackjackMetrics.totalBetAmount > 0 else {
            return nil
        }

        // Calculate total duration: accumulated time + current active period (if any)
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
            atmVisitIndices: nil,  // ATM visits not implemented for Blackjack yet
            handCount: handCount,
            blackjackMetrics: blackjackMetrics
        )

        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        delegate?.sessionWasSaved(session: session)
        return session
    }

    /// Get a snapshot of the current session
    func currentSessionSnapshot() -> GameSession? {
        guard let sessionId = sessionId, let startTime = sessionStartTime else { return nil }

        // Calculate duration including current period
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
            atmVisitIndices: nil,  // ATM visits not implemented for Blackjack yet
            handCount: handCount,
            blackjackMetrics: blackjackMetrics
        )
    }

    /// Check if there's an active session
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
