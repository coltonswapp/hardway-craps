//
//  CrapsSpecialBetsManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/28/26.
//

import Foundation

/// Result of a hardway bet evaluation
struct HardwayResult {
    let total: Int
    let isWin: Bool
    let isSoftWayLoss: Bool  // Same total but rolled the "easy way"
    let betAmount: Int
    let oddsMultiplier: Double?
    let winAmount: Int?
}

/// Result of a horn bet evaluation
struct HornResult {
    let isWin: Bool
    let betAmount: Int
    let hornName: String
    let oddsMultiplier: Double?
    let winAmount: Int?
}

/// Result of a field bet evaluation
struct FieldResult {
    let isWin: Bool
    let betAmount: Int
    let oddsMultiplier: Double
    let winAmount: Int
}

/// Result of a don't pass bet evaluation
struct DontPassResult {
    let isWin: Bool
    let isPush: Bool  // True when 12 is rolled on come-out (tie)
    let betAmount: Int
    let oddsMultiplier: Double
    let winAmount: Int
}

/// Result of a Make Em bet evaluation
struct MakeEmResult {
    let isWin: Bool
    let isNewNumber: Bool  // True if this roll marks a new number in the bet
    let betAmount: Int
    let oddsMultiplier: Double?
    let winAmount: Int?
    let hitNumbers: Set<Int>  // All numbers hit so far
}

/// Delegate protocol for special bets events
protocol CrapsSpecialBetsManagerDelegate: AnyObject {
    func hardwayWinEvaluated(total: Int, betAmount: Int, multiplier: Double, winAmount: Int)
    func hardwayLossEvaluated(total: Int, betAmount: Int, isSoftWay: Bool)
    func hornWinEvaluated(hornName: String, betAmount: Int, multiplier: Double, winAmount: Int)
    func fieldWinEvaluated(total: Int, betAmount: Int, multiplier: Double, winAmount: Int)
    func dontPassWinEvaluated(total: Int, betAmount: Int, multiplier: Double, winAmount: Int, isPointPhase: Bool)
    func dontPassPushEvaluated(total: Int, betAmount: Int)
    func makeEmWinEvaluated(betName: String, betAmount: Int, multiplier: Double, winAmount: Int)
    func makeEmNumberHit(betName: String, number: Int)
}

/// Manages hardway, horn, and field bet evaluations and calculations
final class CrapsSpecialBetsManager {

    // MARK: - Properties

    weak var delegate: CrapsSpecialBetsManagerDelegate?

    // MARK: - Hardway Methods

    /// Check if a roll is a hardway (both dice same value)
    /// - Parameters:
    ///   - die1: First die value
    ///   - die2: Second die value
    /// - Returns: True if both dice are the same
    func isHardway(die1: Int, die2: Int) -> Bool {
        return die1 == die2
    }

    /// Evaluate a hardway bet
    /// - Parameters:
    ///   - die1: First die value
    ///   - die2: Second die value
    ///   - hardwayDieValue: The target hardway die value (e.g., 3 for hard 6, 4 for hard 8)
    ///   - betAmount: The bet amount
    ///   - oddsString: The odds string (e.g., "9:1" or "7:1")
    /// - Returns: Hardway result with win/loss information
    func evaluateHardwayBet(
        die1: Int,
        die2: Int,
        hardwayDieValue: Int,
        betAmount: Int,
        oddsString: String
    ) -> HardwayResult {
        let total = die1 + die2
        let hardwayTotal = hardwayDieValue * 2

        // Check if rolled the exact hardway
        let isExactMatch = die1 == hardwayDieValue && die2 == hardwayDieValue

        if isExactMatch {
            // Hardway win!
            let multiplier = calculateHardwayMultiplier(oddsString: oddsString)
            let winAmount = Int(Double(betAmount) * multiplier)
            delegate?.hardwayWinEvaluated(
                total: hardwayTotal,
                betAmount: betAmount,
                multiplier: multiplier,
                winAmount: winAmount
            )
            return HardwayResult(
                total: hardwayTotal,
                isWin: true,
                isSoftWayLoss: false,
                betAmount: betAmount,
                oddsMultiplier: multiplier,
                winAmount: winAmount
            )
        } else if total == hardwayTotal && die1 != die2 {
            // Same total but soft way (easy way) - hardway loses
            delegate?.hardwayLossEvaluated(total: hardwayTotal, betAmount: betAmount, isSoftWay: true)
            return HardwayResult(
                total: hardwayTotal,
                isWin: false,
                isSoftWayLoss: true,
                betAmount: betAmount,
                oddsMultiplier: nil,
                winAmount: nil
            )
        } else {
            // No action
            return HardwayResult(
                total: hardwayTotal,
                isWin: false,
                isSoftWayLoss: false,
                betAmount: betAmount,
                oddsMultiplier: nil,
                winAmount: nil
            )
        }
    }

    /// Calculate hardway multiplier from odds string
    /// - Parameter oddsString: Odds string (e.g., "9:1")
    /// - Returns: Multiplier (9:1 = 10x, 7:1 = 8x)
    private func calculateHardwayMultiplier(oddsString: String) -> Double {
        if oddsString == "9:1" {
            return 10.0  // 9:1 means you get 9x profit + original bet = 10x total
        } else {
            return 8.0   // 7:1 means you get 7x profit + original bet = 8x total
        }
    }

    // MARK: - Horn Methods

    /// Evaluate a horn bet
    /// - Parameters:
    ///   - die1: First die value rolled
    ///   - die2: Second die value rolled
    ///   - hornDieValue1: First die value of horn bet
    ///   - hornDieValue2: Second die value of horn bet
    ///   - betAmount: The bet amount
    ///   - oddsString: The odds string (e.g., "30:1" or "15:1")
    /// - Returns: Horn result with win/loss information
    func evaluateHornBet(
        die1: Int,
        die2: Int,
        hornDieValue1: Int,
        hornDieValue2: Int,
        betAmount: Int,
        oddsString: String
    ) -> HornResult {
        // Check if this roll matches the horn bet exactly (both orders)
        let isMatch = (die1 == hornDieValue1 && die2 == hornDieValue2) ||
                      (die1 == hornDieValue2 && die2 == hornDieValue1)

        if isMatch {
            // Horn bet wins!
            let multiplier = calculateHornMultiplier(oddsString: oddsString)
            let winAmount = Int(Double(betAmount) * multiplier)
            let hornName = getHornBetName(dieValue1: hornDieValue1, dieValue2: hornDieValue2)

            delegate?.hornWinEvaluated(
                hornName: hornName,
                betAmount: betAmount,
                multiplier: multiplier,
                winAmount: winAmount
            )

            return HornResult(
                isWin: true,
                betAmount: betAmount,
                hornName: hornName,
                oddsMultiplier: multiplier,
                winAmount: winAmount
            )
        } else {
            let hornName = getHornBetName(dieValue1: hornDieValue1, dieValue2: hornDieValue2)
            return HornResult(
                isWin: false,
                betAmount: betAmount,
                hornName: hornName,
                oddsMultiplier: nil,
                winAmount: nil
            )
        }
    }

    /// Calculate horn multiplier from odds string
    /// - Parameter oddsString: Odds string (e.g., "30:1")
    /// - Returns: Multiplier (30:1 = 31x, 15:1 = 16x)
    private func calculateHornMultiplier(oddsString: String) -> Double {
        if oddsString == "30:1" {
            return 31.0  // 30:1 means you get 30x profit + original bet = 31x total
        } else {
            return 16.0  // 15:1 means you get 15x profit + original bet = 16x total
        }
    }

    /// Get descriptive name for horn bet
    /// - Parameters:
    ///   - dieValue1: First die value
    ///   - dieValue2: Second die value
    /// - Returns: Descriptive name (e.g., "Snake Eyes", "Boxcars")
    func getHornBetName(dieValue1: Int, dieValue2: Int) -> String {
        if dieValue1 == 1 && dieValue2 == 1 {
            return "Snake Eyes"
        } else if dieValue1 == 6 && dieValue2 == 6 {
            return "Boxcars"
        } else if (dieValue1 == 1 && dieValue2 == 2) || (dieValue1 == 2 && dieValue2 == 1) {
            return "Ace-Deuce"
        } else if (dieValue1 == 5 && dieValue2 == 6) || (dieValue1 == 6 && dieValue2 == 5) {
            return "Five-Six"
        } else {
            return "Horn Bet"
        }
    }

    // MARK: - Field Methods

    /// Check if a number is a field number
    /// - Parameter total: Dice total
    /// - Returns: True if field number (2, 3, 4, 9, 10, 11, 12)
    func isFieldNumber(_ total: Int) -> Bool {
        return [2, 3, 4, 9, 10, 11, 12].contains(total)
    }

    /// Evaluate a field bet
    /// - Parameters:
    ///   - total: Dice total
    ///   - betAmount: The bet amount
    /// - Returns: Field result with win/loss and payout information
    func evaluateFieldBet(total: Int, betAmount: Int) -> FieldResult {
        if isFieldNumber(total) {
            // Field pays 2:1 on 2 and 12, 1:1 on other field numbers
            let multiplier: Double = (total == 2 || total == 12) ? 2.0 : 1.0
            let winAmount = Int(Double(betAmount) * multiplier)

            delegate?.fieldWinEvaluated(
                total: total,
                betAmount: betAmount,
                multiplier: multiplier,
                winAmount: winAmount
            )

            return FieldResult(
                isWin: true,
                betAmount: betAmount,
                oddsMultiplier: multiplier,
                winAmount: winAmount
            )
        } else {
            return FieldResult(
                isWin: false,
                betAmount: betAmount,
                oddsMultiplier: 0.0,
                winAmount: 0
            )
        }
    }

    /// Calculate field payout
    /// - Parameters:
    ///   - total: Dice total
    ///   - betAmount: The bet amount
    /// - Returns: Win amount (2x for 2/12, 1x for other field numbers, 0 for non-field)
    func calculateFieldPayout(total: Int, betAmount: Int) -> Int {
        let result = evaluateFieldBet(total: total, betAmount: betAmount)
        return result.winAmount
    }

    // MARK: - Don't Pass Methods

    /// Evaluate a don't pass bet on come-out roll
    /// - Parameters:
    ///   - total: Dice total
    ///   - betAmount: The bet amount
    /// - Returns: Don't pass result with win/loss/push information
    func evaluateDontPassComeOutRoll(total: Int, betAmount: Int) -> DontPassResult {
        if total == 2 || total == 3 {
            // Don't pass wins on 2 or 3 (pays 1:1)
            let multiplier = 1.0
            let winAmount = Int(Double(betAmount) * multiplier)

            delegate?.dontPassWinEvaluated(
                total: total,
                betAmount: betAmount,
                multiplier: multiplier,
                winAmount: winAmount,
                isPointPhase: false
            )

            return DontPassResult(
                isWin: true,
                isPush: false,
                betAmount: betAmount,
                oddsMultiplier: multiplier,
                winAmount: winAmount
            )
        } else if total == 12 {
            // Don't pass pushes (tie) on 12
            delegate?.dontPassPushEvaluated(total: total, betAmount: betAmount)

            return DontPassResult(
                isWin: false,
                isPush: true,
                betAmount: betAmount,
                oddsMultiplier: 0.0,
                winAmount: 0
            )
        } else if total == 7 || total == 11 {
            // Don't pass loses on 7 or 11
            return DontPassResult(
                isWin: false,
                isPush: false,
                betAmount: betAmount,
                oddsMultiplier: 0.0,
                winAmount: 0
            )
        } else {
            // Point established (4, 5, 6, 8, 9, 10) - no action yet
            return DontPassResult(
                isWin: false,
                isPush: false,
                betAmount: betAmount,
                oddsMultiplier: 0.0,
                winAmount: 0
            )
        }
    }

    /// Evaluate a don't pass bet during point phase
    /// - Parameters:
    ///   - total: Dice total
    ///   - point: The established point
    ///   - betAmount: The bet amount
    /// - Returns: Don't pass result with win/loss information
    func evaluateDontPassPointPhase(total: Int, point: Int, betAmount: Int) -> DontPassResult {
        if total == 7 {
            // Don't pass wins on 7 before point (pays 1:1)
            let multiplier = 1.0
            let winAmount = Int(Double(betAmount) * multiplier)

            delegate?.dontPassWinEvaluated(
                total: total,
                betAmount: betAmount,
                multiplier: multiplier,
                winAmount: winAmount,
                isPointPhase: true
            )

            return DontPassResult(
                isWin: true,
                isPush: false,
                betAmount: betAmount,
                oddsMultiplier: multiplier,
                winAmount: winAmount
            )
        } else if total == point {
            // Don't pass loses if point is made
            return DontPassResult(
                isWin: false,
                isPush: false,
                betAmount: betAmount,
                oddsMultiplier: 0.0,
                winAmount: 0
            )
        } else {
            // No action
            return DontPassResult(
                isWin: false,
                isPush: false,
                betAmount: betAmount,
                oddsMultiplier: 0.0,
                winAmount: 0
            )
        }
    }

    // MARK: - Make Em Methods

    /// Evaluate a Make Em bet
    /// - Parameters:
    ///   - total: Dice total rolled
    ///   - betName: Name of the bet ("Make Em Small" or "Make Em Tall")
    ///   - targetNumbers: Array of target numbers for this bet
    ///   - hitNumbers: Set of numbers already hit
    ///   - betAmount: The bet amount
    ///   - oddsString: The odds string (e.g., "150:1" or "150:1")
    /// - Returns: Make Em result with win/loss and progress information
    func evaluateMakeEmBet(
        total: Int,
        betName: String,
        targetNumbers: [Int],
        hitNumbers: Set<Int>,
        betAmount: Int,
        oddsString: String
    ) -> MakeEmResult {
        var updatedHitNumbers = hitNumbers

        // Check if this roll is one of the target numbers
        if targetNumbers.contains(total) {
            let isNewNumber = !hitNumbers.contains(total)

            if isNewNumber {
                updatedHitNumbers.insert(total)
                delegate?.makeEmNumberHit(betName: betName, number: total)
            }

            // Check if all numbers have been hit
            let allNumbersHit = targetNumbers.allSatisfy { updatedHitNumbers.contains($0) }

            if allNumbersHit {
                // Make Em bet wins!
                let multiplier = calculateMakeEmMultiplier(oddsString: oddsString)
                let winAmount = Int(Double(betAmount) * multiplier)

                delegate?.makeEmWinEvaluated(
                    betName: betName,
                    betAmount: betAmount,
                    multiplier: multiplier,
                    winAmount: winAmount
                )

                return MakeEmResult(
                    isWin: true,
                    isNewNumber: isNewNumber,
                    betAmount: betAmount,
                    oddsMultiplier: multiplier,
                    winAmount: winAmount,
                    hitNumbers: updatedHitNumbers
                )
            } else {
                // Progress made, but not complete yet
                return MakeEmResult(
                    isWin: false,
                    isNewNumber: isNewNumber,
                    betAmount: betAmount,
                    oddsMultiplier: nil,
                    winAmount: nil,
                    hitNumbers: updatedHitNumbers
                )
            }
        } else {
            // No action - rolled a number not in the target set
            return MakeEmResult(
                isWin: false,
                isNewNumber: false,
                betAmount: betAmount,
                oddsMultiplier: nil,
                winAmount: nil,
                hitNumbers: updatedHitNumbers
            )
        }
    }

    /// Calculate Make Em multiplier from odds string
    /// - Parameter oddsString: Odds string (e.g., "34:1")
    /// - Returns: Multiplier (150:1 = 151x, 175:1 = 176x)
    private func calculateMakeEmMultiplier(oddsString: String) -> Double {
        if oddsString == "34:1" {
            return 35.0  // 34:1 means you get 150x profit + original bet = 35x total
        } else {
            return 35.0
        }
    }
}
