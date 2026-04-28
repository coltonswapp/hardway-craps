//
//  PlaceAcrossMenuPresenter.swift
//  hardway-craps
//

import UIKit

enum PlaceAcrossMenuPresenter {

    private static func actionTitle(for allocation: PlaceAcrossAllocation) -> String {
        if allocation == PlaceAcrossAllocator.canonicalMinimumAcross {
            return "$\(allocation.total) minimum across"
        }
        if allocation.total == PlaceAcrossAllocator.featuredAcrossTotal {
            return "$\(allocation.total) classic across"
        }
        return "$\(allocation.total) across"
    }

    private static func actionSubtitle(for allocation: PlaceAcrossAllocation, balance: Int) -> String {
        let breakdown = "$\(allocation.outsideEach) on 4·5·9·10, $\(allocation.insideEach) on 6 & 8"
        if allocation.total > balance {
            return "\(breakdown) · Need $\(allocation.total - balance) more"
        }
        return breakdown
    }

    /// Menu that re-evaluates presets when opened (balance / chip can change).
    static func menu(
        balanceProvider: @escaping () -> Int,
        onSelect: @escaping (PlaceAcrossAllocation) -> Void
    ) -> UIMenu {
        let deferred = UIDeferredMenuElement { completion in
            let balance = balanceProvider()
            let rows = PlaceAcrossAllocator.menuRows(balance: balance)

            if rows.isEmpty {
                let subtitle: String
                let minimumAcross = PlaceAcrossAllocator.minimumSpreadTotal
                if balance < minimumAcross {
                    subtitle = "Need at least $\(minimumAcross) ($10+ per box)"
                } else {
                    subtitle = "Try another chip size"
                }
                let empty = UIAction(
                    title: "No valid spreads",
                    subtitle: subtitle,
                    attributes: .disabled
                ) { _ in }
                completion([empty])
                return
            }

            let actions: [UIAction] = rows.map { row in
                let enabled = row.isEnabled && row.allocation.total <= balance
                return UIAction(
                    title: actionTitle(for: row.allocation),
                    subtitle: actionSubtitle(for: row.allocation, balance: balance),
                    attributes: enabled ? [] : .disabled
                ) { _ in
                    guard enabled else { return }
                    onSelect(row.allocation)
                }
            }
            completion(actions)
        }
        return UIMenu(title: "Place across", children: [deferred])
    }

    static func configureButton(
        _ button: UIButton,
        balanceProvider: @escaping () -> Int,
        selectedChipProvider _: @escaping () -> Int,
        onSelect: @escaping (PlaceAcrossAllocation) -> Void
    ) {
        button.menu = menu(
            balanceProvider: balanceProvider,
            onSelect: onSelect
        )
        button.showsMenuAsPrimaryAction = true
    }
}
