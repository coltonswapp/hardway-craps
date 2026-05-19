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
}

/// Manages pass line and odds bet logic, calculations, and animations
final class CrapsPassLineManager {

    // MARK: - Properties

    weak var delegate: CrapsPassLineManagerDelegate?
    var rules: CrapsVariantRules = StandardCrapsVariantRules()

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// Calculate odds multiplier for a given point number
    /// - Parameter point: The point number (4, 5, 6, 8, 9, 10)
    /// - Returns: The odds multiplier (2.0, 1.5, or 1.2)
    func calculateOddsMultiplier(for point: Int) -> Double {
        return rules.passLineOddsMultiplier(for: point)
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
    /// Returns TOTAL payout (original bet + profit)
    /// - Parameters:
    ///   - betAmount: The odds bet amount
    ///   - point: The point number
    /// - Returns: Win result with point-based payout
    func calculateOddsPayout(betAmount: Int, point: Int) -> PassLineWinResult {
        let multiplier = calculateOddsMultiplier(for: point)
        let profit = Int(Double(betAmount) * multiplier)
        let winnings = betAmount + profit  // Original bet + profit
        return PassLineWinResult(
            originalBet: betAmount,
            winnings: winnings,  // Total payout (bet + profit)
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

    // MARK: - Don't Pass Odds

    /// Calculate don't pass (lay) odds multiplier for a given point
    /// Lay odds are the inverse of pass line odds
    /// - Parameter point: The point number (4, 5, 6, 8, 9, or 10)
    /// - Returns: The lay odds multiplier
    func calculateDontPassOddsMultiplier(for point: Int) -> Double {
        return rules.dontPassOddsMultiplier(for: point)
    }

    /// Calculate don't pass odds payout based on point number
    /// Returns TOTAL payout (original bet + profit)
    /// - Parameters:
    ///   - betAmount: The odds bet amount
    ///   - point: The point number
    /// - Returns: Win result with lay odds payout
    func calculateDontPassOddsPayout(betAmount: Int, point: Int) -> PassLineWinResult {
        let multiplier = calculateDontPassOddsMultiplier(for: point)
        let profit = Int(Double(betAmount) * multiplier)
        let totalPayout = betAmount + profit  // Original bet + profit
        return PassLineWinResult(
            originalBet: betAmount,
            winnings: totalPayout,  // Total payout (bet + profit)
            oddsMultiplier: multiplier
        )
    }

    /// Update pass line control states based on game phase
    /// - Parameters:
    ///   - isPointPhase: Whether the game is in point phase
    ///   - hasPassLineBet: Whether there's a pass line bet
    ///   - passLineControl: The pass line control to update (with integrated odds support)
    ///   - shouldLock: Whether the bet should be locked (only after first roll after placing bet during point phase)
    func updateControlStates(
        isPointPhase: Bool,
        hasPassLineBet: Bool,
        passLineControl: PlainControl,
        shouldLock: Bool = false
    ) {
        // Keep control enabled at all times - use locking instead of disabling
        // This allows adding odds when point is set
        passLineControl.isEnabled = true

        // Update disabled state for pass line control (visual locked appearance)
        // Only show locked/greyed out appearance when bet is actually locked (after first roll)
        // This prevents the control from looking locked when bet is first placed during point phase
        passLineControl.setBetRemovalDisabled(shouldLock)

        // Lock/unlock bet for odds support
        // Only lock if shouldLock is true (bet was placed during point phase and roll has occurred)
        // This allows adding to bet when point is set but bet hasn't been rolled yet
        if isPointPhase && hasPassLineBet && shouldLock {
            // Point is set, bet exists, and roll has occurred - lock the bet so odds can be added
            passLineControl.lockBet()
        } else if !isPointPhase || !hasPassLineBet {
            // Not in point phase or no bet - unlock (will clear odds if any)
            // Only unlock when we're actually leaving point phase or removing bet
            passLineControl.unlockBet(clearOdds: true)
        } else {
            // We're in point phase with a bet but not locked yet - ensure unlocked state without clearing odds
            // This prevents clearing odds when we're just updating state after adding to bet
            passLineControl.unlockBet(clearOdds: false)
        }
    }
}
