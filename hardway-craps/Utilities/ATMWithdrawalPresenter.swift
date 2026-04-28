//
//  ATMWithdrawalPresenter.swift
//  hardway-craps
//

import UIKit

enum ATMWithdrawalPresenter {

    private static let presetAmounts = [100, 200, 500, 1000, 1500, 2000]

    static func randomMessage(for amount: Int) -> String {
        let templates: [String] = [
            "Cash acquired! $\(amount) added!",
            "Don't tell your spouse! $\(amount) added!",
            "You're a lucky bastard! $\(amount) added!",
            "Shhh... $\(amount) added!",
            "Added $\(amount) to bankroll!",
        ]
        return templates.randomElement() ?? "Cash acquired! $\(amount) added!"
    }

    /// Build a `UIMenu` for ATM withdrawal amounts.
    /// Attach the returned menu to any `UIButton` or use it in a context menu interaction.
    static func menu(onSelect: @escaping (Int) -> Void) -> UIMenu {
        let amountActions = presetAmounts.map { amount in
            UIAction(
                title: "$\(amount)",
                image: UIImage(systemName: "dollarsign.circle")
            ) { _ in
                onSelect(amount)
            }
        }

        return UIMenu(title: "Hit the ATM", children: amountActions)
    }

    /// Convenience: configure a `UIButton` so tapping it shows the ATM menu natively.
    static func configureButton(_ button: UIButton, onSelect: @escaping (Int) -> Void) {
        button.menu = menu(onSelect: onSelect)
        button.showsMenuAsPrimaryAction = true
    }
}
