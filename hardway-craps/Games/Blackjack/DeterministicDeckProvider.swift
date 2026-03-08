/**
 * Deterministic deck creation for multiplayer blackjack.
 * Algorithm must match functions/src/deck.ts exactly so that
 * same (seed, deckCount) produces identical deck order on server and client.
 */

import Foundation

struct DeterministicDeckProvider {
    private let cards: [Card]

    struct Card: Equatable {
        let rank: String
        let suit: String
    }

    /// Replicates deck.ts: same suit/rank order, LCG with 0x7fffffff masking, Fisher-Yates shuffle.
    /// Uses Double arithmetic to match JavaScript's Number (64-bit float) behavior exactly.
    init(seed: Int, deckCount: Int) {
        let suits = ["hearts", "clubs", "diamonds", "spades"]
        let ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
        var deck: [Card] = []
        for _ in 0..<deckCount {
            for suit in suits {
                for rank in ranks {
                    deck.append(Card(rank: rank, suit: suit))
                }
            }
        }
        // LCG matching deck.ts — arithmetic in Double to replicate JS Number precision
        let mod: Double = 4_294_967_296 // 2^32
        let mask: Int = 0x7fffffff
        var state: Double = Double(seed)
        func nextRandom() -> Double {
            let raw = state * 1103515245 + 12345
            state = Double(Int(raw.truncatingRemainder(dividingBy: mod)) & mask)
            return state / Double(mask)
        }
        // Fisher-Yates matching deck.ts
        for i in stride(from: deck.count - 1, through: 1, by: -1) {
            let j = Int(nextRandom() * Double(i + 1))
            deck.swapAt(i, j)
        }
        self.cards = deck
    }

    func card(at index: Int) -> Card? {
        guard index >= 0, index < cards.count else { return nil }
        return cards[index]
    }

    var count: Int { cards.count }

    // MARK: - Verification (matches TypeScript createShuffledDeck(12345, 1) first 15 cards)

    /// Call to verify Swift output matches TypeScript. First 15 cards for seed 12345, deckCount 1.
    static func verifyAgainstTypeScript() -> Bool {
        let provider = DeterministicDeckProvider(seed: 12345, deckCount: 1)
        let expected: [(String, String)] = [
            ("7", "clubs"), ("2", "hearts"), ("5", "clubs"), ("2", "spades"), ("A", "hearts"),
            ("5", "diamonds"), ("Q", "hearts"), ("5", "hearts"), ("K", "hearts"), ("4", "clubs"),
            ("Q", "diamonds"), ("6", "hearts"), ("3", "hearts"), ("K", "clubs"), ("9", "spades"),
        ]
        for (i, (rank, suit)) in expected.enumerated() {
            guard let card = provider.card(at: i), card.rank == rank, card.suit == suit else {
                return false
            }
        }
        return true
    }
}
