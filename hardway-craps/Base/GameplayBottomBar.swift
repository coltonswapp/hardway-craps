//
//  GameplayBottomBar.swift
//  hardway-craps
//

import UIKit

class GameplayBottomBar: UIView {

    let balanceView: BalanceView
    let chipSelector: ChipSelector

    private(set) var leftStack: UIStackView!

    override init(frame: CGRect) {
        balanceView = BalanceView()
        chipSelector = ChipSelector()
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupLeftStack()
    }

    init(chipSelector: ChipSelector) {
        self.balanceView = BalanceView()
        self.chipSelector = chipSelector
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupLeftStack()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLeftStack() {
        leftStack = UIStackView()
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftStack.axis = .vertical
        leftStack.distribution = .fill
        leftStack.alignment = .leading
        leftStack.spacing = 4

        leftStack.addArrangedSubview(balanceView)
        leftStack.addArrangedSubview(chipSelector)
        addSubview(leftStack)

        leftStack.setContentHuggingPriority(.required, for: .vertical)
        leftStack.setContentCompressionResistancePriority(.required, for: .vertical)
        balanceView.setContentCompressionResistancePriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            leftStack.topAnchor.constraint(equalTo: topAnchor),
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            leftStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            chipSelector.heightAnchor.constraint(equalToConstant: UIDevice.current.userInterfaceIdiom == .pad ? chipSelector.chipSize + 13 : 60),
            // Ensure chipSelector has sufficient width for hit targets (scales with chip size)
            chipSelector.widthAnchor.constraint(greaterThanOrEqualToConstant: chipSelector.chipSize * 2.2),
        ])
    }

    /// Updates spacing between balance and chip selector. Use tighter values (e.g. 2) for iPad landscape.
    func setBalanceChipSpacing(_ spacing: CGFloat) {
        leftStack.spacing = spacing
    }

    func installConstraints(in parent: UIView) {
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 16),
            bottomAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }
}
