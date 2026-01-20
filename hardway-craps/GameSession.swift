//
//  GameSession.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import Foundation

struct GameSession: Codable {
    let id: String
    let date: Date
    let duration: TimeInterval
    let startingBalance: Int
    let endingBalance: Int
    let rollCount: Int?
    let gameplayMetrics: GameplayMetrics?
    let sevensRolled: Int?
    let pointsHit: Int?
    let balanceHistory: [Int]?
    let betSizeHistory: [Int]?
    
    // Blackjack-specific fields
    let handCount: Int?
    let blackjackMetrics: BlackjackGameplayMetrics?
    
    var netResult: Int {
        return endingBalance - startingBalance
    }
    
    var isWin: Bool {
        return endingBalance > startingBalance
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy, h:mma"
        // Remove space before AM/PM if present
        var dateString = formatter.string(from: date)
        dateString = dateString.replacingOccurrences(of: " AM", with: "AM")
        dateString = dateString.replacingOccurrences(of: " PM", with: "PM")
        return dateString
    }
    
    var formattedDurationWithRolls: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let durationString: String
        if minutes > 0 {
            durationString = "\(minutes)m \(seconds)s"
        } else {
            durationString = "\(seconds)s"
        }
        if let rollCount = rollCount {
            return "\(durationString), \(rollCount) rolls"
        } else if let handCount = handCount {
            return "\(durationString), \(handCount) hands"
        } else {
            return durationString
        }
    }
    
    var handCountValue: Int {
        return handCount ?? 0
    }
    
    var isBlackjackSession: Bool {
        return handCount != nil
    }

    var rollCountValue: Int {
        return rollCount ?? 0
    }

    var sevensRolledValue: Int {
        return sevensRolled ?? 0
    }

    var pointsHitValue: Int {
        return pointsHit ?? 0
    }

    var balanceHistoryValue: [Int] {
        if let balanceHistory, !balanceHistory.isEmpty {
            return balanceHistory
        }
        let count = rollCountValue > 0 ? rollCountValue : handCountValue
        if count > 0 {
            return [startingBalance, endingBalance]
        }
        return [endingBalance]
    }

    var betSizeHistoryValue: [Int] {
        if let betSizeHistory, !betSizeHistory.isEmpty {
            return betSizeHistory
        }
        let count = rollCountValue > 0 ? rollCountValue : handCountValue
        if count > 0 {
            return Array(repeating: 0, count: balanceHistoryValue.count)
        }
        return [0]
    }

    var winningRollsCount: Int {
        return rollDeltas.filter { $0 > 0 }.count
    }

    var losingRollsCount: Int {
        return rollDeltas.filter { $0 < 0 }.count
    }
    
    var winningHandsCount: Int {
        guard let metrics = blackjackMetrics else { return 0 }
        return metrics.wins
    }
    
    var losingHandsCount: Int {
        guard let metrics = blackjackMetrics else { return 0 }
        return metrics.losses
    }

    var winRate: Double {
        if isBlackjackSession {
            guard let metrics = blackjackMetrics, handCountValue > 0 else { return 0 }
            let totalHands = metrics.wins + metrics.losses + metrics.pushes
            guard totalHands > 0 else { return 0 }
            return Double(metrics.wins) / Double(totalHands)
        } else {
            guard rollCountValue > 0 else { return 0 }
            return Double(winningRollsCount) / Double(rollCountValue)
        }
    }

    var averageBetSize: Double {
        let bets = betSizeHistoryValue
        guard !bets.isEmpty else { return 0 }
        let total = bets.reduce(0, +)
        return Double(total) / Double(bets.count)
    }

    var biggestSwing: Int {
        return rollDeltas.map { abs($0) }.max() ?? 0
    }

    var longestWinStreak: Int {
        return longestStreak(where: { $0 > 0 })
    }

    var longestLossStreak: Int {
        return longestStreak(where: { $0 < 0 })
    }

    var timePerRoll: TimeInterval {
        guard rollCountValue > 0 else { return 0 }
        return duration / Double(rollCountValue)
    }
    
    var timePerHand: TimeInterval {
        guard handCountValue > 0 else { return 0 }
        return duration / Double(handCountValue)
    }

    var betMixBreakdown: [(label: String, amount: Int, percent: Double)] {
        if isBlackjackSession {
            guard let metrics = blackjackMetrics, metrics.totalBetAmount > 0 else { return [] }
            let total = Double(metrics.totalBetAmount)
            let items: [(String, Int)] = [
                ("Main Bet", metrics.totalMainBetAmount),
                ("Bonus Bet", metrics.totalBonusBetAmount)
            ]
            return items.map { label, amount in
                let percent = total > 0 ? Double(amount) / total : 0
                return (label: label, amount: amount, percent: percent)
            }
        } else {
            guard let metrics = gameplayMetrics, metrics.totalBetAmount > 0 else { return [] }
            let total = Double(metrics.totalBetAmount)
            let items: [(String, Int)] = [
                ("Pass Line", metrics.totalPassLineAmount),
                ("Odds", metrics.totalOddsAmount),
                ("Place", metrics.totalPlaceAmount),
                ("Hardway", metrics.totalHardwayAmount),
                ("Horn", metrics.totalHornAmount),
                ("Field", metrics.totalFieldAmount)
            ]
            return items.map { label, amount in
                let percent = total > 0 ? Double(amount) / total : 0
                return (label: label, amount: amount, percent: percent)
            }
        }
    }

    private var rollDeltas: [Int] {
        let history = balanceHistoryValue
        guard history.count > 1 else { return [] }
        return zip(history.dropFirst(), history.dropLast()).map { $0 - $1 }
    }

    private func longestStreak(where isMatch: (Int) -> Bool) -> Int {
        var longest = 0
        var current = 0
        for delta in rollDeltas {
            if isMatch(delta) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }
    
    var playerType: PlayerType {
        if isBlackjackSession {
            guard let metrics = blackjackMetrics, metrics.totalBetAmount > 0 else {
                return .balanced // Default if no metrics
            }
            
            // Calculate ratios
            let bonusBetRatio = metrics.bonusBetRatio
            
            // Bet sizing (largest bet as % of starting balance)
            let betSizeScore = metrics.largestBetPercent
            
            // Concurrent bets
            let concurrentBetScore = Double(metrics.maxConcurrentBets)
            
            // Loss chasing behavior
            let lossChasingScore = Double(metrics.betsAfterLossCount) / Double(max(handCount ?? 1, 1))
            
            // Calculate scores for each type
            var conservativeScore: Double = 0
            var strategicScore: Double = 0
            var balancedScore: Double = 0
            var aggressiveScore: Double = 0
            var recklessScore: Double = 0
            
            // Conservative: Low bet sizes, low concurrent bets, minimal bonus bets
            conservativeScore += (betSizeScore < 0.05 ? 1.0 : (betSizeScore < 0.15 ? 0.5 : 0.0)) * 0.4
            conservativeScore += (concurrentBetScore <= 1 ? 1.0 : (concurrentBetScore <= 2 ? 0.5 : 0.0)) * 0.3
            conservativeScore += (bonusBetRatio < 0.1 ? 1.0 : (bonusBetRatio < 0.2 ? 0.5 : 0.0)) * 0.3
            
            // Strategic: Moderate bet sizes, calculated decisions, some bonus bets
            strategicScore += (betSizeScore >= 0.05 && betSizeScore <= 0.15 ? 1.0 : 0.0) * 0.4
            strategicScore += (concurrentBetScore >= 1 && concurrentBetScore <= 2 ? 1.0 : 0.0) * 0.3
            strategicScore += (bonusBetRatio >= 0.1 && bonusBetRatio <= 0.3 ? 1.0 : 0.0) * 0.3
            
            // Balanced: Mix of everything, moderate ratios
            balancedScore += (betSizeScore >= 0.05 && betSizeScore <= 0.2 ? 1.0 : 0.0) * 0.3
            balancedScore += (concurrentBetScore >= 1 && concurrentBetScore <= 3 ? 1.0 : 0.0) * 0.3
            balancedScore += (bonusBetRatio >= 0.1 && bonusBetRatio <= 0.3 ? 1.0 : 0.0) * 0.2
            balancedScore += (lossChasingScore < 0.3 ? 1.0 : 0.0) * 0.2
            
            // Aggressive: Higher bet sizes, more concurrent bets, more bonus bets
            aggressiveScore += (betSizeScore >= 0.15 && betSizeScore <= 0.3 ? 1.0 : 0.0) * 0.3
            aggressiveScore += (concurrentBetScore >= 2 ? 1.0 : (concurrentBetScore >= 1 ? 0.5 : 0.0)) * 0.3
            aggressiveScore += (bonusBetRatio >= 0.2 && bonusBetRatio <= 0.4 ? 1.0 : 0.0) * 0.2
            aggressiveScore += (lossChasingScore >= 0.2 && lossChasingScore <= 0.4 ? 1.0 : 0.0) * 0.2
            
            // Reckless: Very high bet sizes, many bonus bets, loss chasing
            recklessScore += (betSizeScore > 0.3 ? 1.0 : (betSizeScore > 0.25 ? 0.5 : 0.0)) * 0.3
            recklessScore += (bonusBetRatio > 0.4 ? 1.0 : (bonusBetRatio > 0.3 ? 0.5 : 0.0)) * 0.3
            recklessScore += (lossChasingScore > 0.4 ? 1.0 : (lossChasingScore > 0.3 ? 0.5 : 0.0)) * 0.2
            recklessScore += (concurrentBetScore >= 3 ? 1.0 : 0.0) * 0.2
            
            // Find the highest score
            let scores: [(PlayerType, Double)] = [
                (.conservative, conservativeScore),
                (.strategic, strategicScore),
                (.balanced, balancedScore),
                (.aggressive, aggressiveScore),
                (.reckless, recklessScore)
            ]
            
            let maxScore = scores.max(by: { $0.1 < $1.1 })!
            
            // If scores are very close, default to balanced
            if maxScore.1 < 0.3 {
                return .balanced
            }
            
            return maxScore.0
        } else {
            guard let metrics = gameplayMetrics, metrics.totalBetAmount > 0 else {
                return .balanced // Default if no metrics
            }
            
            // Calculate ratios
            let propBetRatio = Double(metrics.propBetAmount) / Double(metrics.totalBetAmount)
            let safeBetRatio = Double(metrics.safeBetAmount) / Double(metrics.totalBetAmount)
            
            // Odds bet usage (strategic players maximize odds)
            let oddsUsageRatio = metrics.totalPassLineAmount > 0 ? 
                Double(metrics.totalOddsAmount) / Double(metrics.totalPassLineAmount) : 0.0
            
            // Bet sizing (largest bet as % of starting balance)
            let betSizeScore = metrics.largestBetPercent
            
            // Concurrent bets
            let concurrentBetScore = Double(metrics.maxConcurrentBets)
            
            // Loss chasing behavior
            let lossChasingScore = Double(metrics.betsAfterLossCount) / Double(max(rollCount ?? 1, 1))
            
            // Calculate scores for each type
            var conservativeScore: Double = 0
            var strategicScore: Double = 0
            var balancedScore: Double = 0
            var aggressiveScore: Double = 0
            var recklessScore: Double = 0
            
            // Conservative: High safe bets, low bet sizes, low concurrent bets
            conservativeScore += safeBetRatio * 0.3
            conservativeScore += (betSizeScore < 0.05 ? 1.0 : (betSizeScore < 0.15 ? 0.5 : 0.0)) * 0.3
            conservativeScore += (concurrentBetScore <= 2 ? 1.0 : (concurrentBetScore <= 3 ? 0.5 : 0.0)) * 0.2
            conservativeScore += (propBetRatio < 0.1 ? 1.0 : (propBetRatio < 0.2 ? 0.5 : 0.0)) * 0.2
            
            // Strategic: High odds usage, moderate bet sizes, calculated bets
            strategicScore += (oddsUsageRatio > 0.5 ? 1.0 : (oddsUsageRatio > 0.2 ? 0.5 : 0.0)) * 0.4
            strategicScore += (betSizeScore >= 0.05 && betSizeScore <= 0.15 ? 1.0 : 0.0) * 0.3
            strategicScore += (concurrentBetScore >= 2 && concurrentBetScore <= 4 ? 1.0 : 0.0) * 0.3
            
            // Balanced: Mix of everything, moderate ratios
            balancedScore += (propBetRatio >= 0.1 && propBetRatio <= 0.3 ? 1.0 : 0.0) * 0.3
            balancedScore += (betSizeScore >= 0.05 && betSizeScore <= 0.2 ? 1.0 : 0.0) * 0.3
            balancedScore += (concurrentBetScore >= 2 && concurrentBetScore <= 4 ? 1.0 : 0.0) * 0.2
            balancedScore += (lossChasingScore < 0.3 ? 1.0 : 0.0) * 0.2
            
            // Aggressive: Higher bet sizes, more concurrent bets, more prop bets
            aggressiveScore += (betSizeScore >= 0.15 && betSizeScore <= 0.3 ? 1.0 : 0.0) * 0.3
            aggressiveScore += (concurrentBetScore >= 4 ? 1.0 : (concurrentBetScore >= 3 ? 0.5 : 0.0)) * 0.3
            aggressiveScore += (propBetRatio >= 0.2 && propBetRatio <= 0.4 ? 1.0 : 0.0) * 0.2
            aggressiveScore += (lossChasingScore >= 0.2 && lossChasingScore <= 0.4 ? 1.0 : 0.0) * 0.2
            
            // Reckless: Very high bet sizes, many prop bets, loss chasing
            recklessScore += (betSizeScore > 0.3 ? 1.0 : (betSizeScore > 0.25 ? 0.5 : 0.0)) * 0.3
            recklessScore += (propBetRatio > 0.4 ? 1.0 : (propBetRatio > 0.3 ? 0.5 : 0.0)) * 0.3
            recklessScore += (lossChasingScore > 0.4 ? 1.0 : (lossChasingScore > 0.3 ? 0.5 : 0.0)) * 0.2
            recklessScore += (concurrentBetScore >= 5 ? 1.0 : 0.0) * 0.2
            
            // Find the highest score
            let scores: [(PlayerType, Double)] = [
                (.conservative, conservativeScore),
                (.strategic, strategicScore),
                (.balanced, balancedScore),
                (.aggressive, aggressiveScore),
                (.reckless, recklessScore)
            ]
            
            let maxScore = scores.max(by: { $0.1 < $1.1 })!
            
            // If scores are very close, default to balanced
            if maxScore.1 < 0.3 {
                return .balanced
            }
            
            return maxScore.0
        }
    }
}

