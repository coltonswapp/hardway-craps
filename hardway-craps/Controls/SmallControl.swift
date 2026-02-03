//
//  SmallControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/23/25.
//

import UIKit

class SmallControl: PlainControl {
    
    private let dieImageView1: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let dieImageView2: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let oddsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = HardwayColors.label.withAlphaComponent(0.6)
        return label
    }()
    
    private let diceStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.isUserInteractionEnabled = false
        return stackView
    }()
    
    private let contentStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.isUserInteractionEnabled = false
        return stackView
    }()
    
    let dieValue1: Int
    let dieValue2: Int
    let odds: String
    
    init(dieValue1: Int, dieValue2: Int, odds: String) {
        self.dieValue1 = dieValue1
        self.dieValue2 = dieValue2
        self.odds = odds
        super.init(title: nil)
        setupSmallControlView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupSmallControlView() {
        let dieSize: CGFloat = 28

        // Set die images
        dieImageView1.image = UIImage(named: "hardway-die-\(dieValue1)")
        dieImageView2.image = UIImage(named: "hardway-die-\(dieValue2)")
        oddsLabel.text = odds

        // Style the control to match action buttons
        backgroundColor = HardwayColors.surfaceGray
        layer.cornerRadius = 16
        layer.borderWidth = 1.5
        layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor

        // Add dice to dice stack view
        diceStackView.addArrangedSubview(dieImageView1)
        diceStackView.addArrangedSubview(dieImageView2)

        // Add dice stack and odds label to content stack view
        contentStackView.addArrangedSubview(diceStackView)
        contentStackView.addArrangedSubview(oddsLabel)

        addSubview(contentStackView)
        
        NSLayoutConstraint.activate([
            // Die images - slightly bigger
            dieImageView1.widthAnchor.constraint(equalToConstant: dieSize),
            dieImageView1.heightAnchor.constraint(equalToConstant: dieSize),
            
            dieImageView2.widthAnchor.constraint(equalToConstant: dieSize),
            dieImageView2.heightAnchor.constraint(equalToConstant: dieSize),
            
            // Content stack view - centered
            contentStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    override func configureBetViewConstraints() {
        NSLayoutConstraint.activate([
            betView.centerYAnchor.constraint(equalTo: centerYAnchor),
            betView.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }
}

