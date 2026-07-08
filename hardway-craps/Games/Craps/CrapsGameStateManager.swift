//
//  CrapsGameStateManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/28/26.
//

import Foundation

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

    var currentVariant: CrapsVariant {
        return game.rules.variant
    }

    /// Active variant rules (pass-line events, payouts, etc.).
    var rules: CrapsVariantRules {
        return game.rules
    }

    // MARK: - Initialization

    init(variant: CrapsVariant = .standard) {
        self.game = CrapsGame(rules: CrapsVariantRulesFactory.makeRules(for: variant))
    }

    // MARK: - Public Methods

    func setVariant(_ variant: CrapsVariant) {
        let oldPhase = game.phase
        game.updateRules(CrapsVariantRulesFactory.makeRules(for: variant))
        let newPhase = game.phase

        if !phasesAreEqual(oldPhase, newPhase) {
            delegate?.gamePhaseDidChange(from: oldPhase, to: newPhase)
        }
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

    /// Return and broadcast whether rolling should currently be enabled.
    @discardableResult
    func updateRollingState(hasAnyBetPlaced: Bool) -> Bool {
        let shouldEnable = game.isPointPhase || hasAnyBetPlaced
        delegate?.rollingStateDidChange(enabled: shouldEnable)
        return shouldEnable
    }

    /// Reset to come out phase (used when starting new game or ending session)
    func resetToComeOutPhase() {
        let oldPhase = game.phase
        game = CrapsGame(rules: game.rules) // Reset game to initial state
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
