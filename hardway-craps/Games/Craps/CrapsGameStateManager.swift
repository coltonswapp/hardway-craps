//
//  CrapsGameStateManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/28/26.
//

import Foundation
import UIKit

/// Delegate protocol for game state changes
protocol CrapsGameStateManagerDelegate: AnyObject {
    func gamePhaseDidChange(from: CrapsGame.Phase, to: CrapsGame.Phase)
    func rollingStateDidChange(enabled: Bool)
    func pointWasEstablished(number: Int)
    func pointWasMade(number: Int)
    func sevenOut()
}

/// Manages game phase, rolling state, and game event processing
final class CrapsGameStateManager {

    // MARK: - Properties

    weak var delegate: CrapsGameStateManagerDelegate?

    private var game: CrapsGame
    private var rollingStateUpdateWorkItem: DispatchWorkItem?
    private weak var flipDiceContainer: FlipDiceContainer?
    private weak var passLineControl: PlainControl?
    private weak var dontPassControl: PlainControl?
    private var hasAnyBet: (() -> Bool)?

    // MARK: - Public Properties

    /// Current game phase (come out or point)
    var currentPhase: CrapsGame.Phase {
        return game.phase
    }

    /// Current point number (nil if in come out phase)
    var currentPoint: Int? {
        return game.currentPoint
    }

    /// Whether the game is in point phase
    var isPointPhase: Bool {
        return game.isPointPhase
    }

    // MARK: - Initialization

    init() {
        self.game = CrapsGame()
    }

    // MARK: - Public Methods

    /// Set references to UI controls for rolling state management
    func setUIReferences(flipDiceContainer: FlipDiceContainer, passLineControl: PlainControl, dontPassControl: PlainControl? = nil, hasAnyBet: @escaping () -> Bool) {
        self.flipDiceContainer = flipDiceContainer
        self.passLineControl = passLineControl
        self.dontPassControl = dontPassControl
        self.hasAnyBet = hasAnyBet
    }

    /// Process a dice roll and return the game event
    /// - Parameter total: The total of the two dice
    /// - Returns: The game event that occurred
    func processRoll(_ total: Int) -> GameEvent {
        let oldPhase = game.phase
        let event = game.processRoll(total)
        let newPhase = game.phase

        // Notify delegate if phase changed
        if !phasesAreEqual(oldPhase, newPhase) {
            delegate?.gamePhaseDidChange(from: oldPhase, to: newPhase)
        }

        // Notify delegate of specific events
        switch event {
        case .pointEstablished(let number):
            delegate?.pointWasEstablished(number: number)
        case .pointMade:
            if case .comeOut = oldPhase {
                // Already in comeOut, means we just transitioned from point
            }
            if let point = extractPointNumber(from: oldPhase) {
                delegate?.pointWasMade(number: point)
            }
        case .sevenOut:
            delegate?.sevenOut()
        default:
            break
        }

        return event
    }

    /// Update the rolling enabled/disabled state based on game conditions
    func updateRollingState() {
        guard let flipDiceContainer = flipDiceContainer,
              let passLineControl = passLineControl else { return }

        // Cancel any pending rolling state updates
        rollingStateUpdateWorkItem?.cancel()

        // Enable rolling if:
        // 1. We're in point phase (can always roll), OR
        // 2. We have any bet placed (pass line, don't pass, field, point numbers, etc.)
        let hasAnyBetPlaced = hasAnyBet?() ?? false
        let shouldEnable = game.isPointPhase || hasAnyBetPlaced

        if shouldEnable {
            // If we're in point phase, enable immediately (can always roll)
            // If we have any bet in come out phase, enable immediately (bet was just placed)
            // Otherwise delay to allow roll result animations to complete
            let delay: TimeInterval
            if game.isPointPhase {
                delay = 0.2  // Point phase - enable after brief delay to ensure dice animation completes
            } else if hasAnyBetPlaced {
                delay = 0.0  // Any bet placed - enable immediately
            } else {
                delay = 1.5  // After roll result - wait for animations to complete
            }

            let workItem = DispatchWorkItem { [weak self, weak flipDiceContainer] in
                guard let self = self,
                      let flipDiceContainer = flipDiceContainer else { return }

                // Double-check condition hasn't changed
                let stillHasAnyBet = self.hasAnyBet?() ?? false
                let stillShouldEnable = self.game.isPointPhase || stillHasAnyBet
                if stillShouldEnable {
                    flipDiceContainer.enableRolling()
                    self.delegate?.rollingStateDidChange(enabled: true)
                } else {
                    flipDiceContainer.disableRolling()
                    self.delegate?.rollingStateDidChange(enabled: false)
                }
            }

            rollingStateUpdateWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            flipDiceContainer.disableRolling()
            delegate?.rollingStateDidChange(enabled: false)
        }
    }

    /// Reset to come out phase (used when starting new game or ending session)
    func resetToComeOutPhase() {
        let oldPhase = game.phase
        game = CrapsGame() // Reset game to initial state
        let newPhase = game.phase

        if !phasesAreEqual(oldPhase, newPhase) {
            delegate?.gamePhaseDidChange(from: oldPhase, to: newPhase)
        }
    }

    // MARK: - Private Helper Methods

    /// Check if two phases are equal
    private func phasesAreEqual(_ phase1: CrapsGame.Phase, _ phase2: CrapsGame.Phase) -> Bool {
        switch (phase1, phase2) {
        case (.comeOut, .comeOut):
            return true
        case (.point(let num1), .point(let num2)):
            return num1 == num2
        default:
            return false
        }
    }

    /// Extract point number from a phase
    private func extractPointNumber(from phase: CrapsGame.Phase) -> Int? {
        if case .point(let number) = phase {
            return number
        }
        return nil
    }
}
