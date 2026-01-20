//
//  DeckView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

class DeckView: UIView {
    
    private let cardHeight: CGFloat = 60
    private let cardAspectRatio: CGFloat = 60.0 / 88.0
    private let cardStackOffset: CGFloat = 2.5
    private let maxVisibleCards = 3
    
    private var cardViews: [PlayingCardView] = []
    private var cardCount: Int = 52
    private let countLabel = UILabel()
    
    var deckCenter: CGPoint {
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        
        // Ensure the view can receive taps
        isUserInteractionEnabled = true
        
        // Setup count label
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 14, weight: .bold)
        countLabel.textColor = .white
        countLabel.textAlignment = .center
        countLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        countLabel.layer.cornerRadius = 4
        countLabel.layer.masksToBounds = true
        countLabel.isHidden = true
        countLabel.isUserInteractionEnabled = false // Don't block taps
        addSubview(countLabel)
        
        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: topAnchor, constant: -8),
            countLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            countLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Create a visual representation of the deck
        updateDeckVisual()
    }
    
    func setCardCount(_ count: Int, animated: Bool = false) {
        cardCount = max(0, count)
        // Update count label immediately so it shows the correct count right away
        updateCountLabel()
        if animated && count == 52 {
            // Shuffle animation when resetting to full deck
            // Ensure deck visual is updated first (in case it was at 0)
            updateDeckVisual()
            animateShuffle()
        } else {
            updateDeckVisual()
        }
    }
    
    func drawCard() {
        guard cardCount > 0 else { return }
        cardCount -= 1
        updateDeckVisual()
        updateCountLabel()
    }
    
    func setCountLabelVisible(_ visible: Bool) {
        countLabel.isHidden = !visible
    }
    
    private func updateCountLabel() {
        countLabel.text = "\(cardCount)"
    }
    
    private func animateShuffle() {
        // First, show the deck
        updateDeckVisual()
        
        // Wait for the next run loop to ensure view is fully laid out and visible
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Ensure layout is finalized before calculating positions
            self.layoutIfNeeded()
            
            // Get the superview to add shuffle cards on top
            guard let containerView = self.superview else { return }
            
            // Force layout to ensure frame is correct
            containerView.layoutIfNeeded()
            
            // Calculate deck center - use the top card's center position for accuracy
            let deckCenterInContainer: CGPoint
            if let topCard = self.cardViews.first {
                let topCardCenterInContainer = containerView.convert(CGPoint(x: topCard.frame.midX, y: topCard.frame.midY), from: self)
                // Use the top card's center as the deck center
                deckCenterInContainer = topCardCenterInContainer
            } else {
                // Fallback to frame center if no cards
                deckCenterInContainer = CGPoint(x: self.frame.midX, y: self.frame.midY)
            }
            
            // Create temporary cards for shuffle animation
            var tempCards: [PlayingCardView] = []
            let shuffleCount = 8 // More cards for a more dramatic shuffle
            
            for i in 0..<shuffleCount {
                let cardView = PlayingCardView()
                cardView.translatesAutoresizingMaskIntoConstraints = true
                cardView.setFaceDown(true, animated: false)
                cardView.configure(rank: .ace, suit: .spades)
                
                // Position card in container view's coordinate system
                let cardWidth = self.cardHeight * self.cardAspectRatio
                let cardFrame = CGRect(x: deckCenterInContainer.x - (cardWidth / 2),
                                       y: deckCenterInContainer.y - (self.cardHeight / 2),
                                       width: cardWidth,
                                       height: self.cardHeight)
                cardView.frame = cardFrame
                
                // Apply shadow
                cardView.layer.masksToBounds = false
                cardView.layer.shadowColor = UIColor.black.cgColor
                cardView.layer.shadowOpacity = 0.25
                cardView.layer.shadowRadius = 4
                cardView.layer.shadowOffset = CGSize(width: 0, height: 2)
                
                // Add to container view (superview) so it appears on top of deck
                containerView.addSubview(cardView)
                containerView.bringSubviewToFront(cardView)
                tempCards.append(cardView)
                
                // Animate each card with a different pattern - use circular pattern
                let angle = CGFloat(i) * (CGFloat.pi * 2.0 / CGFloat(shuffleCount))
                let distance: CGFloat = 40 // Increased distance
                let delay = Double(i) * 0.08 // Slightly longer stagger
                
                // Hide initially
                cardView.alpha = 0
                cardView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                
                // Longer, more elaborate animation
                UIView.animateKeyframes(withDuration: 1.4, delay: delay, options: [.calculationModeCubic], animations: {
                    // Keyframe 1: Appear and move out (0-30%)
                    UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.3) {
                        cardView.alpha = 1
                        cardView.transform = CGAffineTransform(translationX: cos(angle) * distance,
                                                              y: sin(angle) * distance)
                            .scaledBy(x: 1.1, y: 1.1)
                            .rotated(by: angle * 0.5)
                    }
                    
                    // Keyframe 2: Circle around (30-50%)
                    UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.2) {
                        let circleAngle = angle + CGFloat.pi * 0.3
                        cardView.transform = CGAffineTransform(translationX: cos(circleAngle) * distance * 1.1,
                                                              y: sin(circleAngle) * distance * 1.1)
                            .scaledBy(x: 1.05, y: 1.05)
                            .rotated(by: circleAngle * 0.5)
                    }
                    
                    // Keyframe 3: Move back (50-75%)
                    UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.25) {
                        cardView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                    }
                    
                    // Keyframe 4: Fade out (75-100%)
                    UIView.addKeyframe(withRelativeStartTime: 0.75, relativeDuration: 0.25) {
                        cardView.alpha = 0
                        cardView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                    }
                }, completion: { _ in
                    cardView.removeFromSuperview()
                })
            }
        }
    }
    
    private func updateDeckVisual() {
        // Remove existing card views
        cardViews.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()
        
        guard cardCount > 0 else { return }
        
        // Create stacked card views (face down)
        let visibleCount = min(cardCount, maxVisibleCards)
        
        for i in 0..<visibleCount {
            let cardView = PlayingCardView()
            cardView.translatesAutoresizingMaskIntoConstraints = false
            cardView.setFaceDown(true, animated: false)
            cardView.configure(rank: .ace, suit: .spades) // Dummy values, won't be visible
            cardView.isUserInteractionEnabled = false // Don't block taps on deck
            addSubview(cardView)
            cardViews.append(cardView)
            
            // Apply shadow
            cardView.layer.masksToBounds = false
            cardView.layer.shadowColor = UIColor.black.cgColor
            cardView.layer.shadowOpacity = 0.25
            cardView.layer.shadowRadius = 4
            cardView.layer.shadowOffset = CGSize(width: 0, height: 2)
            
            // Position cards with slight vertical offset to show stack
            let offset = CGFloat(i) * cardStackOffset
            let scale = 1.0 - (CGFloat(i) * 0.02) // Slight scale decrease for depth
            
            NSLayoutConstraint.activate([
                cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
                cardView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -offset),
                cardView.heightAnchor.constraint(equalToConstant: cardHeight),
                cardView.widthAnchor.constraint(equalTo: cardView.heightAnchor, multiplier: cardAspectRatio)
            ])
            
            cardView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }
    
    override var intrinsicContentSize: CGSize {
        let cardWidth = cardHeight * cardAspectRatio
        return CGSize(width: cardWidth, 
                     height: cardHeight + cardStackOffset * CGFloat(maxVisibleCards - 1))
    }
}
