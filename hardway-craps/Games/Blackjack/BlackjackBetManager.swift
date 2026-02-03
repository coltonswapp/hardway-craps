//
//  BlackjackBetManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/26/26.
//

import Foundation

/// Delegate protocol for bet-related events
protocol BlackjackBetManagerDelegate: AnyObject {
    func rebetAmountDidUpdate(amount: Int)
    func betWasPlaced(amount: Int, isMainBet: Bool)
    func betWasRemoved(amount: Int)
}

/// Manages betting logic including rebet functionality and bet validation
final class BlackjackBetManager {

    // MARK: - Properties

    weak var delegate: BlackjackBetManagerDelegate?

    private(set) var rebetEnabled: Bool
    private(set) var rebetAmount: Int
    private(set) var consecutiveBetCount: Int = 0
    private(set) var lastBetAmount: Int = 0

    // MARK: - Initialization

    init(rebetEnabled: Bool = false, rebetAmount: Int = 10) {
        self.rebetEnabled = rebetEnabled
        self.rebetAmount = rebetAmount
    }

    // MARK: - Public Methods

    /// Update rebet settings
    func updateRebetSettings(enabled: Bool, amount: Int) {
        rebetEnabled = enabled
        rebetAmount = amount
    }

    /// Set rebet enabled state
    func setRebetEnabled(_ enabled: Bool) {
        rebetEnabled = enabled
    }

    /// Set rebet amount
    func setRebetAmount(_ amount: Int) {
        rebetAmount = amount
        delegate?.rebetAmountDidUpdate(amount: amount)
    }

    /// Track a bet for rebet functionality
    /// Updates rebet amount immediately to the current bet amount
    func trackBetForRebet(amount: Int) {
        guard amount > 0 else { return }

        // Update rebet amount immediately to reflect current bet
        setRebetAmount(amount)
        lastBetAmount = amount
    }

    /// Calculate the rebet amount to apply
    /// Returns nil if rebet shouldn't be applied
    func calculateRebetAmount(currentBetAmount: Int, balance: Int) -> Int? {
        guard rebetEnabled else { return nil }

        // Check if player already has a bet placed
        if currentBetAmount > 0 {
            // Player already has a bet (from winning the last hand)
            // The bet stayed on the control and was never returned to balance
            // So we don't need to deduct anything
            return nil
        }

        // No bet on control (player lost last hand)
        // Check if player has enough balance for rebet
        guard rebetAmount <= balance else { return nil }

        return rebetAmount
    }

    /// Check if a bet amount is valid given the current balance
    func canPlaceBet(amount: Int, currentBalance: Int) -> Bool {
        guard amount > 0 else { return false }
        return amount <= currentBalance
    }

    /// Check if a bonus bet can be placed during current game phase
    func canPlaceBonusBet(gamePhase: PlayerControlStack.GamePhase) -> Bool {
        return gamePhase == .waitingForBet || gamePhase == .readyToDeal
    }

    /// Notify delegate that a bet was placed
    func notifyBetPlaced(amount: Int, isMainBet: Bool) {
        delegate?.betWasPlaced(amount: amount, isMainBet: isMainBet)
    }

    /// Notify delegate that a bet was removed
    func notifyBetRemoved(amount: Int) {
        delegate?.betWasRemoved(amount: amount)
    }

    /// Reset consecutive bet tracking
    func resetConsecutiveBetTracking() {
        consecutiveBetCount = 0
        lastBetAmount = 0
    }
}
