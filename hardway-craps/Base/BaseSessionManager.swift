//
//  BaseSessionManager.swift
//  hardway-craps
//

import Foundation

/// Shared delegate methods common to all game session managers.
protocol BaseSessionManagerDelegate: AnyObject {
    func sessionDidStart(id: String)
    func sessionWasSaved(session: GameSession)
    func balanceDidChange(from oldBalance: Int, to newBalance: Int)
}

/// Extracts the duplicated session lifecycle, timer, balance/bet-size history,
/// ATM tracking, and persistence pipeline shared by Craps, Blackjack, and Baccarat.
///
/// Subclasses provide:
///   - `eventCount` (rolls for craps, hands for BJ/Baccarat)
///   - `hasGameplay` (whether any meaningful gameplay occurred)
///   - `buildGameSession(...)` (fills game-specific fields on `GameSession`)
///   - `resetGameSpecificState()` (clears game-specific counters/metrics)
///   - `onSessionStarted()` (initializes game-specific metrics for a new session)
class BaseSessionManager {

    // MARK: - Shared State

    private(set) var sessionId: String?
    private(set) var sessionStartTime: Date?
    private(set) var accumulatedPlayTime: TimeInterval = 0
    private(set) var currentPeriodStartTime: Date?
    private(set) var balanceHistory: [Int] = []
    private(set) var betSizeHistory: [Int] = []
    private(set) var atmVisitIndices: [Int] = []
    private(set) var hasBeenSaved: Bool = false

    let startingBalance: Int
    var pendingBetSizeSnapshot: Int = 0

    var currentBalance: Int {
        didSet {
            if oldValue != currentBalance {
                balanceDidChange(from: oldValue, to: currentBalance)
            }
        }
    }

    // MARK: - Subclass Hooks

    /// Number of gameplay events (rolls or hands). Override in subclass.
    var eventCount: Int { 0 }

    /// Whether any meaningful gameplay occurred. Override in subclass.
    var hasGameplay: Bool { eventCount > 0 }

    /// Build the full `GameSession` with game-specific fields. Override required.
    func buildGameSession(id: String, startTime: Date, duration: TimeInterval, endingBalance: Int) -> GameSession {
        fatalError("Subclasses must override buildGameSession")
    }

    /// Reset game-specific counters/metrics for a new session. Override in subclass.
    func resetGameSpecificState() {}

    /// Called after a new session ID is created. Override to init game-specific metrics.
    func onSessionStarted() {}

    /// Called when balance changes. Override to notify game-specific delegate.
    func balanceDidChange(from oldBalance: Int, to newBalance: Int) {}

    /// Called when session is saved. Override to notify game-specific delegate.
    func notifySessionSaved(_ session: GameSession) {}

    /// Called when session starts. Override to notify game-specific delegate.
    func notifySessionStarted(id: String) {}

    // MARK: - Initialization

    init(startingBalance: Int, resumingSession: GameSession? = nil) {
        self.startingBalance = startingBalance
        self.currentBalance = startingBalance

        if let resuming = resumingSession {
            self.sessionId = resuming.id
            self.sessionStartTime = resuming.date
            self.accumulatedPlayTime = resuming.duration
            self.currentPeriodStartTime = Date()
            self.balanceHistory = resuming.balanceHistory ?? [resuming.endingBalance]
            self.betSizeHistory = resuming.betSizeHistory ?? []
            self.atmVisitIndices = resuming.atmVisitIndices ?? []
            self.currentBalance = resuming.endingBalance
            self.hasBeenSaved = false
        } else {
            self.balanceHistory = [startingBalance]
            self.betSizeHistory = []
            self.atmVisitIndices = []
        }
    }

    // MARK: - Session Lifecycle

    func startSession() {
        guard sessionId == nil else { return }

        sessionId = UUID().uuidString
        sessionStartTime = Date()
        accumulatedPlayTime = 0
        currentPeriodStartTime = Date()
        balanceHistory = [startingBalance]
        betSizeHistory = []
        atmVisitIndices = []
        pendingBetSizeSnapshot = 0
        hasBeenSaved = false

        onSessionStarted()

        if let id = sessionId {
            notifySessionStarted(id: id)
        }
    }

    func pauseSessionTimer() {
        guard let periodStart = currentPeriodStartTime else { return }
        accumulatedPlayTime += Date().timeIntervalSince(periodStart)
        currentPeriodStartTime = nil
    }

    func resumeSessionTimer() {
        guard hasActiveSession() else { return }
        currentPeriodStartTime = Date()
    }

    func hasActiveSession() -> Bool {
        sessionId != nil && sessionStartTime != nil
    }

    // MARK: - Balance / Bet History

    func recordBalanceSnapshot() {
        balanceHistory.append(currentBalance)
        betSizeHistory.append(pendingBetSizeSnapshot)
    }

    func snapshotBetSize(_ betSize: Int) {
        pendingBetSizeSnapshot = betSize
    }

    func trackATMVisit(amount: Int) {
        atmVisitIndices.append(balanceHistory.count)
    }

    // MARK: - Persistence

    func updateSession() {
        guard let sessionId, let startTime = sessionStartTime else { return }
        guard hasGameplay else { return }
        if UITestLaunchConfiguration.suppressGameplaySessionRecording { return }

        let duration = computeDuration()
        finalizeBalanceHistory()

        let session = buildGameSession(id: sessionId, startTime: startTime, duration: duration, endingBalance: currentBalance)
        SessionPersistenceManager.shared.saveSession(session)
    }

    @discardableResult
    func saveCurrentSession() -> GameSession? {
        guard let sessionId, let startTime = sessionStartTime else { return nil }
        if hasBeenSaved { return nil }
        guard hasGameplay else { return nil }

        if UITestLaunchConfiguration.suppressGameplaySessionRecording {
            hasBeenSaved = true
            return nil
        }

        let duration = computeDuration()
        finalizeBalanceHistory()

        let session = buildGameSession(id: sessionId, startTime: startTime, duration: duration, endingBalance: currentBalance)
        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        notifySessionSaved(session)
        return session
    }

    @discardableResult
    func saveCurrentSessionForced() -> GameSession? {
        guard let sessionId, let startTime = sessionStartTime else { return nil }
        guard hasGameplay else { return nil }

        if UITestLaunchConfiguration.suppressGameplaySessionRecording {
            hasBeenSaved = true
            return nil
        }

        let duration = computeDuration()
        finalizeBalanceHistory()

        let session = buildGameSession(id: sessionId, startTime: startTime, duration: duration, endingBalance: currentBalance)
        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        notifySessionSaved(session)
        return session
    }

    func currentSessionSnapshot() -> GameSession? {
        guard let sessionId, let startTime = sessionStartTime else { return nil }

        let duration = computeDuration()
        let endingBalance = currentBalance

        let savedBalance = balanceHistory
        let savedBets = betSizeHistory

        if eventCount == 0 {
            balanceHistory = [endingBalance]
            betSizeHistory = [0]
        } else {
            if balanceHistory.isEmpty {
                balanceHistory = [startingBalance, endingBalance]
            } else if balanceHistory.last != endingBalance {
                balanceHistory.append(endingBalance)
            }

            if betSizeHistory.isEmpty {
                betSizeHistory = Array(repeating: 0, count: balanceHistory.count)
            } else if betSizeHistory.count < balanceHistory.count {
                let lastBet = betSizeHistory.last ?? 0
                betSizeHistory.append(contentsOf: Array(repeating: lastBet, count: balanceHistory.count - betSizeHistory.count))
            } else if betSizeHistory.count > balanceHistory.count {
                betSizeHistory = Array(betSizeHistory.prefix(balanceHistory.count))
            }
        }

        let session = buildGameSession(
            id: sessionId,
            startTime: startTime,
            duration: duration,
            endingBalance: endingBalance
        )

        balanceHistory = savedBalance
        betSizeHistory = savedBets

        return session
    }

    @discardableResult
    func endSession() -> GameSession? {
        let session = saveCurrentSessionForced()

        sessionId = nil
        sessionStartTime = nil
        accumulatedPlayTime = 0
        currentPeriodStartTime = nil
        balanceHistory = []
        betSizeHistory = []
        pendingBetSizeSnapshot = 0
        hasBeenSaved = false

        resetGameSpecificState()

        return session
    }

    // MARK: - Private

    func computeDuration() -> TimeInterval {
        var duration = accumulatedPlayTime
        if let periodStart = currentPeriodStartTime {
            duration += Date().timeIntervalSince(periodStart)
        }
        return duration
    }

    func finalizeBalanceHistory() {
        if eventCount == 0 {
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
