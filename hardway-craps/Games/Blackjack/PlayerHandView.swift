//
//  PlayerHandView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

final class PlayerHandView: UIView {

    let betControl = PlainControl(title: "Bet")
    let handView: BlackjackHandView

    var onTap: (() -> Void)? {
        didSet { handView.onTap = onTap }
    }

    var canTap: (() -> Bool)? {
        didSet { handView.canTap = canTap }
    }

    // Expose BlackjackHandView properties and methods
    var currentCards: [BlackjackHandView.Card] {
        return handView.currentCards
    }

    var cardViewsForAnimation: [PlayingCardView] {
        return handView.cardViewsForAnimation
    }

    func getCardViewFrame(at index: Int, in targetView: UIView) -> CGRect? {
        return handView.getCardViewFrame(at: index, in: targetView)
    }

    convenience init() {
        self.init(stackDirection: .down, hidesFirstCard: false, scale: 1)
    }

    init(stackDirection: BlackjackHandView.StackDirection, hidesFirstCard: Bool, scale: CGFloat = 1) {
        handView = BlackjackHandView(stackDirection: stackDirection, hidesFirstCard: hidesFirstCard, scale: scale)
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        handView.translatesAutoresizingMaskIntoConstraints = false
        handView.isUserInteractionEnabled = true // Enable for tap handling
        addSubview(handView)

        betControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(betControl)

        // Find the contentStackView in the handView
        var foundStackView: UIStackView?
        for subview in handView.subviews {
            if let stackView = subview as? UIStackView {
                foundStackView = stackView
                break
            }
        }

        guard let contentStackView = foundStackView else {
            return
        }

        // Find and deactivate ALL constraints on contentStackView to reconfigure layout
        var constraintsToDeactivate: [NSLayoutConstraint] = []

        for constraint in handView.constraints {
            if constraint.firstItem === contentStackView || constraint.secondItem === contentStackView {
                constraintsToDeactivate.append(constraint)
            }
        }

        constraintsToDeactivate.forEach { $0.isActive = false }

        // Add new constraints
        NSLayoutConstraint.activate([
            // Pin handView to fill the container
            handView.topAnchor.constraint(equalTo: topAnchor),
            handView.leadingAnchor.constraint(equalTo: leadingAnchor),
            handView.trailingAnchor.constraint(equalTo: trailingAnchor),
            handView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Pin betControl to bottom, centered
            betControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            betControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            betControl.widthAnchor.constraint(equalToConstant: 150),
            betControl.heightAnchor.constraint(equalToConstant: 50),

            // Center contentStackView horizontally - this keeps cards dead center
            contentStackView.centerXAnchor.constraint(equalTo: handView.centerXAnchor),
            // Pin contentStackView above betControl (bottom-aligned) with more spacing
            contentStackView.bottomAnchor.constraint(equalTo: betControl.topAnchor, constant: -24),
            // Allow contentStackView to grow upward by only constraining from bottom
            contentStackView.topAnchor.constraint(greaterThanOrEqualTo: handView.topAnchor, constant: 8)
        ])
    }

    // Passthrough methods to BlackjackHandView
    func configure(firstCard: BlackjackHandView.Card, secondCard: BlackjackHandView.Card) {
        handView.configure(firstCard: firstCard, secondCard: secondCard)
    }

    func clearCards() {
        handView.clearCards()
    }

    func discardCards(to endPoint: CGPoint, in containerView: UIView, completion: @escaping () -> Void) {
        handView.discardCards(to: endPoint, in: containerView, completion: completion)
    }

    func addCard(_ card: BlackjackHandView.Card) {
        handView.addCard(card)
    }

    func dealCard(_ card: BlackjackHandView.Card, from startPoint: CGPoint, in containerView: UIView) {
        handView.dealCard(card, from: startPoint, in: containerView)
    }

    func dealCardFaceDown(_ card: BlackjackHandView.Card, from startPoint: CGPoint, in containerView: UIView) {
        handView.dealCardFaceDown(card, from: startPoint, in: containerView)
    }

    @discardableResult
    func revealCard(at index: Int, animated: Bool = true) -> Bool {
        return handView.revealCard(at: index, animated: animated)
    }

    func setTotalsHidden(_ hidden: Bool) {
        handView.setTotalsHidden(hidden)
    }

    func setCardsWithoutAnimation(_ cards: [BlackjackHandView.Card]) {
        handView.setCardsWithoutAnimation(cards)
    }
}
