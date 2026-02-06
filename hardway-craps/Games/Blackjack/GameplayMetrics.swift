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
    var dontPassBetCount: Int = 0
    var comeBetCount: Int = 0

    var totalPassLineAmount: Int = 0
    var totalOddsAmount: Int = 0
    var totalPlaceAmount: Int = 0
    var totalHardwayAmount: Int = 0
    var totalHornAmount: Int = 0
    var totalFieldAmount: Int = 0
    var totalDontPassAmount: Int = 0
    var totalComeBetAmount: Int = 0

    var maxConcurrentBets: Int = 0
    var largestBetAmount: Int = 0
    var largestBetPercent: Double = 0.0

    var betsAfterLossCount: Int = 0
    var lastBalanceBeforeRoll: Int = 0
    var atmVisitsCount: Int = 0

    var totalBetAmount: Int {
        return totalPassLineAmount + totalOddsAmount + totalPlaceAmount +
               totalHardwayAmount + totalHornAmount + totalFieldAmount + totalDontPassAmount + totalComeBetAmount
    }

    var propBetAmount: Int {
        return totalHardwayAmount + totalHornAmount
    }

    var safeBetAmount: Int {
        return totalPassLineAmount + totalOddsAmount + totalPlaceAmount + totalFieldAmount + totalDontPassAmount + totalComeBetAmount
    }

    // Default initializer
    init() {}

    // Custom decoder for backwards compatibility with existing saved sessions
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        passLineBetCount = try container.decode(Int.self, forKey: .passLineBetCount)
        oddsBetCount = try container.decode(Int.self, forKey: .oddsBetCount)
        placeBetCount = try container.decode(Int.self, forKey: .placeBetCount)
        hardwayBetCount = try container.decode(Int.self, forKey: .hardwayBetCount)
        hornBetCount = try container.decode(Int.self, forKey: .hornBetCount)
        fieldBetCount = try container.decode(Int.self, forKey: .fieldBetCount)

        totalPassLineAmount = try container.decode(Int.self, forKey: .totalPassLineAmount)
        totalOddsAmount = try container.decode(Int.self, forKey: .totalOddsAmount)
        totalPlaceAmount = try container.decode(Int.self, forKey: .totalPlaceAmount)
        totalHardwayAmount = try container.decode(Int.self, forKey: .totalHardwayAmount)
        totalHornAmount = try container.decode(Int.self, forKey: .totalHornAmount)
        totalFieldAmount = try container.decode(Int.self, forKey: .totalFieldAmount)

        maxConcurrentBets = try container.decode(Int.self, forKey: .maxConcurrentBets)
        largestBetAmount = try container.decode(Int.self, forKey: .largestBetAmount)
        largestBetPercent = try container.decode(Double.self, forKey: .largestBetPercent)

        betsAfterLossCount = try container.decode(Int.self, forKey: .betsAfterLossCount)
        lastBalanceBeforeRoll = try container.decode(Int.self, forKey: .lastBalanceBeforeRoll)

        // New fields - use default values if not present (backwards compatibility)
        dontPassBetCount = try container.decodeIfPresent(Int.self, forKey: .dontPassBetCount) ?? 0
        totalDontPassAmount = try container.decodeIfPresent(Int.self, forKey: .totalDontPassAmount) ?? 0
        comeBetCount = try container.decodeIfPresent(Int.self, forKey: .comeBetCount) ?? 0
        totalComeBetAmount = try container.decodeIfPresent(Int.self, forKey: .totalComeBetAmount) ?? 0
        atmVisitsCount = try container.decodeIfPresent(Int.self, forKey: .atmVisitsCount) ?? 0
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
    var atmVisitsCount: Int = 0

    var blackjacksHit: Int = 0
    var doublesDown: Int = 0
    var splits: Int = 0
    var wins: Int = 0
    var losses: Int = 0
    var pushes: Int = 0

    // Bonus tracking - Perfect Pairs
    var perfectPairsWon: Int = 0        // 30:1 - same rank and suit
    var coloredPairsWon: Int = 0        // 10:1 - same rank, same color
    var mixedPairsWon: Int = 0          // 5:1 - same rank, different colors

    // Bonus tracking - Royal Match
    var royalMatchesWon: Int = 0        // 25:1 - K+Q suited
    var suitedMatchesWon: Int = 0       // 3:1 - any suited cards

    // Bonus tracking - totals
    var bonusesWon: Int = 0
    var totalBonusWinnings: Int = 0

    var totalBetAmount: Int {
        return totalMainBetAmount + totalBonusBetAmount
    }

    var bonusBetRatio: Double {
        guard totalBetAmount > 0 else { return 0 }
        return Double(totalBonusBetAmount) / Double(totalBetAmount)
    }

    // Default initializer
    init() {}

    // Custom decoder for backwards compatibility with existing saved sessions
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        mainBetCount = try container.decode(Int.self, forKey: .mainBetCount)
        bonusBetCount = try container.decode(Int.self, forKey: .bonusBetCount)

        totalMainBetAmount = try container.decode(Int.self, forKey: .totalMainBetAmount)
        totalBonusBetAmount = try container.decode(Int.self, forKey: .totalBonusBetAmount)

        maxConcurrentBets = try container.decode(Int.self, forKey: .maxConcurrentBets)
        largestBetAmount = try container.decode(Int.self, forKey: .largestBetAmount)
        largestBetPercent = try container.decode(Double.self, forKey: .largestBetPercent)

        betsAfterLossCount = try container.decode(Int.self, forKey: .betsAfterLossCount)
        lastBalanceBeforeHand = try container.decode(Int.self, forKey: .lastBalanceBeforeHand)

        // New fields - use default values if not present (backwards compatibility)
        atmVisitsCount = try container.decodeIfPresent(Int.self, forKey: .atmVisitsCount) ?? 0

        blackjacksHit = try container.decode(Int.self, forKey: .blackjacksHit)
        doublesDown = try container.decode(Int.self, forKey: .doublesDown)
        splits = try container.decode(Int.self, forKey: .splits)
        wins = try container.decode(Int.self, forKey: .wins)
        losses = try container.decode(Int.self, forKey: .losses)
        pushes = try container.decode(Int.self, forKey: .pushes)

        // New fields - use default values if not present
        perfectPairsWon = try container.decodeIfPresent(Int.self, forKey: .perfectPairsWon) ?? 0
        coloredPairsWon = try container.decodeIfPresent(Int.self, forKey: .coloredPairsWon) ?? 0
        mixedPairsWon = try container.decodeIfPresent(Int.self, forKey: .mixedPairsWon) ?? 0
        royalMatchesWon = try container.decodeIfPresent(Int.self, forKey: .royalMatchesWon) ?? 0
        suitedMatchesWon = try container.decodeIfPresent(Int.self, forKey: .suitedMatchesWon) ?? 0
        bonusesWon = try container.decodeIfPresent(Int.self, forKey: .bonusesWon) ?? 0
        totalBonusWinnings = try container.decodeIfPresent(Int.self, forKey: .totalBonusWinnings) ?? 0
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

