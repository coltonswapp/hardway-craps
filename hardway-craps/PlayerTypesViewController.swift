//
//  PlayerTypesViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class PlayerTypesViewController: UIViewController {
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Player Types"
        
        setupScrollView()
        setupContent()
    }
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func setupContent() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 24
        stackView.alignment = .fill
        
        // Add header
        let headerLabel = UILabel()
        headerLabel.text = "Understanding Your Play Style"
        headerLabel.font = .systemFont(ofSize: 24, weight: .bold)
        headerLabel.textColor = .white
        headerLabel.numberOfLines = 0
        headerLabel.textAlignment = .center
        
        let descriptionLabel = UILabel()
        descriptionLabel.text = "Your gameplay is analyzed based on bet types, sizing, and behavior patterns. Each session receives a player type classification."
        descriptionLabel.font = .systemFont(ofSize: 16, weight: .regular)
        descriptionLabel.textColor = .lightGray
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textAlignment = .center
        
        let headerStack = UIStackView(arrangedSubviews: [headerLabel, descriptionLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 12
        headerStack.alignment = .center
        
        stackView.addArrangedSubview(headerStack)
        
        // Add spacing
        stackView.addArrangedSubview(createSpacer(height: 8))
        
        // Add player type cards
        addPlayerTypeCard(
            type: .conservative,
            title: "Conservative 🛡️",
            description: "Plays it safe with fundamental bets and small wagers",
            characteristics: [
                "Sticks to Pass Line, Odds, and Place bets",
                "Small bet sizes (< 5% of balance)",
                "Minimal concurrent bets (1-2)",
                "Avoids prop bets (Hardways, Horn)"
            ]
        )
        
        addPlayerTypeCard(
            type: .strategic,
            title: "Strategic 🧠",
            description: "Maximizes odds bets and makes calculated decisions",
            characteristics: [
                "Heavy use of Pass Line Odds (best odds)",
                "Moderate bet sizes (5-15% of balance)",
                "Balanced concurrent bets (2-4)",
                "Focuses on bets with lowest house edge"
            ]
        )
        
        addPlayerTypeCard(
            type: .balanced,
            title: "Balanced ⚖️",
            description: "Healthy mix of safe and exciting bets",
            characteristics: [
                "Mix of safe and prop bets (10-30% props)",
                "Moderate bet sizes (5-20% of balance)",
                "Moderate concurrent bets (2-4)",
                "Disciplined - doesn't chase losses"
            ]
        )
        
        addPlayerTypeCard(
            type: .aggressive,
            title: "Aggressive ⚡",
            description: "Likes action with larger bets and multiple wagers",
            characteristics: [
                "Higher bet sizes (15-30% of balance)",
                "Many concurrent bets (4+)",
                "More prop bets (20-40% of total)",
                "Some loss chasing behavior"
            ]
        )
        
        addPlayerTypeCard(
            type: .reckless,
            title: "Reckless 🔥",
            description: "High-risk, high-reward with heavy prop betting",
            characteristics: [
                "Very large bet sizes (> 30% of balance)",
                "Heavy prop betting (> 40% of total)",
                "Frequent loss chasing",
                "Many simultaneous bets (5+)"
            ]
        )
        
        contentView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    private func addPlayerTypeCard(type: PlayerType, title: String, description: String, characteristics: [String]) {
        let cardView = UIView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = HardwayColors.surfaceGray
        cardView.layer.cornerRadius = 12
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        
        let descriptionLabel = UILabel()
        descriptionLabel.text = description
        descriptionLabel.font = .systemFont(ofSize: 16, weight: .regular)
        descriptionLabel.textColor = .lightGray
        descriptionLabel.numberOfLines = 0
        
        let characteristicsStack = UIStackView()
        characteristicsStack.axis = .vertical
        characteristicsStack.spacing = 8
        characteristicsStack.alignment = .leading
        
        for characteristic in characteristics {
            let bulletLabel = UILabel()
            bulletLabel.text = "• \(characteristic)"
            bulletLabel.font = .systemFont(ofSize: 14, weight: .regular)
            bulletLabel.textColor = HardwayColors.label
            bulletLabel.numberOfLines = 0
            characteristicsStack.addArrangedSubview(bulletLabel)
        }
        
        let cardStack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, characteristicsStack])
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.axis = .vertical
        cardStack.spacing = 12
        cardStack.alignment = .leading
        
        cardView.addSubview(cardStack)
        stackView.addArrangedSubview(cardView)
        
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            cardStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            cardStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        ])
    }
    
    private func createSpacer(height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }
}

