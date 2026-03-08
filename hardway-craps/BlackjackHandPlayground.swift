//
//  BlackjackHandPlayground.swift
//  hardway-craps
//
//  Experimental playground for CompactPlayerHandView: deal, hit, split, clear.
//

import UIKit

final class BlackjackHandPlayground: UIViewController {

  private enum State {
    case idle
    case dealt
    case split
  }

  private var state: State = .idle {
    didSet { updateButtonStates() }
  }

  private let handSpacing: CGFloat = 16
  private let singleHandWidth: CGFloat = 180

  private let handAreaMargin: CGFloat = 12
  private let deckView = DeckView()
  private let playerBalanceView: MPPlayerBalanceView = {
    let v = MPPlayerBalanceView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.nameText = "Colton S."
    v.balanceText = "$225"
    return v
  }()
  private let handsStackView: UIStackView = {
    let v = UIStackView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.axis = .horizontal
    v.alignment = .bottom
    v.distribution = .fillEqually
    v.spacing = 16
    return v
  }()

  private let compactHandView = CompactPlayerHandView()
  private var playerHands: [CompactPlayerHandView] { [compactHandView] + additionalHands }
  private var additionalHands: [CompactPlayerHandView] = []
  private var selectedHandIndex: Int = 0
  private let activeHandDot: UIView = {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.backgroundColor = HardwayColors.yellow
    v.layer.cornerRadius = 4
    v.clipsToBounds = true
    v.isHidden = true
    return v
  }()
  private var activeHandDotCenterXConstraint: NSLayoutConstraint?
  private var activeHandDotBottomConstraint: NSLayoutConstraint?
  private var handsStackViewWidthConstraint: NSLayoutConstraint?
  private weak var handsContainerView: UIView?
  private var playerBalanceViewCenterXConstraint: NSLayoutConstraint?

  private var dealButton: UIButton!
  private var hitButton: UIButton!
  private var standButton: UIButton!
  private var splitButton: UIButton!
  private var doubleButton: UIButton!
  private var clearButton: UIButton!
  private var buttonsStackView: UIStackView!
  private var clearButtonStackView: UIStackView!

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    title = "Blackjack Hand Playground"

    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .close,
      target: self,
      action: #selector(dismissPlayground)
    )

    setupDeckView()
    setupHandsArea()
    setupButtons()
    updateButtonStates()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateHandsStackViewWidth()
  }

  private func setupDeckView() {
    deckView.translatesAutoresizingMaskIntoConstraints = false
    deckView.setCardCount(52 * 6, animated: false)
    view.addSubview(deckView)

    NSLayoutConstraint.activate([
      deckView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      deckView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
    ])
  }

  private func setupHandsArea() {
    let handsContainerView = UIView()
    handsContainerView.translatesAutoresizingMaskIntoConstraints = false
    handsContainerView.backgroundColor = .clear

    view.addSubview(playerBalanceView)
    view.addSubview(handsContainerView)
    self.handsContainerView = handsContainerView
    handsContainerView.addSubview(handsStackView)
    compactHandView.translatesAutoresizingMaskIntoConstraints = false
    handsStackView.addArrangedSubview(compactHandView)

    handsStackViewWidthConstraint = handsStackView.widthAnchor.constraint(
      equalToConstant: singleHandWidth)

    view.addSubview(activeHandDot)
    activeHandDotCenterXConstraint = activeHandDot.centerXAnchor.constraint(
      equalTo: compactHandView.centerXAnchor)
    activeHandDotBottomConstraint = activeHandDot.bottomAnchor.constraint(
      equalTo: compactHandView.handView.cardContainer.topAnchor, constant: -6)

    playerBalanceViewCenterXConstraint = playerBalanceView.centerXAnchor.constraint(
      equalTo: compactHandView.centerXAnchor)

    NSLayoutConstraint.activate([
      playerBalanceView.topAnchor.constraint(equalTo: handsContainerView.bottomAnchor, constant: 8),
      playerBalanceViewCenterXConstraint!,

      handsContainerView.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: handAreaMargin),
      handsContainerView.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -handAreaMargin),
      handsContainerView.topAnchor.constraint(equalTo: deckView.bottomAnchor, constant: 24),
      handsContainerView.heightAnchor.constraint(equalToConstant: 170),

      handsStackView.topAnchor.constraint(equalTo: handsContainerView.topAnchor),
      handsStackView.centerXAnchor.constraint(equalTo: handsContainerView.centerXAnchor),
      handsStackView.heightAnchor.constraint(equalTo: handsContainerView.heightAnchor),
      handsStackView.widthAnchor.constraint(lessThanOrEqualTo: handsContainerView.widthAnchor),
      handsStackViewWidthConstraint!,

      activeHandDot.widthAnchor.constraint(equalToConstant: 8),
      activeHandDot.heightAnchor.constraint(equalToConstant: 8),
      activeHandDotCenterXConstraint!,
      activeHandDotBottomConstraint!,
    ])
    setupHandTapGestures()
  }

  private func updatePlayerBalanceViewPosition() {
    let count = playerHands.count
    playerBalanceViewCenterXConstraint?.isActive = false
    if count >= 2 {
      playerBalanceViewCenterXConstraint = playerBalanceView.centerXAnchor.constraint(
        equalTo: handsStackView.centerXAnchor)
    } else {
      playerBalanceViewCenterXConstraint = playerBalanceView.centerXAnchor.constraint(
        equalTo: compactHandView.centerXAnchor)
    }
    playerBalanceViewCenterXConstraint?.isActive = true
  }

  private func setupHandTapGestures() {
    for (index, hand) in playerHands.enumerated() {
      hand.gestureRecognizers?.removeAll(where: { $0 is UITapGestureRecognizer })
      let tap = UITapGestureRecognizer(target: self, action: #selector(handTapped(_:)))
      hand.addGestureRecognizer(tap)
      hand.tag = index
    }
  }

  @objc private func handTapped(_ sender: UITapGestureRecognizer) {
    guard let hand = sender.view as? CompactPlayerHandView,
      playerHands.count >= 2
    else { return }
    let index = hand.tag
    guard index >= 0 && index < playerHands.count else { return }
    selectedHandIndex = index
    updateActiveHandDot()
    HapticsHelper.lightHaptic()
  }

  private func updateHandsStackViewWidth() {
    let count = playerHands.count
    let width: CGFloat
    if count == 1 {
      width = singleHandWidth
    } else {
      let needed = singleHandWidth * CGFloat(count) + handSpacing * CGFloat(count - 1)
      let maxWidth: CGFloat = handsContainerView.map { $0.bounds.width } ?? (view.bounds.width - 40)
      width = min(needed, maxWidth)
    }
    handsStackViewWidthConstraint?.constant = width
  }

  private func setupButtons() {
    dealButton = createControlButton(title: "Deal", backgroundColor: HardwayColors.green)
    dealButton.addTarget(self, action: #selector(dealTapped), for: .touchUpInside)

    hitButton = createControlButton(title: "Hit", backgroundColor: HardwayColors.surfaceGray)
    hitButton.addTarget(self, action: #selector(hitTapped), for: .touchUpInside)

    standButton = createControlButton(title: "Stand", backgroundColor: HardwayColors.surfaceGray)
    standButton.addTarget(self, action: #selector(standTapped), for: .touchUpInside)

    splitButton = createControlButton(title: "Split", backgroundColor: HardwayColors.surfaceGray)
    splitButton.addTarget(self, action: #selector(splitTapped), for: .touchUpInside)

    doubleButton = createControlButton(title: "Double", backgroundColor: HardwayColors.surfaceGray)
    doubleButton.addTarget(self, action: #selector(doubleTapped), for: .touchUpInside)

    clearButton = createControlButton(title: "Clear", backgroundColor: HardwayColors.surfaceGray)
    clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

    let firstRow = UIStackView(arrangedSubviews: [dealButton, hitButton])
    firstRow.axis = .horizontal
    firstRow.distribution = .fillEqually
    firstRow.spacing = 8

    let secondRow = UIStackView(arrangedSubviews: [standButton, splitButton, doubleButton])
    secondRow.axis = .horizontal
    secondRow.distribution = .fillEqually
    secondRow.spacing = 8

    clearButtonStackView = UIStackView(arrangedSubviews: [clearButton])
    clearButtonStackView.axis = .horizontal
    clearButtonStackView.distribution = .fill

    buttonsStackView = UIStackView(arrangedSubviews: [firstRow, secondRow, clearButtonStackView])
    buttonsStackView.translatesAutoresizingMaskIntoConstraints = false
    buttonsStackView.axis = .vertical
    buttonsStackView.distribution = .fillEqually
    buttonsStackView.spacing = 8
    view.addSubview(buttonsStackView)

    NSLayoutConstraint.activate([
      buttonsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      buttonsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      buttonsStackView.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
      buttonsStackView.heightAnchor.constraint(equalToConstant: 144),
    ])
  }

  private func createControlButton(title: String, backgroundColor: UIColor) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    button.backgroundColor = backgroundColor
    button.setTitleColor(.white, for: .normal)
    button.layer.cornerRadius = 16
    button.layer.borderWidth = 1.5
    button.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
    return button
  }

  private func updateButtonStates() {
    switch state {
    case .idle:
      dealButton.isEnabled = true
      hitButton.isEnabled = false
      standButton.isEnabled = false
      splitButton.isEnabled = false
      doubleButton.isEnabled = false
      clearButton.isEnabled = false
    case .dealt, .split:
      dealButton.isEnabled = false
      hitButton.isEnabled = true
      standButton.isEnabled = true
      splitButton.isEnabled = canSplitCurrentHand
      doubleButton.isEnabled = true
      clearButton.isEnabled = true
    }
  }

  private var currentHandIndex: Int {
    min(max(0, selectedHandIndex), playerHands.count - 1)
  }

  private var currentHand: CompactPlayerHandView {
    playerHands[currentHandIndex]
  }

  private var canSplitCurrentHand: Bool {
    currentHand.currentCards.count == 2
  }

  private func rankValue(_ rank: PlayingCardView.Rank) -> Int {
    switch rank {
    case .ace: return 1
    case .two: return 2
    case .three: return 3
    case .four: return 4
    case .five: return 5
    case .six: return 6
    case .seven: return 7
    case .eight: return 8
    case .nine: return 9
    case .ten, .jack, .queen, .king: return 10
    }
  }

  private func randomCard() -> BlackjackHandView.Card {
    let rank = PlayingCardView.Rank.allCases.randomElement() ?? .ace
    let suit = PlayingCardView.Suit.allCases.randomElement() ?? .spades
    return BlackjackHandView.Card(rank: rank, suit: suit, isCutCard: false)
  }

  private var deckCenterInView: CGPoint {
    view.convert(deckView.deckCenter, from: deckView)
  }

  @objc private func dismissPlayground() {
    dismiss(animated: true)
  }

  @objc private func dealTapped() {
    guard state == .idle else { return }
    HapticsHelper.lightHaptic()

    let c1 = randomCard()
    let c2 = randomCard()
    compactHandView.dealCard(c1, from: deckCenterInView, in: view)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      self.compactHandView.dealCard(c2, from: self.deckCenterInView, in: self.view)
      self.state = .dealt
    }
  }

  @objc private func hitTapped() {
    guard state == .dealt || state == .split else { return }
    HapticsHelper.lightHaptic()
    currentHand.broadcastAction("Hit")
    let card = randomCard()
    currentHand.dealCard(card, from: deckCenterInView, in: view)
  }

  @objc private func standTapped() {
    guard state == .dealt || state == .split else { return }
    HapticsHelper.lightHaptic()
    currentHand.broadcastAction("Stand")
  }

  @objc private func doubleTapped() {
    guard state == .dealt || state == .split else { return }
    HapticsHelper.lightHaptic()
    currentHand.broadcastAction("Double!")
    let card = randomCard()
    currentHand.dealCard(card, from: deckCenterInView, in: view)
  }

  @objc private func splitTapped() {
    guard currentHand.currentCards.count == 2 else {
      HapticsHelper.failureHaptic()
      return
    }
    HapticsHelper.lightHaptic()
    currentHand.broadcastAction("Split")

    let hand = currentHand
    let cards = hand.currentCards
    let firstCard = cards[0]
    let secondCard = cards[1]
    let splitIndex = currentHandIndex

    hand.setCardsWithoutAnimation([firstCard])

    let newHand = CompactPlayerHandView()
    newHand.translatesAutoresizingMaskIntoConstraints = false
    newHand.handView.showsEmptyPlaceholders = false
    newHand.setCardsWithoutAnimation([secondCard])

    handsStackView.insertArrangedSubview(newHand, at: splitIndex + 1)
    additionalHands.insert(newHand, at: splitIndex)

    updateHandsStackViewWidth()
    selectedHandIndex = splitIndex
    setupHandTapGestures()
    updateActiveHandDot()
    updatePlayerBalanceViewPosition()
    state = .split
  }

  @objc private func clearTapped() {
    guard state != .idle else { return }
    HapticsHelper.lightHaptic()
    let deckCenter = view.convert(deckView.deckCenter, from: deckView)

    if additionalHands.isEmpty {
      compactHandView.discardCards(to: deckCenter, in: view) { [weak self] in
        self?.state = .idle
        self?.updateButtonStates()
      }
    } else {
      discardAllHands(to: deckCenter, handIndex: 0)
    }
  }

  private func discardAllHands(to deckCenter: CGPoint, handIndex: Int) {
    let hands = playerHands
    guard handIndex < hands.count else {
      removeSplitAndReset()
      return
    }
    let hand = hands[handIndex]
    hand.discardCards(to: deckCenter, in: view) { [weak self] in
      self?.discardAllHands(to: deckCenter, handIndex: handIndex + 1)
    }
  }

  private func removeSplitAndReset() {
    for split in additionalHands {
      handsStackView.removeArrangedSubview(split)
      split.removeFromSuperview()
    }
    additionalHands.removeAll()
    compactHandView.clearCards()
    selectedHandIndex = 0
    state = .idle
    updateHandsStackViewWidth()
    setupHandTapGestures()
    updateActiveHandDot()
    updatePlayerBalanceViewPosition()
    updateButtonStates()
  }

  private func updateActiveHandDot() {
    let count = playerHands.count
    activeHandDot.isHidden = count < 2
    guard count >= 2, selectedHandIndex < count else { return }
    let activeHand = playerHands[selectedHandIndex]
    activeHandDotCenterXConstraint?.isActive = false
    activeHandDotCenterXConstraint = activeHandDot.centerXAnchor.constraint(
      equalTo: activeHand.centerXAnchor)
    activeHandDotCenterXConstraint?.isActive = true
    activeHandDotBottomConstraint?.isActive = false
    activeHandDotBottomConstraint = activeHandDot.bottomAnchor.constraint(
      equalTo: activeHand.handView.cardContainer.topAnchor, constant: -6)
    activeHandDotBottomConstraint?.isActive = true
  }

}
