//
//  InsuranceControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/24/26.
//

import UIKit

final class InsuranceControl: PlainControl {
    
    private let iconImageView = UIImageView()
    private var hasSetupIcon = false
    
    override init(title: String? = nil) {
        super.init(title: title)
        
        // Override height constraint from PlainControl (which sets it to 50)
        // Deactivate the 50 height constraint and set it to 60 for circular button
        for constraint in constraints {
            if constraint.firstAttribute == .height && constraint.constant == 50 {
                constraint.isActive = false
                break
            }
        }
        
        // Set fixed size for circular button (60x60)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 60),
            heightAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Make it circular
        layer.cornerRadius = bounds.width / 2
        
        // Set up icon and hide title label on first layout
        if !hasSetupIcon && bounds.width > 0 {
            setupIcon()
            hideTitleLabel()
            hasSetupIcon = true
        }
    }
    
    private func hideTitleLabel() {
        // Hide title label - find the UILabel that was added by PlainControl
        for subview in subviews {
            if let label = subview as? UILabel, label.textAlignment == .center {
                label.isHidden = true
                break
            }
        }
    }
    
    private func setupIcon() {
        // Configure icon
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        iconImageView.image = UIImage(systemName: "shield.pattern.checkered", withConfiguration: config)
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.isUserInteractionEnabled = false
        
        addSubview(iconImageView)
        
        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    override func configureBetViewConstraints() {
        // Position betView on trailing edge (hanging off the button)
        NSLayoutConstraint.activate([
            betView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 12),
            betView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    override func setBetRemovalDisabled(_ disabled: Bool) {
        if disabled {
            // Tint the control to show it's disabled
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.5)
                self.iconImageView.tintColor = HardwayColors.label.withAlphaComponent(0.5)
            }
        } else {
            // Restore normal appearance
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = self.background
                self.iconImageView.tintColor = .white
            }
        }
    }
    
}
