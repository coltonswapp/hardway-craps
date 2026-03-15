//
//  BaccaratHandView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 3/7/26.
//

import UIKit

final class BaccaratHandView: UIView {

  enum HandState {
    case stacked   // Overlapped, compact (dealt from deck)
    case spread    // Separated, slightly larger, tappable cards
  }

  // MARK: - Public

  private(set) var handState: HandState = .stacked

  var currentCards: [BlackjackHandView.Card] {
    return cards
  }

  /// Called each time a card is revealed so the controller can react.
  var onCardRevealed: ((Int) -> Void)?

  /// Total value of revealed cards (baccarat mod-10 rule).
  var revealedTotal: Int {
    let revealed = cards.enumerated().compactMap { index, card in
      revealedIndices.contains(index) ? card : nil
    }
    return baccaratTotal(revealed)
  }

  var allCardsRevealed: Bool {
    return !cards.isEmpty && revealedIndices.count == cards.count
  }

  // MARK: - Layout constants

  private static let compactScale: CGFloat = 0.55
  private static let compactSuitScale: CGFloat = 0.6
  private static let compactCardPadding: CGFloat = 4
  private static let compactValueScale: CGFloat = 0.75

  private static let spreadScale: CGFloat = 0.70
  private static let spreadSuitScale: CGFloat = 0.75
  private static let spreadCardPadding: CGFloat = 6
  private static let spreadValueScale: CGFloat = 0.85

  private let baseCardHeight: CGFloat = 120
  private let cardAspectRatio: CGFloat = 60.0 / 88.0

  // Stacked layout (overlapped like BlackjackHandView)
  private let stackedHorizontalOffset: CGFloat = 45
  private let stackedVerticalOffset: CGFloat = 7.5
  private let stackedHorizontalStepScale: Double = 0.9

  // Spread layout
  private let spreadCardSpacing: CGFloat = 12

  // MARK: - Subviews

  private let totalLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 18, weight: .semibold)
    label.textColor = .white
    label.textAlignment = .center
    label.text = "0"
    label.isHidden = true
    return label
  }()

  let cardContainer = UIView()
  private var cardViews: [PlayingCardView] = []
  private var cards: [BlackjackHandView.Card] = []
  private var revealedIndices: Set<Int> = []
  private var cardRotations: [CGFloat] = []

  private var containerWidthConstraint: NSLayoutConstraint!
  private var containerHeightConstraint: NSLayoutConstraint!
  private var cardConstraints: [NSLayoutConstraint] = []
  private var trailingPaddingConstraint: NSLayoutConstraint!

  // MARK: - Initialization

  init() {
    super.init(frame: .zero)
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Setup

  private func setupView() {
    translatesAutoresizingMaskIntoConstraints = false

    addSubview(totalLabel)
    addSubview(cardContainer)

    cardContainer.translatesAutoresizingMaskIntoConstraints = false
    cardContainer.clipsToBounds = false

    let initialHeight = baseCardHeight * Self.compactScale
    let initialWidth = initialHeight * cardAspectRatio

    containerHeightConstraint = cardContainer.heightAnchor.constraint(equalToConstant: initialHeight)
    containerWidthConstraint = cardContainer.widthAnchor.constraint(equalToConstant: initialWidth)
    // Extra trailing space so that view.centerX aligns with cardContainer.centerX (cards visually centered)
    let totalLabelWidth: CGFloat = 40
    let gap: CGFloat = 12
    trailingPaddingConstraint = trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: totalLabelWidth + gap)

    NSLayoutConstraint.activate([
      totalLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      totalLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      totalLabel.widthAnchor.constraint(equalToConstant: totalLabelWidth),

      totalLabel.trailingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: -gap),
      cardContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
      cardContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
      containerHeightConstraint,
      containerWidthConstraint,

      trailingPaddingConstraint,
      heightAnchor.constraint(equalToConstant: initialHeight),
    ])
  }

  // MARK: - Card Management

  func clearCards() {
    cards.removeAll()
    revealedIndices.removeAll()
    cardRotations.removeAll()
    cardViews.forEach { $0.removeFromSuperview() }
    cardViews.removeAll()
    handState = .stacked
    totalLabel.text = "0"
    totalLabel.isHidden = true
    totalLabel.alpha = 1
    updateContainerSize()
  }

  func dealCard(_ card: BlackjackHandView.Card, from startPoint: CGPoint, in containerView: UIView) {
    cards.append(card)
    cardRotations.append(generateRandomRotation())

    // Resolve current layout before changing constraints (same pattern as BlackjackHandView)
    layoutIfNeeded()

    // Reuse existing card views, only create what's needed (don't rebuild)
    while cardViews.count < cards.count {
      let cv = PlayingCardView()
      cv.translatesAutoresizingMaskIntoConstraints = false
      cv.suitScale = Self.compactSuitScale
      cv.valueScale = Self.compactValueScale
      cv.padding = Self.compactCardPadding
      applyCardShadow(to: cv)
      cardViews.append(cv)
      cardContainer.addSubview(cv)
    }

    // Configure the new card view
    let newCardView = cardViews.last!
    if card.isCutCard {
      newCardView.configureCutCard()
    } else {
      newCardView.configure(rank: card.rank, suit: card.suit)
    }
    newCardView.setFaceDown(true, animated: false)
    newCardView.alpha = 0

    // Update constraints for new layout
    layoutStacked(animated: false)
    layoutIfNeeded()

    // Compute target from the laid-out new card view
    let cardFrame = newCardView.superview?.convert(newCardView.frame, to: containerView) ?? .zero
    let targetCenter = CGPoint(x: cardFrame.midX, y: cardFrame.midY)

    let cs = cardSize(for: Self.compactScale)
    let tempCard = makeTempCard(for: card, scale: Self.compactScale, suitScale: Self.compactSuitScale, valueScale: Self.compactValueScale, padding: Self.compactCardPadding)
    tempCard.setFaceDown(true, animated: false)
    tempCard.bounds = CGRect(origin: .zero, size: cs)
    tempCard.center = startPoint

    let deckScale: CGFloat = 0.5
    let cardIndex = cards.count - 1
    let targetScale = stackedScaleForCard(at: cardIndex, total: cards.count)
    let targetRotation = cardIndex < cardRotations.count ? cardRotations[cardIndex] : 0
    tempCard.transform = CGAffineTransform(scaleX: deckScale, y: deckScale)
    containerView.addSubview(tempCard)

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
    }

    HapticsHelper.superLightHaptic()
    animator.startAnimation()
  }

  /// Deal a card into an already-spread hand (e.g. baccarat third card).
  /// Existing cards slide over to make room, then the new card animates in from the deck.
  func dealCardToSpread(_ card: BlackjackHandView.Card, from startPoint: CGPoint, in containerView: UIView) {
    cards.append(card)
    cardRotations.append(0) // No rotation in spread state

    // Create the new card view (hidden initially — placed at final position for constraint calculation)
    let cardView = PlayingCardView()
    cardView.translatesAutoresizingMaskIntoConstraints = false
    cardView.suitScale = Self.spreadSuitScale
    cardView.valueScale = Self.spreadValueScale
    cardView.padding = Self.spreadCardPadding
    cardView.configure(rank: card.rank, suit: card.suit)
    cardView.setFaceDown(true, animated: false)
    applyCardShadow(to: cardView)
    cardViews.append(cardView)
    cardContainer.addSubview(cardView)
    cardView.alpha = 0

    // Update constraints for new spread layout (all cards including new one)
    cardConstraints.forEach { $0.isActive = false }
    cardConstraints.removeAll()

    let cs = cardSize(for: Self.spreadScale)
    let totalWidth = CGFloat(cards.count) * cs.width + CGFloat(max(0, cards.count - 1)) * spreadCardSpacing
    containerWidthConstraint.constant = totalWidth
    containerHeightConstraint.constant = cs.height

    var xOffset: CGFloat = 0
    for (_, cv) in cardViews.enumerated() {
      let leading = cv.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: xOffset)
      let centerY = cv.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor)
      let w = cv.widthAnchor.constraint(equalToConstant: cs.width)
      let h = cv.heightAnchor.constraint(equalToConstant: cs.height)
      cardConstraints.append(contentsOf: [leading, centerY, w, h])
      xOffset += cs.width + spreadCardSpacing
    }
    cardConstraints.forEach { $0.isActive = true }

    // Step 1: Animate existing cards sliding over to make room
    UIView.animate(
      withDuration: 0.3,
      delay: 0,
      usingSpringWithDamping: 0.85,
      initialSpringVelocity: 0.3,
      options: .curveEaseOut
    ) {
      self.superview?.layoutIfNeeded()
    } completion: { [weak self] _ in
      guard let self = self else { return }

      // Step 2: After slide completes, get the target position and animate card from deck
      let cardFrame = cardView.superview?.convert(cardView.frame, to: containerView) ?? .zero
      let targetCenter = CGPoint(x: cardFrame.midX, y: cardFrame.midY)

      let tempCard = self.makeTempCard(for: card, scale: Self.spreadScale, suitScale: Self.spreadSuitScale, valueScale: Self.spreadValueScale, padding: Self.spreadCardPadding)
      tempCard.setFaceDown(true, animated: false)
      tempCard.bounds = CGRect(origin: .zero, size: cs)
      tempCard.center = startPoint

      let deckScale: CGFloat = 0.5
      tempCard.transform = CGAffineTransform(scaleX: deckScale, y: deckScale)
      containerView.addSubview(tempCard)

      let animator = UIViewPropertyAnimator(
        duration: 0.25,
        controlPoint1: CGPoint(x: 0.45, y: 0),
        controlPoint2: CGPoint(x: 0.07, y: 1.1)
      ) {
        tempCard.center = targetCenter
        tempCard.transform = .identity
      }

      animator.addCompletion { _ in
        tempCard.removeFromSuperview()
        cardView.alpha = 1
      }

      // Re-install tap gestures to include the new card
      self.installCardTapGestures()

      HapticsHelper.superLightHaptic()
      animator.startAnimation()
    }
  }

  // MARK: - State Transitions

  /// Animate from stacked (overlapped) to spread (separated, slightly larger).
  /// Set `installTapGestures` to false to defer tap gesture installation (caller must call `installCardTapGesturesPublic()` later).
  func animateToSpread(installTapGestures: Bool = true, completion: (() -> Void)? = nil) {
    guard handState == .stacked, !cards.isEmpty else {
      completion?()
      return
    }
    handState = .spread

    updateCardAppearance(scale: Self.spreadScale, suitScale: Self.spreadSuitScale, valueScale: Self.spreadValueScale, padding: Self.spreadCardPadding)

    cardConstraints.forEach { $0.isActive = false }
    cardConstraints.removeAll()

    let cs = cardSize(for: Self.spreadScale)
    let totalWidth = CGFloat(cards.count) * cs.width + CGFloat(max(0, cards.count - 1)) * spreadCardSpacing
    containerWidthConstraint.constant = totalWidth
    containerHeightConstraint.constant = cs.height

    var xOffset: CGFloat = 0
    for (index, cardView) in cardViews.enumerated() {
      let leading = cardView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: xOffset)
      let centerY = cardView.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor)
      let w = cardView.widthAnchor.constraint(equalToConstant: cs.width)
      let h = cardView.heightAnchor.constraint(equalToConstant: cs.height)
      cardConstraints.append(contentsOf: [leading, centerY, w, h])
      xOffset += cs.width + spreadCardSpacing
    }
    cardConstraints.forEach { $0.isActive = true }

    UIView.animate(
      withDuration: 0.4,
      delay: 0,
      usingSpringWithDamping: 0.8,
      initialSpringVelocity: 0.5,
      options: .curveEaseOut
    ) {
      for cardView in self.cardViews {
        cardView.transform = .identity
      }
      self.superview?.layoutIfNeeded()
    } completion: { _ in
      if installTapGestures {
        self.installCardTapGestures()
      }
      completion?()
    }
  }

  /// Animate from spread back to stacked (overlapped).
  func animateToStacked(completion: (() -> Void)? = nil) {
    guard handState == .spread else {
      completion?()
      return
    }
    handState = .stacked
    removeCardTapGestures()

    updateCardAppearance(scale: Self.compactScale, suitScale: Self.compactSuitScale, valueScale: Self.compactValueScale, padding: Self.compactCardPadding)
    layoutStacked(animated: true, completion: completion)
  }

  // MARK: - Card Reveal

  func revealCard(at index: Int) {
    guard index >= 0 && index < cardViews.count else { return }
    guard !revealedIndices.contains(index) else { return }
    revealedIndices.insert(index)
    cardViews[index].setFaceDown(false, animated: true)
    HapticsHelper.lightHaptic()
    updateTotal()
    totalLabel.isHidden = totalsHidden
    onCardRevealed?(index)
  }

  func revealAllCards() {
    for index in 0..<cardViews.count {
      if !revealedIndices.contains(index) {
        revealedIndices.insert(index)
        cardViews[index].setFaceDown(false, animated: true)
      }
    }
    updateTotal()
    totalLabel.isHidden = totalsHidden
  }

  // MARK: - Private: Card View Construction

  private func rebuildCardViews() {
    cardViews.forEach { $0.removeFromSuperview() }
    cardViews.removeAll()

    for (index, card) in cards.enumerated() {
      let cardView = PlayingCardView()
      cardView.translatesAutoresizingMaskIntoConstraints = false
      cardView.suitScale = Self.compactSuitScale
      cardView.valueScale = Self.compactValueScale
      cardView.padding = Self.compactCardPadding
      if card.isCutCard {
        cardView.configureCutCard()
      } else {
        cardView.configure(rank: card.rank, suit: card.suit)
      }
      let isFaceDown = !revealedIndices.contains(index)
      cardView.setFaceDown(isFaceDown, animated: false)
      applyCardShadow(to: cardView)
      cardViews.append(cardView)
      cardContainer.addSubview(cardView)
    }
  }

  private func makeTempCard(for card: BlackjackHandView.Card, scale: CGFloat, suitScale: CGFloat, valueScale: CGFloat, padding: CGFloat) -> PlayingCardView {
    let tempCard = PlayingCardView()
    tempCard.suitScale = suitScale
    tempCard.valueScale = valueScale
    tempCard.padding = padding
    if card.isCutCard {
      tempCard.configureCutCard()
    } else {
      tempCard.configure(rank: card.rank, suit: card.suit)
    }
    applyCardShadow(to: tempCard)
    return tempCard
  }

  private func updateCardAppearance(scale: CGFloat, suitScale: CGFloat, valueScale: CGFloat, padding: CGFloat) {
    for cardView in cardViews {
      cardView.suitScale = suitScale
      cardView.valueScale = valueScale
      cardView.padding = padding
    }
  }

  // MARK: - Private: Stacked Layout

  private func layoutStacked(animated: Bool, completion: (() -> Void)? = nil) {
    cardConstraints.forEach { $0.isActive = false }
    cardConstraints.removeAll()

    let scale = Self.compactScale
    let cs = cardSize(for: scale)
    var accumulatedHOffset: CGFloat = 0

    for (index, cardView) in cardViews.enumerated() {
      cardContainer.bringSubviewToFront(cardView)

      let leading = cardView.leadingAnchor.constraint(
        equalTo: cardContainer.leadingAnchor,
        constant: accumulatedHOffset
      )
      let bottom = cardView.bottomAnchor.constraint(
        equalTo: cardContainer.bottomAnchor,
        constant: -(stackedVerticalOffset * scale) * CGFloat(index)
      )
      let w = cardView.widthAnchor.constraint(equalToConstant: cs.width)
      let h = cardView.heightAnchor.constraint(equalToConstant: cs.height)
      cardConstraints.append(contentsOf: [leading, bottom, w, h])

      let stepScale = pow(stackedHorizontalStepScale, Double((cards.count - 1) - index))
      accumulatedHOffset += (stackedHorizontalOffset * scale) * CGFloat(stepScale)
    }
    cardConstraints.forEach { $0.isActive = true }

    updateContainerSize()

    if animated {
      UIView.animate(
        withDuration: 0.4,
        delay: 0,
        usingSpringWithDamping: 0.8,
        initialSpringVelocity: 0.5,
        options: .curveEaseOut
      ) {
        for (index, cardView) in self.cardViews.enumerated() {
          let s = self.stackedScaleForCard(at: index, total: self.cards.count)
          let r = index < self.cardRotations.count ? self.cardRotations[index] : 0
          cardView.transform = CGAffineTransform(scaleX: s, y: s).rotated(by: r)
        }
        self.superview?.layoutIfNeeded()
      } completion: { _ in
        completion?()
      }
    } else {
      for (index, cardView) in cardViews.enumerated() {
        let s = stackedScaleForCard(at: index, total: cards.count)
        let r = index < cardRotations.count ? cardRotations[index] : 0
        cardView.transform = CGAffineTransform(scaleX: s, y: s).rotated(by: r)
      }
      layoutIfNeeded()
      completion?()
    }
  }

  private func updateContainerSize() {
    let count = max(cards.count, 1)
    let scale = Self.compactScale
    let cs = cardSize(for: scale)

    let newHeight = cs.height + abs(stackedVerticalOffset * scale) * CGFloat(count - 1)
    let newWidth = cs.width + totalStackedHorizontalOffset(for: count)

    containerHeightConstraint.constant = newHeight
    containerWidthConstraint.constant = newWidth
  }

  private func totalStackedHorizontalOffset(for count: Int) -> CGFloat {
    guard count > 1 else { return 0 }
    let scale = Self.compactScale
    let ratio = stackedHorizontalStepScale
    let steps = count - 1
    let factor = (1 - pow(ratio, Double(steps))) / (1 - ratio)
    return (stackedHorizontalOffset * scale) * CGFloat(factor)
  }

  private func stackedScaleForCard(at index: Int, total: Int) -> CGFloat {
    return pow(0.95, Double((total - 1) - index))
  }

  // MARK: - Card Tap Gestures (spread state)

  /// Public entry point for installing tap gestures on spread cards.
  func installCardTapGesturesPublic() {
    installCardTapGestures()
  }

  private var cardTapGestures: [UITapGestureRecognizer] = []

  private func installCardTapGestures() {
    removeCardTapGestures()
    for (index, cardView) in cardViews.enumerated() {
      cardView.isUserInteractionEnabled = true
      let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:)))
      tap.cancelsTouchesInView = true
      cardView.tag = index
      cardView.addGestureRecognizer(tap)
      cardTapGestures.append(tap)
    }
  }

  private func removeCardTapGestures() {
    for (gesture, cardView) in zip(cardTapGestures, cardViews) {
      cardView.removeGestureRecognizer(gesture)
      cardView.isUserInteractionEnabled = false
    }
    cardTapGestures.removeAll()
  }

  @objc private func cardTapped(_ gesture: UITapGestureRecognizer) {
    guard let cardView = gesture.view, handState == .spread else { return }
    revealCard(at: cardView.tag)
  }

  // MARK: - Private: Helpers

  private func cardSize(for scale: CGFloat) -> CGSize {
    let h = baseCardHeight * scale
    return CGSize(width: h * cardAspectRatio, height: h)
  }

  private func generateRandomRotation() -> CGFloat {
    let degrees = CGFloat.random(in: -3...3)
    return degrees * .pi / 180
  }

  private func applyCardShadow(to card: PlayingCardView) {
    card.layer.masksToBounds = false
    card.layer.shadowColor = UIColor.black.cgColor
    card.layer.shadowOpacity = 0.18
    card.layer.shadowRadius = 6
    card.layer.shadowOffset = CGSize(width: 0, height: 3)
  }

  // MARK: - Discard Animation

  func discardCards(to endPoint: CGPoint, in containerView: UIView, completion: @escaping () -> Void) {
    guard !cards.isEmpty else {
      completion()
      return
    }

    layoutIfNeeded()

    // Fade out total label
    UIView.animate(withDuration: 0.3) {
      self.totalLabel.alpha = 0
    }

    let cardsToDiscard = Array(cardViews)
    var completedAnimations = 0
    let totalCards = cardsToDiscard.count

    for (index, cardView) in cardsToDiscard.enumerated() {
      let card = cards[index]

      // Get the card's current position in the container view
      let cardFrameInContainer = cardView.superview?.convert(cardView.frame, to: containerView) ?? .zero
      let startCenter = CGPoint(x: cardFrameInContainer.midX, y: cardFrameInContainer.midY)

      // Create temporary card for animation
      let scale = handState == .spread ? Self.spreadScale : Self.compactScale
      let suitScale = handState == .spread ? Self.spreadSuitScale : Self.compactSuitScale
      let valueScale = handState == .spread ? Self.spreadValueScale : Self.compactValueScale
      let padding = handState == .spread ? Self.spreadCardPadding : Self.compactCardPadding

      let tempCard = makeTempCard(for: card, scale: scale, suitScale: suitScale, valueScale: valueScale, padding: padding)
      let isFaceDown = !revealedIndices.contains(index)
      tempCard.setFaceDown(isFaceDown, animated: false)

      let cs = cardSize(for: scale)
      tempCard.bounds = CGRect(origin: .zero, size: cs)
      tempCard.center = startCenter
      tempCard.transform = cardView.transform

      containerView.addSubview(tempCard)
      cardView.alpha = 0

      let randomDelay = Double.random(in: 0...0.15)

      UIView.animate(
        withDuration: 0.5, delay: randomDelay, options: .curveEaseIn,
        animations: {
          tempCard.center = endPoint
          tempCard.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        },
        completion: { _ in
          UIView.animate(withDuration: 0.2, animations: {
            tempCard.alpha = 0
          }, completion: { _ in
            tempCard.removeFromSuperview()
            completedAnimations += 1
            if completedAnimations >= totalCards {
              self.clearCards()
              completion()
            }
          })
        })
    }
  }

  // MARK: - Settings

  private var totalsHidden: Bool = false

  func setTotalsHidden(_ hidden: Bool) {
    totalsHidden = hidden
    if hidden {
      totalLabel.isHidden = true
    }
    // When not hidden, totalLabel visibility is managed by card reveal logic
  }

  // MARK: - Baccarat Calculation

  private func updateTotal() {
    let revealed = cards.enumerated().compactMap { index, card in
      revealedIndices.contains(index) ? card : nil
    }
    let total = baccaratTotal(revealed)
    totalLabel.text = "\(total)"

    totalLabel.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
    UIView.animate(
      withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5
    ) {
      self.totalLabel.transform = .identity
    }
  }

  private func baccaratTotal(_ cards: [BlackjackHandView.Card]) -> Int {
    let sum = cards.reduce(0) { total, card in
      switch card.rank {
      case .ace: return total + 1
      case .two: return total + 2
      case .three: return total + 3
      case .four: return total + 4
      case .five: return total + 5
      case .six: return total + 6
      case .seven: return total + 7
      case .eight: return total + 8
      case .nine: return total + 9
      case .ten, .jack, .queen, .king: return total + 0
      }
    }
    return sum % 10
  }
}
