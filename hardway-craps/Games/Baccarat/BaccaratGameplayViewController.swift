//
//  BaccaratGameplayViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 3/7/26.
//

import UIKit

class BaccaratGameplayViewController: UIViewController {

  // MARK: - Game Phase

  private enum GamePhase {
    case waitingForBet
    case dealing
    case revealingCards
    case gameOver
  }

  // MARK: - UI Components

  private var instructionLabel: InstructionLabel!
  private let deckView = DeckView()
  private var balanceView: BalanceView!
  private var chipSelector: ChipSelector!
  private var bottomStackView: UIStackView!

  private var dealButton: UIButton!
  private var newHandButton: UIButton!

  // Betting controls
  private var bettingStackView: UIStackView!
  private var bankerControl: PlainControl!
  private var playerControl: PlainControl!

  // Hand views
  private var bankerHandView: BaccaratHandView!
  private var playerHandView: BaccaratHandView!

  // Hand labels
  private var bankerLabel: UILabel!
  private var playerLabel: UILabel!
  private var bankerLabelBottomConstraint: NSLayoutConstraint!
  private var playerLabelBottomConstraint: NSLayoutConstraint!

  private static let labelPaddingStacked: CGFloat = 20
  private static let labelPaddingSpread: CGFloat = 24

  // Constraints for animating hands
  private var bankerTopConstraint: NSLayoutConstraint!
  private var playerTopConstraint: NSLayoutConstraint!
  private var bankerCenterXConstraint: NSLayoutConstraint!
  private var playerCenterXConstraint: NSLayoutConstraint!

  // Roadmap (Big Road scoreboard)
  private var roadmapView: BaccaratRoadmapView!
  private var roadmapHeightConstraint: NSLayoutConstraint!

  // Helpers
  private var chipAnimator: ChipAnimationHelper!

  // MARK: - Managers

  private var settingsManager: BaccaratSettingsManager!
  private var sessionManager: BaccaratSessionManager!

  // MARK: - Settings Computed Properties

  private var showTotals: Bool { settingsManager.currentSettings.showTotals }
  private var showBigRoad: Bool { settingsManager.currentSettings.showBigRoad }

  // MARK: - Session Computed Properties

  private var sessionId: String? { sessionManager.sessionId }
  private var handCount: Int { sessionManager.handCount }

  // State
  private var gamePhase: GamePhase = .waitingForBet
  private var waitingForHandSelection = false
  private var userSelectedHand: BaccaratHandView?
  private var lastHandWasTie = false

  // Deck tracking (8-deck shoe)
  private static let numberOfDecks = 8
  private var deck: [BlackjackHandView.Card] = []

  // Optional session to resume from
  private var resumingSession: GameSession?

  private var startingBalance: Int {
    return AppSettingsViewController.startingBankroll
  }
  private var initialBalance: Int = AppSettingsViewController.startingBankroll

  // MARK: - Initialization

  init(resumingSession: GameSession? = nil) {
    self.resumingSession = resumingSession
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - State

  private var balance: Int {
    get { sessionManager?.currentBalance ?? (balanceView?.balance ?? startingBalance) }
    set {
      sessionManager?.currentBalance = newValue
      balanceView?.balance = newValue
      chipSelector?.updateAvailableChips(balance: newValue)
    }
  }

  var selectedChipValue: Int {
    chipSelector?.selectedValue ?? 5
  }

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    title = "Baccarat"

    // Disable interactive pop gesture to prevent accidental dismissal when dragging bets
    navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    if #available(iOS 26.0, *) {
      navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = false
    }

    // Initialize managers
    setupManagers()

    // Start session tracking
    startSession()

    // Register for app lifecycle notifications
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppWillTerminate),
      name: UIApplication.willTerminateNotification,
      object: nil
    )

    setupUI()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    chipSelector?.initializeIndicatorPosition()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)

    // Save session if view controller is being dismissed
    if isMovingFromParent && sessionManager.hasActiveSession() {
      sessionManager.saveCurrentSessionForced()
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - App Lifecycle

  @objc private func handleAppWillResignActive() {
    sessionManager.pauseSessionTimer()
  }

  @objc private func handleAppDidEnterBackground() {
    sessionManager.pauseSessionTimer()
  }

  @objc private func handleAppDidBecomeActive() {
    sessionManager.resumeSessionTimer()
  }

  @objc private func handleAppWillTerminate() {
    if sessionManager.hasActiveSession() {
      sessionManager.pauseSessionTimer()
      sessionManager.saveCurrentSessionForced()
    }
  }

  // MARK: - Manager Setup

  private func setupManagers() {
    settingsManager = BaccaratSettingsManager()
    settingsManager.delegate = self

    sessionManager = BaccaratSessionManager(
      startingBalance: startingBalance,
      resumingSession: resumingSession
    )
    sessionManager.delegate = self

    initialBalance = sessionManager.currentBalance
  }

  private func startSession() {
    if resumingSession == nil {
      sessionManager.startSession()
      GameAnalyticsEvent.baccaratGameStarted.log()
    }
  }

  // MARK: - Setup

  private func setupUI() {
    setupNavigationBarMenu()
    setupInstructionLabel()
    setupDeckView()
    setupRoadmapView()
    setupBettingControls()
    setupHandViews()
    setupBalanceView()
    setupChipSelector()
    setupBottomStackView()
    setupDealButton()
    setupNewHandButton()

    chipAnimator = ChipAnimationHelper(containerView: view, balanceView: balanceView)

    // Set the initial balance now that balanceView is created
    balance = initialBalance
    createAndShuffleDeck()
    deckView.setCountLabelVisible(false)

    // Apply settings
    bankerHandView.setTotalsHidden(!showTotals)
    playerHandView.setTotalsHidden(!showTotals)
    if !showBigRoad {
      setRoadmapVisible(false, animated: false)
    }

    // Restore Big Road history from resumed session
    restoreRoadmapHistory()

    instructionLabel.showMessage("Place your bets", shouldFade: false)
    updateDealButtonState()
  }

  private func setupNavigationBarMenu() {
    let settingsButton = UIBarButtonItem(
      image: UIImage(systemName: "gearshape"),
      style: .plain,
      target: self,
      action: #selector(showSettings)
    )
    navigationItem.rightBarButtonItem = settingsButton
  }

  @objc private func showSettings() {
    showSettingsViewController()
  }

  private func setupInstructionLabel() {
    instructionLabel = InstructionLabel()
    instructionLabel.translatesAutoresizingMaskIntoConstraints = false
    instructionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    instructionLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)

    view.addSubview(instructionLabel)

    NSLayoutConstraint.activate([
      instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      instructionLabel.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      instructionLabel.heightAnchor.constraint(lessThanOrEqualToConstant: 44),
    ])
  }

  private func setupDeckView() {
    view.addSubview(deckView)
    NSLayoutConstraint.activate([
      deckView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
      deckView.topAnchor.constraint(equalTo: instructionLabel.topAnchor),
      deckView.widthAnchor.constraint(equalToConstant: 80),
      deckView.heightAnchor.constraint(equalToConstant: 110),
      instructionLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: deckView.leadingAnchor, constant: -12),
    ])
  }

  private func restoreRoadmapHistory() {
    for record in sessionManager.baccaratMetrics.handHistory {
      let result: BaccaratResult
      switch record.result {
      case .banker: result = .banker
      case .player: result = .player
      case .tie: result = .tie
      }
      roadmapView.addResult(result, isNatural: record.isNatural, hasPair: record.hasPair)
    }
  }

  private func setupRoadmapView() {
    roadmapView = BaccaratRoadmapView(compact: true)
    roadmapView.translatesAutoresizingMaskIntoConstraints = false
    roadmapHeightConstraint = roadmapView.heightAnchor.constraint(equalToConstant: 100)
    roadmapHeightConstraint.isActive = true
  }

  private func setupBettingControls() {
    bankerControl = PlainControl(title: "Banker")
    bankerControl.translatesAutoresizingMaskIntoConstraints = false
    bankerControl.getSelectedChipValue = { [weak self] in
      self?.selectedChipValue ?? 5
    }
    bankerControl.getBalance = { [weak self] in
      self?.balance ?? 0
    }
    bankerControl.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      self.balance -= amount
      self.sessionManager.trackBet(amount: amount, isBankerBet: true)
      self.updateConcurrentBets()
      self.updateDealButtonState()
    }
    bankerControl.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateDealButtonState()
    }

    playerControl = PlainControl(title: "Player")
    playerControl.translatesAutoresizingMaskIntoConstraints = false
    playerControl.getSelectedChipValue = { [weak self] in
      self?.selectedChipValue ?? 5
    }
    playerControl.getBalance = { [weak self] in
      self?.balance ?? 0
    }
    playerControl.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      self.balance -= amount
      self.sessionManager.trackBet(amount: amount, isBankerBet: false)
      self.updateConcurrentBets()
      self.updateDealButtonState()
    }
    playerControl.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateDealButtonState()
    }

    // Add Chinese characters to controls
    addChineseLabel("庄", color: .systemRed, to: bankerControl)
    addChineseLabel("闲", color: .systemBlue, to: playerControl)

    bettingStackView = UIStackView(arrangedSubviews: [bankerControl, roadmapView, playerControl])
    bettingStackView.translatesAutoresizingMaskIntoConstraints = false
    bettingStackView.axis = .vertical
    bettingStackView.spacing = 12
    bettingStackView.distribution = .fill
    bettingStackView.alignment = .fill

    view.addSubview(bettingStackView)

    NSLayoutConstraint.activate([
      bettingStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      bettingStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      bettingStackView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.7),

      bankerControl.heightAnchor.constraint(equalToConstant: 55),
      playerControl.heightAnchor.constraint(equalToConstant: 55),
    ])
  }

  private func setupHandViews() {
    bankerHandView = BaccaratHandView()
    playerHandView = BaccaratHandView()

    view.addSubview(bankerHandView)
    view.addSubview(playerHandView)

    let bankerTap = UITapGestureRecognizer(target: self, action: #selector(bankerHandTapped))
    bankerHandView.addGestureRecognizer(bankerTap)
    bankerHandView.isUserInteractionEnabled = true

    let playerTap = UITapGestureRecognizer(target: self, action: #selector(playerHandTapped))
    playerHandView.addGestureRecognizer(playerTap)
    playerHandView.isUserInteractionEnabled = true

    bankerHandView.onCardRevealed = { [weak self] index in
      guard let self = self else { return }
      self.handleCardRevealed(in: self.bankerHandView, index: index)
    }
    playerHandView.onCardRevealed = { [weak self] index in
      guard let self = self else { return }
      self.handleCardRevealed(in: self.playerHandView, index: index)
    }

    // Setup hand labels (hidden until dealing begins)
    bankerLabel = createHandLabel(text: "Banker")
    playerLabel = createHandLabel(text: "Player")
    bankerLabel.alpha = 0
    playerLabel.alpha = 0

    view.addSubview(bankerLabel)
    view.addSubview(playerLabel)

    bankerTopConstraint = bankerHandView.topAnchor.constraint(
      equalTo: deckView.bottomAnchor, constant: 20)
    playerTopConstraint = playerHandView.topAnchor.constraint(
      equalTo: deckView.bottomAnchor, constant: 20)

    bankerCenterXConstraint = bankerHandView.centerXAnchor.constraint(
      equalTo: view.centerXAnchor, constant: -90)
    playerCenterXConstraint = playerHandView.centerXAnchor.constraint(
      equalTo: view.centerXAnchor, constant: 90)

    bankerLabelBottomConstraint = bankerLabel.bottomAnchor.constraint(
      equalTo: bankerHandView.topAnchor, constant: -Self.labelPaddingStacked)
    playerLabelBottomConstraint = playerLabel.bottomAnchor.constraint(
      equalTo: playerHandView.topAnchor, constant: -Self.labelPaddingStacked)

    NSLayoutConstraint.activate([
      bankerTopConstraint,
      bankerCenterXConstraint,
      playerTopConstraint,
      playerCenterXConstraint,

      bankerLabelBottomConstraint,
      bankerLabel.centerXAnchor.constraint(equalTo: bankerHandView.cardContainer.centerXAnchor),

      playerLabelBottomConstraint,
      playerLabel.centerXAnchor.constraint(equalTo: playerHandView.cardContainer.centerXAnchor),
    ])
  }

  private func createHandLabel(text: String) -> UILabel {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = text
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    label.textColor = .white
    label.textAlignment = .center
    return label
  }

  private func setupBalanceView() {
    balanceView = BalanceView()
  }

  private func setupChipSelector() {
    chipSelector = ChipSelector(compact: [1, 5, 25, 50, 100])
    chipSelector.delegate = self
  }

  private func setupBottomStackView() {
    bottomStackView = UIStackView()
    bottomStackView.translatesAutoresizingMaskIntoConstraints = false
    bottomStackView.axis = .vertical
    bottomStackView.distribution = .fill
    bottomStackView.alignment = .leading
    bottomStackView.spacing = 8

    bottomStackView.addArrangedSubview(balanceView)
    bottomStackView.addArrangedSubview(chipSelector)
    view.addSubview(bottomStackView)

    bottomStackView.setContentHuggingPriority(.required, for: .vertical)
    bottomStackView.setContentCompressionResistancePriority(.required, for: .vertical)
    balanceView.setContentCompressionResistancePriority(.required, for: .vertical)

    let chipSelectorHeight: CGFloat = 60
    NSLayoutConstraint.activate([
      bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      bottomStackView.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
      chipSelector.heightAnchor.constraint(equalToConstant: chipSelectorHeight),
    ])
  }

  private func setupDealButton() {
    dealButton = UIButton.createActionButton(
      title: "Deal",
      target: self,
      action: #selector(dealTapped)
    )

    view.addSubview(dealButton)

    NSLayoutConstraint.activate([
      dealButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      dealButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
      dealButton.heightAnchor.constraint(equalToConstant: 98),
      dealButton.widthAnchor.constraint(equalToConstant: 120),
    ])

    // Initially disabled until bet is placed
    updateDealButtonState()
  }

  private func setupNewHandButton() {
    newHandButton = UIButton.createActionButton(
      title: "New Hand",
      target: self,
      action: #selector(newHandTapped),
      isInitiallyHidden: true,
      initialAlpha: 0
    )

    view.addSubview(newHandButton)

    NSLayoutConstraint.activate([
      newHandButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      newHandButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
      newHandButton.heightAnchor.constraint(equalToConstant: 98),
      newHandButton.widthAnchor.constraint(equalToConstant: 120),
    ])
  }

  private func updateDealButtonState() {
    let hasBet = (bankerControl?.betAmount ?? 0) > 0 || (playerControl?.betAmount ?? 0) > 0
    dealButton?.isEnabled = hasBet
    dealButton?.alpha = hasBet ? 1.0 : 0.5
  }

  private func setBettingLocked(_ locked: Bool) {
    bankerControl?.setBetRemovalDisabled(locked)
    bankerControl?.isEnabled = !locked
    playerControl?.setBetRemovalDisabled(locked)
    playerControl?.isEnabled = !locked
  }

  private func addChineseLabel(_ character: String, color: UIColor, to control: PlainControl) {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = character
    label.font = .systemFont(ofSize: 22, weight: .medium)
    label.textColor = color.withAlphaComponent(0.6)
    label.isUserInteractionEnabled = false
    control.addSubview(label)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 12),
      label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
    ])
  }

  private func updateConcurrentBets() {
    var concurrentCount = 0
    if (bankerControl?.betAmount ?? 0) > 0 { concurrentCount += 1 }
    if (playerControl?.betAmount ?? 0) > 0 { concurrentCount += 1 }
    sessionManager.updateConcurrentBets(count: concurrentCount)
  }

  private func setRoadmapVisible(_ visible: Bool, animated: Bool = true) {
    let newHeight: CGFloat = visible ? 100 : 0
    let newAlpha: CGFloat = visible ? 1 : 0

    guard animated else {
      roadmapHeightConstraint.constant = newHeight
      roadmapView.alpha = newAlpha
      view.layoutIfNeeded()
      return
    }

    roadmapHeightConstraint.constant = newHeight
    roadmapView.setNeedsLayout()

    UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5) {
      self.roadmapView.alpha = newAlpha
      self.view.layoutIfNeeded()
    }
  }

  // MARK: - Settings

  private func showSettingsViewController() {
    let settingsViewController = BaccaratSettingsViewController()
    let navigationController = UINavigationController(rootViewController: settingsViewController)

    if let sheet = navigationController.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
      sheet.largestUndimmedDetentIdentifier = .medium
    }

    settingsViewController.onSettingsChanged = { [weak self] in
      self?.refreshSettings()
    }

    settingsViewController.onShowGameDetails = { [weak self] in
      navigationController.dismiss(animated: true) {
        self?.showCurrentGameDetails()
      }
    }

    settingsViewController.onHitATM = { [weak self] in
      guard let self = self else { return }
      self.hitATM()
    }

    present(navigationController, animated: true)
  }

  private func refreshSettings() {
    settingsManager.loadSettings()
    settingsManager.delegate?.settingsDidChange(settingsManager.currentSettings)
  }

  private func showCurrentGameDetails() {
    guard let snapshot = sessionManager.currentSessionSnapshot() else { return }
    let detailViewController = GameDetailViewController(session: snapshot)
    navigationController?.pushViewController(detailViewController, animated: true)
  }

  private func hitATM() {
    let amount = 200

    let messages: [String] = [
      "Cash acquired! $\(amount) added!",
      "Don't tell your spouse! $\(amount) added!",
      "You're a lucky bastard! $\(amount) added!",
      "Shhh... $\(amount) added!",
      "Added \(amount) to bankroll!",
    ]

    balance += amount

    sessionManager.recordBalanceSnapshot()
    sessionManager.trackATMVisit()

    instructionLabel.showMessage(messages.randomElement() ?? "Cash acquired! $\(amount) added!", shouldFade: true)
    HapticsHelper.successHaptic()
  }

  // MARK: - Actions

  @objc private func bankerHandTapped() {
    guard waitingForHandSelection else { return }
    guard userSelectedHand == nil else { return }
    HapticsHelper.lightHaptic()
    userSelectedHand = bankerHandView
    selectUserHand(bankerHandView, isPlayer: false)
  }

  @objc private func playerHandTapped() {
    guard waitingForHandSelection else { return }
    guard userSelectedHand == nil else { return }
    HapticsHelper.lightHaptic()
    userSelectedHand = playerHandView
    selectUserHand(playerHandView, isPlayer: true)
  }

  /// User selects which hand they want to reveal. Move only that hand down and spread it.
  /// The other hand stays at top, centers, and spreads.
  private func selectUserHand(_ handView: BaccaratHandView, isPlayer: Bool) {
    waitingForHandSelection = false
    gamePhase = .revealingCards
    instructionLabel.showMessage("Tap cards to reveal", shouldFade: false)

    let otherHand = isPlayer ? bankerHandView! : playerHandView!
    let otherIsPlayer = !isPlayer

    // Move only the selected hand down and center it
    let topConstraint = isPlayer ? playerTopConstraint : bankerTopConstraint
    let centerConstraint = isPlayer ? playerCenterXConstraint : bankerCenterXConstraint

    topConstraint?.isActive = false
    // Position the hand halfway between the bottom betting control and the balance area
    let newCenterY = handView.centerYAnchor.constraint(
      equalTo: bettingStackView.bottomAnchor,
      constant: (bottomStackView.frame.minY - bettingStackView.frame.maxY) / 2)
    newCenterY.isActive = true
    centerConstraint?.constant = 0

    if isPlayer {
      playerTopConstraint = newCenterY
    } else {
      bankerTopConstraint = newCenterY
    }

    // Center and spread the other hand (stays at top)
    let otherCenterConstraint = otherIsPlayer ? playerCenterXConstraint : bankerCenterXConstraint
    otherCenterConstraint?.constant = 0

    // Spread selected hand first, then the other hand after a short delay
    handView.animateToSpread()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      otherHand.animateToSpread()
    }

    // More padding between Banker/Player labels and cards when spread
    bankerLabelBottomConstraint.constant = -Self.labelPaddingSpread
    playerLabelBottomConstraint.constant = -Self.labelPaddingSpread

    UIView.animate(
      withDuration: 0.4,
      delay: 0,
      usingSpringWithDamping: 0.8,
      initialSpringVelocity: 0.5,
      options: .curveEaseOut
    ) {
      self.view.layoutIfNeeded()
    }
  }

  @objc private func dealTapped() {
    guard gamePhase == .waitingForBet else { return }
    let hasBet = (bankerControl?.betAmount ?? 0) > 0 || (playerControl?.betAmount ?? 0) > 0
    guard hasBet else { return }

    HapticsHelper.lightHaptic()
    gamePhase = .dealing
    revealPhase = .revealingInitialCards
    instructionLabel.showMessage("Dealing cards...", shouldFade: false)
    waitingForHandSelection = false
    userSelectedHand = nil

    // Record balance before hand starts
    sessionManager.updateLastBalanceBeforeHand(balance)

    // Snapshot bet size
    let bankerBet = bankerControl?.betAmount ?? 0
    let playerBet = playerControl?.betAmount ?? 0
    sessionManager.snapshotBetSize(bankerBet + playerBet)

    // If bets carried over from a tie, track them as bets for this new hand
    if lastHandWasTie {
      if bankerBet > 0 { sessionManager.trackBet(amount: bankerBet, isBankerBet: true) }
      if playerBet > 0 { sessionManager.trackBet(amount: playerBet, isBankerBet: false) }
      updateConcurrentBets()
      lastHandWasTie = false
    }

    // Hide roadmap, deal button, lock bets, show hand labels
    setRoadmapVisible(false)
    dealButton.fadeOut()
    setBettingLocked(true)

    UIView.animate(withDuration: 0.3) {
      self.bankerLabel.alpha = 1
      self.playerLabel.alpha = 1
    }

    bankerHandView.clearCards()
    playerHandView.clearCards()
    resetHandPositions()

    // Draw and deal each card one at a time so the deck count animates properly
    let dc1 = view.convert(deckView.deckCenter, from: deckView)
    let playerCard1 = drawCard()
    playerHandView.dealCard(playerCard1, from: dc1, in: view)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      let dc = self.view.convert(self.deckView.deckCenter, from: self.deckView)
      let bankerCard1 = self.drawCard()
      self.bankerHandView.dealCard(bankerCard1, from: dc, in: self.view)

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        guard let self = self else { return }
        let dc = self.view.convert(self.deckView.deckCenter, from: self.deckView)
        let playerCard2 = self.drawCard()
        self.playerHandView.dealCard(playerCard2, from: dc, in: self.view)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
          guard let self = self else { return }
          let dc = self.view.convert(self.deckView.deckCenter, from: self.deckView)
          let bankerCard2 = self.drawCard()
          self.bankerHandView.dealCard(bankerCard2, from: dc, in: self.view)

          // After initial deal, auto-select hand and begin reveal sequence
          // Extra delay to allow the second card slide + fly-in animations to finish
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            let hasBankerBet = (self.bankerControl?.betAmount ?? 0) > 0
            let hasPlayerBet = (self.playerControl?.betAmount ?? 0) > 0

            if hasBankerBet && !hasPlayerBet {
              self.userSelectedHand = self.bankerHandView
              self.selectUserHand(self.bankerHandView, isPlayer: false)
            } else if hasPlayerBet && !hasBankerBet {
              self.userSelectedHand = self.playerHandView
              self.selectUserHand(self.playerHandView, isPlayer: true)
            } else {
              // Both sides have bets — let user choose
              self.waitingForHandSelection = true
              self.instructionLabel.showMessage("Tap a hand to reveal", shouldFade: false)
            }
          }
        }
      }
    }
  }

  @objc private func newHandTapped() {
    guard gamePhase == .gameOver else { return }
    HapticsHelper.lightHaptic()

    // Hide new hand button
    newHandButton.fadeOut()

    // Reset state immediately
    gamePhase = .waitingForBet
    waitingForHandSelection = false
    userSelectedHand = nil

    // Update last balance before next hand
    sessionManager.updateLastBalanceBeforeHand(balance)

    // Fade out hand labels
    UIView.animate(withDuration: 0.3) {
      self.bankerLabel.alpha = 0
      self.playerLabel.alpha = 0
    }

    // Discard cards with animation, then reset for next hand
    discardHandsToTopLeft { [weak self] in
      guard let self = self else { return }

      self.resetHandPositions()

      // Only clear bets if last hand was NOT a tie (ties leave bets in place)
      if !self.lastHandWasTie {
        self.bankerControl.betAmount = 0
        self.playerControl.betAmount = 0
      }

      // Unlock betting and show deal button
      self.setBettingLocked(false)
      self.dealButton.isHidden = false
      self.dealButton.alpha = 0
      self.updateDealButtonState()

      let hasBet = (self.bankerControl?.betAmount ?? 0) > 0 || (self.playerControl?.betAmount ?? 0) > 0
      UIView.animate(withDuration: 0.3) {
        self.dealButton.alpha = hasBet ? 1.0 : 0.5
      }

      // Show roadmap between controls again (if enabled)
      if self.showBigRoad {
        self.setRoadmapVisible(true)
      }

      self.instructionLabel.showMessage(
        hasBet ? "Deal or adjust your bets" : "Place your bets", shouldFade: false)
    }
  }

  private func discardHandsToTopLeft(completion: (() -> Void)? = nil) {
    let topLeftPoint = CGPoint(x: -100, y: -100)

    let bankerCards = bankerHandView.currentCards
    let playerCards = playerHandView.currentCards

    guard !bankerCards.isEmpty || !playerCards.isEmpty else {
      completion?()
      return
    }

    var completedDiscards = 0
    let totalDiscards = (bankerCards.isEmpty ? 0 : 1) + (playerCards.isEmpty ? 0 : 1)

    func checkCompletion() {
      completedDiscards += 1
      if completedDiscards >= totalDiscards {
        completion?()
      }
    }

    if !bankerCards.isEmpty {
      bankerHandView.discardCards(to: topLeftPoint, in: view) {
        checkCompletion()
      }
    }

    if !playerCards.isEmpty {
      playerHandView.discardCards(to: topLeftPoint, in: view) {
        checkCompletion()
      }
    }
  }

  // MARK: - Baccarat Game Logic

  /// Tracks what we're waiting for the user to reveal next.
  private enum RevealPhase {
    case revealingInitialCards
    case waitingForPlayerThirdReveal(playerThirdCard: BlackjackHandView.Card)
    case waitingForBankerThirdReveal
    case done
  }

  private var revealPhase: RevealPhase = .revealingInitialCards

  /// Called whenever any card is revealed. Drives the entire reveal flow.
  private func handleCardRevealed(in handView: BaccaratHandView, index: Int) {
    switch revealPhase {
    case .revealingInitialCards:
      // User can flip cards on either hand in any order
      if bankerHandView.allCardsRevealed && playerHandView.allCardsRevealed {
        revealPhase = .done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
          self?.applyThirdCardRules()
        }
      }

    case .waitingForPlayerThirdReveal(let playerThirdCard):
      if handView === playerHandView && index == 2 {
        revealPhase = .done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
          self?.applyBankerThirdCardRule(playerThirdCard: playerThirdCard)
        }
      }

    case .waitingForBankerThirdReveal:
      if handView === bankerHandView && index == 2 {
        revealPhase = .done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
          self?.resolveGame()
        }
      }

    case .done:
      break
    }
  }

  private func applyThirdCardRules() {
    let playerTotal = baccaratTotal(for: playerHandView.currentCards)
    let bankerTotal = baccaratTotal(for: bankerHandView.currentCards)

    // Natural: if either hand is 8 or 9 with first two cards, no more cards drawn
    if playerTotal >= 8 || bankerTotal >= 8 {
      sessionManager.recordNatural()
      resolveGame()
      return
    }

    // Player draws third card if total is 0-5
    if playerTotal <= 5 {
      let thirdCard = drawCard()
      let dc = view.convert(deckView.deckCenter, from: deckView)
      playerHandView.dealCardToSpread(thirdCard, from: dc, in: view)

      // Wait for user to tap the third card to reveal it
      revealPhase = .waitingForPlayerThirdReveal(playerThirdCard: thirdCard)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
        self?.instructionLabel.showMessage("Tap card to reveal", shouldFade: false)
      }
    } else {
      // Player stands (6 or 7) — banker draws on 0-5, stands on 6-7
      if bankerTotal <= 5 {
        dealBankerThirdCard()
      } else {
        resolveGame()
      }
    }
  }

  /// Banker third-card tableau: determines if banker draws based on player's third card.
  private func applyBankerThirdCardRule(playerThirdCard: BlackjackHandView.Card) {
    let bankerTotal = baccaratTotal(for: bankerHandView.currentCards)
    let playerThirdValue = baccaratCardValue(playerThirdCard)

    var bankerDraws = false

    switch bankerTotal {
    case 0, 1, 2:
      bankerDraws = true
    case 3:
      bankerDraws = playerThirdValue != 8
    case 4:
      bankerDraws = (2...7).contains(playerThirdValue)
    case 5:
      bankerDraws = (4...7).contains(playerThirdValue)
    case 6:
      bankerDraws = playerThirdValue == 6 || playerThirdValue == 7
    default:
      bankerDraws = false
    }

    if bankerDraws {
      dealBankerThirdCard()
    } else {
      resolveGame()
    }
  }

  private func dealBankerThirdCard() {
    let thirdCard = drawCard()
    let dc = view.convert(deckView.deckCenter, from: deckView)
    bankerHandView.dealCardToSpread(thirdCard, from: dc, in: view)

    // Wait for user to tap the third card to reveal it
    revealPhase = .waitingForBankerThirdReveal
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
      self?.instructionLabel.showMessage("Tap card to reveal", shouldFade: false)
    }
  }

  private func resolveGame() {
    gamePhase = .gameOver

    let playerCards = playerHandView.currentCards
    let bankerCards = bankerHandView.currentCards
    let playerTotal = baccaratTotal(for: playerCards)
    let bankerTotal = baccaratTotal(for: bankerCards)

    // Detect natural: either hand is 8 or 9 with exactly 2 cards
    let isNatural = (playerCards.count == 2 && playerTotal >= 8)
      || (bankerCards.count == 2 && bankerTotal >= 8)

    // Detect pair: either hand's first two cards share the same rank
    let hasPair: Bool = {
      let playerPair = playerCards.count >= 2 && playerCards[0].rank == playerCards[1].rank
      let bankerPair = bankerCards.count >= 2 && bankerCards[0].rank == bankerCards[1].rank
      return playerPair || bankerPair
    }()

    let bankerBet = bankerControl?.betAmount ?? 0
    let playerBet = playerControl?.betAmount ?? 0

    var message: String

    let playerWins = playerTotal > bankerTotal
    let bankerWins = bankerTotal > playerTotal
    let isTie = playerTotal == bankerTotal

    if playerWins {
      message = "Player wins! \(playerTotal) over \(bankerTotal)."
      sessionManager.recordPlayerWin()
      sessionManager.recordHandResult(.player, isNatural: isNatural, hasPair: hasPair)
      lastHandWasTie = false
      roadmapView.addResult(.player, isNatural: isNatural, hasPair: hasPair)
    } else if bankerWins {
      message = "Banker wins! \(bankerTotal) over \(playerTotal)."
      sessionManager.recordBankerWin()
      sessionManager.recordHandResult(.banker, isNatural: isNatural, hasPair: hasPair)
      lastHandWasTie = false
      roadmapView.addResult(.banker, isNatural: isNatural, hasPair: hasPair)
    } else {
      message = "Tie! Both have \(playerTotal)."
      sessionManager.recordTie()
      sessionManager.recordHandResult(.tie, isNatural: isNatural, hasPair: hasPair)
      lastHandWasTie = true
      roadmapView.addResult(.tie, isNatural: isNatural, hasPair: hasPair)
    }

    instructionLabel.showMessage(message, shouldFade: false)

    // Increment hand count and record balance snapshot
    sessionManager.incrementHandCount()

    // Calculate total win/loss for bet result display
    var totalWinAmount = 0
    var totalLossAmount = 0

    if playerBet > 0 {
      if playerWins {
        totalWinAmount += playerBet
      } else if bankerWins {
        totalLossAmount += playerBet
      }
    }
    if bankerBet > 0 {
      if bankerWins {
        totalWinAmount += bankerBet
      } else if playerWins {
        totalLossAmount += bankerBet
      }
    }

    // Show liquid glass bet result container
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      let naturalDesc = isNatural ? "Natural!" : nil
      if totalWinAmount > 0 {
        self.showBetResult(amount: totalWinAmount, isWin: true, description: naturalDesc)
      } else if totalLossAmount > 0 {
        self.showBetResult(amount: totalLossAmount, isWin: false, description: naturalDesc)
      }
    }

    // Animate chip results for each bet control
    let bets: [(control: PlainControl, bet: Int, won: Bool, lost: Bool)] = [
      (playerControl, playerBet, playerWins, bankerWins),
      (bankerControl, bankerBet, bankerWins, playerWins),
    ]

    for (control, bet, won, lost) in bets {
      guard bet > 0 else { continue }
      if won {
        // House chip → control, pause, then both chips → balance
        chipAnimator.animateChip(amount: bet, steps: [
          .standard(path: .houseToControl(control: control, offset: control.winningsAnimationOffset),
                    duration: 0.75, scaleTransform: CGAffineTransform(scaleX: 1.5, y: 1.5),
                    onCompletion: { [weak self] in
                      // Hide real bet view and launch the original bet chip → balance
                      control.betView.alpha = 0
                      self?.chipAnimator.animateChip(amount: bet, steps: [
                        .standard(path: .controlToBalance(control: control), duration: 0.45, delay: 0.18,
                                  scaleTransform: CGAffineTransform(scaleX: 0.2, y: 0.2),
                                  onCompletion: {
                                    self?.balance += bet
                                    control.betAmount = 0
                                    control.betView.alpha = 1
                                  })
                      ])
                    }),
          // Winnings chip continues → balance (same timing as above)
          .standard(path: .controlToBalance(control: control), duration: 0.5, delay: 0.1,
                    scaleTransform: CGAffineTransform(scaleX: 0.2, y: 0.2),
                    onCompletion: { [weak self] in
                      self?.balance += bet
                    })
        ])
      } else if lost {
        chipAnimator.animateChipsAway(from: control)
      } else {
        // Tie: leave bet in place for next hand
      }
    }

    // Record balance snapshot after chip animations settle and save session
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
      guard let self = self else { return }
      self.sessionManager.recordBalanceSnapshot()
      self.sessionManager.updateSession()
    }

    // Show new hand button after animations settle
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      guard let self = self else { return }
      self.newHandButton.isHidden = false
      self.newHandButton.fadeIn()
    }
  }

  // MARK: - Baccarat Helpers

  private func baccaratTotal(for cards: [BlackjackHandView.Card]) -> Int {
    let sum = cards.reduce(0) { total, card in
      total + baccaratCardValue(card)
    }
    return sum % 10
  }

  private func baccaratCardValue(_ card: BlackjackHandView.Card) -> Int {
    switch card.rank {
    case .ace: return 1
    case .two: return 2
    case .three: return 3
    case .four: return 4
    case .five: return 5
    case .six: return 6
    case .seven: return 7
    case .eight: return 8
    case .nine: return 9
    case .ten, .jack, .queen, .king: return 0
    }
  }

  /// Reset both hands to original top/center positions.
  private func resetHandPositions() {
    bankerTopConstraint?.isActive = false
    playerTopConstraint?.isActive = false

    bankerTopConstraint = bankerHandView.topAnchor.constraint(
      equalTo: deckView.bottomAnchor, constant: 20)
    playerTopConstraint = playerHandView.topAnchor.constraint(
      equalTo: deckView.bottomAnchor, constant: 20)

    bankerTopConstraint.isActive = true
    playerTopConstraint.isActive = true

    bankerCenterXConstraint.constant = -90
    playerCenterXConstraint.constant = 90

    bankerLabelBottomConstraint?.constant = -Self.labelPaddingStacked
    playerLabelBottomConstraint?.constant = -Self.labelPaddingStacked

    view.layoutIfNeeded()
  }

  private func createAndShuffleDeck() {
    let ranks: [PlayingCardView.Rank] = [
      .ace, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .jack, .queen, .king,
    ]
    let suits: [PlayingCardView.Suit] = [.hearts, .diamonds, .clubs, .spades]

    deck = []
    for _ in 0..<Self.numberOfDecks {
      for rank in ranks {
        for suit in suits {
          deck.append(BlackjackHandView.Card(rank: rank, suit: suit))
        }
      }
    }
    deck.shuffle()
    deckView.setCardCount(deck.count, animated: false)
  }

  private func drawCard() -> BlackjackHandView.Card {
    // Reshuffle if deck runs low (below ~30 cards)
    if deck.count < 30 {
      createAndShuffleDeck()
    }
    return deck.removeLast()
  }
}

// MARK: - ChipSelectorDelegate

extension BaccaratGameplayViewController: ChipSelectorDelegate {
  func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {
    // Handle chip selection
  }
}

// MARK: - BaccaratSettingsManagerDelegate

extension BaccaratGameplayViewController: BaccaratSettingsManagerDelegate {
  func settingsDidChange(_ settings: BaccaratSettings) {
    bankerHandView?.setTotalsHidden(!settings.showTotals)
    playerHandView?.setTotalsHidden(!settings.showTotals)

    // Show/hide big road (only when waiting for bet)
    if gamePhase == .waitingForBet {
      setRoadmapVisible(settings.showBigRoad)
    }
  }
}

// MARK: - BaccaratSessionManagerDelegate

extension BaccaratGameplayViewController: BaccaratSessionManagerDelegate {
  func sessionDidStart(id: String) {
    // Session started
  }

  func sessionWasSaved(session: GameSession) {
    // Session saved
  }

  func metricsDidUpdate(metrics: BaccaratGameplayMetrics) {
    // Metrics updated
  }

  func balanceDidChange(from oldBalance: Int, to newBalance: Int) {
    // Balance synced through the balance property setter
  }

  func handCountDidChange(count: Int) {
    // Hand count updated
  }
}
