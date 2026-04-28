//
//  BlackjackGameStateManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/26/26.
//

import Foundation

/// Delegate protocol for game state-related events
protocol BlackjackGameStateManagerDelegate: AnyObject {
    func gamePhaseDidChange(from oldPhase: PlayerControlStack.GamePhase, to newPhase: PlayerControlStack.GamePhase)
    func playerActionStateDidChange()
    func splitStateDidChange(isSplit: Bool, activeHandIndex: Int)
}

/// Manages game phase, player actions, and hand states
final class BlackjackGameStateManager {

    // MARK: - Types

    typealias GamePhase = PlayerControlStack.GamePhase

    /// Per-hand state for every hand the player holds (primary + any split hands).
    struct PlayerHand {
        var bet: Int
        var hasHit: Bool
        var hasStood: Bool
        var hasDoubled: Bool
        var busted: Bool
        var isFromSplit: Bool
        var doubleDownCardIndex: Int?

        init(bet: Int = 0,
             hasHit: Bool = false,
             hasStood: Bool = false,
             hasDoubled: Bool = false,
             busted: Bool = false,
             isFromSplit: Bool = false,
             doubleDownCardIndex: Int? = nil) {
            self.bet = bet
            self.hasHit = hasHit
            self.hasStood = hasStood
            self.hasDoubled = hasDoubled
            self.busted = busted
            self.isFromSplit = isFromSplit
            self.doubleDownCardIndex = doubleDownCardIndex
        }

        /// A hand is complete once it can no longer take actions.
        var isComplete: Bool { hasStood || busted }
    }

    /// Maximum number of hands one player can have (primary + up to 3 splits).
    static let maxHands = 4

    // MARK: - Properties

    weak var delegate: BlackjackGameStateManagerDelegate?

    private(set) var gamePhase: GamePhase = .waitingForBet {
        didSet {
            if oldValue != gamePhase {
                delegate?.gamePhaseDidChange(from: oldValue, to: gamePhase)
            }
        }
    }

    /// Every hand the player currently holds, in play order. Always length >= 1 once a
    /// round is underway. Index 0 is the primary hand; indices 1+ come from splits.
    private(set) var playerHands: [PlayerHand] = [PlayerHand()]

    /// Index of the hand currently receiving player actions.
    private(set) var activeHandIndex: Int = 0 {
        didSet {
            if oldValue != activeHandIndex {
                delegate?.splitStateDidChange(isSplit: isSplit, activeHandIndex: activeHandIndex)
            }
        }
    }

    private(set) var hasInsuranceBeenChecked: Bool = false

    /// True whenever the player has more than one hand in play.
    var isSplit: Bool { playerHands.count > 1 }

    // MARK: - Legacy accessors (read from the active hand)

    /// Legacy: has the *active* hand hit?
    var hasPlayerHit: Bool { activeHand?.hasHit ?? false }

    /// Legacy: has the *active* hand stood?
    var hasPlayerStood: Bool { activeHand?.hasStood ?? false }

    /// Legacy: has the *active* hand doubled down?
    var hasPlayerDoubled: Bool { activeHand?.hasDoubled ?? false }

    /// Legacy: is the *active* hand busted?
    var playerBusted: Bool { activeHand?.busted ?? false }

    /// Legacy: index of the double-down card on the *active* hand (if any).
    var playerDoubleDownCardIndex: Int? { activeHand?.doubleDownCardIndex }

    private var activeHand: PlayerHand? {
        guard activeHandIndex >= 0 && activeHandIndex < playerHands.count else { return nil }
        return playerHands[activeHandIndex]
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Game Phase Methods

    /// Set the current game phase
    func setGamePhase(_ phase: GamePhase) {
        gamePhase = phase
    }

    /// Reset game to initial state (waiting for bet)
    func resetToWaitingForBet() {
        gamePhase = .waitingForBet
        resetHands()
        hasInsuranceBeenChecked = false
    }

    // MARK: - Hand Action Methods (operate on the active hand)

    /// Record that the active hand hit
    func setPlayerHit() {
        updateActiveHand { $0.hasHit = true }
    }

    /// Record that the active hand stood
    func setPlayerStood() {
        updateActiveHand { $0.hasStood = true }
    }

    /// Record that the active hand doubled down
    func setPlayerDoubled(cardIndex: Int?) {
        updateActiveHand {
            $0.hasDoubled = true
            $0.doubleDownCardIndex = cardIndex
        }
    }

    /// Set busted state on the active hand
    func setPlayerBusted(_ busted: Bool) {
        updateActiveHand { $0.busted = busted }
    }

    /// Reset the active hand's action flags. Use sparingly — normally you'll reset all hands.
    func resetPlayerActions() {
        updateActiveHand {
            $0.hasHit = false
            $0.hasStood = false
            $0.hasDoubled = false
            $0.doubleDownCardIndex = nil
            $0.busted = false
        }
        hasInsuranceBeenChecked = false
    }

    /// Mark insurance as checked
    func setInsuranceChecked() {
        hasInsuranceBeenChecked = true
    }

    // MARK: - Multi-Hand Methods

    /// Reset to a single fresh primary hand and clear all flags. Called at the start of every deal.
    func resetHands(primaryBet: Int = 0) {
        playerHands = [PlayerHand(bet: primaryBet)]
        activeHandIndex = 0
        // Fire delegate so listeners can tear down any split UI.
        delegate?.splitStateDidChange(isSplit: false, activeHandIndex: 0)
        delegate?.playerActionStateDidChange()
    }

    /// Legacy name kept for callers that predate the multi-hand model.
    func resetSplitState() {
        resetHands()
    }

    /// Initialize a classic two-hand split (primary already exists; adds one sibling).
    /// Kept for backwards compatibility with older call sites. For re-splits, use `appendSplitHand`.
    func initializeSplitState() {
        // Preserve the primary hand's bet on the new sibling.
        let primaryBet = playerHands.first?.bet ?? 0
        playerHands = [
            PlayerHand(bet: primaryBet),
            PlayerHand(bet: primaryBet, isFromSplit: true),
        ]
        activeHandIndex = 0
        delegate?.splitStateDidChange(isSplit: true, activeHandIndex: 0)
        delegate?.playerActionStateDidChange()
    }

    /// Insert a new split hand immediately after the given source index.
    /// Returns the index of the newly-inserted hand, or nil if the max is reached.
    @discardableResult
    func appendSplitHand(fromHandIndex sourceIndex: Int, bet: Int) -> Int? {
        guard playerHands.count < Self.maxHands else { return nil }
        guard sourceIndex >= 0 && sourceIndex < playerHands.count else { return nil }
        let insertionIndex = sourceIndex + 1
        let newHand = PlayerHand(bet: bet, isFromSplit: true)
        playerHands.insert(newHand, at: insertionIndex)
        delegate?.splitStateDidChange(isSplit: true, activeHandIndex: activeHandIndex)
        delegate?.playerActionStateDidChange()
        return insertionIndex
    }

    /// Set the active hand index
    func setActiveHandIndex(_ index: Int) {
        guard index >= 0 && index < playerHands.count else { return }
        activeHandIndex = index
    }

    /// Update a specific hand in-place.
    func updatePlayerHand(at index: Int, _ mutate: (inout PlayerHand) -> Void) {
        guard index >= 0 && index < playerHands.count else { return }
        var hand = playerHands[index]
        mutate(&hand)
        playerHands[index] = hand
        delegate?.playerActionStateDidChange()
    }

    /// Update the active hand in-place.
    func updateActiveHand(_ mutate: (inout PlayerHand) -> Void) {
        updatePlayerHand(at: activeHandIndex, mutate)
    }

    /// Set the bet on a specific hand (used when syncing UI bet control to state).
    func setBet(at index: Int, bet: Int) {
        guard index >= 0 && index < playerHands.count else { return }
        playerHands[index].bet = bet
    }

    /// Returns the hand at the given index, if any.
    func playerHand(at index: Int) -> PlayerHand? {
        guard index >= 0 && index < playerHands.count else { return nil }
        return playerHands[index]
    }

    // MARK: - Legacy shims

    /// Legacy shim — prefer `updatePlayerHand(at:)`.
    func updateSplitHandState(index: Int,
                              hasHit: Bool? = nil,
                              hasStood: Bool? = nil,
                              hasDoubled: Bool? = nil,
                              busted: Bool? = nil) {
        updatePlayerHand(at: index) { hand in
            if let hasHit = hasHit { hand.hasHit = hasHit }
            if let hasStood = hasStood { hand.hasStood = hasStood }
            if let hasDoubled = hasDoubled { hand.hasDoubled = hasDoubled }
            if let busted = busted { hand.busted = busted }
        }
    }

    /// Legacy shim — prefer `playerHand(at:)`.
    func getSplitHandState(index: Int) -> PlayerHand? {
        return playerHand(at: index)
    }

    /// Check if every hand is done (stood or busted). Meaningful only when split.
    func areAllSplitHandsDone() -> Bool {
        guard isSplit else { return false }
        return playerHands.allSatisfy { $0.isComplete }
    }

    /// Index of the next hand that still needs to act, or nil if all are done.
    func nextIncompleteHandIndex(after index: Int) -> Int? {
        var i = index + 1
        while i < playerHands.count {
            if !playerHands[i].isComplete { return i }
            i += 1
        }
        return nil
    }

    // MARK: - Game State Queries

    /// Check if player can split (exactly two cards of the same rank, enough balance,
    /// and the 4-hand cap hasn't been reached). Supports re-splits.
    func canPlayerSplit(cards: [BlackjackHandView.Card], balance: Int, betAmount: Int) -> Bool {
        guard cards.count == 2 else { return false }
        guard cards[0].rank == cards[1].rank else { return false }
        guard balance >= betAmount else { return false }
        guard playerHands.count < Self.maxHands else { return false }
        return true
    }

    /// Check if cards form a blackjack (21 with exactly 2 cards including an Ace and a 10-value card)
    func isBlackjack(cards: [BlackjackHandView.Card]) -> Bool {
        guard cards.count == 2 else { return false }

        let hasAce = cards.contains { $0.rank == .ace }
        let hasTenValue = cards.contains { card in
            card.rank == .ten || card.rank == .jack || card.rank == .queen || card.rank == .king
        }

        return hasAce && hasTenValue
    }

    /// Calculate the total value of a hand
    func calculateHandTotal(cards: [BlackjackHandView.Card]) -> Int {
        var total = 0
        var aceCount = 0

        for card in cards {
            switch card.rank {
            case .ace:
                aceCount += 1
                total += 11
            case .two:
                total += 2
            case .three:
                total += 3
            case .four:
                total += 4
            case .five:
                total += 5
            case .six:
                total += 6
            case .seven:
                total += 7
            case .eight:
                total += 8
            case .nine:
                total += 9
            case .ten, .jack, .queen, .king:
                total += 10
            }
        }

        // Adjust for aces if total is over 21
        while total > 21 && aceCount > 0 {
            total -= 10
            aceCount -= 1
        }

        return total
    }

    /// Check if a hand is busted (over 21)
    func isBusted(cards: [BlackjackHandView.Card]) -> Bool {
        return calculateHandTotal(cards: cards) > 21
    }

    /// Check if a hand is a soft 17 (contains an Ace counted as 11, total is 17)
    func isSoft17(cards: [BlackjackHandView.Card]) -> Bool {
        let total = calculateHandTotal(cards: cards)
        guard total == 17 else { return false }

        // Check if hand contains an Ace
        let hasAce = cards.contains { $0.rank == .ace }
        guard hasAce else { return false }

        // If total is 17 with an Ace, check if the Ace is being counted as 11
        // Calculate total counting all Aces as 1
        var hardTotal = 0
        for card in cards {
            switch card.rank {
            case .ace:
                hardTotal += 1
            case .two:
                hardTotal += 2
            case .three:
                hardTotal += 3
            case .four:
                hardTotal += 4
            case .five:
                hardTotal += 5
            case .six:
                hardTotal += 6
            case .seven:
                hardTotal += 7
            case .eight:
                hardTotal += 8
            case .nine:
                hardTotal += 9
            case .ten, .jack, .queen, .king:
                hardTotal += 10
            }
        }

        // If hard total + 10 equals 17, then one Ace is being counted as 11 (soft)
        return hardTotal + 10 == 17
    }

    /// Check if insurance should be available (dealer showing Ace)
    func isInsuranceAvailable(dealerUpcard: BlackjackHandView.Card?, hasBeenChecked: Bool) -> Bool {
        guard let upcard = dealerUpcard else { return false }
        guard !hasBeenChecked else { return false }
        return upcard.rank == .ace
    }
}
