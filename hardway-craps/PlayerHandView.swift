//
//  PlayerHandView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

final class PlayerHandView: BlackjackHandView {
    
    let betControl = PlainControl(title: "Bet")
    
    convenience init() {
        self.init(stackDirection: .down, hidesFirstCard: false, scale: 1)
//        backgroundColor = .red.withAlphaComponent(0.2)
    }
    
    override init(stackDirection: StackDirection, hidesFirstCard: Bool, scale: CGFloat = 1) {
        super.init(stackDirection: stackDirection, hidesFirstCard: hidesFirstCard, scale: scale)
        setupBetControl()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupBetControl() {
        betControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(betControl)
        
        // Find the contentStackView by looking for a UIStackView subview
        var foundStackView: UIStackView?
        for subview in subviews {
            if let stackView = subview as? UIStackView {
                foundStackView = stackView
                break
            }
        }
        
        guard let contentStackView = foundStackView else {
            print("Warning: Could not find contentStackView in PlayerHandView")
            return
        }
        
        // Find and deactivate ALL constraints on contentStackView to reconfigure layout
        var constraintsToDeactivate: [NSLayoutConstraint] = []
        
        for constraint in constraints {
            if constraint.firstItem === contentStackView || constraint.secondItem === contentStackView {
                constraintsToDeactivate.append(constraint)
            }
        }
        
        constraintsToDeactivate.forEach { $0.isActive = false }
        
        // Add new constraints - center horizontally, bottom-aligned above bet control
        NSLayoutConstraint.activate([
            // Pin betControl to bottom, centered
            betControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            betControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            betControl.widthAnchor.constraint(equalToConstant: 150),
            betControl.heightAnchor.constraint(equalToConstant: 50),
            
            // Center contentStackView horizontally - this keeps cards dead center
            contentStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            // Pin contentStackView above betControl (bottom-aligned) with more spacing
            contentStackView.bottomAnchor.constraint(equalTo: betControl.topAnchor, constant: -12),
            // Allow contentStackView to grow upward by only constraining from bottom
            contentStackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8)
        ])
    }
}
