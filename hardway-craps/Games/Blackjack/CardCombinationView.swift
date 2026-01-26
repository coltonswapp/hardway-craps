//
//  CardCombinationView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/25/26.
//

import UIKit

final class CardCombinationView: UIView {

    private let cardsStack = UIStackView()
    private let outerStack = UIStackView()
    private let oddsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        // Setup cards stack (horizontal)
        cardsStack.axis = .horizontal
        cardsStack.spacing = -10 // Negative spacing for overlap
        cardsStack.alignment = .center
        cardsStack.distribution = .fill
        cardsStack.translatesAutoresizingMaskIntoConstraints = false

        // Setup odds label
        oddsLabel.font = .systemFont(ofSize: 10, weight: .medium)
        oddsLabel.textColor = .white.withAlphaComponent(0.5)
        oddsLabel.textAlignment = .center
        oddsLabel.translatesAutoresizingMaskIntoConstraints = false

        // Setup outer stack (vertical)
        outerStack.axis = .vertical
        outerStack.spacing = 3
        outerStack.alignment = .center
        outerStack.distribution = .fill
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        outerStack.addArrangedSubview(cardsStack)
        outerStack.addArrangedSubview(oddsLabel)

        addSubview(outerStack)

        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(cards: [(rank: PlayingCardView.Rank, suit: PlayingCardView.Suit)], odds: String) {
        // Clear existing cards
        cardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Add new cards
        for (rank, suit) in cards {
            let cardView = SmallPlayingCardView()
            cardView.configure(rank: rank, suit: suit)
            cardView.translatesAutoresizingMaskIntoConstraints = false

            let randomDegrees = CGFloat.random(in: -5...5)
            let randomRadians = randomDegrees * .pi / 180
            cardView.transform = CGAffineTransform(rotationAngle: randomRadians)

            NSLayoutConstraint.activate([
                cardView.widthAnchor.constraint(equalToConstant: 28),
                cardView.heightAnchor.constraint(equalToConstant: 38)
            ])

            cardsStack.addArrangedSubview(cardView)
        }

        oddsLabel.text = odds
    }
}
