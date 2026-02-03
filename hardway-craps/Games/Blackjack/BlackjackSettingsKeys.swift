//
//  BlackjackSettingsKeys.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/26/26.
//

import Foundation

enum BlackjackSettingsKeys {
    static let showTotals = "BlackjackShowTotals"
    static let showDeckCount = "BlackjackShowDeckCount"
    static let showCardCount = "BlackjackShowCardCount"
    static let deckCount = "BlackjackDeckCount"
    static let rebetEnabled = "BlackjackRebetEnabled"
    static let rebetAmount = "BlackjackRebetAmount"
    static let fixedHandType = "BlackjackFixedHandType"
    static let deckPenetration = "BlackjackDeckPenetration"
    static let selectedSideBets = "BlackjackSelectedSideBets"
    static let faceUpDoubleDown = "BlackjackFaceUpDoubleDown"
}

enum FixedHandType: String {
    case perfectPair = "Perfect Pair (30:1)"
    case coloredPair = "Colored Pair (10:1)"
    case mixedPair = "Mixed Pair (5:1)"
    case royalMatch = "Royal Match (25:1)"
    case suitedCards = "Suited Cards (3:1)"
    case regular = "Regular Hand"
    case aceUp = "Ace Up"
    case dealerBlackjack = "Dealer BlackJack"
    case random = "Random"
}
