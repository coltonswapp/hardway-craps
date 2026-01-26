//
//  BonusBetControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/16/26.
//

import UIKit

final class BonusBetControl: PlainControl {

    private let betNameLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let labelStack = UIStackView()

    override var title: String? {
        didSet {
            betNameLabel.text = title
        }
    }

    init(title: String, description: String) {
        super.init(title: title)
        descriptionLabel.text = description
        isPerpetualBet = false
        setupBonusLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // Remove height constraints once we're in the stack view
        if superview != nil {
            removeHeightConstraints()
        }
    }
    
    private func removeHeightConstraints() {
        // Remove any height constraints on self
        for constraint in constraints {
            if constraint.firstAttribute == .height && constraint.relation == .equal {
                constraint.isActive = false
            }
        }
        
        // Remove height constraints from superview that reference self
        if let superview = superview {
            for constraint in superview.constraints {
                if (constraint.firstItem === self && constraint.firstAttribute == .height) ||
                   (constraint.secondItem === self && constraint.secondAttribute == .height) {
                    if constraint.relation == .equal {
                        constraint.isActive = false
                    }
                }
            }
        }
    }

    private func setupBonusLayout() {
        // Set low content hugging priority so the view can expand to fill available space
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        // Remove height constraints (will also be called in didMoveToSuperview as backup)
        removeHeightConstraints()
        
        // Hide the base title label from PlainControl.
        for subview in subviews {
            if subview is UILabel {
                subview.isHidden = true
                break
            }
        }

        betNameLabel.translatesAutoresizingMaskIntoConstraints = false
        betNameLabel.text = title
        betNameLabel.font = .systemFont(ofSize: 14, weight: .regular)
        betNameLabel.textColor = HardwayColors.label
        betNameLabel.textAlignment = .left
        betNameLabel.isUserInteractionEnabled = false  // Allow taps to pass through

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .systemFont(ofSize: 10, weight: .regular)
        descriptionLabel.textColor = HardwayColors.label.withAlphaComponent(0.7)
        descriptionLabel.textAlignment = .left
        descriptionLabel.numberOfLines = 1
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.isUserInteractionEnabled = false  // Allow taps to pass through

        labelStack.translatesAutoresizingMaskIntoConstraints = false
        labelStack.axis = .vertical
        labelStack.alignment = .leading
        labelStack.distribution = .fill
        labelStack.spacing = 2
        labelStack.isUserInteractionEnabled = false  // Allow taps to pass through to control
        labelStack.addArrangedSubview(betNameLabel)
        labelStack.addArrangedSubview(descriptionLabel)
        addSubview(labelStack)

        NSLayoutConstraint.activate([
            labelStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            labelStack.trailingAnchor.constraint(lessThanOrEqualTo: betView.leadingAnchor, constant: -4),
            labelStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
            labelStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
            labelStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        layer.borderWidth = 1.5
        layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
        
        // Ensure betView stays on top and is properly configured
        bringSubviewToFront(betView)
        backgroundColor = nil
    }

    override func configureBetViewConstraints() {
        for constraint in constraints {
            if constraint.firstItem === betView || constraint.secondItem === betView {
                constraint.isActive = false
            }
        }
        betView.clipsToBounds = true
        betView.backgroundColor = HardwayColors.betGray  // Ensure solid background

        NSLayoutConstraint.activate([
            betView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            betView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
