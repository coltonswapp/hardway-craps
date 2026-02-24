//
//  CompactPlayerHandView.swift
//  hardway-craps
//
//  Experimental compact hand layout: smaller cards, left-aligned total, compact bet control.
//

import UIKit

final class CompactPlayerHandView: UIView {

    private static let compactScale: CGFloat = 0.55
    private static let compactHandHeight: CGFloat = 140
    private static let compactHandWidth: CGFloat = 160
    private static let betControlWidth: CGFloat = 110
    private static let betControlHeight: CGFloat = 40

    /// Debug: background colors for layout inspection. Set to non-nil to show.
    private static let debugTotalBackground: UIColor? = nil
    private static let debugCardContainerBackground: UIColor? = nil
    private static let debugContentStackBackground: UIColor? = nil
    private static let debugBetControlBackground: UIColor? = nil

    let betControl: PlainControl
    let handView: BlackjackHandView

    private let totalLabel = UILabel()
    private var contentStackView: UIStackView?

    var onTap: (() -> Void)? {
        didSet { handView.onTap = onTap }
    }

    var canTap: (() -> Bool)? {
        didSet { handView.canTap = canTap }
    }

    var currentCards: [BlackjackHandView.Card] {
        return handView.currentCards
    }

    var cardViewsForAnimation: [PlayingCardView] {
        return handView.cardViewsForAnimation
    }

    func getCardViewFrame(at index: Int, in targetView: UIView) -> CGRect? {
        return handView.getCardViewFrame(at: index, in: targetView)
    }

    /// Suit icon scale for cards (1.0 = full size). Smaller values give a more compact look.
    private static let compactSuitScale: CGFloat = 0.6
    /// Less padding around value and suit on the card face (default elsewhere is 8).
    private static let compactCardPadding: CGFloat = 4

    /// Scale down cards when many are dealt so 5–7+ fit in the compact width. 1.0 for ≤4 cards, then step down.
    private static func countBasedScaleFactor(for cardCount: Int) -> CGFloat {
        switch cardCount {
        case 0...4: return 1.0
        case 5: return 0.88
        case 6: return 0.78
        case 7: return 0.70
        default: return max(0.6, 0.70 - CGFloat(cardCount - 7) * 0.05)
        }
    }

    init(mpChipStyle: MPSmallBetChipStyle? = nil) {
        betControl = PlainControl(title: "Bet", mpChipStyle: mpChipStyle)
        handView = BlackjackHandView(
            stackDirection: .down,
            hidesFirstCard: false,
            scale: Self.compactScale,
            suitScale: Self.compactSuitScale,
            cardPadding: Self.compactCardPadding,
            valueScale: 0.75
        )
        super.init(frame: .zero)
        handView.countBasedScaleFactor = { Self.countBasedScaleFactor(for: $0) }
        handView.showsEmptyPlaceholders = true
        setupView()

        // Configure bet control: centered title that shifts left when bet is placed
        betControl.title = "Bet"
        betControl.shouldAnimateTitleShift = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.compactHandWidth, height: Self.compactHandHeight)
    }

    private func setupView() {
        handView.translatesAutoresizingMaskIntoConstraints = false
        handView.isUserInteractionEnabled = true
        handView.setTotalsHidden(true)
        addSubview(handView)

        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        totalLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        totalLabel.textColor = .white
        totalLabel.textAlignment = .left
        totalLabel.text = "0"
        if let bg = Self.debugTotalBackground { totalLabel.backgroundColor = bg }
        totalLabel.layer.cornerRadius = 4
        totalLabel.clipsToBounds = true
        addSubview(totalLabel)

        betControl.translatesAutoresizingMaskIntoConstraints = false
        if let bg = Self.debugBetControlBackground { betControl.backgroundColor = bg }
        betControl.layer.cornerRadius = 18
        addSubview(betControl)

        if let bg = Self.debugCardContainerBackground { handView.cardContainer.backgroundColor = bg }
        handView.cardContainer.layer.cornerRadius = 6

        contentStackView = handView.subviews.compactMap { $0 as? UIStackView }.first
        guard let contentStackView = contentStackView else { return }
        if let bg = Self.debugContentStackBackground { contentStackView.backgroundColor = bg }
        contentStackView.layer.cornerRadius = 6

        for constraint in handView.constraints {
            if constraint.firstItem === contentStackView || constraint.secondItem === contentStackView {
                constraint.isActive = false
            }
        }

        NSLayoutConstraint.activate([
            handView.topAnchor.constraint(equalTo: topAnchor),
            handView.leadingAnchor.constraint(equalTo: leadingAnchor),
            handView.trailingAnchor.constraint(equalTo: trailingAnchor),
            handView.bottomAnchor.constraint(equalTo: bottomAnchor),

            totalLabel.trailingAnchor.constraint(equalTo: handView.cardContainer.leadingAnchor, constant: -16),
            totalLabel.centerYAnchor.constraint(equalTo: handView.cardContainer.centerYAnchor),
            totalLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),

            betControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            betControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            betControl.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            betControl.heightAnchor.constraint(equalToConstant: Self.betControlHeight),

            contentStackView.bottomAnchor.constraint(equalTo: betControl.topAnchor, constant: -8),
            contentStackView.topAnchor.constraint(equalTo: handView.topAnchor, constant: 8),
            contentStackView.leadingAnchor.constraint(greaterThanOrEqualTo: handView.leadingAnchor, constant: 8),
            contentStackView.trailingAnchor.constraint(lessThanOrEqualTo: handView.trailingAnchor, constant: -8),
            handView.cardContainer.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
        updateTotalLabel()
    }

    private func updateTotalLabel() {
        let visible = handView.visibleCardsForTotal
        let cards = handView.currentCards
        // Show label when we have 2+ cards in hand, or when placeholders (empty + showsEmptyPlaceholders)
        let shouldShow = cards.count >= 2 || (cards.isEmpty && handView.showsEmptyPlaceholders)
        totalLabel.isHidden = !shouldShow
        guard shouldShow else { return }
        
        if visible.isEmpty {
            totalLabel.text = "0"
        } else {
            let totals = Self.calculateBlackjackTotals(for: visible)
            totalLabel.text = "\(totals.primary)"
        }
    }

    private static func calculateBlackjackTotals(for cards: [BlackjackHandView.Card]) -> (primary: Int, alternative: Int?) {
        var aceCount = 0
        var nonAceTotal = 0
        for card in cards {
            if card.rank == .ace {
                aceCount += 1
            } else {
                nonAceTotal += cardValue(for: card.rank)
            }
        }
        var total = nonAceTotal + (aceCount * 11)
        var acesAsOne = 0
        while total > 21 && acesAsOne < aceCount {
            total -= 10
            acesAsOne += 1
        }
        let primary = total
        let acesStillAsEleven = aceCount - acesAsOne
        let alternative: Int? = (acesStillAsEleven > 0 && primary <= 21) ? primary - 10 : nil
        return (primary, alternative)
    }

    private static func cardValue(for rank: PlayingCardView.Rank) -> Int {
        switch rank {
        case .ace: return 11
        case .king, .queen, .jack: return 10
        case .ten: return 10
        case .nine: return 9
        case .eight: return 8
        case .seven: return 7
        case .six: return 6
        case .five: return 5
        case .four: return 4
        case .three: return 3
        case .two: return 2
        }
    }

    // MARK: - Passthrough (update total after each card change)

    func configure(firstCard: BlackjackHandView.Card, secondCard: BlackjackHandView.Card) {
        handView.configure(firstCard: firstCard, secondCard: secondCard)
        updateTotalLabel()
    }

    func clearCards() {
        handView.clearCards()
        updateTotalLabel()
        // Force layout after clearing to ensure placeholder cards get proper frames
        DispatchQueue.main.async {
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.handView.setNeedsLayout()
            self.handView.layoutIfNeeded()
        }
    }

    func discardCards(to endPoint: CGPoint, in containerView: UIView, completion: @escaping () -> Void) {
        handView.discardCards(to: endPoint, in: containerView) { [weak self] in
            self?.updateTotalLabel()
            completion()
        }
    }

    func addCard(_ card: BlackjackHandView.Card) {
        handView.addCard(card)
        updateTotalLabel()
    }

    func dealCard(_ card: BlackjackHandView.Card, from startPoint: CGPoint, in containerView: UIView) {
        handView.dealCard(card, from: startPoint, in: containerView)
        updateTotalLabel()
    }

    func dealCardFaceDown(_ card: BlackjackHandView.Card, from startPoint: CGPoint, in containerView: UIView) {
        handView.dealCardFaceDown(card, from: startPoint, in: containerView)
        updateTotalLabel()
    }

    @discardableResult
    func revealCard(at index: Int, animated: Bool = true) -> Bool {
        let result = handView.revealCard(at: index, animated: animated)
        if result { updateTotalLabel() }
        return result
    }

    func setTotalsHidden(_ hidden: Bool) {
        handView.setTotalsHidden(hidden)
    }

    func setCardsWithoutAnimation(_ cards: [BlackjackHandView.Card]) {
        handView.setCardsWithoutAnimation(cards)
        updateTotalLabel()
    }
    
    /// Two face-down placeholder cards for empty seat (same as BlackjackHandPlayground style).
    func setPlaceholderCards() {
        handView.setPlaceholderCards()
        updateTotalLabel()
    }
}
