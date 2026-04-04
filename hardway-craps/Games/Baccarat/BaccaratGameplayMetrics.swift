//
//  BaccaratGameplayMetrics.swift
//  hardway-craps
//
//  Created by Claude Code on 3/10/26.
//

import Foundation

/// Codable record of a single hand result for Big Road persistence
struct BaccaratHandRecord: Codable {
    enum Result: String, Codable {
        case banker, player, tie
    }
    let result: Result
    var isNatural: Bool = false
    var hasPair: Bool = false
}

struct BaccaratGameplayMetrics: Codable {
    // Hand history for Big Road
    var handHistory: [BaccaratHandRecord] = []

    // Bet metrics
    var bankerBetCount: Int = 0
    var playerBetCount: Int = 0
    var totalBankerBetAmount: Int = 0
    var totalPlayerBetAmount: Int = 0

    var maxConcurrentBets: Int = 0
    var largestBetAmount: Int = 0
    var largestBetPercent: Double = 0.0

    var betsAfterLossCount: Int = 0
    var lastBalanceBeforeHand: Int = 0
    var atmVisitsCount: Int = 0
    var totalATMAmount: Int = 0

    // Outcome metrics
    var bankerWins: Int = 0
    var playerWins: Int = 0
    var ties: Int = 0
    var naturals: Int = 0  // Natural 8 or 9

    // Computed
    var totalBetAmount: Int {
        return totalBankerBetAmount + totalPlayerBetAmount
    }

    var totalHandsPlayed: Int {
        return bankerWins + playerWins + ties
    }

    // Default initializer
    init() {}

    // Custom decoder for backwards compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        handHistory = try container.decodeIfPresent([BaccaratHandRecord].self, forKey: .handHistory) ?? []

        bankerBetCount = try container.decodeIfPresent(Int.self, forKey: .bankerBetCount) ?? 0
        playerBetCount = try container.decodeIfPresent(Int.self, forKey: .playerBetCount) ?? 0
        totalBankerBetAmount = try container.decodeIfPresent(Int.self, forKey: .totalBankerBetAmount) ?? 0
        totalPlayerBetAmount = try container.decodeIfPresent(Int.self, forKey: .totalPlayerBetAmount) ?? 0

        maxConcurrentBets = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentBets) ?? 0
        largestBetAmount = try container.decodeIfPresent(Int.self, forKey: .largestBetAmount) ?? 0
        largestBetPercent = try container.decodeIfPresent(Double.self, forKey: .largestBetPercent) ?? 0.0

        betsAfterLossCount = try container.decodeIfPresent(Int.self, forKey: .betsAfterLossCount) ?? 0
        lastBalanceBeforeHand = try container.decodeIfPresent(Int.self, forKey: .lastBalanceBeforeHand) ?? 0
        atmVisitsCount = try container.decodeIfPresent(Int.self, forKey: .atmVisitsCount) ?? 0
        totalATMAmount = try container.decodeIfPresent(Int.self, forKey: .totalATMAmount) ?? 0

        bankerWins = try container.decodeIfPresent(Int.self, forKey: .bankerWins) ?? 0
        playerWins = try container.decodeIfPresent(Int.self, forKey: .playerWins) ?? 0
        ties = try container.decodeIfPresent(Int.self, forKey: .ties) ?? 0
        naturals = try container.decodeIfPresent(Int.self, forKey: .naturals) ?? 0
    }
}
