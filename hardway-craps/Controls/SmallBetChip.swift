//
//  SmallBetChip.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class SmallBetChip: UIView, BetChipViewProtocol {

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = HardwayColors.yellow
        return label
    }()

    private let normalBackgroundColor = HardwayColors.betGray
    private let lockedBackgroundColor: UIColor = {
        // Darker version of betGray for locked state
        return HardwayColors.betGray.darker(by: 6.0)
    }()

    var amount: Int = 0 {
        didSet {
            amountLabel.text = "\(amount)"
            isHidden = amount == 0
        }
    }
    
    func setLocked(_ locked: Bool) {
        backgroundColor = locked ? lockedBackgroundColor : normalBackgroundColor
    }

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        // Scale up by 25% on iPad
        let baseHeight: CGFloat = 30
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let height: CGFloat = isIPad ? baseHeight * 1.25 : baseHeight

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = HardwayColors.betGray
        // Corner radius will be set in layoutSubviews to handle animations properly

        // Ensure chip is fully opaque
        alpha = 1.0
        isOpaque = true

        // Add shadow for depth (scale proportionally) - reduced opacity to prevent transparency appearance
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = isIPad ? 5 * 1.25 : 5
        layer.shadowOffset = CGSize(width: 0, height: isIPad ? 3 * 1.25 : 3)

        // Scale font size proportionally
        amountLabel.font = .systemFont(ofSize: isIPad ? 12 * 1.25 : 12, weight: .semibold)

        isHidden = true

        addSubview(amountLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: height),
            heightAnchor.constraint(equalToConstant: height),

            amountLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            amountLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update corner radius to always be half the height, ensuring perfect circle
        // This handles both static layout and animated size changes
        layer.cornerRadius = bounds.height / 2
    }

    func addToBet(_ value: Int) {
        amount += value
    }

    func clearBet() {
        amount = 0
    }
}
