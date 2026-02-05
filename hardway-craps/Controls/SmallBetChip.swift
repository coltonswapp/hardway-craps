//
//  SmallBetChip.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class SmallBetChip: UIView {

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = HardwayColors.yellow
        return label
    }()

    var amount: Int = 0 {
        didSet {
            amountLabel.text = "\(amount)"
            isHidden = amount == 0
        }
    }

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let height: CGFloat = 30
        
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = HardwayColors.betGray
        layer.cornerRadius = height / 2
        
        // Add shadow for depth
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 3)
        
        isHidden = true

        addSubview(amountLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: height),
            heightAnchor.constraint(equalToConstant: height),

            amountLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            amountLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func addToBet(_ value: Int) {
        amount += value
    }

    func clearBet() {
        amount = 0
    }
}
