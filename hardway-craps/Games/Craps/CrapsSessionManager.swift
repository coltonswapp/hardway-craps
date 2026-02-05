//
//  CrapsSessionManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/28/26.
//

import Foundation

/// Delegate protocol for session-related events
protocol CrapsSessionManagerDelegate: AnyObject {
    func sessionDidStart(id: String)
    func sessionWasSaved(session: GameSession)
    func metricsDidUpdate(metrics: GameplayMetrics)
    func balanceDidChange(from oldBalance: Int, to newBalance: Int)
    func rollCountDidChange(count: Int)
    func sevenWasRolled(total: Int)
    func pointWasMade(number: Int)
}

/// Manages session lifecycle, metrics collection, and persistence for Craps
final class CrapsSessionManager {

    // MARK: - Properties

    weak var delegate: CrapsSessionManagerDelegate?

    private(set) var sessionId: String?
    private(set) var sessionStartTime: Date?
    private(set) var accumulatedPlayTime: TimeInterval = 0
    private(set) var currentPeriodStartTime: Date?
    private(set) var rollCount: Int = 0
    private(set) var sevensRolled: Int = 0
    private(set) var pointsHit: Int = 0
    private(set) var balanceHistory: [Int] = []
    private(set) var betSizeHistory: [Int] = []
    private(set) var atmVisitIndices: [Int] = []  // Track which balance history indices are ATM visits
    private(set) var lastBalanceBeforeRoll: Int
    private(set) var hasBeenSaved: Bool = false
    private(set) var gameplayMetrics: GameplayMetrics

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
        self.lastBalanceBeforeRoll = startingBalance

        if let resuming = resumingSession {
            // Resume existing session
            self.sessionId = resuming.id
            self.sessionStartTime = resuming.date
            self.accumulatedPlayTime = resuming.duration
            self.currentPeriodStartTime = Date() // Start tracking active time from now
            self.rollCount = resuming.rollCount ?? 0
            self.sevensRolled = resuming.sevensRolled ?? 0
            self.pointsHit = resuming.pointsHit ?? 0
            self.gameplayMetrics = resuming.gameplayMetrics ?? GameplayMetrics()
            self.gameplayMetrics.lastBalanceBeforeRoll = resuming.endingBalance
            self.balanceHistory = resuming.balanceHistory ?? [resuming.endingBalance]
            self.betSizeHistory = resuming.betSizeHistory ?? []
            self.atmVisitIndices = resuming.atmVisitIndices ?? []
            self.lastBalanceBeforeRoll = resuming.endingBalance
            self.currentBalance = resuming.endingBalance
            self.hasBeenSaved = false
        } else {
            // Start new session
            self.gameplayMetrics = GameplayMetrics()
            self.gameplayMetrics.lastBalanceBeforeRoll = startingBalance
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
        rollCount = 0
        sevensRolled = 0
        pointsHit = 0
        gameplayMetrics = GameplayMetrics()
        gameplayMetrics.lastBalanceBeforeRoll = startingBalance
        balanceHistory = [startingBalance]
        betSizeHistory = []
        atmVisitIndices = []
        lastBalanceBeforeRoll = startingBalance
        pendingBetSizeSnapshot = 0
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

    /// Record a balance snapshot after a roll completes
    func recordBalanceSnapshot() {
        balanceHistory.append(currentBalance)
        betSizeHistory.append(pendingBetSizeSnapshot)
    }

    /// Snapshot the bet size before rolling
    func snapshotBetSize(_ betSize: Int) {
        pendingBetSizeSnapshot = betSize
    }

    /// Update last balance before roll starts
    func updateLastBalanceBeforeRoll(_ balance: Int) {
        lastBalanceBeforeRoll = balance
        gameplayMetrics.lastBalanceBeforeRoll = balance
    }

    /// Increment roll count
    func incrementRollCount() {
        rollCount += 1
        delegate?.rollCountDidChange(count: rollCount)
    }

    /// Track that a seven was rolled
    func trackSevenRolled() {
        sevensRolled += 1
        delegate?.sevenWasRolled(total: sevensRolled)
    }

    /// Track that a point was made
    func trackPointMade(number: Int) {
        pointsHit += 1
        delegate?.pointWasMade(number: number)
    }

    /// Track an ATM visit (bankroll reload)
    func trackATMVisit() {
        gameplayMetrics.atmVisitsCount += 1
        // Record the index in balance history where ATM visit occurred
        // This will be used to exclude ATM visits from biggest swing calculation
        atmVisitIndices.append(balanceHistory.count)
        delegate?.metricsDidUpdate(metrics: gameplayMetrics)
    }

    /// Track a bet placed
    func trackBet(amount: Int, type: BetType) {
        let betPercent = Double(amount) / Double(max(currentBalance + amount, 1)) * 100.0

        // Check for loss chasing: if placing bet after a loss
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
        }

        // Track largest bet
        if amount > gameplayMetrics.largestBetAmount {
            gameplayMetrics.largestBetAmount = amount
            gameplayMetrics.largestBetPercent = betPercent
        }

        delegate?.metricsDidUpdate(metrics: gameplayMetrics)
    }

    /// Update concurrent bet count
    func updateConcurrentBets(count: Int) {
        if count > gameplayMetrics.maxConcurrentBets {
            gameplayMetrics.maxConcurrentBets = count
            delegate?.metricsDidUpdate(metrics: gameplayMetrics)
        }
    }

    /// Update and save the current session (called after every roll)
    /// This always saves, updating the existing session, so the app can be backgrounded/quit safely
    func updateSession() {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return }

        // Only save session if there was actual gameplay (bets placed or rolls made)
        guard rollCount > 0 || gameplayMetrics.totalBetAmount > 0 else {
            return
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
            rollCount: rollCount,
            gameplayMetrics: gameplayMetrics,
            sevensRolled: sevensRolled,
            pointsHit: pointsHit,
            balanceHistory: balanceHistory,
            betSizeHistory: betSizeHistory,
            atmVisitIndices: atmVisitIndices,
            handCount: nil,
            blackjackMetrics: nil
        )

        SessionPersistenceManager.shared.saveSession(session)
        // Note: Don't set hasBeenSaved = true here, so this can be called multiple times
    }

    /// Save the current session
    func saveCurrentSession() -> GameSession? {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return nil }

        // If already saved (e.g., on background), don't save again unless explicitly ending
        if hasBeenSaved {
            return nil
        }

        // Only save session if there was actual gameplay (bets placed or rolls made)
        guard rollCount > 0 || gameplayMetrics.totalBetAmount > 0 else {
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
            rollCount: rollCount,
            gameplayMetrics: gameplayMetrics,
            sevensRolled: sevensRolled,
            pointsHit: pointsHit,
            balanceHistory: balanceHistory,
            betSizeHistory: betSizeHistory,
            atmVisitIndices: atmVisitIndices,
            handCount: nil,
            blackjackMetrics: nil
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
        guard rollCount > 0 || gameplayMetrics.totalBetAmount > 0 else {
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
            rollCount: rollCount,
            gameplayMetrics: gameplayMetrics,
            sevensRolled: sevensRolled,
            pointsHit: pointsHit,
            balanceHistory: balanceHistory,
            betSizeHistory: betSizeHistory,
            atmVisitIndices: atmVisitIndices,
            handCount: nil,
            blackjackMetrics: nil
        )

        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        delegate?.sessionWasSaved(session: session)
        return session
    }

    /// End the current session and clear state
    func endSession() -> GameSession? {
        let session = saveCurrentSessionForced()

        // Clear session tracking
        sessionId = nil
        sessionStartTime = nil
        accumulatedPlayTime = 0
        currentPeriodStartTime = nil
        rollCount = 0
        sevensRolled = 0
        pointsHit = 0
        gameplayMetrics = GameplayMetrics()
        balanceHistory = []
        betSizeHistory = []
        pendingBetSizeSnapshot = 0
        hasBeenSaved = false

        return session
    }

    /// Get a snapshot of the current session (for live display)
    func currentSessionSnapshot() -> GameSession? {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return nil }

        // Use accumulated time for duration (not including current period)
        let duration = Date().timeIntervalSince(startTime)
        let endingBalance = currentBalance

        var balanceSnapshot = balanceHistory
        var betSnapshot = betSizeHistory

        if rollCount == 0 {
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
            rollCount: rollCount,
            gameplayMetrics: gameplayMetrics,
            sevensRolled: sevensRolled,
            pointsHit: pointsHit,
            balanceHistory: balanceSnapshot,
            betSizeHistory: betSnapshot,
            atmVisitIndices: atmVisitIndices,
            handCount: nil,
            blackjackMetrics: nil
        )
    }

    /// Check if there's an active session
    func hasActiveSession() -> Bool {
        return sessionId != nil && sessionStartTime != nil
    }

    // MARK: - Private Helper Methods

    /// Finalize balance history to ensure consistency
    private func finalizeBalanceHistory() {
        if rollCount == 0 {
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

// MARK: - BetType Enum

/// Types of bets available in Craps
enum BetType {
    case passLine
    case odds
    case place
    case hardway
    case horn
    case field
    case dontPass
}
