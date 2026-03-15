//
//  BaccaratCardPlayground.swift
//  hardway-craps
//
//  Created by Colton Swapp on 3/7/26.
//

import UIKit

final class BaccaratCardPlayground: UIViewController {

    private let cardView = BaccaratCardView()
    private let instructionLabel = UILabel()
    private let resetButton = UIButton(type: .system)

    // Card dimensions
    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 280

    // Current card state
    private var currentRank: BaccaratCardView.Rank = .ace
    private var currentSuit: BaccaratCardView.Suit = .spades

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewController()
        setupCardView()
        setupInstructions()
        setupResetButton()

        // Configure with a random card
        randomizeCard()
    }

    private func setupViewController() {
        title = "Baccarat Card Transitions"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissPlayground)
        )
    }

    private func setupCardView() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.widthAnchor.constraint(equalToConstant: cardWidth),
            cardView.heightAnchor.constraint(equalToConstant: cardHeight)
        ])

        // Add shadow
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.3
        cardView.layer.shadowOffset = CGSize(width: 0, height: 4)
        cardView.layer.shadowRadius = 8

        // Add tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        cardView.addGestureRecognizer(tap)
    }

    private func setupInstructions() {
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.text = "Tap to flip card"
        instructionLabel.font = .systemFont(ofSize: 16, weight: .medium)
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        view.addSubview(instructionLabel)

        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 40),
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func setupResetButton() {
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.setTitle("New Random Card", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.backgroundColor = HardwayColors.surfaceGray
        resetButton.layer.cornerRadius = 12
        resetButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        resetButton.addTarget(self, action: #selector(resetCard), for: .touchUpInside)
        view.addSubview(resetButton)

        NSLayoutConstraint.activate([
            resetButton.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 20),
            resetButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func handleTap() {
        cardView.setFaceDown(!cardView.isFaceDown, animated: true)
        HapticsHelper.lightHaptic()
    }

    @objc private func resetCard() {
        // Reset to face down and randomize
        UIView.transition(with: cardView, duration: 0.4, options: .transitionFlipFromRight) {
            self.cardView.setFaceDown(true, animated: false)
        } completion: { _ in
            self.randomizeCard()
        }

        HapticsHelper.mediumHaptic()
    }

    private func randomizeCard() {
        currentRank = BaccaratCardView.Rank.allCases.randomElement() ?? .ace
        currentSuit = BaccaratCardView.Suit.allCases.randomElement() ?? .spades
        cardView.configure(rank: currentRank, suit: currentSuit)
    }

    @objc private func dismissPlayground() {
        dismiss(animated: true)
    }
}
