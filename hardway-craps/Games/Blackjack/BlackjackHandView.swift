//
//  BlackjackHandView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

class BlackjackHandView: UIControl {

    struct Card {
        let rank: PlayingCardView.Rank
        let suit: PlayingCardView.Suit
        let isCutCard: Bool

        init(rank: PlayingCardView.Rank, suit: PlayingCardView.Suit, isCutCard: Bool = false) {
            self.rank = rank
            self.suit = suit
            self.isCutCard = isCutCard
        }

        static func cutCard() -> Card {
            // Use a dummy rank/suit for the cut card - it won't be displayed
            return Card(rank: .ace, suit: .spades, isCutCard: true)
        }
    }

    enum StackDirection {
        case down
        case up
    }

    private let stackDirection: StackDirection
    private let hidesFirstCard: Bool
    private let scale: CGFloat

    let cardContainer = UIView()
    private var cardViews: [PlayingCardView] = []
    private var cardConstraints: [NSLayoutConstraint] = []
    private let totalLabel = UILabel()
    private let alternativeTotalLabel = UILabel()
    private let contentStackView = UIStackView()
    private let labelStackView = UIStackView()
    private let placeholderView1 = UIView()
    private let placeholderView2 = UIView()

    private let cardHeight: CGFloat = 120
    private let cardAspectRatio: CGFloat = 60.0 / 88.0
    private let horizontalOffset: CGFloat = 45
    private let verticalOffset: CGFloat = 7.5
    private let horizontalStepScale: Double = 0.9

    private var containerHeightConstraint: NSLayoutConstraint!
    private var containerWidthConstraint: NSLayoutConstraint!

    private var cards: [Card] = []
    private var isFirstCardHidden = false
    private var faceDownCardIndices: Set<Int> = [] // Track which card indices should be face-down
    private var cardRotations: [CGFloat] = [] // Random rotation for each card (-5° to +5°)

    var currentCards: [Card] {
        return cards
    }

    // Expose card views for animations
    var cardViewsForAnimation: [PlayingCardView] {
        return cardViews
    }

    func getCardViewFrame(at index: Int, in targetView: UIView) -> CGRect? {
        guard index >= 0 && index < cardViews.count else { return nil }
        let cardView = cardViews[index]
        return cardView.superview?.convert(cardView.frame, to: targetView)
    }

    // Touch handling properties
    var onTap: (() -> Void)?
    var canTap: (() -> Bool)?
    
    init(stackDirection: StackDirection, hidesFirstCard: Bool, scale: CGFloat = 1) {
        self.stackDirection = stackDirection
        self.hidesFirstCard = hidesFirstCard
        self.scale = scale
        super.init(frame: .zero)
        setupView()
    }
    
    override init(frame: CGRect) {
        self.stackDirection = .down
        self.hidesFirstCard = false
        self.scale = 1
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(firstCard: Card, secondCard: Card) {
        isFirstCardHidden = hidesFirstCard
        setCards([firstCard, secondCard], animated: false)
    }

    func setCardsWithoutAnimation(_ cards: [Card]) {
        self.cards = cards

        // Generate random rotations for new cards
        cardRotations.removeAll()
        for _ in 0..<cards.count {
            cardRotations.append(generateRandomRotation())
        }

        updateCards(animated: false)
        updatePlaceholderVisibility()
    }
    
    func clearCards() {
        cards = []
        faceDownCardIndices.removeAll()
        cardRotations.removeAll()
        updateCards(animated: false)
        // Keep placeholders hidden when clearing - they'll show when cards are dealt
        placeholderView1.isHidden = true
        placeholderView2.isHidden = true
    }
    
    func discardCards(to endPoint: CGPoint, in containerView: UIView, completion: @escaping () -> Void) {
        guard !cards.isEmpty else {
            completion()
            return
        }
        
        // Force layout to ensure card positions are accurate
        layoutIfNeeded()
        
        // Animate total label opacity to zero
        UIView.animate(withDuration: 0.3, animations: {
            self.totalLabel.alpha = 0
            self.alternativeTotalLabel.alpha = 0
        })
        
        let cardsToDiscard = cards
        let cardViewsToDiscard = Array(cardViews) // Create a copy of the array
        
        // Track completion for all cards
        var completedAnimations = 0
        let totalCards = cardsToDiscard.count
        
        // Animate all cards simultaneously with random delays (like chip animation)
        for (index, cardView) in cardViewsToDiscard.enumerated() {
            let card = cardsToDiscard[index]
            
            // Get the card's current position - convert from cardContainer to containerView
            let cardFrameInContainer = cardView.superview?.convert(cardView.frame, to: cardContainer) ?? .zero
            let cardCenterInContainer = CGPoint(x: cardFrameInContainer.midX, y: cardFrameInContainer.midY)
            let startPointInContainer = cardContainer.convert(cardCenterInContainer, to: containerView)
            
            // Create temporary card for animation (matching chip animation approach)
            let tempCard = PlayingCardView()
            tempCard.padding = cardView.padding
            if card.isCutCard {
                tempCard.configureCutCard()
            } else {
                tempCard.configure(rank: card.rank, suit: card.suit)
            }
            tempCard.setFaceDown(index == 0 && isFirstCardHidden, animated: false)
            applyCardShadow(to: tempCard)
            
            // Start with the card's current size and transform
            let currentCardSize = cardSize()
            tempCard.bounds = CGRect(origin: .zero, size: currentCardSize)
            tempCard.center = startPointInContainer

            // Use the card's current transform (scale and rotation based on position in hand)
            let currentScale = scaleForCard(at: index, total: cardsToDiscard.count)
            let currentRotation = index < cardRotations.count ? cardRotations[index] : 0
            tempCard.transform = CGAffineTransform(scaleX: currentScale, y: currentScale).rotated(by: currentRotation)
            
            containerView.addSubview(tempCard)
            
            // Hide the original card immediately
            cardView.alpha = 0
            
            // Random delay for cascading effect (like chip animation)
            let randomDelay = Double.random(in: 0...0.15)
            
            // Animate to destination with easeIn curve (matching chip animation)
            UIView.animate(withDuration: 0.5, delay: randomDelay, options: .curveEaseIn, animations: {
                tempCard.center = endPoint
                tempCard.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            }, completion: { _ in
                // Fade out after reaching destination (matching chip animation)
                UIView.animate(withDuration: 0.2, animations: {
                    tempCard.alpha = 0
                }, completion: { _ in
                    tempCard.removeFromSuperview()
                    completedAnimations += 1
                    
                    // When all cards are done, clear the hand without showing placeholders
                    if completedAnimations >= totalCards {
                        self.cards = []
                        self.cardRotations.removeAll()
                        self.updateCards(animated: false)
                        // Keep placeholders hidden during discard - they'll show when a new hand starts
                        self.placeholderView1.isHidden = true
                        self.placeholderView2.isHidden = true
                        completion()
                    }
                })
            })
        }
    }
    
    func addCard(_ card: Card) {
        if cards.isEmpty && hidesFirstCard {
            isFirstCardHidden = true
        }
        var updatedCards = cards
        updatedCards.append(card)
        setCards(updatedCards, animated: true)
    }
    
    func dealCard(_ card: Card, from startPoint: CGPoint, in containerView: UIView) {
        if cards.isEmpty && hidesFirstCard {
            isFirstCardHidden = true
        }
        var updatedCards = cards
        updatedCards.append(card)
        setCards(updatedCards, animated: true)
        
        // Force layout to get the final position (this happens before the animation starts)
        layoutIfNeeded()
        
        guard let newCardView = cardViews.last else { return }
        newCardView.alpha = 0
        
        // Read the actual center from the card view's frame after layout
        // Convert from cardContainer's coordinate space
        let cardFrame = newCardView.superview?.convert(newCardView.frame, to: cardContainer) ?? .zero
        let targetCenter = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
        let startPointInContainer = containerView.convert(startPoint, to: cardContainer)
        let tempCard = PlayingCardView()
        tempCard.padding = newCardView.padding
        if card.isCutCard {
            tempCard.configureCutCard()
        } else {
            tempCard.configure(rank: card.rank, suit: card.suit)
        }
        tempCard.setFaceDown(isFirstCardHidden && updatedCards.count == 1)
        applyCardShadow(to: tempCard)
        tempCard.bounds = CGRect(origin: .zero, size: cardSize())
        tempCard.center = startPointInContainer
        
        // Start at deck scale (deck cards are 60px, hand cards are 120px, so start at 0.5 scale)
        let deckScale: CGFloat = 0.5
        let targetScale = scaleForCard(at: updatedCards.count - 1, total: updatedCards.count)
        let targetRotation = cardRotations.count > updatedCards.count - 1 ? cardRotations[updatedCards.count - 1] : 0
        tempCard.transform = CGAffineTransform(scaleX: deckScale, y: deckScale)
        cardContainer.addSubview(tempCard)

        let calculatedCenter = cardCenter(at: updatedCards.count - 1, total: updatedCards.count)
        print("[BlackjackHandView] deal target (actual):", targetCenter, "calculated:", calculatedCenter, "diff:", targetCenter.x - calculatedCenter.x, "cards:", updatedCards.count)

        let animator = UIViewPropertyAnimator(
            duration: 0.25,
            controlPoint1: CGPoint(x: 0.45, y: 0),
            controlPoint2: CGPoint(x: 0.07, y: 1.1)
        ) {
            tempCard.center = targetCenter
            tempCard.transform = CGAffineTransform(scaleX: targetScale, y: targetScale).rotated(by: targetRotation)
        }
        animator.addCompletion { [weak self] _ in
            tempCard.removeFromSuperview()
            newCardView.alpha = 1

            // Only count cards that are dealt face-up (not the dealer's hole card)
            let isFaceDown = self?.isFirstCardHidden == true && updatedCards.count == 1
            if !isFaceDown {
                // Notify that a card animation completed (for card count updates)
                var responder: UIResponder? = self
                while responder != nil {
                    if let vc = responder as? BlackjackGameplayViewController {
                        vc.onCardAnimationComplete(card: card)
                        break
                    }
                    responder = responder?.next
                }
            }
        }

        // Trigger super light haptic when card starts dealing
        HapticsHelper.superLightHaptic()

        // Notify that a card is being dealt (for deck count updates)
        var responder: UIResponder? = self
        while responder != nil {
            if let vc = responder as? BlackjackGameplayViewController {
                vc.onCardDealt()
                break
            }
            responder = responder?.next
        }

        animator.startAnimation()
    }
    
    func isFirstCardFaceDown() -> Bool {
        guard let firstCardView = cardViews.first else { return false }
        return firstCardView.isFaceDownCard
    }
    
    @discardableResult
    func revealFirstCard(animated: Bool = true) -> Bool {
        guard isFirstCardHidden, let firstCardView = cardViews.first else { return false }
        isFirstCardHidden = false
        firstCardView.setFaceDown(false, animated: animated)

        // Recalculate totals now that the first card is visible
        // All cards are now visible (no more hidden cards)
        let visibleCards = cards
        let totals = calculateBlackjackTotals(for: visibleCards)
        totalLabel.text = "\(totals.primary)"

        let totalUpdate = {
            // Add back to arranged subviews if it was removed
            if !self.contentStackView.arrangedSubviews.contains(self.labelStackView) {
                self.contentStackView.insertArrangedSubview(self.labelStackView, at: 0)
            }

            // Show the label stack (which will properly center the cards)
            self.labelStackView.isHidden = false
            self.totalLabel.alpha = 1

            // Update alternative total if it exists (but only if totals aren't explicitly hidden)
            if let alternative = totals.alternative, !visibleCards.isEmpty, !self.totalLabel.isHidden {
                self.alternativeTotalLabel.text = "or \(alternative)"
                self.alternativeTotalLabel.isHidden = false
                self.alternativeTotalLabel.alpha = 1
            } else {
                self.alternativeTotalLabel.isHidden = true
                self.alternativeTotalLabel.alpha = 0
            }
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: totalUpdate)
        } else {
            totalUpdate()
        }

        // Update card count when the hole card is revealed
        if let firstCard = cards.first {
            var responder: UIResponder? = self
            while responder != nil {
                if let vc = responder as? BlackjackGameplayViewController {
                    vc.onCardAnimationComplete(card: firstCard)
                    break
                }
                responder = responder?.next
            }
        }

        return true
    }
    
    /// Deal a card face-down (for double down scenarios)
    func dealCardFaceDown(_ card: Card, from startPoint: CGPoint, in containerView: UIView) {
        var updatedCards = cards
        updatedCards.append(card)
        // Mark this card index as face-down
        faceDownCardIndices.insert(updatedCards.count - 1)
        setCards(updatedCards, animated: true)
        
        // Force layout to get the final position
        layoutIfNeeded()
        
        guard let newCardView = cardViews.last else { return }
        newCardView.alpha = 0
        
        // Read the actual center from the card view's frame after layout
        let cardFrame = newCardView.superview?.convert(newCardView.frame, to: cardContainer) ?? .zero
        let targetCenter = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
        let startPointInContainer = containerView.convert(startPoint, to: cardContainer)
        let tempCard = PlayingCardView()
        tempCard.padding = newCardView.padding
        if card.isCutCard {
            tempCard.configureCutCard()
        } else {
            tempCard.configure(rank: card.rank, suit: card.suit)
        }
        tempCard.setFaceDown(true, animated: false) // Always face-down
        applyCardShadow(to: tempCard)
        tempCard.bounds = CGRect(origin: .zero, size: cardSize())
        tempCard.center = startPointInContainer
        
        // Start at deck scale
        let deckScale: CGFloat = 0.5
        let targetScale = scaleForCard(at: updatedCards.count - 1, total: updatedCards.count)
        let targetRotation = cardRotations.count > updatedCards.count - 1 ? cardRotations[updatedCards.count - 1] : 0
        tempCard.transform = CGAffineTransform(scaleX: deckScale, y: deckScale)
        cardContainer.addSubview(tempCard)

        let animator = UIViewPropertyAnimator(
            duration: 0.25,
            controlPoint1: CGPoint(x: 0.45, y: 0),
            controlPoint2: CGPoint(x: 0.07, y: 1.1)
        ) {
            tempCard.center = targetCenter
            tempCard.transform = CGAffineTransform(scaleX: targetScale, y: targetScale).rotated(by: targetRotation)
        }
        animator.addCompletion { _ in
            tempCard.removeFromSuperview()
            newCardView.alpha = 1
            // Ensure the card stays face-down
            newCardView.setFaceDown(true, animated: false)

            // Don't count face-down cards (like double-down cards or dealer's hole card)
            // They'll be counted when revealed
        }

        // Trigger super light haptic when card starts dealing
        HapticsHelper.superLightHaptic()

        // Notify that a card is being dealt (for deck count updates)
        var responder: UIResponder? = self
        while responder != nil {
            if let vc = responder as? BlackjackGameplayViewController {
                vc.onCardDealt()
                break
            }
            responder = responder?.next
        }

        animator.startAnimation()
    }
    
    /// Reveal a specific card by index (for double down scenarios)
    @discardableResult
    func revealCard(at index: Int, animated: Bool = true) -> Bool {
        guard index >= 0 && index < cardViews.count else { return false }
        guard index < cards.count else { return false }

        // Get the card before removing from face-down set
        let revealedCard = cards[index]

        // Remove from face-down set
        faceDownCardIndices.remove(index)
        let cardView = cardViews[index]
        cardView.setFaceDown(false, animated: animated)

        // Recalculate totals now that the card is visible
        // Calculate totals using only visible cards (exclude face-down cards except dealer's hole card)
        let visibleCards: [Card]
        if hidesFirstCard && isFirstCardHidden {
            // Dealer's hole card scenario: exclude first card from totals
            visibleCards = Array(cards.dropFirst())
        } else {
            // Player scenario: exclude any remaining face-down cards (double down cards)
            visibleCards = cards.enumerated().compactMap { cardIndex, card in
                faceDownCardIndices.contains(cardIndex) ? nil : card
            }
        }

        let totals = calculateBlackjackTotals(for: visibleCards)
        totalLabel.text = "\(totals.primary)"

        // Update totals display
        let totalUpdate = {
            // Add back to arranged subviews if it was removed
            if !self.contentStackView.arrangedSubviews.contains(self.labelStackView) {
                self.contentStackView.insertArrangedSubview(self.labelStackView, at: 0)
            }

            self.labelStackView.isHidden = false
            self.totalLabel.alpha = 1

            // Update alternative total if it exists (but only if totals aren't explicitly hidden)
            if let alternative = totals.alternative, !visibleCards.isEmpty, !self.totalLabel.isHidden {
                self.alternativeTotalLabel.text = "or \(alternative)"
                self.alternativeTotalLabel.isHidden = false
                self.alternativeTotalLabel.alpha = 1
            } else {
                self.alternativeTotalLabel.isHidden = true
                self.alternativeTotalLabel.alpha = 0
            }
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: totalUpdate)
        } else {
            totalUpdate()
        }

        // Update card count when the card is revealed
        var responder: UIResponder? = self
        while responder != nil {
            if let vc = responder as? BlackjackGameplayViewController {
                vc.onCardAnimationComplete(card: revealedCard)
                break
            }
            responder = responder?.next
        }

        return true
    }
    
    func setTotalsHidden(_ hidden: Bool) {
        // If first card is hidden, keep label stack hidden regardless of this setting
        if hidesFirstCard && isFirstCardHidden {
            labelStackView.isHidden = true
            alternativeTotalLabel.isHidden = true // Explicitly hide alternative label
            // Remove from arranged subviews to center cards
            if contentStackView.arrangedSubviews.contains(labelStackView) {
                contentStackView.removeArrangedSubview(labelStackView)
                labelStackView.removeFromSuperview()
            }
            return
        }

        // Otherwise, respect the hidden parameter
        if hidden {
            // Remove from arranged subviews to center cards when hidden
            if contentStackView.arrangedSubviews.contains(labelStackView) {
                contentStackView.removeArrangedSubview(labelStackView)
                labelStackView.removeFromSuperview()
            }
        } else {
            // Add back to arranged subviews when showing
            if !contentStackView.arrangedSubviews.contains(labelStackView) {
                contentStackView.insertArrangedSubview(labelStackView, at: 0)
            }
        }

        labelStackView.isHidden = hidden
        totalLabel.isHidden = hidden
        alternativeTotalLabel.isHidden = hidden // Always hide alternative when totals are hidden
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        // Setup touch handling
        setupGestures()
        
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .horizontal
        contentStackView.alignment = .center
        contentStackView.distribution = .fill
        contentStackView.spacing = 4
        contentStackView.isUserInteractionEnabled = false // Allow touches to pass through to control
        addSubview(contentStackView)
        
        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        totalLabel.font = .systemFont(ofSize: 22, weight: .semibold) // Always full size, not scaled with cards
        totalLabel.textColor = .white
        totalLabel.textAlignment = .left
        
        alternativeTotalLabel.translatesAutoresizingMaskIntoConstraints = false
        alternativeTotalLabel.font = .systemFont(ofSize: 16, weight: .regular) // Always full size, not scaled with cards
        alternativeTotalLabel.textColor = .white.withAlphaComponent(0.7)
        alternativeTotalLabel.textAlignment = .left
        alternativeTotalLabel.isHidden = true
        
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.isUserInteractionEnabled = false // Allow touches to pass through

        // Setup placeholder views for first 2 cards
        setupPlaceholderViews()
        
        labelStackView.axis = .vertical
        labelStackView.alignment = .leading
        labelStackView.spacing = 2
        labelStackView.addArrangedSubview(totalLabel)
        labelStackView.addArrangedSubview(alternativeTotalLabel)
        
        // Set content hugging priority so label gets space before cards compress
        labelStackView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cardContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // Set compression resistance so label doesn't compress when space is tight
        labelStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
        totalLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        contentStackView.addArrangedSubview(labelStackView)
        contentStackView.addArrangedSubview(cardContainer)
        
        containerHeightConstraint = cardContainer.heightAnchor.constraint(equalToConstant: cardHeight * scale)
        containerWidthConstraint = cardContainer.widthAnchor.constraint(equalToConstant: (cardHeight * cardAspectRatio * scale) - 20)
        
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Ensure label has enough width for 2-digit numbers (e.g., "17")
            totalLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            labelStackView.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            
            containerHeightConstraint,
            containerWidthConstraint
        ])
        
        updateCards(animated: false)
        updatePlaceholderVisibility()
    }
    
    private func setupPlaceholderViews() {
        // Configure placeholder views
        [placeholderView1, placeholderView2].forEach { placeholder in
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            placeholder.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.5)
            placeholder.layer.borderWidth = 1.0
            placeholder.layer.borderColor = HardwayColors.label.withAlphaComponent(0.3).cgColor
            placeholder.layer.cornerRadius = 8
            cardContainer.addSubview(placeholder)
        }
        
        // Position placeholder views for first 2 cards
        let cardWidth = cardHeight * cardAspectRatio * scale
        let cardHeightScaled = cardHeight * scale
        
        // First card placeholder
        let placeholder1Leading = placeholderView1.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor)
        let placeholder1Height = placeholderView1.heightAnchor.constraint(equalToConstant: cardHeightScaled)
        let placeholder1Width = placeholderView1.widthAnchor.constraint(equalToConstant: cardWidth)
        
        // Second card placeholder - positioned with horizontal offset
        let stepScale = pow(horizontalStepScale, Double(1)) // For second card (index 1, total 2)
        let secondCardOffset = (horizontalOffset * scale) * CGFloat(stepScale)
        let placeholder2Leading = placeholderView2.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: secondCardOffset)
        let placeholder2Height = placeholderView2.heightAnchor.constraint(equalToConstant: cardHeightScaled)
        let placeholder2Width = placeholderView2.widthAnchor.constraint(equalToConstant: cardWidth)
        
        // Vertical positioning based on stack direction
        let placeholder1Vertical: NSLayoutConstraint
        let placeholder2Vertical: NSLayoutConstraint
        
        switch stackDirection {
        case .down:
            placeholder1Vertical = placeholderView1.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor)
            placeholder2Vertical = placeholderView2.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -(verticalOffset * scale))
        case .up:
            placeholder1Vertical = placeholderView1.topAnchor.constraint(equalTo: cardContainer.topAnchor)
            placeholder2Vertical = placeholderView2.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: (verticalOffset * scale))
        }
        
        NSLayoutConstraint.activate([
            placeholder1Leading,
            placeholder1Vertical,
            placeholder1Height,
            placeholder1Width,
            placeholder2Leading,
            placeholder2Vertical,
            placeholder2Height,
            placeholder2Width
        ])
    }
    
    private func applyCardShadow(to cardView: PlayingCardView) {
        cardView.layer.masksToBounds = false
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.18
        cardView.layer.shadowRadius = 6
        cardView.layer.shadowOffset = CGSize(width: 0, height: 3)
    }
    
    private func generateRandomRotation() -> CGFloat {
        // Generate random rotation for cards
        let degrees = CGFloat.random(in: -3...3)
        return degrees * .pi / 180 // Convert to radians
    }

    private func setCards(_ cards: [Card], animated: Bool) {
        self.cards = cards

        // Generate random rotations for new cards
        while cardRotations.count < cards.count {
            cardRotations.append(generateRandomRotation())
        }
        // Remove excess rotations if cards were removed
        if cardRotations.count > cards.count {
            cardRotations = Array(cardRotations.prefix(cards.count))
        }

        updateCards(animated: animated)
        updatePlaceholderVisibility()
    }
    
    private func updatePlaceholderVisibility() {
        // Hide placeholders when cards are present
        // Only show placeholders when explicitly requested (not during discard/clear)
        let shouldHide = !cards.isEmpty
        if shouldHide {
            placeholderView1.isHidden = true
            placeholderView2.isHidden = true
        }
        // Note: We don't show placeholders here - they're shown explicitly via showPlaceholders()
    }
    
    func showPlaceholders() {
        // Explicitly show placeholders when ready for a new hand
        guard cards.isEmpty else { return }
        placeholderView1.isHidden = false
        placeholderView2.isHidden = false
    }
    
    private func updateCards(animated: Bool) {
        if animated {
            layoutIfNeeded()
        }
        cardConstraints.forEach { $0.isActive = false }
        cardConstraints.removeAll()
        
        if cardViews.count > cards.count {
            cardViews.dropFirst(cards.count).forEach { $0.removeFromSuperview() }
            cardViews = Array(cardViews.prefix(cards.count))
        }
        
        while cardViews.count < cards.count {
            let cardView = PlayingCardView()
            cardView.translatesAutoresizingMaskIntoConstraints = false
            cardView.isUserInteractionEnabled = false // Allow touches to pass through to the control
            applyCardShadow(to: cardView)
            cardContainer.addSubview(cardView)
            cardViews.append(cardView)
        }
        
        var accumulatedHorizontalOffset: CGFloat = 0
        
        for (index, card) in cards.enumerated() {
            let cardView = cardViews[index]
            if card.isCutCard {
                cardView.configureCutCard()
            } else {
                cardView.configure(rank: card.rank, suit: card.suit)
            }
            // Set face-down if it's the first card and hidden, OR if it's in the faceDownCardIndices set
            let shouldBeFaceDown = (index == 0 && isFirstCardHidden) || faceDownCardIndices.contains(index)
            cardView.setFaceDown(shouldBeFaceDown, animated: false)
            cardContainer.bringSubviewToFront(cardView)
            
            let leading = cardView.leadingAnchor.constraint(
                equalTo: cardContainer.leadingAnchor,
                constant: accumulatedHorizontalOffset
            )
            
            let verticalAnchor: NSLayoutConstraint
            switch stackDirection {
            case .down:
                verticalAnchor = cardView.bottomAnchor.constraint(
                    equalTo: cardContainer.bottomAnchor,
                    constant: -(verticalOffset * scale) * CGFloat(index)
                )
            case .up:
                verticalAnchor = cardView.topAnchor.constraint(
                    equalTo: cardContainer.topAnchor,
                    constant: (verticalOffset * scale) * CGFloat(index)
                )
            }
            
            let height = cardView.heightAnchor.constraint(equalToConstant: cardHeight * scale)
            let width = cardView.widthAnchor.constraint(equalTo: cardView.heightAnchor, multiplier: cardAspectRatio)
            cardConstraints.append(contentsOf: [leading, verticalAnchor, height, width])
            
            let scale = scaleForCard(at: index, total: cards.count)
            let rotation = index < cardRotations.count ? cardRotations[index] : 0
            if !animated {
                cardView.transform = CGAffineTransform(scaleX: scale, y: scale).rotated(by: rotation)
            }
            
            let stepScale = pow(horizontalStepScale, Double((cards.count - 1) - index))
            accumulatedHorizontalOffset += (horizontalOffset * scale) * CGFloat(stepScale)
        }
        
        cardConstraints.forEach { $0.isActive = true }
        
        // When showing placeholders (no cards), size container for 2 cards
        let count = cards.isEmpty ? 2 : max(cards.count, 1)
        containerHeightConstraint.constant = cardHeight * scale + abs(verticalOffset * scale) * CGFloat(count - 1)
        containerWidthConstraint.constant = cardHeight * cardAspectRatio * scale + totalHorizontalOffset(for: count, stepScale: horizontalStepScale)
        
        // Calculate totals using only visible cards (exclude face-down cards except dealer's hole card)
        // For dealer's hole card, we still want to show totals based on visible card only
        // For player's double down card, exclude it from totals until revealed
        let visibleCards: [Card]
        if hidesFirstCard && isFirstCardHidden {
            // Dealer's hole card scenario: exclude first card from totals
            visibleCards = Array(cards.dropFirst())
        } else {
            // Player scenario: exclude any face-down cards (double down cards)
            visibleCards = cards.enumerated().compactMap { index, card in
                faceDownCardIndices.contains(index) ? nil : card
            }
        }
        
        let totals = calculateBlackjackTotals(for: visibleCards)
        totalLabel.text = "\(totals.primary)"
        
        // Hide label stack entirely when first card is hidden (not just alpha) to keep cards centered
        let shouldHideLabels = cards.isEmpty || (hidesFirstCard && isFirstCardHidden)
        
        if shouldHideLabels {
            labelStackView.isHidden = true
            totalLabel.alpha = 0
            alternativeTotalLabel.alpha = 0
            alternativeTotalLabel.isHidden = true // Explicitly hide alternative label when labels are hidden
        } else {
            labelStackView.isHidden = false
            totalLabel.alpha = 1

            // Only show alternative total if we have visible cards, an alternative exists, and totals aren't explicitly hidden
            if let alternative = totals.alternative, !visibleCards.isEmpty, !totalLabel.isHidden {
                alternativeTotalLabel.text = "or \(alternative)"
                alternativeTotalLabel.isHidden = false
                alternativeTotalLabel.alpha = 1
            } else {
                alternativeTotalLabel.isHidden = true
                alternativeTotalLabel.alpha = 0
            }
        }
        
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
                self.layoutIfNeeded()
                for (index, cardView) in self.cardViews.enumerated() {
                    let scale = self.scaleForCard(at: index, total: self.cards.count)
                    let rotation = index < self.cardRotations.count ? self.cardRotations[index] : 0
                    cardView.transform = CGAffineTransform(scaleX: scale, y: scale).rotated(by: rotation)
                }
            })
        } else {
            layoutIfNeeded()
        }
    }
    
    private func cardValue(for rank: PlayingCardView.Rank) -> Int {
        switch rank {
        case .ace:
            return 11
        case .king, .queen, .jack, .ten:
            return 10
        case .nine:
            return 9
        case .eight:
            return 8
        case .seven:
            return 7
        case .six:
            return 6
        case .five:
            return 5
        case .four:
            return 4
        case .three:
            return 3
        case .two:
            return 2
        }
    }
    
    private struct BlackjackTotals {
        let primary: Int
        let alternative: Int?
    }
    
    private func calculateBlackjackTotals(for cards: [Card]) -> BlackjackTotals {
        // Count aces separately
        var aceCount = 0
        var nonAceTotal = 0
        
        for card in cards {
            if card.rank == .ace {
                aceCount += 1
            } else {
                nonAceTotal += cardValue(for: card.rank)
            }
        }
        
        // Start with all aces as 11
        var total = nonAceTotal + (aceCount * 11)
        
        // Convert aces to 1 if we're over 21
        var acesAsOne = 0
        while total > 21 && acesAsOne < aceCount {
            total -= 10 // Convert one ace from 11 to 1
            acesAsOne += 1
        }
        
        let primaryTotal = total
        
        // If we have an ace still counted as 11 (meaning total <= 21), show alternative
        let acesStillAsEleven = aceCount - acesAsOne
        let alternativeTotal: Int?
        
        if acesStillAsEleven > 0 && primaryTotal <= 21 {
            // Show alternative where one more ace is counted as 1
            alternativeTotal = primaryTotal - 10
        } else {
            alternativeTotal = nil
        }
        
        return BlackjackTotals(primary: primaryTotal, alternative: alternativeTotal)
    }
    
    private func scaleForCard(at index: Int, total: Int) -> CGFloat {
        return pow(0.95, Double((total - 1) - index))
    }
    
    private func cardSize() -> CGSize {
        return CGSize(width: cardHeight * cardAspectRatio * scale, height: cardHeight * scale)
    }
    
    private func totalHorizontalOffset(for count: Int, stepScale: Double) -> CGFloat {
        guard count > 1 else { return 0 }
        let ratio = stepScale
        let steps = count - 1
        let factor = (1 - pow(ratio, Double(steps))) / (1 - ratio)
        return (horizontalOffset * scale) * CGFloat(factor)
    }
    
    private func cardCenter(at index: Int, total: Int) -> CGPoint {
        let containerSize = CGSize(
            width: containerWidthConstraint.constant,
            height: containerHeightConstraint.constant
        )
        var accumulatedOffset: CGFloat = 0
        if index > 0 {
            for i in 0..<index {
                let stepScale = pow(horizontalStepScale, Double((total - 1) - i))
                accumulatedOffset += (horizontalOffset * scale) * CGFloat(stepScale)
            }
        }
        
        let cardWidth = cardHeight * cardAspectRatio * scale
        let centerX = accumulatedOffset + cardWidth / 2
        
        let centerY: CGFloat
        switch stackDirection {
        case .down:
            let bottomY = containerSize.height - (verticalOffset * scale) * CGFloat(index)
            centerY = bottomY - (cardHeight * scale) / 2
        case .up:
            let topY = (verticalOffset * scale) * CGFloat(index)
            centerY = topY + (cardHeight * scale) / 2
        }
        
        return CGPoint(x: centerX, y: centerY)
    }
    
    func playSpreadAnimation() {
        guard cards.count > 1 else { return } // Need at least 2 cards to spread

        let spreadDuration: TimeInterval = 0.2
        let returnDuration: TimeInterval = 0.2
        let extraSpacing: CGFloat = 30 * scale // Extra horizontal spacing per card

        // Animate spreading
        UIView.animate(withDuration: spreadDuration, delay: 0, options: .curveEaseOut) {
            for (index, cardView) in self.cardViews.enumerated() {
                let baseScale = self.scaleForCard(at: index, total: self.cards.count)
                let rotation = index < self.cardRotations.count ? self.cardRotations[index] : 0

                // Create base transform (scale + rotation)
                let baseTransform = CGAffineTransform(scaleX: baseScale, y: baseScale).rotated(by: rotation)

                // Add translation to spread cards apart (applied in screen space)
                let translation = CGFloat(index) * extraSpacing
                let spreadTransform = CGAffineTransform(translationX: translation, y: 0).concatenating(baseTransform)

                cardView.transform = spreadTransform
            }
        } completion: { _ in
            // Animate back to original positions
            UIView.animate(withDuration: returnDuration, delay: 0, options: .curveEaseInOut) {
                for (index, cardView) in self.cardViews.enumerated() {
                    let baseScale = self.scaleForCard(at: index, total: self.cards.count)
                    let rotation = index < self.cardRotations.count ? self.cardRotations[index] : 0
                    cardView.transform = CGAffineTransform(scaleX: baseScale, y: baseScale).rotated(by: rotation)
                }
            }
        }
    }

    // MARK: - Touch Handling

    private func setupGestures() {
        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchDragExit, .touchCancel])
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    @objc private func touchDown() {
        // Check if tapping is allowed
        guard canTap?() ?? false else { return }

        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        }
    }

    @objc private func touchUp() {
        // Always reset transform
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.transform = .identity
        }
    }

    @objc private func handleTap() {
        // Check if tapping is allowed before executing tap action
        guard canTap?() ?? false else { return }

        HapticsHelper.lightHaptic()
        onTap?()
    }

    // Only accept touches that are within the card container bounds
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let pointInContainer = cardContainer.convert(point, from: self)
        return cardContainer.bounds.contains(pointInContainer)
    }

    // Allow pan gestures from the scroll view to work even when touching this control
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // If it's a pan gesture (for scrolling), allow it
        if gestureRecognizer is UIPanGestureRecognizer {
            return true
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
