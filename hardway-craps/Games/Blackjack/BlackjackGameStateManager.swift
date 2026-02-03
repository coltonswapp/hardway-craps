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

    struct SplitHandState {
        var hasHit: Bool
        var hasStood: Bool
        var hasDoubled: Bool
        var busted: Bool

        init(hasHit: Bool = false, hasStood: Bool = false, hasDoubled: Bool = false, busted: Bool = false) {
            self.hasHit = hasHit
            self.hasStood = hasStood
            self.hasDoubled = hasDoubled
            self.busted = busted
        }
    }

    // MARK: - Properties

    weak var delegate: BlackjackGameStateManagerDelegate?

    private(set) var gamePhase: GamePhase = .waitingForBet {
        didSet {
            if oldValue != gamePhase {
                delegate?.gamePhaseDidChange(from: oldValue, to: gamePhase)
            }
        }
    }

    private(set) var hasPlayerHit: Bool = false {
        didSet {
            if oldValue != hasPlayerHit {
                delegate?.playerActionStateDidChange()
            }
        }
    }

    private(set) var hasPlayerStood: Bool = false {
        didSet {
            if oldValue != hasPlayerStood {
                delegate?.playerActionStateDidChange()
            }
        }
    }

    private(set) var hasPlayerDoubled: Bool = false {
        didSet {
            if oldValue != hasPlayerDoubled {
                delegate?.playerActionStateDidChange()
            }
        }
    }

    private(set) var hasInsuranceBeenChecked: Bool = false
    private(set) var playerDoubleDownCardIndex: Int? = nil
    private(set) var playerBusted: Bool = false

    // Split state
    private(set) var isSplit: Bool = false {
        didSet {
            if oldValue != isSplit {
                delegate?.splitStateDidChange(isSplit: isSplit, activeHandIndex: activeHandIndex)
            }
        }
    }

    private(set) var activeHandIndex: Int = 0 {
        didSet {
            if oldValue != activeHandIndex {
                delegate?.splitStateDidChange(isSplit: isSplit, activeHandIndex: activeHandIndex)
            }
        }
    }

    private(set) var splitHandStates: [SplitHandState] = []

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
        resetPlayerActions()
        resetSplitState()
        playerBusted = false
    }

    // MARK: - Player Action Methods

    /// Record that player hit
    func setPlayerHit() {
        hasPlayerHit = true
    }

    /// Record that player stood
    func setPlayerStood() {
        hasPlayerStood = true
    }

    /// Record that player doubled down
    func setPlayerDoubled(cardIndex: Int?) {
        hasPlayerDoubled = true
        playerDoubleDownCardIndex = cardIndex
    }

    /// Set player busted state
    func setPlayerBusted(_ busted: Bool) {
        playerBusted = busted
    }

    /// Reset all player action flags
    func resetPlayerActions() {
        hasPlayerHit = false
        hasPlayerStood = false
        hasPlayerDoubled = false
        hasInsuranceBeenChecked = false
        playerDoubleDownCardIndex = nil
    }

    /// Mark insurance as checked
    func setInsuranceChecked() {
        hasInsuranceBeenChecked = true
    }

    // MARK: - Split State Methods

    /// Initialize split state with two hands
    func initializeSplitState() {
        isSplit = true
        activeHandIndex = 0
        splitHandStates = [
            SplitHandState(),
            SplitHandState()
        ]
    }

    /// Set the active hand index (0 or 1)
    func setActiveHandIndex(_ index: Int) {
        guard index >= 0 && index < splitHandStates.count else { return }
        activeHandIndex = index
    }

    /// Update split hand state for a specific hand
    func updateSplitHandState(index: Int, hasHit: Bool? = nil, hasStood: Bool? = nil, hasDoubled: Bool? = nil, busted: Bool? = nil) {
        guard index >= 0 && index < splitHandStates.count else { return }

        var state = splitHandStates[index]
        if let hasHit = hasHit { state.hasHit = hasHit }
        if let hasStood = hasStood { state.hasStood = hasStood }
        if let hasDoubled = hasDoubled { state.hasDoubled = hasDoubled }
        if let busted = busted { state.busted = busted }
        splitHandStates[index] = state
    }

    /// Get split hand state for a specific hand
    func getSplitHandState(index: Int) -> SplitHandState? {
        guard index >= 0 && index < splitHandStates.count else { return nil }
        return splitHandStates[index]
    }

    /// Check if all split hands are done (stood or busted)
    func areAllSplitHandsDone() -> Bool {
        guard isSplit else { return false }
        return splitHandStates.allSatisfy { $0.hasStood || $0.busted }
    }

    /// Reset split state
    func resetSplitState() {
        isSplit = false
        activeHandIndex = 0
        splitHandStates = []
    }

    // MARK: - Game State Queries

    /// Check if player can split (first two cards, same rank)
    func canPlayerSplit(cards: [BlackjackHandView.Card], balance: Int, betAmount: Int) -> Bool {
        guard cards.count == 2 else { return false }
        guard cards[0].rank == cards[1].rank else { return false }
        guard balance >= betAmount else { return false }
        guard !isSplit else { return false } // Can't split again after already splitting
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
