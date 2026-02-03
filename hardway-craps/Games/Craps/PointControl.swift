//
//  PointControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class PointControl: PlainControl {

    private let numberLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 24, weight: .medium)
        label.textColor = HardwayColors.label
        return label
    }()

    private let oddsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = HardwayColors.label.withAlphaComponent(0.6)
        return label
    }()

    let pointNumber: Int
    let odds: String

    var oddsMultiplier: Double {
        switch pointNumber {
        case 4, 10:
            return 2.0  // 2:1
        case 5, 9:
            return 1.5  // 3:2
        case 6, 8:
            return 1.2  // 6:5
        default:
            return 1.0
        }
    }

    var isOn: Bool = false
    
    /// Override to animate winnings slightly above the bet (instead of to the right)
    override var winningsAnimationOffset: CGPoint {
        return CGPoint(x: 0, y: -30)  // Offset 30 points above the bet
    }

    init(pointNumber: Int) {
        self.pointNumber = pointNumber

        // Calculate odds based on point number
        switch pointNumber {
        case 4, 10:
            self.odds = "2:1"
        case 5, 9:
            self.odds = "3:2"
        case 6, 8:
            self.odds = "6:5"
        default:
            self.odds = ""
        }

        super.init(title: nil)
        
        // Remove PlainControl's default 50pt height constraint
        var heightConstraintsToRemove: [NSLayoutConstraint] = []
        for constraint in constraints {
            if constraint.firstAttribute == .height && constraint.firstItem === self && constraint.constant == 50 {
                heightConstraintsToRemove.append(constraint)
            }
        }
        NSLayoutConstraint.deactivate(heightConstraintsToRemove)
        
        setupPointView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPointView() {
        numberLabel.text = "\(pointNumber)"
        oddsLabel.text = odds

        addSubview(numberLabel)
        addSubview(oddsLabel)

        NSLayoutConstraint.activate([
            // Number label - centered but slightly above center
            numberLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),

            // Odds label - below number
            oddsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            oddsLabel.topAnchor.constraint(equalTo: numberLabel.bottomAnchor, constant: 4)
        ])
    }

    override func configureBetViewConstraints() {
        NSLayoutConstraint.activate([
            betView.centerXAnchor.constraint(equalTo: centerXAnchor),
            betView.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
}
