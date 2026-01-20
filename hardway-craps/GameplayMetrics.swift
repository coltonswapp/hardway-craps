//
//  GameplayMetrics.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import Foundation

struct GameplayMetrics: Codable {
    var passLineBetCount: Int = 0
    var oddsBetCount: Int = 0
    var placeBetCount: Int = 0
    var hardwayBetCount: Int = 0
    var hornBetCount: Int = 0
    var fieldBetCount: Int = 0
    
    var totalPassLineAmount: Int = 0
    var totalOddsAmount: Int = 0
    var totalPlaceAmount: Int = 0
    var totalHardwayAmount: Int = 0
    var totalHornAmount: Int = 0
    var totalFieldAmount: Int = 0
    
    var maxConcurrentBets: Int = 0
    var largestBetAmount: Int = 0
    var largestBetPercent: Double = 0.0
    
    var betsAfterLossCount: Int = 0
    var lastBalanceBeforeRoll: Int = 0
    
    var totalBetAmount: Int {
        return totalPassLineAmount + totalOddsAmount + totalPlaceAmount + 
               totalHardwayAmount + totalHornAmount + totalFieldAmount
    }
    
    var propBetAmount: Int {
        return totalHardwayAmount + totalHornAmount
    }
    
    var safeBetAmount: Int {
        return totalPassLineAmount + totalOddsAmount + totalPlaceAmount + totalFieldAmount
    }
}

struct BlackjackGameplayMetrics: Codable {
    var mainBetCount: Int = 0
    var bonusBetCount: Int = 0
    
    var totalMainBetAmount: Int = 0
    var totalBonusBetAmount: Int = 0
    
    var maxConcurrentBets: Int = 0
    var largestBetAmount: Int = 0
    var largestBetPercent: Double = 0.0
    
    var betsAfterLossCount: Int = 0
    var lastBalanceBeforeHand: Int = 0
    
    var blackjacksHit: Int = 0
    var doublesDown: Int = 0
    var splits: Int = 0
    var wins: Int = 0
    var losses: Int = 0
    var pushes: Int = 0
    
    var totalBetAmount: Int {
        return totalMainBetAmount + totalBonusBetAmount
    }
    
    var bonusBetRatio: Double {
        guard totalBetAmount > 0 else { return 0 }
        return Double(totalBonusBetAmount) / Double(totalBetAmount)
    }
}

enum PlayerType: String, Codable {
    case conservative = "Conservative"
    case strategic = "Strategic"
    case balanced = "Balanced"
    case aggressive = "Aggressive"
    case reckless = "Reckless"
    
    var emoji: String {
        switch self {
        case .conservative: return "🛡️"
        case .strategic: return "🧠"
        case .balanced: return "⚖️"
        case .aggressive: return "⚡"
        case .reckless: return "🔥"
        }
    }
}

