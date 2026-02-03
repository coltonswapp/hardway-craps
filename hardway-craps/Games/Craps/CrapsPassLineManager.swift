//
//  CrapsPassLineManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/28/26.
//

import Foundation
import UIKit

/// Result of a pass line win calculation
struct PassLineWinResult {
    let originalBet: Int
    let winnings: Int
    let oddsMultiplier: Double
}

/// Delegate protocol for pass line events
protocol CrapsPassLineManagerDelegate: AnyObject {
    func passLineWinProcessed(originalBet: Int, winnings: Int)
    func passLineOddsWinProcessed(originalBet: Int, winnings: Int, point: Int, multiplier: Double)
    func passLineLossProcessed(lostAmount: Int)
    func passLineOddsLossProcessed(lostAmount: Int)
    func rebetAmountDidUpdate(amount: Int)
}

/// Manages pass line and odds bet logic, calculations, and animations
final class CrapsPassLineManager {

    // MARK: - Properties

    weak var delegate: CrapsPassLineManagerDelegate?

    private(set) var rebetEnabled: Bool
    private(set) var rebetAmount: Int
    private(set) var consecutiveBetCount: Int = 0
    private(set) var lastBetAmount: Int = 0

    // MARK: - Initialization

    init(rebetEnabled: Bool = false, rebetAmount: Int = 10) {
        self.rebetEnabled = rebetEnabled
        self.rebetAmount = rebetAmount
    }

    // MARK: - Rebet Methods

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

    // MARK: - Public Methods

    /// Calculate odds multiplier for a given point number
    /// - Parameter point: The point number (4, 5, 6, 8, 9, 10)
    /// - Returns: The odds multiplier (2.0, 1.5, or 1.2)
    func calculateOddsMultiplier(for point: Int) -> Double {
        switch point {
        case 4, 10:
            return 2.0  // 2:1 odds
        case 5, 9:
            return 1.5  // 3:2 odds
        case 6, 8:
            return 1.2  // 6:5 odds
        default:
            return 1.0
        }
    }

    /// Determine if odds should be visible/enabled
    /// - Parameters:
    ///   - isPointPhase: Whether the game is in point phase
    ///   - hasPassLineBet: Whether there's a pass line bet
    /// - Returns: True if odds should be enabled (when point is set and there's a pass line bet)
    func shouldEnableOdds(isPointPhase: Bool, hasPassLineBet: Bool) -> Bool {
        // Odds can only be placed after the point is established
        return isPointPhase && hasPassLineBet
    }

    /// Calculate pass line payout (always 1:1)
    /// - Parameter betAmount: The bet amount
    /// - Returns: Win result with 1:1 payout
    func calculatePassLinePayout(betAmount: Int) -> PassLineWinResult {
        return PassLineWinResult(
            originalBet: betAmount,
            winnings: betAmount,  // 1:1 odds
            oddsMultiplier: 1.0
        )
    }

    /// Calculate odds payout based on point number
    /// - Parameters:
    ///   - betAmount: The odds bet amount
    ///   - point: The point number
    /// - Returns: Win result with point-based payout
    func calculateOddsPayout(betAmount: Int, point: Int) -> PassLineWinResult {
        let multiplier = calculateOddsMultiplier(for: point)
        let winnings = Int(Double(betAmount) * multiplier)
        return PassLineWinResult(
            originalBet: betAmount,
            winnings: winnings,
            oddsMultiplier: multiplier
        )
    }

    /// Process a pass line win
    /// - Parameter betAmount: The bet amount
    /// - Returns: Win result
    func processPassLineWin(betAmount: Int) -> PassLineWinResult {
        let result = calculatePassLinePayout(betAmount: betAmount)
        delegate?.passLineWinProcessed(originalBet: result.originalBet, winnings: result.winnings)
        return result
    }

    /// Process a pass line odds win
    /// - Parameters:
    ///   - betAmount: The odds bet amount
    ///   - point: The point number
    /// - Returns: Win result with odds-based payout
    func processPassLineOddsWin(betAmount: Int, point: Int) -> PassLineWinResult {
        let result = calculateOddsPayout(betAmount: betAmount, point: point)
        delegate?.passLineOddsWinProcessed(
            originalBet: result.originalBet,
            winnings: result.winnings,
            point: point,
            multiplier: result.oddsMultiplier
        )
        return result
    }

    /// Process a pass line loss
    /// - Parameter betAmount: The bet amount lost
    func processPassLineLoss(betAmount: Int) {
        delegate?.passLineLossProcessed(lostAmount: betAmount)
    }

    /// Process a pass line odds loss
    /// - Parameter betAmount: The odds bet amount lost
    func processPassLineOddsLoss(betAmount: Int) {
        delegate?.passLineOddsLossProcessed(lostAmount: betAmount)
    }

    /// Update pass line control states based on game phase
    /// - Parameters:
    ///   - isPointPhase: Whether the game is in point phase
    ///   - hasPassLineBet: Whether there's a pass line bet
    ///   - passLineControl: The pass line control to update
    ///   - oddsControl: The odds control to update
    func updateControlStates(
        isPointPhase: Bool,
        hasPassLineBet: Bool,
        passLineControl: PlainControl,
        oddsControl: PlainControl
    ) {
        let isEnabled = shouldEnableOdds(isPointPhase: isPointPhase, hasPassLineBet: hasPassLineBet)

        // Allow pass line betting at any time, EXCEPT when it already has a bet AND point is set
        // This prevents adding additional bets once a bet exists and point is established
        passLineControl.isEnabled = !(hasPassLineBet && isPointPhase)

        // Update disabled state for pass line control (cannot remove bet when point is set)
        passLineControl.setBetRemovalDisabled(isPointPhase)

        // Update disabled state for odds control (can bet when there's a pass line bet and point is set)
        oddsControl.setBetRemovalDisabled(!isEnabled)
        oddsControl.isEnabled = isEnabled

        // Always show odds control
        oddsControl.isHidden = false
    }
}
