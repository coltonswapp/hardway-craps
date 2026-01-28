//
//  BlackjackDeckManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/26/26.
//

import Foundation

/// Delegate protocol for deck-related events
protocol BlackjackDeckManagerDelegate: AnyObject {
    func deckWasShuffled(cardCount: Int)
    func cutCardWasReached()
    func cardCountDidUpdate(running: Int, trueCount: Int)
    func deckCountDidChange(remaining: Int)
}

/// Manages deck creation, shuffling, card drawing, and card counting
final class BlackjackDeckManager {

    // MARK: - Properties

    weak var delegate: BlackjackDeckManagerDelegate?

    private(set) var deck: [BlackjackHandView.Card] = []
    private(set) var runningCount: Int = 0
    private(set) var cutCardPosition: Int?
    private(set) var shouldShuffleAfterHand: Bool = false

    var deckCount: Int {
        didSet {
            guard [1, 2, 4, 6].contains(deckCount) else {
                deckCount = oldValue
                return
            }
        }
    }

    var deckPenetration: Double? // nil = full deck, -1.0 = random, 0.0-1.0 = percentage
    var fixedHandType: FixedHandType?

    var cardsRemaining: Int {
        return deck.count
    }

    var trueCount: Int {
        return calculateTrueCount()
    }

    // MARK: - Initialization

    init(deckCount: Int = 1, deckPenetration: Double? = nil, fixedHandType: FixedHandType? = nil) {
        self.deckCount = deckCount
        self.deckPenetration = deckPenetration
        self.fixedHandType = fixedHandType
    }

    // MARK: - Public Methods

    /// Create and shuffle a new deck
    func createAndShuffleDeck() {
        deck.removeAll()

        // Create multiple decks based on deckCount
        for _ in 0..<deckCount {
            // Create a standard 52-card deck
            for suit in PlayingCardView.Suit.allCases {
                for rank in PlayingCardView.Rank.allCases {
                    deck.append(BlackjackHandView.Card(rank: rank, suit: suit))
                }
            }
        }

        // Shuffle the deck
        deck.shuffle()

        // Insert cut card based on deck penetration
        insertCutCard()

        // Reset shuffle flag
        shouldShuffleAfterHand = false

        // Reset card count when deck is shuffled
        runningCount = 0
        delegate?.deckWasShuffled(cardCount: 52 * deckCount)
        delegate?.cardCountDidUpdate(running: 0, trueCount: 0)
    }

    /// Draw a card from the deck
    func drawCard() -> BlackjackHandView.Card {
        // Check if we need to reshuffle before drawing
        if deck.isEmpty || deck.count < 6 {
            // Out of cards or too few cards - shuffle immediately
            createAndShuffleDeck()
            delegate?.deckWasShuffled(cardCount: 52 * deckCount)
        }

        // Draw and remove the top card
        let card = deck.removeFirst()

        // Check if we drew the cut card
        if card.isCutCard {
            // Set flag to shuffle after hand completes
            if !shouldShuffleAfterHand {
                shouldShuffleAfterHand = true
                delegate?.cutCardWasReached()
            }

            // Draw the next card recursively (which should be a real card)
            // Don't update deck count here - let the recursive call handle it
            return drawCard()
        }

        // Only update deck count when returning a real card
        delegate?.deckCountDidChange(remaining: deck.count)
        return card
    }

    /// Deal a fixed hand for testing purposes
    func dealFixedHand(type: FixedHandType) -> (playerCard1: BlackjackHandView.Card,
                                                  playerCard2: BlackjackHandView.Card,
                                                  dealerCard1: BlackjackHandView.Card,
                                                  dealerCard2: BlackjackHandView.Card) {
        let playerCard1: BlackjackHandView.Card
        let playerCard2: BlackjackHandView.Card

        switch type {
        case .perfectPair:
            // Perfect Pair: Same rank and suit (e.g., 7♠, 7♠) - pays 30:1
            playerCard1 = BlackjackHandView.Card(rank: .seven, suit: .spades)
            playerCard2 = BlackjackHandView.Card(rank: .seven, suit: .spades)

        case .coloredPair:
            // Colored Pair: Same rank, same color, different suits (e.g., 7♥, 7♦) - pays 10:1
            playerCard1 = BlackjackHandView.Card(rank: .seven, suit: .hearts)
            playerCard2 = BlackjackHandView.Card(rank: .seven, suit: .diamonds)

        case .mixedPair:
            // Mixed Pair: Same rank, different colors (e.g., 7♥, 7♣) - pays 5:1
            playerCard1 = BlackjackHandView.Card(rank: .seven, suit: .hearts)
            playerCard2 = BlackjackHandView.Card(rank: .seven, suit: .clubs)

        case .royalMatch:
            // Royal Match: Suited King and Queen (e.g., K♥, Q♥) - pays 25:1
            playerCard1 = BlackjackHandView.Card(rank: .king, suit: .hearts)
            playerCard2 = BlackjackHandView.Card(rank: .queen, suit: .hearts)

        case .suitedCards:
            // Suited Cards: Any two suited cards (e.g., 7♥, K♥) - pays 3:1
            playerCard1 = BlackjackHandView.Card(rank: .seven, suit: .hearts)
            playerCard2 = BlackjackHandView.Card(rank: .king, suit: .hearts)

        case .regular:
            // Regular hand: No bonus (e.g., 7♥, 9♣)
            playerCard1 = BlackjackHandView.Card(rank: .seven, suit: .hearts)
            playerCard2 = BlackjackHandView.Card(rank: .nine, suit: .clubs)

        case .aceUp:
            // Ace Up: Dealer's up-card is Ace, first card is random
            let aceUpPlayerCard1 = drawCard()
            let aceUpPlayerCard2 = drawCard()
            let aceUpDealerCard1 = drawCard()
            // Dealer's second card (up-card) is Ace
            let aceUpDealerCard2 = BlackjackHandView.Card(rank: .ace, suit: .spades)
            return (aceUpPlayerCard1, aceUpPlayerCard2, aceUpDealerCard1, aceUpDealerCard2)

        case .dealerBlackjack:
            // Dealer BlackJack: Dealer gets Ace + King for blackjack
            let dealerBJPlayerCard1 = drawCard()
            let dealerBJPlayerCard2 = drawCard()
            // Dealer gets blackjack (Ace as hole card, King as up-card)
            let dealerBJDealerCard2 = BlackjackHandView.Card(rank: .king, suit: .hearts)
            let dealerBJDealerCard1 = BlackjackHandView.Card(rank: .ace, suit: .spades)
            return (dealerBJPlayerCard1, dealerBJPlayerCard2, dealerBJDealerCard1, dealerBJDealerCard2)

        case .random:
            // Random: All cards are random (drawn from deck)
            let randomPlayerCard1 = drawCard()
            let randomPlayerCard2 = drawCard()
            let randomDealerCard1 = drawCard()
            let randomDealerCard2 = drawCard()
            return (randomPlayerCard1, randomPlayerCard2, randomDealerCard1, randomDealerCard2)
        }

        // Dealer cards are always random (drawn from deck to maintain deck count)
        let dealerCard1 = drawCard()
        let dealerCard2 = drawCard()

        return (playerCard1, playerCard2, dealerCard1, dealerCard2)
    }

    /// Update card count after a card is revealed
    func updateCardCount(for card: BlackjackHandView.Card) {
        runningCount += getCardCountValue(for: card)
        let trueCount = calculateTrueCount()
        delegate?.cardCountDidUpdate(running: runningCount, trueCount: trueCount)
    }

    /// Set the fixed hand type for testing
    func setFixedHandType(_ handType: FixedHandType?) {
        fixedHandType = handType
    }

    /// Reset the shuffle flag
    func resetShuffleFlag() {
        shouldShuffleAfterHand = false
    }

    // MARK: - Private Methods

    private func insertCutCard() {
        guard let penetration = deckPenetration else {
            // No cut card - use full deck
            cutCardPosition = nil
            return
        }

        // If random, select a random penetration from available options
        let actualPenetration: Double
        if penetration == -1.0 {
            // Random: choose from 50%, 60%, 70%, 75%
            let options: [Double] = [0.5, 0.6, 0.7, 0.75]
            actualPenetration = options.randomElement() ?? 0.75
        } else {
            actualPenetration = penetration
        }

        // Cut card is placed at penetration % through the deck
        // For example, 75% penetration means we can use 75% of the deck
        let totalCards = deck.count
        let cardsToUse = Int(Double(totalCards) * actualPenetration)
        let cutPosition = cardsToUse

        // Insert the cut card at the calculated position
        if cutPosition >= 0 && cutPosition <= deck.count {
            deck.insert(BlackjackHandView.Card.cutCard(), at: cutPosition)
            cutCardPosition = cutPosition
        } else {
            cutCardPosition = nil
        }
    }

    private func getCardCountValue(for card: BlackjackHandView.Card) -> Int {
        switch card.rank {
        case .two, .three, .four, .five, .six:
            return 1  // Low cards: +1
        case .seven, .eight, .nine:
            return 0  // Neutral cards: 0
        case .ten, .jack, .queen, .king, .ace:
            return -1 // High cards: -1
        }
    }

    private func calculateTrueCount() -> Int {
        // True count = running count / number of decks remaining
        let decksRemaining = max(1.0, Double(deck.count) / 52.0)
        let trueCount = Double(runningCount) / decksRemaining
        return Int(round(trueCount))
    }
}
