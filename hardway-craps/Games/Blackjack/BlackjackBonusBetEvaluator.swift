//
//  BlackjackBonusBetEvaluator.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/25/26.
//

import Foundation

/// Evaluates bonus bets for blackjack hands
struct BlackjackBonusBetEvaluator {
    
    // MARK: - Types
    
    typealias Card = BlackjackHandView.Card
    
    /// Result of evaluating a bonus bet
    struct BonusBetResult {
        let isWin: Bool
        let odds: Double
        let winMessage: String?
        let bonusDescription: String?
        let metricsUpdate: MetricsUpdate?
        
        struct MetricsUpdate {
            let perfectPairsWon: Int
            let coloredPairsWon: Int
            let mixedPairsWon: Int
            let royalMatchesWon: Int
            let suitedMatchesWon: Int
            
            static let none = MetricsUpdate(
                perfectPairsWon: 0,
                coloredPairsWon: 0,
                mixedPairsWon: 0,
                royalMatchesWon: 0,
                suitedMatchesWon: 0
            )
        }
    }
    
    /// Result of evaluating a Buster bet
    struct BusterBetResult {
        let isWin: Bool
        let odds: Double
        let winMessage: String?
        let bonusDescription: String?
    }
    
    // MARK: - Public Methods
    
    /// Evaluates a bonus bet based on the bet type and player's first two cards
    /// - Parameters:
    ///   - betType: The type of bonus bet (e.g., "Perfect Pairs", "Lucky Ladies")
    ///   - firstCard: Player's first card
    ///   - secondCard: Player's second card
    ///   - dealerUpcard: Optional dealer upcard (for Lucky 7)
    /// - Returns: Result containing win status, odds, messages, and metrics updates
    static func evaluate(
        betType: String,
        firstCard: Card,
        secondCard: Card,
        dealerUpcard: Card? = nil
    ) -> BonusBetResult {
        switch betType {
        case "Perfect Pairs":
            return evaluatePerfectPairs(firstCard: firstCard, secondCard: secondCard)
        case "Royal Match":
            return evaluateRoyalMatch(firstCard: firstCard, secondCard: secondCard)
        case "Lucky Ladies":
            return evaluateLuckyLadies(firstCard: firstCard, secondCard: secondCard)
        case "Lucky 7":
            return evaluateLucky7(firstCard: firstCard, secondCard: secondCard, dealerUpcard: dealerUpcard)
        default:
            return BonusBetResult(
                isWin: false,
                odds: 0.0,
                winMessage: nil,
                bonusDescription: nil,
                metricsUpdate: nil
            )
        }
    }
    
    /// Evaluates a Buster bet based on dealer's final hand
    /// - Parameters:
    ///   - dealerTotal: Dealer's hand total
    ///   - dealerCardCount: Number of cards in dealer's hand
    /// - Returns: Result containing win status, odds, and messages
    static func evaluateBuster(
        dealerTotal: Int,
        dealerCardCount: Int
    ) -> BusterBetResult {
        guard dealerTotal > 21 else {
            return BusterBetResult(
                isWin: false,
                odds: 0.0,
                winMessage: nil,
                bonusDescription: nil
            )
        }

        // Dealer busted - calculate payout based on number of cards
        let (odds, message, description): (Double, String, String)

        if dealerCardCount >= 6 {
            odds = 250.0
            message = "Buster! Dealer busts with \(dealerCardCount) cards! Pays 250:1!"
            description = "BUSTER 6+"
        } else if dealerCardCount == 5 {
            odds = 6.0
            message = "Buster! Dealer busts with 5 cards! Pays 6:1!"
            description = "BUSTER 5"
        } else if dealerCardCount == 4 {
            odds = 4.0
            message = "Buster! Dealer busts with 4 cards! Pays 4:1!"
            description = "BUSTER 4"
        } else if dealerCardCount == 3 {
            odds = 2.0
            message = "Buster! Dealer busts with 3 cards! Pays 2:1!"
            description = "BUSTER 3"
        } else {
            // Shouldn't happen (dealer needs at least 3 cards to bust), but handle gracefully
            odds = 2.0
            message = "Buster! Dealer busts! Pays 2:1!"
            description = "BUSTER"
        }

        return BusterBetResult(
            isWin: true,
            odds: odds,
            winMessage: message,
            bonusDescription: description
        )
    }

    /// Evaluates a Lucky 7 bet based on all player cards at hand completion
    /// - Parameters:
    ///   - playerCards: All cards in the player's final hand
    /// - Returns: Result containing win status, odds, and messages
    static func evaluateLucky7Complete(playerCards: [Card]) -> BonusBetResult {
        // Count all 7s in the player's hand
        let sevenCount = playerCards.filter { $0.rank == .seven }.count

        guard sevenCount > 0 else {
            return BonusBetResult(
                isWin: false,
                odds: 0.0,
                winMessage: nil,
                bonusDescription: nil,
                metricsUpdate: nil
            )
        }

        if sevenCount >= 3 {
            // Three or more 7s - pays 500:1
            return BonusBetResult(
                isWin: true,
                odds: 500.0,
                winMessage: "Lucky 7! Three 7s pay 500:1!",
                bonusDescription: "LUCKY 7 TRIPLE",
                metricsUpdate: nil
            )
        } else if sevenCount == 2 {
            // Two 7s - check if suited
            let sevens = playerCards.filter { $0.rank == .seven }
            if sevens[0].suit == sevens[1].suit {
                // Two suited 7s - pays 100:1
                return BonusBetResult(
                    isWin: true,
                    odds: 100.0,
                    winMessage: "Lucky 7! Two suited 7s pay 100:1!",
                    bonusDescription: "LUCKY 7 SUITED",
                    metricsUpdate: nil
                )
            } else {
                // Two unsuited 7s - pays 50:1
                return BonusBetResult(
                    isWin: true,
                    odds: 50.0,
                    winMessage: "Lucky 7! Two unsuited 7s pay 50:1!",
                    bonusDescription: "LUCKY 7 PAIR",
                    metricsUpdate: nil
                )
            }
        } else {
            // One 7 - pays 3:1
            return BonusBetResult(
                isWin: true,
                odds: 3.0,
                winMessage: "Lucky 7! One 7 pays 3:1!",
                bonusDescription: "LUCKY 7",
                metricsUpdate: nil
            )
        }
    }
    
    // MARK: - Private Evaluation Methods
    
    private static func evaluatePerfectPairs(firstCard: Card, secondCard: Card) -> BonusBetResult {
        guard firstCard.rank == secondCard.rank else {
            return BonusBetResult(
                isWin: false,
                odds: 0.0,
                winMessage: nil,
                bonusDescription: nil,
                metricsUpdate: nil
            )
        }
        
        // Determine pair type and payout (check highest odds first)
        if firstCard.suit == secondCard.suit {
            // Perfect Pair: same rank and suit - pays 30:1 (highest)
            return BonusBetResult(
                isWin: true,
                odds: 30.0,
                winMessage: "Perfect Pair! Identical \(firstCard.rank.rawValue)s pay 30:1!",
                bonusDescription: "PERFECT PAIR",
                metricsUpdate: BonusBetResult.MetricsUpdate(
                    perfectPairsWon: 1,
                    coloredPairsWon: 0,
                    mixedPairsWon: 0,
                    royalMatchesWon: 0,
                    suitedMatchesWon: 0
                )
            )
        } else {
            // Check if same color (colored pair) or different color (mixed pair)
            let firstIsRed = (firstCard.suit == .hearts || firstCard.suit == .diamonds)
            let secondIsRed = (secondCard.suit == .hearts || secondCard.suit == .diamonds)
            let isSameColor = (firstIsRed == secondIsRed)
            
            if isSameColor {
                // Colored Pair: same rank, same color, different suits - pays 10:1
                return BonusBetResult(
                    isWin: true,
                    odds: 10.0,
                    winMessage: "Colored Pair! \(firstCard.rank.rawValue)s pay 10:1!",
                    bonusDescription: "COLORED PAIR",
                    metricsUpdate: BonusBetResult.MetricsUpdate(
                        perfectPairsWon: 0,
                        coloredPairsWon: 1,
                        mixedPairsWon: 0,
                        royalMatchesWon: 0,
                        suitedMatchesWon: 0
                    )
                )
            } else {
                // Mixed Pair: same rank, different colors - pays 5:1 (lowest)
                return BonusBetResult(
                    isWin: true,
                    odds: 5.0,
                    winMessage: "Mixed Pair! \(firstCard.rank.rawValue)s pay 5:1!",
                    bonusDescription: "MIXED PAIR",
                    metricsUpdate: BonusBetResult.MetricsUpdate(
                        perfectPairsWon: 0,
                        coloredPairsWon: 0,
                        mixedPairsWon: 1,
                        royalMatchesWon: 0,
                        suitedMatchesWon: 0
                    )
                )
            }
        }
    }
    
    private static func evaluateRoyalMatch(firstCard: Card, secondCard: Card) -> BonusBetResult {
        guard firstCard.suit == secondCard.suit else {
            return BonusBetResult(
                isWin: false,
                odds: 0.0,
                winMessage: nil,
                bonusDescription: nil,
                metricsUpdate: nil
            )
        }
        
        // Check if it's a Royal Match (King and Queen of same suit)
        let isKing = (firstCard.rank == .king || secondCard.rank == .king)
        let isQueen = (firstCard.rank == .queen || secondCard.rank == .queen)
        let isRoyalMatch = isKing && isQueen
        
        if isRoyalMatch {
            // Royal Match: K+Q suited - pays 25:1 (highest)
            return BonusBetResult(
                isWin: true,
                odds: 25.0,
                winMessage: "Royal Match! King & Queen suited pay 25:1!",
                bonusDescription: "ROYAL MATCH",
                metricsUpdate: BonusBetResult.MetricsUpdate(
                    perfectPairsWon: 0,
                    coloredPairsWon: 0,
                    mixedPairsWon: 0,
                    royalMatchesWon: 1,
                    suitedMatchesWon: 0
                )
            )
        } else {
            // Suited Cards: Any two suited cards - pays 3:1
            return BonusBetResult(
                isWin: true,
                odds: 3.0,
                winMessage: "Suited Match! Suited cards pay 3:1!",
                bonusDescription: "SUITED MATCH",
                metricsUpdate: BonusBetResult.MetricsUpdate(
                    perfectPairsWon: 0,
                    coloredPairsWon: 0,
                    mixedPairsWon: 0,
                    royalMatchesWon: 0,
                    suitedMatchesWon: 1
                )
            )
        }
    }
    
    private static func evaluateLuckyLadies(firstCard: Card, secondCard: Card) -> BonusBetResult {
        let firstValue = cardValue(firstCard.rank)
        let secondValue = cardValue(secondCard.rank)
        let total = firstValue + secondValue
        
        guard total == 20 else {
            return BonusBetResult(
                isWin: false,
                odds: 0.0,
                winMessage: nil,
                bonusDescription: nil,
                metricsUpdate: nil
            )
        }
        
        // Check for highest payout first
        if firstCard.rank == .queen && secondCard.rank == .queen && 
           firstCard.suit == .hearts && secondCard.suit == .hearts {
            // Queen of Hearts + Queen of Hearts - pays 200:1
            return BonusBetResult(
                isWin: true,
                odds: 200.0,
                winMessage: "Lucky Ladies! Q♥ Q♥ pays 200:1!",
                bonusDescription: "LUCKY LADIES Q♥Q♥",
                metricsUpdate: nil
            )
        } else if firstCard.rank == secondCard.rank {
            // Matched 20 (same rank) - pays 10:1
            return BonusBetResult(
                isWin: true,
                odds: 10.0,
                winMessage: "Lucky Ladies! Matched 20 pays 10:1!",
                bonusDescription: "LUCKY LADIES MATCHED",
                metricsUpdate: nil
            )
        } else if firstCard.suit == secondCard.suit {
            // Suited 20 - pays 25:1
            return BonusBetResult(
                isWin: true,
                odds: 25.0,
                winMessage: "Lucky Ladies! Suited 20 pays 25:1!",
                bonusDescription: "LUCKY LADIES SUITED",
                metricsUpdate: nil
            )
        } else {
            // Any 20 - pays 4:1
            return BonusBetResult(
                isWin: true,
                odds: 4.0,
                winMessage: "Lucky Ladies! Any 20 pays 4:1!",
                bonusDescription: "LUCKY LADIES",
                metricsUpdate: nil
            )
        }
    }
    
    private static func evaluateLucky7(
        firstCard: Card,
        secondCard: Card,
        dealerUpcard: Card?
    ) -> BonusBetResult {
        let playerSevenCount = (firstCard.rank == .seven ? 1 : 0) + (secondCard.rank == .seven ? 1 : 0)
        
        // Check dealer's upcard if available
        let dealerUpcardIsSeven = dealerUpcard?.rank == .seven
        let totalSevenCount = playerSevenCount + (dealerUpcardIsSeven ? 1 : 0)
        
        if totalSevenCount == 3 {
            // Three 7s (player has two 7s + dealer upcard is 7) - pays 500:1
            return BonusBetResult(
                isWin: true,
                odds: 500.0,
                winMessage: "Lucky 7! Three 7s pay 500:1!",
                bonusDescription: "LUCKY 7 TRIPLE",
                metricsUpdate: nil
            )
        } else if playerSevenCount == 2 {
            // Two 7s in player's hand
            if firstCard.suit == secondCard.suit {
                // Two suited 7s - pays 100:1
                return BonusBetResult(
                    isWin: true,
                    odds: 100.0,
                    winMessage: "Lucky 7! Two suited 7s pay 100:1!",
                    bonusDescription: "LUCKY 7 SUITED",
                    metricsUpdate: nil
                )
            } else {
                // Two unsuited 7s - pays 50:1
                return BonusBetResult(
                    isWin: true,
                    odds: 50.0,
                    winMessage: "Lucky 7! Two unsuited 7s pay 50:1!",
                    bonusDescription: "LUCKY 7 PAIR",
                    metricsUpdate: nil
                )
            }
        } else if playerSevenCount == 1 {
            // One 7 - pays 3:1
            return BonusBetResult(
                isWin: true,
                odds: 3.0,
                winMessage: "Lucky 7! One 7 pays 3:1!",
                bonusDescription: "LUCKY 7",
                metricsUpdate: nil
            )
        } else {
            return BonusBetResult(
                isWin: false,
                odds: 0.0,
                winMessage: nil,
                bonusDescription: nil,
                metricsUpdate: nil
            )
        }
    }
    
    // MARK: - Helper Methods
    
    /// Gets the numeric value of a card rank (for side bets)
    private static func cardValue(_ rank: PlayingCardView.Rank) -> Int {
        switch rank {
        case .ace: return 11
        case .king, .queen, .jack, .ten: return 10
        case .nine: return 9
        case .eight: return 8
        case .seven: return 7
        case .six: return 6
        case .five: return 5
        case .four: return 4
        case .three: return 3
        case .two: return 2
        }
    }
}
