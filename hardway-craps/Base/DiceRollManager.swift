//
//  DiceRollManager.swift
//  hardway-craps
//

import UIKit

protocol DiceRollManagerDelegate: AnyObject {
    func diceRollManager(_ manager: DiceRollManager, didRoll die1: Int, die2: Int, total: Int)
    func diceRollManagerDidTapWhileDisabled(_ manager: DiceRollManager)
}

/// Game-agnostic dice rolling service. Any game calls `roll()` and receives results
/// through the delegate -- no game-specific logic lives here.
final class DiceRollManager {

    weak var delegate: DiceRollManagerDelegate?

    let container: FlipDiceContainer

    var isRolling: Bool { container.isRolling }

    init() {
        container = FlipDiceContainer()
        container.translatesAutoresizingMaskIntoConstraints = false
        wireCallbacks()
    }

    // MARK: - Public API

    func roll() {
        container.roll()
    }

    func rollFixed(total: Int) {
        container.rollFixedTotal(total)
    }

    func enableRolling() {
        container.enableRolling()
    }

    func disableRolling() {
        container.disableRolling()
    }

    // MARK: - Wiring

    private func wireCallbacks() {
        container.onRollComplete = { [weak self] die1, die2, total in
            guard let self else { return }
            self.delegate?.diceRollManager(self, didRoll: die1, die2: die2, total: total)
        }

        container.onDisabledTap = { [weak self] in
            guard let self else { return }
            self.delegate?.diceRollManagerDidTapWhileDisabled(self)
        }
    }
}
