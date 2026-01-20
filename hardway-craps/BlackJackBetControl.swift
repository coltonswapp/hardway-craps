//
//  BlackJackBetControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

class BlackJackBetControl: PlainControl {
    
    private let betLabelBackground = UIView()
    private let betLabel = UILabel()
    
    private let customLabelColor: UIColor = UIColor(red: 155/255, green: 155/255, blue: 155/255, alpha: 1.0) // Light grey
    
    override var title: String? {
        didSet {
            betLabel.text = title
        }
    }
    
    override init(title: String? = nil) {
        super.init(title: title ?? "BET")
        setupBlackjackLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupBlackjackLayout() {
        // Set custom background color (darker than default)
        backgroundColor = UIColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1.0) // Dark grey/black
        
        // Override the height constraint from PlainControl to be 50pt
        // The betView chip will spill out the bottom since it's not constrained
        for constraint in constraints {
            if constraint.firstAttribute == .height && constraint.constant == 50 {
                constraint.constant = 50 // Control height
                break
            }
        }
        
        // Hide the original titleLabel (we'll use our own)
        // Find and hide the titleLabel by looking for a UILabel that's centered
        for subview in subviews {
            if let label = subview as? UILabel, label !== betLabel {
                label.isHidden = true
                break
            }
        }
        
        // Setup the oval background for the BET label
        betLabelBackground.translatesAutoresizingMaskIntoConstraints = false
        betLabelBackground.backgroundColor = HardwayColors.betGray
        betLabelBackground.layer.cornerRadius = 12
        addSubview(betLabelBackground)
        
        // Setup our own BET label
        betLabel.translatesAutoresizingMaskIntoConstraints = false
        betLabel.text = title ?? "BET"
        betLabel.font = .systemFont(ofSize: 12, weight: .medium)
        betLabel.textColor = customLabelColor
        betLabel.textAlignment = .center
        betLabelBackground.addSubview(betLabel)
        
        // Position the oval background at the top edge, centered
        NSLayoutConstraint.activate([
            betLabelBackground.topAnchor.constraint(equalTo: topAnchor, constant: -8), // Overlap top edge
            betLabelBackground.centerXAnchor.constraint(equalTo: centerXAnchor),
            betLabelBackground.heightAnchor.constraint(equalToConstant: 24),
            betLabelBackground.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            
            // Center betLabel in the oval background
            betLabel.centerXAnchor.constraint(equalTo: betLabelBackground.centerXAnchor),
            betLabel.centerYAnchor.constraint(equalTo: betLabelBackground.centerYAnchor),
            betLabel.leadingAnchor.constraint(greaterThanOrEqualTo: betLabelBackground.leadingAnchor, constant: 12),
            betLabel.trailingAnchor.constraint(lessThanOrEqualTo: betLabelBackground.trailingAnchor, constant: -12)
        ])
        
        // Adjust corner radius for softer, larger rounded corners
        layer.cornerRadius = 20
        
        // Now that betLabelBackground exists, update betView constraints
        updateBetViewConstraints()
        
        // Ensure proper z-ordering
        bringSubviewToFront(betLabelBackground)
        bringSubviewToFront(betView)
    }
    
    override func configureBetViewConstraints() {
        // This is called during super.init() before betLabelBackground exists
        // We'll set up temporary constraints here, then update them in setupBlackjackLayout()
        let chipSize: CGFloat = 40 // Slightly smaller chip
        
        // Remove existing size constraints from betView
        var constraintsToRemove: [NSLayoutConstraint] = []
        for constraint in betView.constraints {
            if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
                constraintsToRemove.append(constraint)
            }
        }
        constraintsToRemove.forEach { $0.isActive = false }
        
        // Remove existing positioning constraints from self that involve betView
        for constraint in constraints {
            if (constraint.firstItem === betView || constraint.secondItem === betView) &&
               (constraint.firstAttribute == .centerY || constraint.firstAttribute == .trailing) {
                constraint.isActive = false
            }
        }
        
        // Set up temporary constraints (will be updated in setupBlackjackLayout)
        NSLayoutConstraint.activate([
            // Make betView larger
            betView.widthAnchor.constraint(equalToConstant: chipSize),
            betView.heightAnchor.constraint(equalToConstant: chipSize),
            
            // Center horizontally
            betView.centerXAnchor.constraint(equalTo: centerXAnchor),
            
            // Temporary: position from top (will be updated to betLabelBackground.bottomAnchor)
            betView.topAnchor.constraint(equalTo: topAnchor, constant: 32)
        ])
        
        // Update corner radius and font size for larger chip
        betView.layer.cornerRadius = chipSize / 2
        
        // Update font size in the amountLabel for better visibility
        // Find the label inside betView
        for subview in betView.subviews {
            if let label = subview as? UILabel {
                label.font = .systemFont(ofSize: 18, weight: .semibold) // Larger font for larger chip
                break
            }
        }
    }
    
    private func updateBetViewConstraints() {
        // Update betView constraints to position relative to betLabelBackground
        // This is called after betLabelBackground is created
        
        // Find and remove the temporary top constraint
        var topConstraintToRemove: NSLayoutConstraint?
        for constraint in constraints {
            if (constraint.firstItem === betView && constraint.firstAttribute == .top) ||
               (constraint.secondItem === betView && constraint.secondAttribute == .top) {
                topConstraintToRemove = constraint
                break
            }
        }
        topConstraintToRemove?.isActive = false
        
        // Add new constraint relative to betLabelBackground
        NSLayoutConstraint.activate([
            betView.topAnchor.constraint(equalTo: betLabelBackground.bottomAnchor, constant: 8)
        ])
    }
    
    override func shimmerTitleLabel() {
        // Shimmer our custom bet label instead
        betLabel.addShimmerEffect()
    }
    
    override func stopTitleShimmer() {
        // Stop shimmer on our custom bet label
        betLabel.removeShimmerEffect()
    }
    
    override func setBetRemovalDisabled(_ disabled: Bool) {
        if disabled {
            // Tint the control to show it's disabled
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = UIColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 0.5)
                self.betLabel.textColor = self.customLabelColor.withAlphaComponent(0.5)
            }
        } else {
            // Restore normal appearance
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = UIColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1.0)
                self.betLabel.textColor = self.customLabelColor
            }
        }
    }
}
