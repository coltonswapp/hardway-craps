//
//  MultiplayerBlackjackViewController.swift
//  hardway-craps
//
//  Multiplayer Blackjack: join table (name, balance, seat order, chip color) then show
//  gameplay UI. Layout matches BlackjackGameplayViewController.
//

import FirebaseDatabase
import FirebaseFunctions
import UIKit

private enum MultiplayerDisplayNameKey {
  static let key = MultiplayerBlackjackKeys.UserDefaults.displayName
  static var value: String {
    UserDefaults.standard.string(forKey: key) ?? "Player"
  }
  static func set(_ name: String) {
    UserDefaults.standard.set(name, forKey: key)
  }
}

private enum MultiplayerTableCodeKey {
  static let key = MultiplayerBlackjackKeys.UserDefaults.tableCode
  static var value: String {
    UserDefaults.standard.string(forKey: key) ?? "0000"
  }
  static func set(_ code: String) {
    UserDefaults.standard.set(code, forKey: key)
  }
}

private enum MultiplayerPlayerIdKey {
  static let key = MultiplayerBlackjackKeys.UserDefaults.playerId
  static var value: String {
    if let saved = UserDefaults.standard.string(forKey: key) { return saved }
    let newId = UUID().uuidString
    UserDefaults.standard.set(newId, forKey: key)
    return newId
  }
}

final class MultiplayerBlackjackViewController: UIViewController, UIScrollViewDelegate {

  // MARK: - Injected Configuration

  private let injectedTableCode: String
  private let injectedBankroll: Int

  init(tableCode: String, bankroll: Int) {
    self.injectedTableCode = tableCode
    self.injectedBankroll = bankroll
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - UI (matching BlackjackGameplayViewController layout)

  private let dealerHandView = DealerHandView()
  private let standButton = ActionButton(title: "Stand")
  private let doubleButton = ActionButton(title: "Double")
  private let splitButton = CircularActionButton(systemIconName: "arrow.triangle.branch")

  private var instructionLabel: InstructionLabel!
  private let deckView = DeckView()
  private var balanceView: BalanceView!
  private var chipSelector: ChipSelector!
  private var bottomStackView: UIStackView!
  private var newHandButton: UIButton!
  private var dealButton: UIButton!
  private var nextHandButton: UIButton!
  private var rightButtonStack: UIStackView!

  /// Container for player seats: scroll view + horizontal stack of seat cells.
  private var seatsContainerView: UIView!
  private var seatsScrollView: UIScrollView!
  private var seatsStackView: UIStackView!
  /// Local player's seat (interactive); reused for mySeatIndex.
  private var defaultSeat: PlayerSeat!
  /// All seat views by index (local + remote). Rebuilt when observeSeats fires.
  private var seatViewsByIndex: [Int: PlayerSeat] = [:]
  /// Current seats data (updated by observeSeats)
  private var currentSeatsData: [Int: MPBlackjackTableState.SeatData] = [:]
  /// True while the initial deal animation is running (prevents re-applying cards from seat observer)
  private var isDealAnimationRunning = false
  /// True when a deal request is in progress (prevents double-tapping DEAL button)
  private var isDealInProgress = false
  /// True while post-deal blackjack payout animations are playing (suppresses turn indicator / buttons)
  private var isBlackjackPayoutAnimating = false
  /// Incremented each time applyCardsWithoutDealAnimation is called; stale asyncAfter blocks check this to bail out
  private var cardApplyGeneration: Int = 0
  /// Track previous hands for each seat to detect bet changes
  private var previousHandsByIndex: [Int: [MPBlackjackTableState.HandData]] = [:]
  /// Track previous balance for each seat to avoid unnecessary updates
  private var previousBalanceByIndex: [Int: Int] = [:]
  /// Track previous card counts and hasStood flags per seat to detect action changes
  private var previousCardCountsBySeat: [Int: Int] = [:]
  private var previousHasStoodBySeat: [Int: Bool] = [:]
  /// Track previous hand counts per seat to detect split actions
  private var previousHandCountsBySeat: [Int: Int] = [:]
  /// When true, Firebase balance updates for the local player are ignored (balance is applied via animation instead).
  private var isBalanceFrozenForSettlement: Bool = false
  /// The player's balance captured the moment settlement begins, before any payout is applied.
  private var preBetSettlementBalance: Int = 0
  /// When true, Firebase balance updates are ignored during optimistic bet operations (place/remove).
  /// Prevents Firebase listener from overriding optimistic balance updates before backend confirms.
  private var isBalanceFrozenForBetOperation: Bool = false
  /// Expected balance after optimistic bet operation completes (used to validate Firebase updates).
  private var expectedBalanceAfterBetOperation: Int?
  /// Track push bets per seat to carry over to next hand
  private var pushBetsBySeatIndex: [Int: Int] = [:]
  /// Seats whose bust was already animated during player_actions (skip in end-of-hand reconciliation)
  private var bustAnimatedSeatIndices: Set<Int> = []
  /// Track the last instruction message shown to prevent unnecessary animation restarts
  private var lastInstructionMessage: String?
  private let seatWidth: CGFloat = 180
  private let maxSeats = 5
  /// The hand index within our seat that is currently active (from server's currentTurn.handIndex).
  private var activeHandIndex: Int = 0
  /// Small yellow dot above the current player's hand during player_actions; animated left/right when turn changes.
  private var turnIndicatorDot: UIView!
  private var turnIndicatorDotCenterXConstraint: NSLayoutConstraint?
  private var seatsObserverHandle: DatabaseHandle?
  private var gameStateObserverHandle: DatabaseHandle?
  private var hostPlayerIdObserverHandle: DatabaseHandle?
  /// The playerId of the current host as stored in Firebase. Authoritative source of host status.
  private var currentHostPlayerId: String?
  /// Last game state snapshot for diffing cards (to animate new cards only).
  private var lastGameSnapshot: MPBlackjackTableState.GameStateSnapshot?
  /// Previous game state snapshot (before lastGameSnapshot) for detecting phase transitions.
  private var previousGameSnapshot: MPBlackjackTableState.GameStateSnapshot?

  // MARK: - Optimistic UI (seed-only deck, instant feedback for local player)

  private var deckProvider: DeterministicDeckProvider?
  private var optimisticDeckIndex: Int = 0
  /// Cards we predicted for our hand that the server has not confirmed yet.
  private var optimisticCardsForMyHand: [BlackjackHandView.Card] = []
  private var isActionInFlight = false
  private var actionInFlightTimeoutWorkItem: DispatchWorkItem?
  /// True after the initial seat reconciliation completes, used to distinguish initial host assignment from a host transfer.
  private var hasCompletedInitialJoin: Bool = false

  // MARK: - Dealer card queue (sequential animation during dealer turn)

  /// Cards queued to be animated onto the dealer hand one at a time.
  private var dealerCardQueue: [BlackjackHandView.Card] = []
  /// True while a dealer-card animation is in flight; prevents overlapping animations.
  private var isDealerCardAnimating = false
  /// Number of dealer cards already rendered (avoids re-queuing cards we've already shown).
  private var dealerCardsRenderedCount: Int = 0
  /// Whether the dealer's hole card has been revealed during this turn's queue processing.
  private var dealerHoleRevealed = false

  // MARK: - Bonus Bets

  private let mpBonusBetControl = MPBonusBetControl()
  private var previousBonusBetsBySeat: [Int: Int] = [:]
  private var localBonusBetAmount: Int = 0
  private var isBonusBetResolutionAnimating = false
  private var bonusBetResultsProcessed = false
  /// True once the very first game-state snapshot has been received.
  /// Distinguishes a genuine mid-game join from a nil `lastGameSnapshot` caused by
  /// `finishCardClearingCleanup` resetting state between hands.
  private var hasReceivedFirstGameSnapshot = false
  /// Track if we've logged the game started analytics event (only log once per game session)
  private var hasLoggedGameStarted = false
  private var currentSelectedSideBet: String = "Royal Match"
  private var settingsObserverHandle: DatabaseHandle?

  // MARK: - Insurance

  private let mpInsuranceControl = MPInsuranceControl()
  private var continueButton: UIButton!
  private var isInsurancePhaseActive = false
  private var localInsuranceBetAmount: Int = 0
  private var pendingInsuranceSnapshot: MPBlackjackTableState.GameStateSnapshot?
  private var pendingInsuranceHoleCard: BlackjackHandView.Card?
  private var pendingInsuranceUpCard: BlackjackHandView.Card?
  /// Track previous insurance bets per seat to detect remote changes
  private var previousInsuranceBySeat: [Int: Int] = [:]
  /// When true, auto-scroll is disabled until it's the user's turn (allows user to look at their hand without interruption)
  private var shouldIgnoreAutoScroll = false
  /// Track if scrolling is programmatic (to distinguish from user-initiated scrolling)
  private var isProgrammaticScroll = false

  // MARK: - Loading state

  private var loadingOverlayView: UIView!
  private var loadingLabel: UILabel!
  private var loadingSpinner: NNLoadingSpinner!
  private var loadingErrorLabel: UILabel!
  private var loadingRetryButton: UIButton!

  // MARK: - Connection status

  private var connectionStatusView: ConnectionStatusView!
  private var connectedRef: DatabaseReference?
  private var connectedObserverHandle: DatabaseHandle?
  private var connectionDebounceWorkItem: DispatchWorkItem?

  // MARK: - Table state (set after join)

  private var tableState: MPBlackjackTableState!
  private var mySeatIndex: Int = 0
  private var myDisplayName: String = "Player"
  private var myChipColorName: String = "Cyan"
  private var joinedBalance: Int = 200
  /// True when this player occupies the lowest seat index (first to join). Host controls Deal and Next Hand.
  private var isHost: Bool = false

  // MARK: - State

  private var balance: Int {
    get { balanceView?.balance ?? joinedBalance }
    set {
      balanceView?.balance = newValue
      chipSelector?.updateAvailableChips(balance: newValue)
      defaultSeat?.setBalance(newValue, animated: false)
    }
  }

  var selectedChipValue: Int {
    chipSelector?.selectedValue ?? 5
  }

  /// Update chipSelector color to match the assigned chip color name
  private func updateChipSelectorColor(_ colorName: String) {
    guard let colorSet = ChipColorSet.named(colorName) else {
      print("⚠️ [MultiplayerBlackjack] Could not find ChipColorSet for name: '\(colorName)'")
      return
    }
    guard let chipSelector = chipSelector else {
      print("⚠️ [MultiplayerBlackjack] chipSelector is nil, cannot update color")
      return
    }
    print("🎨 [MultiplayerBlackjack] Updating chipSelector to color: '\(colorName)'")
    chipSelector.updateColorSet(colorSet)
    // Force layout update to ensure colors are applied
    chipSelector.setNeedsLayout()
    chipSelector.layoutIfNeeded()
  }

  /// Get descriptions for side bet names
  private func descriptionsForSideBets(_ sideBets: [String]) -> [String] {
    typealias SideBetType = BlackjackSettingsViewController.SideBetType
    return sideBets.map { name in
      if let type = SideBetType.allCases.first(where: { $0.displayName == name }) {
        return type.description
      }
      return ""
    }
  }

  /// Convert chip color name to MPSmallBetChipStyle
  private func chipStyleForColorName(_ colorName: String) -> MPSmallBetChipStyle {
    switch colorName {
    case "Yellow Green": return .yellow
    case "Cyan": return .blue
    case "Green": return .green
    case "Red": return .red
    default:
      // Fallback for lowercase/other variations
      switch colorName.lowercased() {
      case "yellow", "yellow green": return .yellow
      case "cyan", "blue": return .blue
      case "green": return .green
      case "red": return .red
      default: return .yellow
      }
    }
  }

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    title = "Multiplayer Blackjack"

    // Disable interactive pop gesture (edge swipe) to prevent accidental dismissal
    navigationController?.interactivePopGestureRecognizer?.isEnabled = false

    navigationItem.hidesBackButton = true
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "chevron.left"),
      style: .plain,
      target: self,
      action: #selector(backButtonTapped))

    // Add gear button to open settings
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "gearshape"),
      style: .plain,
      target: self,
      action: #selector(showSettingsTapped))

    tableState = MPBlackjackTableState(tableCode: loadTableCode())
    setupLoadingOverlay()
    attemptJoin()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // Re-enable interactive pop gesture when leaving this view controller
    navigationController?.interactivePopGestureRecognizer?.isEnabled = true
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    chipSelector?.initializeIndicatorPosition()
  }

  // MARK: - Loading overlay

  private func setupLoadingOverlay() {
    loadingOverlayView = UIView()
    loadingOverlayView.translatesAutoresizingMaskIntoConstraints = false
    loadingOverlayView.backgroundColor = .black
    view.addSubview(loadingOverlayView)

    loadingLabel = UILabel()
    loadingLabel.translatesAutoresizingMaskIntoConstraints = false
    loadingLabel.text = "Loading table..."
    loadingLabel.font = .systemFont(ofSize: 17, weight: .medium)
    loadingLabel.textColor = HardwayColors.label
    loadingOverlayView.addSubview(loadingLabel)

    loadingSpinner = NNLoadingSpinner()
    loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
    loadingSpinner.configure(with: .white)
    loadingOverlayView.addSubview(loadingSpinner)

    loadingErrorLabel = UILabel()
    loadingErrorLabel.translatesAutoresizingMaskIntoConstraints = false
    loadingErrorLabel.text = "Could not join table."
    loadingErrorLabel.font = .systemFont(ofSize: 15, weight: .regular)
    loadingErrorLabel.textColor = .systemRed
    loadingErrorLabel.textAlignment = .center
    loadingErrorLabel.numberOfLines = 0
    loadingErrorLabel.isHidden = true
    loadingOverlayView.addSubview(loadingErrorLabel)

    loadingRetryButton = UIButton(type: .system)
    loadingRetryButton.translatesAutoresizingMaskIntoConstraints = false
    loadingRetryButton.setTitle("Retry", for: .normal)
    loadingRetryButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    loadingRetryButton.addTarget(self, action: #selector(retryJoinTapped), for: .touchUpInside)
    loadingRetryButton.isHidden = true
    loadingOverlayView.addSubview(loadingRetryButton)

    NSLayoutConstraint.activate([
      loadingOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
      loadingOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      loadingOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      loadingOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      loadingLabel.centerXAnchor.constraint(equalTo: loadingOverlayView.centerXAnchor),
      loadingLabel.centerYAnchor.constraint(
        equalTo: loadingOverlayView.centerYAnchor, constant: -32),

      loadingSpinner.centerXAnchor.constraint(equalTo: loadingOverlayView.centerXAnchor),
      loadingSpinner.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 20),
      loadingSpinner.widthAnchor.constraint(equalToConstant: 44),
      loadingSpinner.heightAnchor.constraint(equalToConstant: 44),

      loadingErrorLabel.centerXAnchor.constraint(equalTo: loadingOverlayView.centerXAnchor),
      loadingErrorLabel.topAnchor.constraint(equalTo: loadingSpinner.bottomAnchor, constant: 24),
      loadingErrorLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: loadingOverlayView.leadingAnchor, constant: 24),
      loadingErrorLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: loadingOverlayView.trailingAnchor, constant: -24),

      loadingRetryButton.centerXAnchor.constraint(equalTo: loadingOverlayView.centerXAnchor),
      loadingRetryButton.topAnchor.constraint(
        equalTo: loadingErrorLabel.bottomAnchor, constant: 16),
    ])
  }

  private func attemptJoin() {
    loadingErrorLabel.isHidden = true
    loadingRetryButton.isHidden = true
    loadingLabel.text = "Loading table..."
    loadingLabel.isHidden = false
    loadingSpinner.isHidden = false

    let playerId = MultiplayerPlayerIdKey.value
    let displayName = MultiplayerDisplayNameKey.value

    // First fetch settings to get the starting bankroll for this table
    tableState.fetchSettings { [weak self] settings in
      guard let self = self else { return }
      // Get startingBankroll from settings, fallback to injectedBankroll if not set
      let balanceToUse: Int
      if let startingBankroll = settings[MultiplayerBlackjackKeys.Settings.startingBankroll]
        as? Int,
        startingBankroll > 0
      {
        balanceToUse = startingBankroll
      } else {
        balanceToUse = self.injectedBankroll
      }
      self.joinedBalance = balanceToUse

      // Table structure is created by the createTable Cloud Function.
      // Ensure seat colors exist (safe no-op if they already do), then join.
      self.tableState.initializeTableIfNeeded { [weak self] result in
        guard let self = self else { return }
        switch result {
        case .success:
          self.tableState.joinTable(
            playerId: playerId, displayName: displayName, balance: balanceToUse, chipColorName: ""
          ) { [weak self] result in
            DispatchQueue.main.async {
              guard let self = self else { return }
              switch result {
              case .success((let seatIndex, let colorName)):
                print(
                  "✅ [MultiplayerBlackjack] Join successful: seatIndex=\(seatIndex), colorName='\(colorName)'"
                )
                self.mySeatIndex = seatIndex
                self.myDisplayName = displayName
                self.myChipColorName = colorName
                self.joinedBalance = balanceToUse
                self.setupGameplayUI()
                self.tableState.ensureGameNodeExistsIfNeeded()
                self.loadingOverlayView.isHidden = true
              case .failure:
                self.loadingLabel.isHidden = true
                self.loadingSpinner.isHidden = true
                self.loadingErrorLabel.isHidden = false
                self.loadingRetryButton.isHidden = false
              }
            }
          }
        case .failure:
          self.loadingLabel.isHidden = true
          self.loadingSpinner.isHidden = true
          self.loadingErrorLabel.isHidden = false
          self.loadingRetryButton.isHidden = false
        }
      }
    }
  }

  @objc private func retryJoinTapped() {
    attemptJoin()
  }

  // MARK: - Gameplay UI (after join success)

  private func setupGameplayUI() {
    setupInstructionLabel()
    setupDeckView()
    setupDealerHandView()
    setupSeatsContainer()
    setupBalanceView()
    setupChipSelector()
    setupBottomStackView()
    setupActionButtons()
    setupConnectionStatusView()

    defaultSeat.nameText = displayLabel(name: myDisplayName, playerId: MultiplayerPlayerIdKey.value)
    balance = joinedBalance

    // Update chipSelector color immediately (chips are created in init, so they exist)
    updateChipSelectorColor(myChipColorName)

    // Also update after layout as a backup
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.updateChipSelectorColor(self.myChipColorName)
    }

    deckView.setCardCount(52, animated: false)

    defaultSeat.primaryHand.handView.showsEmptyPlaceholders = false
    defaultSeat.primaryHand.handView.clearCards()
    wireHandTapHandlers(for: defaultSeat.primaryHand, handIndex: 0)

    seatsObserverHandle = tableState.observeSeats { [weak self] seatsWithIndices in
      guard let self = self else { return }
      self.reconcileSeats(seatsWithIndices)
      // Re-apply cards when seats update during active play (e.g. new card from hit).
      // Only during player_actions (not during betting→player_actions transition) to avoid
      // racing with the initial deal animation.
      if !self.isDealAnimationRunning,
        let snapshot = self.lastGameSnapshot,
        snapshot.phase == MultiplayerBlackjackKeys.Phases.playerActions
      {
        // Check if this is an initial deal transition - if so, skip applying cards here
        // because runInitialDealAnimation will handle it
        let isInitialDeal = self.isInitialDealSnapshot(
          snapshot, previous: self.previousGameSnapshot)
        if !isInitialDeal {
          let deckCenter = self.view.convert(self.deckView.deckCenter, from: self.deckView)
          self.applyCardsWithoutDealAnimation(snapshot: snapshot, deckCenter: deckCenter)
        }
      }
    }
    // Sync immediately with same parsing as observeSeats so second player sees first (no raw cast / NSDictionary miss)
    tableState.getSeatsWithIndices { [weak self] seatsWithIndices in
      self?.reconcileSeats(seatsWithIndices)
      self?.hasCompletedInitialJoin = true
    }

    gameStateObserverHandle = tableState.observeGameState { [weak self] snapshot in
      self?.applyGameStateSnapshot(snapshot)
    }

    hostPlayerIdObserverHandle = tableState.observeHostPlayerId { [weak self] hostPlayerId in
      guard let self = self else { return }
      self.currentHostPlayerId = hostPlayerId
      self.recomputeHostStatus()
    }

    settingsObserverHandle = tableState.observeSettings { [weak self] settings in
      guard let self = self else { return }
      if let sideBets = settings[MultiplayerBlackjackKeys.Settings.selectedSideBets] as? [String],
        let firstBet = sideBets.first, firstBet != self.currentSelectedSideBet
      {
        self.currentSelectedSideBet = firstBet
        let desc = self.descriptionsForSideBets([firstBet]).first ?? ""
        self.mpBonusBetControl.configure(title: firstBet, description: desc)
        self.previousBonusBetsBySeat.removeAll()
      }
    }
  }

  deinit {
    if let handle = seatsObserverHandle {
      tableState?.removeSeatsObserver(handle: handle)
    }
    if let handle = gameStateObserverHandle {
      tableState?.removeGameStateObserver(handle: handle)
    }
    if let handle = hostPlayerIdObserverHandle {
      tableState?.removeHostPlayerIdObserver(handle: handle)
    }
    if let handle = settingsObserverHandle {
      tableState?.removeSettingsObserver(handle: handle)
    }
    removeConnectionObserver()
  }

  private func loadTableCode() -> String {
    injectedTableCode
  }

  // MARK: - Setup

  private func applyHandsToSeat(
    _ seat: PlayerSeat, hands: [MPBlackjackTableState.HandData],
    previousHands: [MPBlackjackTableState.HandData]? = nil, animated: Bool = false
  ) {
    let phase = lastGameSnapshot?.phase ?? ""
    let isBettingOrIdlePhase =
      phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting

    for (i, handData) in hands.enumerated() {
      let handView: CompactPlayerHandView
      if i < seat.hands.count {
        handView = seat.hands[i]
      } else {
        continue
      }
      // If a hand is already busted outside betting, keep its chip hidden.
      let newBet = (handData.busted && !isBettingOrIdlePhase) ? 0 : handData.bet
      let oldBet =
        (previousHands != nil && i < previousHands!.count)
        ? previousHands![i].bet : handView.betControl.betAmount

      if newBet != oldBet {
        if animated && seat.isRemote && newBet > oldBet && i == 0 {
          let delta = newBet - oldBet
          animateChipToBet(for: seat, amount: delta) { [weak self] in
            handView.betControl.setBetAmount(newBet, animated: true)
            self?.animateBetChipUpdate(for: seat)
          }
        } else {
          handView.betControl.setBetAmount(newBet, animated: animated)
        }
      }
    }
  }

  private func animateBetChipUpdate(for seat: PlayerSeat) {
    guard let chip = seat.primaryHand.betControl.betView as? MPSmallBetChip else { return }
    chip.layoutIfNeeded()

    // Scale animation (same as PassLineTwoPlayerControl)
    let originalTransform = chip.transform
    UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut]) {
      chip.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
    } completion: { _ in
      UIView.animate(
        withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5,
        options: .curveEaseInOut
      ) {
        chip.transform = originalTransform
      }
    }

    // Shimmer effect
    chip.playChipShimmer()
  }

  private func animateChipToBet(for seat: PlayerSeat, amount: Int, completion: @escaping () -> Void)
  {
    guard let balanceView = seat.subviews.compactMap({ $0 as? MPPlayerBalanceView }).first else {
      completion()
      return
    }

    // Ensure layout is up to date
    view.layoutIfNeeded()
    seat.layoutIfNeeded()
    seat.primaryHand.layoutIfNeeded()
    seat.primaryHand.betControl.layoutIfNeeded()

    // Get start point (balance view center)
    let balanceFrame = balanceView.frame
    let startPoint = seat.convert(CGPoint(x: balanceFrame.midX, y: balanceFrame.midY), to: view)

    // Get end point (bet chip center on the bet control)
    // The betView is the actual chip inside the bet control
    let betChip = seat.primaryHand.betControl.betView!
    let betChipFrame: CGRect = betChip.frame
    let endPoint = seat.primaryHand.betControl.convert(
      CGPoint(x: betChipFrame.midX, y: betChipFrame.midY), to: view)

    // Create dot with color matching the player's chip style
    let dotView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
    dotView.backgroundColor = seat.chipStyle.textColor
    dotView.layer.cornerRadius = 4
    dotView.center = startPoint
    dotView.alpha = 0

    dotView.layer.shadowColor = UIColor.black.cgColor
    dotView.layer.shadowOpacity = 0.3
    dotView.layer.shadowRadius = 2
    dotView.layer.shadowOffset = CGSize(width: 0, height: 1)

    view.addSubview(dotView)
    view.bringSubviewToFront(dotView)

    // Animate
    let animator = UIViewPropertyAnimator(
      duration: 0.25,
      controlPoint1: CGPoint(x: 0.85, y: 0),
      controlPoint2: CGPoint(x: 0.15, y: 1)
    ) {
      dotView.center = endPoint
      dotView.alpha = 1.0
      dotView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3).rotated(by: .pi / 4)
    }

    // Update bet at 99% of animation
    let updateDelay = 0.25 * 0.99
    DispatchQueue.main.asyncAfter(deadline: .now() + updateDelay) {
      completion()
    }

    animator.addCompletion { _ in
      dotView.removeFromSuperview()
    }

    animator.startAnimation()
  }

  private func syncHandsToFirebase(for seat: PlayerSeat) {
    let playerId = MultiplayerPlayerIdKey.value

    // Collect all hands with their bet amounts
    var hands: [MPBlackjackTableState.HandData] = []
    for handView in seat.hands {
      let betAmount = handView.betControl.betAmount
      if betAmount > 0 {
        hands.append(
          MPBlackjackTableState.HandData(
            bet: betAmount, cards: [], stood: false, doubled: false, busted: false,
            playerId: playerId))
      }
    }

    let totalBet = hands.reduce(0) { $0 + $1.bet }
    print("🟡 [syncHandsToFirebase] Writing betAmount=\(totalBet) to Firebase (from UI betControl)")

    // Sync to Firebase
    tableState?.updateHands(playerId: playerId, hands: hands)
    tableState?.updateBalance(playerId: playerId, balance: balance)
  }

  private func setupBetControlCallbacks(for seat: PlayerSeat) {
    let betControl = seat.primaryHand.betControl

    betControl.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 5
    }

    betControl.getBalance = { [weak self] in
      return self?.balance ?? 0
    }

    betControl.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      let phase = self.lastGameSnapshot?.phase ?? ""
      let canPlaceBet = phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting
      if !canPlaceBet {
        seat.primaryHand.betControl.betAmount -= amount
        HapticsHelper.lightHaptic()
        return
      }
      // Optimistic: deduct immediately so the UI feels instant
      let expectedBalance = self.balance - amount
      self.isBalanceFrozenForBetOperation = true
      self.expectedBalanceAfterBetOperation = expectedBalance
      self.balance -= amount
      self.callPlaceBet(amount: amount, seat: seat) { [weak self] success in
        guard let self = self else { return }
        if success {
          // Backend placeBet already updated Firebase correctly, so we don't need syncHandsToFirebase
          // The Firebase listener will update the UI when the change propagates
          // Clear the freeze flag once we get confirmation (or after timeout)
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.isBalanceFrozenForBetOperation = false
            self?.expectedBalanceAfterBetOperation = nil
          }
          print("✅ [placeBet] Success - backend updated Firebase, no need to sync")
        } else {
          // Rollback both the bet chip and the balance
          seat.primaryHand.betControl.betAmount -= amount
          self.balance += amount
          self.isBalanceFrozenForBetOperation = false
          self.expectedBalanceAfterBetOperation = nil
        }
      }
    }

    betControl.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      let phase = self.lastGameSnapshot?.phase ?? ""
      let canRemoveBet = phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting
      if !canRemoveBet {
        seat.primaryHand.betControl.betAmount += amount
        HapticsHelper.lightHaptic()
        return
      }
      // Optimistic: restore balance immediately so the UI feels instant
      let expectedBalance = self.balance + amount
      self.isBalanceFrozenForBetOperation = true
      self.expectedBalanceAfterBetOperation = expectedBalance
      self.balance += amount
      self.callRemoveBet(amount: amount, seat: seat) { [weak self] success, _ in
        guard let self = self else { return }
        if success {
          // Backend removeBet already updated Firebase correctly, so we don't need syncHandsToFirebase
          // The Firebase listener will update the UI when the change propagates
          // Clear the freeze flag once we get confirmation (or after timeout)
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.isBalanceFrozenForBetOperation = false
            self?.expectedBalanceAfterBetOperation = nil
          }
          print("✅ [removeBet] Success - backend updated Firebase, no need to sync")
        } else {
          // Rollback both the bet chip and the balance
          seat.primaryHand.betControl.betAmount += amount
          self.balance -= amount
          self.isBalanceFrozenForBetOperation = false
          self.expectedBalanceAfterBetOperation = nil
        }
      }
    }
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

  /// Dealer hand top: anchor to view so it actually moves. Smaller constant = closer to top.
  private var dealerHandTopConstraint: NSLayoutConstraint?

  private func setupDealerHandView() {
    dealerHandView.translatesAutoresizingMaskIntoConstraints = false
    dealerHandView.isUserInteractionEnabled = true
    dealerHandView.clipsToBounds = false
    view.addSubview(dealerHandView)

    dealerHandTopConstraint?.isActive = false
    dealerHandTopConstraint = dealerHandView.topAnchor.constraint(
      equalTo: deckView.bottomAnchor, constant: -28)
    dealerHandTopConstraint?.priority = .required
    NSLayoutConstraint.activate([
      dealerHandView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      dealerHandView.heightAnchor.constraint(equalToConstant: 100),
      dealerHandTopConstraint!,
    ])
    view.setNeedsLayout()
    view.layoutIfNeeded()
  }

  private func setupSeatsContainer() {
    seatsContainerView = UIView()
    seatsContainerView.translatesAutoresizingMaskIntoConstraints = false
    seatsContainerView.backgroundColor = .clear

    seatsScrollView = UIScrollView()
    seatsScrollView.translatesAutoresizingMaskIntoConstraints = false
    seatsScrollView.showsHorizontalScrollIndicator = true
    seatsScrollView.showsVerticalScrollIndicator = false
    seatsScrollView.alwaysBounceHorizontal = true
    seatsScrollView.alwaysBounceVertical = false
    seatsScrollView.delaysContentTouches = false
    seatsScrollView.clipsToBounds = false
    seatsScrollView.delegate = self

    seatsStackView = UIStackView()
    seatsStackView.translatesAutoresizingMaskIntoConstraints = false
    seatsStackView.axis = .horizontal
    seatsStackView.alignment = .bottom
    seatsStackView.spacing = 16
    seatsStackView.distribution = .fill

    // Spacer view to add bottom padding without affecting scrollable content size
    let bottomSpacer = UIView()
    bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
    bottomSpacer.isUserInteractionEnabled = false

    defaultSeat = PlayerSeat(chipStyle: chipStyleForColorName(myChipColorName))
    defaultSeat.translatesAutoresizingMaskIntoConstraints = false
    defaultSeat.nameText = displayLabel(name: myDisplayName, playerId: MultiplayerPlayerIdKey.value)
    defaultSeat.setBalance(joinedBalance, animated: false)
    defaultSeat.isRemote = false
    defaultSeat.installWidthConstraint(constant: seatWidth)
    seatViewsByIndex[mySeatIndex] = defaultSeat

    // Wire up bet control callbacks
    setupBetControlCallbacks(for: defaultSeat)
    setupBonusBetControlCallbacks()

    view.addSubview(seatsContainerView)
    seatsContainerView.addSubview(seatsScrollView)
    seatsScrollView.addSubview(seatsStackView)
    seatsScrollView.addSubview(bottomSpacer)

    // Turn indicator: small yellow dot above the current player's hand
    let dotSize: CGFloat = 10
    turnIndicatorDot = UIView()
    turnIndicatorDot.translatesAutoresizingMaskIntoConstraints = false
    turnIndicatorDot.backgroundColor = HardwayColors.yellow
    turnIndicatorDot.layer.cornerRadius = dotSize / 2
    turnIndicatorDot.layer.masksToBounds = true
    turnIndicatorDot.isHidden = true
    turnIndicatorDot.isUserInteractionEnabled = false
    seatsContainerView.addSubview(turnIndicatorDot)
    turnIndicatorDotCenterXConstraint = turnIndicatorDot.centerXAnchor.constraint(
      equalTo: seatsContainerView.leadingAnchor, constant: 0)
    NSLayoutConstraint.activate([
      turnIndicatorDot.topAnchor.constraint(equalTo: seatsContainerView.topAnchor, constant: 4),
      turnIndicatorDot.widthAnchor.constraint(equalToConstant: dotSize),
      turnIndicatorDot.heightAnchor.constraint(equalToConstant: dotSize),
      turnIndicatorDotCenterXConstraint!,
    ])

    // Bonus bet control (visible from betting through play until reconciled)
    view.addSubview(mpBonusBetControl)
    let desc = descriptionsForSideBets([currentSelectedSideBet]).first ?? ""
    mpBonusBetControl.configure(title: currentSelectedSideBet, description: desc)
    mpBonusBetControl.localChipStyle = chipStyleForColorName(myChipColorName)

    // Insurance control (hidden by default, shown when dealer upcard is Ace)
    view.addSubview(mpInsuranceControl)

    NSLayoutConstraint.activate([
      mpBonusBetControl.topAnchor.constraint(equalTo: dealerHandView.bottomAnchor, constant: 20),
      mpBonusBetControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      mpBonusBetControl.widthAnchor.constraint(equalToConstant: 250),
      mpBonusBetControl.heightAnchor.constraint(equalToConstant: 55),

      mpInsuranceControl.topAnchor.constraint(equalTo: mpBonusBetControl.bottomAnchor, constant: 8),
      mpInsuranceControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      mpInsuranceControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      mpInsuranceControl.heightAnchor.constraint(equalToConstant: 55),

      seatsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      seatsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      seatsContainerView.heightAnchor.constraint(equalToConstant: 220),

      seatsScrollView.topAnchor.constraint(equalTo: seatsContainerView.topAnchor),
      seatsScrollView.leadingAnchor.constraint(equalTo: seatsContainerView.leadingAnchor),
      seatsScrollView.trailingAnchor.constraint(equalTo: seatsContainerView.trailingAnchor),
      seatsScrollView.bottomAnchor.constraint(equalTo: seatsContainerView.bottomAnchor),

      seatsStackView.topAnchor.constraint(equalTo: seatsScrollView.contentLayoutGuide.topAnchor),
      seatsStackView.leadingAnchor.constraint(
        equalTo: seatsScrollView.contentLayoutGuide.leadingAnchor),
      seatsStackView.trailingAnchor.constraint(
        equalTo: seatsScrollView.contentLayoutGuide.trailingAnchor),
      seatsStackView.heightAnchor.constraint(
        equalTo: seatsScrollView.frameLayoutGuide.heightAnchor, constant: -8),

      bottomSpacer.topAnchor.constraint(equalTo: seatsStackView.bottomAnchor),
      bottomSpacer.leadingAnchor.constraint(
        equalTo: seatsScrollView.contentLayoutGuide.leadingAnchor),
      bottomSpacer.trailingAnchor.constraint(
        equalTo: seatsScrollView.contentLayoutGuide.trailingAnchor),
      bottomSpacer.bottomAnchor.constraint(
        equalTo: seatsScrollView.contentLayoutGuide.bottomAnchor),
      bottomSpacer.heightAnchor.constraint(equalToConstant: 8),
    ])
  }

  /// Scroll the scrollView to show the seat at the given index
  private func scrollToSeat(_ seatIndex: Int, animated: Bool = true) {
    guard let seatView = seatViewsByIndex[seatIndex] else { return }
    isProgrammaticScroll = true
    let seatRect = seatView.convert(seatView.bounds, to: seatsScrollView)
    seatsScrollView.scrollRectToVisible(seatRect, animated: animated)
    // Reset flag after a short delay to allow scroll animation to complete
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      self?.isProgrammaticScroll = false
    }
  }

  /// Scroll the scrollView to show a specific hand within a seat (for split hands)
  private func scrollToSeatHand(_ seatIndex: Int, handIndex: Int = 0, animated: Bool = true) {
    guard let seatView = seatViewsByIndex[seatIndex] else { return }
    isProgrammaticScroll = true

    // If the seat has multiple hands and handIndex is valid, scroll to that specific hand
    // Otherwise, scroll to the entire seat
    let targetView: UIView
    if seatView.hands.count > 1, handIndex < seatView.hands.count {
      targetView = seatView.hands[handIndex]
    } else {
      targetView = seatView
    }

    let targetRect = targetView.convert(targetView.bounds, to: seatsScrollView)
    seatsScrollView.scrollRectToVisible(targetRect, animated: animated)
    // Reset flag after a short delay to allow scroll animation to complete
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      self?.isProgrammaticScroll = false
    }
  }

  /// Position and show the yellow turn-indicator dot above the current player's hand; animate horizontal movement when turn changes.
  /// When `handIndex` > 0 and the seat has split hands, the dot centers over the specific hand view.
  private func updateTurnIndicatorDot(
    for seatIndex: Int?, handIndex: Int = 0, animated: Bool = true
  ) {
    guard !isDealAnimationRunning else {
      hideTurnIndicatorDot()
      return
    }
    guard let seatIndex = seatIndex,
      let seat = seatViewsByIndex[seatIndex],
      let constraint = turnIndicatorDotCenterXConstraint
    else {
      hideTurnIndicatorDot()
      return
    }
    seatsContainerView.layoutIfNeeded()

    let targetView: UIView
    if seat.hands.count > 1, handIndex < seat.hands.count {
      targetView = seat.hands[handIndex]
    } else {
      targetView = seat
    }
    let centerInContainer = seatsContainerView.convert(
      CGPoint(x: targetView.bounds.midX, y: targetView.bounds.midY), from: targetView)

    let wasHidden = turnIndicatorDot.isHidden
    if wasHidden {
      constraint.constant = centerInContainer.x
      turnIndicatorDot.isHidden = false
      turnIndicatorDot.alpha = 0
      turnIndicatorDot.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
    }
    let applyPosition = {
      constraint.constant = centerInContainer.x
      self.seatsContainerView.layoutIfNeeded()
      if wasHidden {
        self.turnIndicatorDot.alpha = 1
        self.turnIndicatorDot.transform = .identity
      }
    }
    if animated {
      UIView.animate(
        withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5
      ) {
        applyPosition()
      }
    } else {
      applyPosition()
    }
  }

  private func hideTurnIndicatorDot() {
    guard !turnIndicatorDot.isHidden else { return }
    UIView.animate(withDuration: 0.2) {
      self.turnIndicatorDot.alpha = 0
    } completion: { _ in
      self.turnIndicatorDot.isHidden = true
      self.turnIndicatorDot.alpha = 1
    }
  }

  // MARK: - Split Button Positioning

  private var splitButtonHideGeneration: Int = 0

  private func showSplitButton(above handView: CompactPlayerHandView) {
    splitButtonHideGeneration += 1
    splitButton.layer.removeAllAnimations()
    splitButton.isHidden = false
    repositionSplitButton(above: handView)
    if splitButton.alpha >= 1 && splitButton.transform == .identity {
      return
    }
    splitButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
    UIView.animate(
      withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5
    ) {
      self.splitButton.alpha = 1
      self.splitButton.transform = .identity
    }
  }

  private func hideSplitButton() {
    guard !splitButton.isHidden else { return }
    splitButtonHideGeneration += 1
    let gen = splitButtonHideGeneration
    UIView.animate(
      withDuration: 0.15,
      animations: {
        self.splitButton.alpha = 0
      }
    ) { _ in
      guard self.splitButtonHideGeneration == gen else { return }
      self.splitButton.isHidden = true
    }
  }

  private func repositionSplitButton(above handView: CompactPlayerHandView) {
    splitButton.translatesAutoresizingMaskIntoConstraints = true
    let center = seatsContainerView.convert(
      CGPoint(x: handView.bounds.midX, y: handView.bounds.minY), from: handView)
    splitButton.bounds.size = CGSize(width: 48, height: 48)
    splitButton.center = CGPoint(x: center.x, y: center.y - 32)
    splitButton.layer.cornerRadius = 24
  }

  // MARK: - Hand View Reconciliation

  /// Ensure the seat has the correct number of CompactPlayerHandViews to match Firebase hand count.
  private func reconcileHandViews(seat: PlayerSeat, seatIndex: Int, firebaseHandCount: Int) {
    let currentCount = seat.hands.count
    if firebaseHandCount > currentCount {
      for i in currentCount..<firebaseHandCount {
        let newHand = seat.addHand(chipStyle: seat.chipStyle)
        newHand.handView.showsEmptyPlaceholders = false
        newHand.handView.clearCards()
        if seatIndex == mySeatIndex {
          wireHandTapHandlers(for: newHand, handIndex: i)
        }
        if let handsData = currentSeatsData[seatIndex]?.hands, i < handsData.count {
          newHand.betControl.betAmount = handsData[i].bet
        }
      }
      // Animate the stack expanding
      UIView.animate(
        withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5
      ) {
        seat.layoutIfNeeded()
        seat.superview?.layoutIfNeeded()
      }
    } else if firebaseHandCount < currentCount && firebaseHandCount == 1 {
      seat.removeAllAdditionalHands()
    }
  }

  // MARK: - Per-Hand Tap Handling

  /// Wire onTap/canTap closures on a hand view so tap-to-hit works per hand index.
  private func wireHandTapHandlers(for handView: CompactPlayerHandView, handIndex: Int) {
    handView.onTap = { [weak self] in
      guard let self = self else { return }
      self.handleHandTap(for: self.defaultSeat)
    }
    handView.canTap = { [weak self, handIndex] in
      guard let self = self else { return false }
      let snapshot = self.lastGameSnapshot
      let turn = snapshot?.currentTurn
      let isMySeat = turn?.seatIndex == self.mySeatIndex
      let isMyHand = turn?.handIndex == handIndex
      let isPlayerActions = snapshot?.phase == MultiplayerBlackjackKeys.Phases.playerActions
      return isMySeat && isMyHand && isPlayerActions
    }
  }

  /// Returns displayName unless it's empty or "Player", then first 5 chars of playerId.
  private func displayLabel(name: String, playerId: String) -> String {
    if !name.isEmpty && name != "Player" { return name }
    return String(playerId.prefix(5))
  }

  private func configureSeatAsPlayer(
    _ seat: PlayerSeat, displayName: String, balance: Int, isRemote: Bool,
    needsPlaceholderCards: Bool = true
  ) {
    seat.isRemote = isRemote
    seat.nameText = displayName
    seat.setBalance(balance, animated: true)

    // Only set placeholder cards if requested (we'll set them after layout for new seats)
    if needsPlaceholderCards {
      seat.primaryHand.handView.showsEmptyPlaceholders = false
      seat.primaryHand.handView.clearCards()
    }
    seat.alpha = 1.0
  }

  private func recomputeHostStatus() {
    let myPlayerId = MultiplayerPlayerIdKey.value
    let wasHost = isHost
    isHost = (currentHostPlayerId == myPlayerId)
    if wasHost != isHost {
      print(
        "👑 [MultiplayerBlackjack] Host status changed: \(isHost ? "I am host" : "I am not host") (hostPlayerId=\(currentHostPlayerId ?? "nil"), myId=\(myPlayerId))"
      )
      if isHost && !wasHost && hasCompletedInitialJoin {
        instructionLabel.showMessage("You are now the host", shouldFade: true, duration: 3.0)
      }
    }
    // Always refresh buttons when seats change.
    // If lastGameSnapshot is nil (cleared between hands) and we just became host,
    // fetch the current game state so the host buttons (Deal / Next Hand) appear immediately.
    if let snapshot = lastGameSnapshot {
      refreshButtonVisibility(for: snapshot)
    } else if isHost && !wasHost {
      tableState?.fetchGameState { [weak self] snapshot in
        guard let self = self else { return }
        self.lastGameSnapshot = snapshot
        self.refreshButtonVisibility(for: snapshot)
      }
    }
  }

  private func reconcileSeats(
    _ seatsWithIndices: [(seatIndex: Int, seatData: MPBlackjackTableState.SeatData)]
  ) {
    let myPlayerId = MultiplayerPlayerIdKey.value

    // Check if current player was removed from the table (only after initial join)
    // When a player is removed, their seat still exists but playerId is cleared (nil)
    if hasCompletedInitialJoin {
      if let mySeatEntry = seatsWithIndices.first(where: { $0.seatIndex == mySeatIndex }) {
        let mySeatData = mySeatEntry.seatData
        // If the seat exists but playerId is nil or doesn't match, we were removed
        if mySeatData.playerId == nil || mySeatData.playerId != myPlayerId {
          handlePlayerRemoved()
          return
        }
      } else {
        // Seat doesn't exist at all - player was removed
        handlePlayerRemoved()
        return
      }
    }

    // Store current seats data for use in animations
    currentSeatsData = Dictionary(
      uniqueKeysWithValues: seatsWithIndices.map { ($0.seatIndex, $0.seatData) })
    recomputeHostStatus()

    // Track which seats currently have players
    let currentSeatIndices = Set(seatsWithIndices.map { $0.seatIndex })

    // Remove seats that no longer have players (except our own seat)
    var indicesToRemove: [Int] = []
    for (idx, _) in seatViewsByIndex {
      if !currentSeatIndices.contains(idx) && idx != mySeatIndex {
        indicesToRemove.append(idx)
      }
    }
    for idx in indicesToRemove {
      guard let seat = seatViewsByIndex.removeValue(forKey: idx), seat !== defaultSeat else {
        continue
      }
      // Animate seat removal
      UIView.animate(
        withDuration: 0.3, delay: 0, options: .curveEaseOut,
        animations: {
          seat.alpha = 0
          seat.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }
      ) { _ in
        seat.removeFromSuperview()
      }
    }

    // Apply player data to occupied seats and create new seats as needed
    for (seatIndex, data) in seatsWithIndices {
      if data.playerId == myPlayerId, seatIndex == mySeatIndex {
        let isNewSetup = seatViewsByIndex[seatIndex] !== defaultSeat
        seatViewsByIndex[seatIndex] = defaultSeat
        defaultSeat.isRemote = false
        defaultSeat.nameText = data.displayLabel
        // Server balance is source of truth, but skip the update while settlement
        // animations are playing — the animation completions apply the balance directly.
        // Also skip during optimistic bet operations to prevent overriding local-first updates.
        if !isBalanceFrozenForSettlement && !isBalanceFrozenForBetOperation {
          // If we have an expected balance from an optimistic operation, only apply Firebase
          // balance if it matches our expectation (backend confirmed) or is significantly different
          // (indicating a real change from another source)
          if let expected = expectedBalanceAfterBetOperation {
            if data.balance == expected {
              // Backend confirmed our optimistic update - clear the flag and apply
              print(
                "BAL_BUG [observeSeats] Firebase balance \(data.balance) matches expected \(expected) — confirming optimistic update"
              )
              isBalanceFrozenForBetOperation = false
              expectedBalanceAfterBetOperation = nil
              balance = data.balance
            } else {
              // Firebase balance doesn't match expected - might be stale or from another source
              // Keep optimistic update for now, will be corrected by next update
              print(
                "BAL_BUG [observeSeats] SKIPPED Firebase balance \(data.balance) — doesn't match expected \(expected) (current: \(balance))"
              )
            }
          } else {
            print(
              "BAL_BUG [observeSeats] applying Firebase balance: \(data.balance) (was \(balance))")
            balance = data.balance
          }
        } else {
          let reason = isBalanceFrozenForSettlement ? "settlement frozen" : "bet operation frozen"
          print(
            "BAL_BUG [observeSeats] SKIPPED Firebase balance \(data.balance) — \(reason) (current: \(balance))"
          )
        }
        if isNewSetup {
          defaultSeat.primaryHand.handView.showsEmptyPlaceholders = false
          defaultSeat.primaryHand.handView.clearCards()
          wireHandTapHandlers(for: defaultSeat.primaryHand, handIndex: 0)
        }
        defaultSeat.alpha = 1.0

        if myChipColorName != data.chipColorName {
          print(
            "🎨 [MultiplayerBlackjack] Chip color changed from '\(myChipColorName)' to '\(data.chipColorName)'"
          )
          myChipColorName = data.chipColorName
        }
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          self.updateChipSelectorColor(data.chipColorName)
        }
        
        // Sync bets from Firebase for local player only during betting/idle.
        // Outside betting, settlement/player-action animations own chip visibility.
        if !data.hands.isEmpty {
          let phase = lastGameSnapshot?.phase ?? ""
          let isBettingOrIdlePhase =
            phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting
          if isBettingOrIdlePhase {
            let firebaseBet = data.hands[0].bet
            let currentBet = defaultSeat.primaryHand.betControl.betAmount
            if firebaseBet != currentBet {
              defaultSeat.primaryHand.betControl.setBetAmount(firebaseBet, animated: false)
              print("💰 [reconcileSeats] Syncing local player bet from Firebase: \(firebaseBet) (was \(currentBet))")
            }
          }
        }
        
        continue
      }

      // Remote player seat - create if needed
      if let existingSeat = seatViewsByIndex[seatIndex], existingSeat !== defaultSeat {
        // Existing seat - update it incrementally (avoid full reconfiguration)
        // Only update balance if it changed (or if we haven't tracked it yet)
        let previousBalance = previousBalanceByIndex[seatIndex]
        if previousBalance == nil || previousBalance != data.balance {
          existingSeat.setBalance(data.balance, animated: true)
          previousBalanceByIndex[seatIndex] = data.balance
        }
        // Only update name if it changed
        if existingSeat.nameText != data.displayLabel {
          existingSeat.nameText = data.displayLabel
        }
        // Update bet amounts from hands with animation
        let previousHands = previousHandsByIndex[seatIndex]
        applyHandsToSeat(
          existingSeat, hands: data.hands, previousHands: previousHands, animated: true)
        previousHandsByIndex[seatIndex] = data.hands
      } else {
        // New remote seat - create but defer placeholder cards until after it's in the view hierarchy
        let remoteSeat = PlayerSeat(chipStyle: chipStyleForColorName(data.chipColorName))
        remoteSeat.translatesAutoresizingMaskIntoConstraints = false
        remoteSeat.installWidthConstraint(constant: seatWidth)
        configureSeatAsPlayer(
          remoteSeat, displayName: data.displayLabel, balance: data.balance, isRemote: true,
          needsPlaceholderCards: false)
        seatViewsByIndex[seatIndex] = remoteSeat
        // Initialize previousBalanceByIndex so future balance updates are detected
        previousBalanceByIndex[seatIndex] = data.balance
        
        // Play haptic when a new player joins (only after initial join is complete to avoid triggering on our own join)
        if hasCompletedInitialJoin {
          HapticsHelper.superLightHaptic()
        }
      }
    }

    // Only rebuild stack if seats were added or removed
    let currentStackIndices = seatsStackView.arrangedSubviews.compactMap { view -> Int? in
      seatViewsByIndex.first(where: { $0.value === view })?.key
    }.sorted()
    let newStackIndices = seatViewsByIndex.keys.sorted()
    let needsRebuild = currentStackIndices != newStackIndices || !indicesToRemove.isEmpty

    if needsRebuild {
      // Rebuild the stack view with only seats that have players (in seat index order)
      for v in seatsStackView.arrangedSubviews {
        seatsStackView.removeArrangedSubview(v)
        // Don't remove from superview here if it's being animated out
        if !indicesToRemove.contains(where: { seatViewsByIndex[$0] === v }) {
          v.removeFromSuperview()
        }
      }

      // Add seats in seat index order, but only those with players
      let sortedIndices = seatViewsByIndex.keys.sorted()
      var newlyAddedSeats: [PlayerSeat] = []
      for i in sortedIndices {
        if let seatView = seatViewsByIndex[i] {
          // Fade in new seats
          let isNewSeat =
            seatView !== defaultSeat && !seatsStackView.arrangedSubviews.contains(seatView)
          if isNewSeat {
            seatView.alpha = 0
            seatView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
          }

          seatsStackView.addArrangedSubview(seatView)

          // Animate in new seat
          if isNewSeat {
            UIView.animate(
              withDuration: 0.4, delay: 0.1, usingSpringWithDamping: 0.7,
              initialSpringVelocity: 0.5, options: .curveEaseOut,
              animations: {
                seatView.alpha = 1.0
                seatView.transform = .identity
              })
          }

          // Track if this is a new remote seat that needs placeholder cards
          if seatView !== defaultSeat && seatView.primaryHand.currentCards.isEmpty {
            newlyAddedSeats.append(seatView)
          }

          // Update bet amounts for all remote seats
          if seatView !== defaultSeat,
            let seatData = seatsWithIndices.first(where: { $0.seatIndex == i })?.seatData
          {
            applyHandsToSeat(seatView, hands: seatData.hands)
          }
        }
      }

      // Animate the stack view layout changes
      UIView.animate(
        withDuration: 0.3, delay: 0, options: .curveEaseInOut,
        animations: {
          self.seatsStackView.layoutIfNeeded()
        })

      // Force layout of the entire seats hierarchy to ensure all views have valid frames
      seatsStackView.setNeedsLayout()
      seatsStackView.layoutIfNeeded()

      // NOW set placeholder cards on newly added remote seats (after they're laid out)
      for seat in newlyAddedSeats {
        seat.primaryHand.handView.showsEmptyPlaceholders = false
        seat.primaryHand.handView.clearCards()
      }

      // Scroll to user's hand if we're in betting phase (e.g., user just joined)
      if let snapshot = lastGameSnapshot,
        snapshot.phase == MultiplayerBlackjackKeys.Phases.betting
      {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
          guard let self = self else { return }
          self.scrollToSeat(self.mySeatIndex, animated: true)
        }
      }

      // Reposition the turn indicator dot after the stack view was rebuilt,
      // since seat views may have shifted when a player joined or left mid-hand.
      if let snapshot = lastGameSnapshot,
        snapshot.phase == MultiplayerBlackjackKeys.Phases.playerActions
      {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
          guard let self = self else { return }
          self.updateTurnIndicatorDot(
            for: self.lastGameSnapshot?.currentTurn?.seatIndex,
            handIndex: self.lastGameSnapshot?.currentTurn?.handIndex ?? 0, animated: true)
        }
      }
    }

    // Detect remote insurance bet changes and update MPInsuranceControl
    if isInsurancePhaseActive {
      for (seatIndex, seatData) in seatsWithIndices {
        let prevBet = previousInsuranceBySeat[seatIndex] ?? 0
        let newBet = seatData.insuranceBet

        if newBet != prevBet && seatIndex != mySeatIndex {
          let chipStyle = chipStyleForColorName(seatData.chipColorName)
          if newBet > 0 && prevBet == 0 {
            // Animate a dot from the remote player's seat to the insurance control
            if let remoteSeat = seatViewsByIndex[seatIndex] {
              let origin = view.convert(remoteSeat.center, from: remoteSeat.superview)
              let dotColor = chipStyle.strokeColor
              mpInsuranceControl.animateDotToChips(from: origin, in: view, dotColor: dotColor) {
                [weak self] in
                self?.mpInsuranceControl.addInsuranceBet(amount: newBet, chipStyle: chipStyle)
              }
            } else {
              mpInsuranceControl.addInsuranceBet(amount: newBet, chipStyle: chipStyle)
            }
          } else if newBet == 0 && prevBet > 0 {
            mpInsuranceControl.removeInsuranceBet(for: chipStyle)
          }
        }
        previousInsuranceBySeat[seatIndex] = newBet
      }

      checkIfAllPlayersDecidedInsurance()
    }

    // Detect bonus bet changes and update MPBonusBetControl.
    // Same pattern as applyHandsToSeat for CompactPlayerHandView: animate a dot for every
    // increment, not just the first. Local player's chip is managed directly by
    // handleBonusBetTapped/handleBonusBetDragRemoved.
    for (seatIndex, seatData) in seatsWithIndices {
      let prevAmount = previousBonusBetsBySeat[seatIndex] ?? 0
      let newAmount = seatData.bonusBets[0] ?? 0
      guard newAmount != prevAmount else { continue }
      let isLocalPlayer = (seatIndex == mySeatIndex)
      let chipStyle = chipStyleForColorName(seatData.chipColorName)
      if newAmount > prevAmount && !isLocalPlayer {
        if let remoteSeat = seatViewsByIndex[seatIndex],
          let balView = remoteSeat.subviews.compactMap({ $0 as? MPPlayerBalanceView }).first
        {
          let origin = remoteSeat.convert(
            CGPoint(x: balView.frame.midX, y: balView.frame.midY), to: view)
          let dotColor = chipStyle.strokeColor
          mpBonusBetControl.animateDotToChips(
            from: origin, in: view, dotColor: dotColor, chipStyle: chipStyle
          ) {
            [weak self] in
            self?.mpBonusBetControl.setBetAmount(amount: newAmount, chipStyle: chipStyle)
          }
        } else {
          mpBonusBetControl.setBetAmount(amount: newAmount, chipStyle: chipStyle)
        }
      } else if !isLocalPlayer {
        mpBonusBetControl.setBetAmount(amount: newAmount, chipStyle: chipStyle)
      }
      previousBonusBetsBySeat[seatIndex] = newAmount
    }

  }

  private func setupBalanceView() {
    balanceView = BalanceView()
  }

  private func setupChipSelector() {
    chipSelector = ChipSelector(compact: [1, 5, 25, 50, 100])
    chipSelector.delegate = self
    chipSelector.onBetReturned = { [weak self] amount in
      guard let self = self else { return }
      self.callRemoveBet(amount: amount, seat: self.defaultSeat) { [weak self] success, newBet in
        guard let self = self else { return }
        if success {
          if let newBet = newBet {
            self.defaultSeat.primaryHand.betControl.setBetAmount(newBet, animated: true)
          }
          self.syncHandsToFirebase(for: self.defaultSeat)
        } else {
          self.defaultSeat.primaryHand.betControl.betAmount += amount
        }
      }
    }
  }

  private func setupBottomStackView() {
    // Match CrapsGameplayViewController+Layout: stack sized to content, no width constraints
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

      seatsContainerView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -8),
    ])
  }

  private func setupActionButtons() {
    standButton.addTarget(self, action: #selector(standTapped), for: .touchUpInside)
    doubleButton.addTarget(self, action: #selector(doubleTapped), for: .touchUpInside)

    newHandButton = UIButton(type: .system)
    newHandButton.translatesAutoresizingMaskIntoConstraints = false
    newHandButton.setTitle("New Hand", for: .normal)
    newHandButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    newHandButton.backgroundColor = HardwayColors.surfaceGray
    newHandButton.setTitleColor(.white, for: .normal)
    newHandButton.layer.cornerRadius = 16
    newHandButton.layer.borderWidth = 1.5
    newHandButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
    newHandButton.isHidden = true
    newHandButton.alpha = 0
    newHandButton.addTarget(self, action: #selector(newHandTapped), for: .touchUpInside)

    dealButton = UIButton(type: .system)
    dealButton.translatesAutoresizingMaskIntoConstraints = false
    dealButton.setTitle("Deal", for: .normal)
    dealButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    dealButton.backgroundColor = HardwayColors.surfaceGray
    dealButton.setTitleColor(.white, for: .normal)
    dealButton.layer.cornerRadius = 16
    dealButton.layer.borderWidth = 1.5
    dealButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
    dealButton.addTarget(self, action: #selector(dealTapped), for: .touchUpInside)

    nextHandButton = UIButton(type: .system)
    nextHandButton.translatesAutoresizingMaskIntoConstraints = false
    nextHandButton.setTitle("Next Hand", for: .normal)
    nextHandButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    nextHandButton.backgroundColor = HardwayColors.surfaceGray
    nextHandButton.setTitleColor(.white, for: .normal)
    nextHandButton.layer.cornerRadius = 16
    nextHandButton.layer.borderWidth = 1.5
    nextHandButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
    nextHandButton.addTarget(self, action: #selector(nextHandTapped), for: .touchUpInside)

    continueButton = UIButton(type: .system)
    continueButton.translatesAutoresizingMaskIntoConstraints = false
    continueButton.setTitle("Continue", for: .normal)
    continueButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    continueButton.backgroundColor = HardwayColors.surfaceGray
    continueButton.setTitleColor(.white, for: .normal)
    continueButton.layer.cornerRadius = 16
    continueButton.layer.borderWidth = 1.5
    continueButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
    continueButton.addTarget(self, action: #selector(continueButtonTapped), for: .touchUpInside)

    let insuranceStatusLabel = UILabel()
    insuranceStatusLabel.translatesAutoresizingMaskIntoConstraints = false
    insuranceStatusLabel.textAlignment = .center
    insuranceStatusLabel.font = .systemFont(ofSize: 10, weight: .regular)
    insuranceStatusLabel.textColor = HardwayColors.label.withAlphaComponent(0.7)
    insuranceStatusLabel.tag = 999
    continueButton.addSubview(insuranceStatusLabel)

    NSLayoutConstraint.activate([
      insuranceStatusLabel.centerXAnchor.constraint(equalTo: continueButton.centerXAnchor),
      insuranceStatusLabel.topAnchor.constraint(
        equalTo: continueButton.titleLabel!.bottomAnchor, constant: 2),
      insuranceStatusLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: continueButton.leadingAnchor, constant: 4),
      insuranceStatusLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: continueButton.trailingAnchor, constant: -4),
    ])

    rightButtonStack = UIStackView()
    rightButtonStack.translatesAutoresizingMaskIntoConstraints = false
    rightButtonStack.axis = .vertical
    rightButtonStack.spacing = 8
    rightButtonStack.alignment = .fill
    rightButtonStack.distribution = .fillEqually
    rightButtonStack.addArrangedSubview(standButton)
    rightButtonStack.addArrangedSubview(doubleButton)

    view.addSubview(rightButtonStack)
    view.addSubview(newHandButton)
    view.addSubview(dealButton)
    view.addSubview(nextHandButton)
    view.addSubview(continueButton)

    NSLayoutConstraint.activate([
      rightButtonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      rightButtonStack.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
      rightButtonStack.topAnchor.constraint(equalTo: bottomStackView.topAnchor),
      rightButtonStack.widthAnchor.constraint(equalToConstant: 120),

      newHandButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      newHandButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
      newHandButton.topAnchor.constraint(equalTo: bottomStackView.topAnchor),
      newHandButton.widthAnchor.constraint(equalToConstant: 120),

      dealButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      dealButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
      dealButton.heightAnchor.constraint(equalToConstant: 98),
      dealButton.widthAnchor.constraint(equalToConstant: 120),

      nextHandButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      nextHandButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
      nextHandButton.heightAnchor.constraint(equalToConstant: 98),
      nextHandButton.widthAnchor.constraint(equalToConstant: 120),

      continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      continueButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
      continueButton.heightAnchor.constraint(equalToConstant: 98),
      continueButton.widthAnchor.constraint(equalToConstant: 120),
    ])

    rightButtonStack.isHidden = true
    rightButtonStack.alpha = 0
    dealButton.isHidden = true
    dealButton.alpha = 0
    nextHandButton.isHidden = true
    nextHandButton.alpha = 0
    continueButton.isHidden = true
    continueButton.alpha = 0

    splitButton.addTarget(self, action: #selector(splitTapped), for: .touchUpInside)
    splitButton.isHidden = true
    splitButton.alpha = 0
    seatsContainerView.addSubview(splitButton)
  }

  // MARK: - Connection status

  private func setupConnectionStatusView() {
    connectionStatusView = ConnectionStatusView()
    connectionStatusView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(connectionStatusView)

    NSLayoutConstraint.activate([
      connectionStatusView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      connectionStatusView.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
    ])

    connectedRef = Database.database().reference(withPath: ".info/connected")
    connectedObserverHandle = connectedRef?.observe(.value) { [weak self] snapshot in
      guard let self = self else { return }
      let connected = snapshot.value as? Bool ?? false
      DispatchQueue.main.async {
        self.handleConnectionStateChange(connected: connected)
      }
    }
  }

  private func handleConnectionStateChange(connected: Bool) {
    connectionDebounceWorkItem?.cancel()
    connectionDebounceWorkItem = nil

    if connected {
      connectionStatusView.hide()
      // Restore button visibility based on current game state
      if let snapshot = lastGameSnapshot {
        refreshButtonVisibility(for: snapshot)
      }
    } else {
      let work = DispatchWorkItem { [weak self] in
        guard let self = self else { return }
        // Hide all buttons when showing reconnecting state
        self.rightButtonStack.isHidden = true
        self.rightButtonStack.alpha = 0
        self.dealButton.isHidden = true
        self.dealButton.alpha = 0
        self.nextHandButton.isHidden = true
        self.nextHandButton.alpha = 0
        self.continueButton.isHidden = true
        self.continueButton.alpha = 0
        self.hideSplitButton()
        // Show reconnecting indicator
        self.connectionStatusView.show()
      }
      connectionDebounceWorkItem = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
  }

  private func removeConnectionObserver() {
    connectionDebounceWorkItem?.cancel()
    connectionDebounceWorkItem = nil
    if let handle = connectedObserverHandle {
      connectedRef?.removeObserver(withHandle: handle)
      connectedObserverHandle = nil
    }
  }

  // MARK: - Actions

  @objc private func hitTapped() {
    guard !isInsurancePhaseActive else {
      HapticsHelper.lightHaptic()
      return
    }
    HapticsHelper.lightHaptic()
    callPlayerAction(MultiplayerBlackjackKeys.Actions.hit)
  }

  private func handleHandTap(for seat: PlayerSeat) {
    print(
      "🎯 [MP-VC] handleHandTap called! phase=\(lastGameSnapshot?.phase ?? "nil") turnSeat=\(lastGameSnapshot?.currentTurn?.seatIndex ?? -1) mySeat=\(mySeatIndex)"
    )
    guard !isInsurancePhaseActive else {
      print("🎯 [MP-VC] handleHandTap BLOCKED - insurance phase active")
      HapticsHelper.lightHaptic()
      return
    }
    guard !isActionInFlight,
      let snapshot = lastGameSnapshot,
      let turn = snapshot.currentTurn,
      turn.seatIndex == mySeatIndex,
      snapshot.phase == MultiplayerBlackjackKeys.Phases.playerActions
    else {
      print("🎯 [MP-VC] handleHandTap BLOCKED by guard")
      return
    }
    print("🎯 [MP-VC] handleHandTap → calling hit!")
    HapticsHelper.lightHaptic()
    callPlayerAction(MultiplayerBlackjackKeys.Actions.hit)
  }

  @objc private func standTapped() {
    // Prevent action before deal animation completes
    guard !isDealAnimationRunning else {
      HapticsHelper.lightHaptic()
      return
    }
    guard !isInsurancePhaseActive else {
      HapticsHelper.lightHaptic()
      return
    }
    HapticsHelper.lightHaptic()
    let seatHands = defaultSeat.hands
    let hand =
      activeHandIndex < seatHands.count ? seatHands[activeHandIndex] : defaultSeat.primaryHand
    hand.broadcastAction("Stand")
    callPlayerAction(MultiplayerBlackjackKeys.Actions.stand)
  }

  @objc private func doubleTapped() {
    // Prevent action before deal animation completes
    guard !isDealAnimationRunning else {
      HapticsHelper.lightHaptic()
      return
    }
    guard !isInsurancePhaseActive else {
      HapticsHelper.lightHaptic()
      return
    }
    guard !isActionInFlight else { return }
    let seatHands = defaultSeat.hands
    let hand =
      activeHandIndex < seatHands.count ? seatHands[activeHandIndex] : defaultSeat.primaryHand
    let myHandsData = currentSeatsData[mySeatIndex]?.hands ?? []
    let myHandData =
      activeHandIndex < myHandsData.count ? myHandsData[activeHandIndex] : myHandsData.first
    let hasTwoCards = hand.currentCards.count == 2
    let notAlreadyDoubled = myHandData == nil ? true : !(myHandData?.doubled ?? false)
    let betAmount = hand.betControl.betAmount
    let hasBet = betAmount > 0
    let hasEnoughBalance = balance >= betAmount

    guard hasTwoCards && notAlreadyDoubled && hasBet && hasEnoughBalance else {
      HapticsHelper.lightHaptic()
      return
    }

    HapticsHelper.lightHaptic()
    hand.broadcastAction("Double!")
    callPlayerAction(MultiplayerBlackjackKeys.Actions.double)
  }

  @objc private func splitTapped() {
    guard !isActionInFlight else { return }
    // Use turn.handIndex directly to ensure we're splitting the correct hand
    let currentHandIndex = lastGameSnapshot?.currentTurn?.handIndex ?? activeHandIndex
    let seatHands = defaultSeat.hands
    guard seatHands.count < PlayerSeat.maxHandsPerSeat else { return }
    let hand =
      currentHandIndex < seatHands.count ? seatHands[currentHandIndex] : defaultSeat.primaryHand
    let cards = hand.currentCards
    guard cards.count == 2, cards[0].rank == cards[1].rank else { return }
    let betAmount = hand.betControl.betAmount
    guard betAmount > 0, balance >= betAmount else { return }

    // Verify hand hasn't already been acted upon
    let myHandsData = currentSeatsData[mySeatIndex]?.hands ?? []
    let myHandData =
      currentHandIndex < myHandsData.count ? myHandsData[currentHandIndex] : myHandsData.first
    let hasStood = myHandData?.stood ?? false
    let hasDoubled = myHandData?.doubled ?? false
    let hasBusted = myHandData?.busted ?? false
    guard !hasStood && !hasDoubled && !hasBusted else { return }

    HapticsHelper.lightHaptic()
    hand.broadcastAction("Split!")

    balance -= betAmount
    hideSplitButton()

    // Optimistic split animation: create the new hand immediately, slide the card over
    let firstCard = cards[0]
    let secondCard = cards[1]
    let splitIndex = currentHandIndex

    // Create the new hand view
    let newHand = defaultSeat.addHand(at: splitIndex, chipStyle: defaultSeat.chipStyle)
    newHand.handView.showsEmptyPlaceholders = false
    newHand.handView.clearCards()
    newHand.betControl.betAmount = betAmount
    wireHandTapHandlers(for: newHand, handIndex: splitIndex + 1)

    // Also re-wire the original hand's index since hand array shifted
    for (idx, h) in defaultSeat.hands.enumerated() {
      wireHandTapHandlers(for: h, handIndex: idx)
    }

    // Animate the seat expanding
    newHand.alpha = 0
    UIView.animate(
      withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5,
      options: []
    ) {
      newHand.alpha = 1
      self.defaultSeat.layoutIfNeeded()
      self.defaultSeat.superview?.layoutIfNeeded()
    }

    // Get source card frame before modifying the hand
    let sourceFrame = hand.getCardViewFrame(at: 1, in: view)
    let sourceCardViews = hand.cardViewsForAnimation
    let secondCardView = sourceCardViews.count >= 2 ? sourceCardViews[1] : nil

    // Update original hand to just the first card
    hand.setCardsWithoutAnimation([firstCard])

    // Set the second card on the new hand (hidden initially for animation)
    newHand.setCardsWithoutAnimation([secondCard])

    // Animate the second card sliding from original hand to new hand
    if let sourceFrame = sourceFrame {
      let sourceCenter = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)

      let tempCard = PlayingCardView()
      tempCard.configure(rank: secondCard.rank, suit: secondCard.suit)
      tempCard.setFaceDown(false, animated: false)
      tempCard.layer.masksToBounds = false
      tempCard.layer.shadowColor = UIColor.black.cgColor
      tempCard.layer.shadowOpacity = 0.18
      tempCard.layer.shadowRadius = 6
      tempCard.layer.shadowOffset = CGSize(width: 0, height: 3)
      tempCard.bounds = CGRect(origin: .zero, size: sourceFrame.size)
      tempCard.center = sourceCenter
      if let srcTransform = secondCardView?.transform {
        tempCard.transform = srcTransform
      }
      view.addSubview(tempCard)

      // Hide the target card until animation completes
      let targetCardViews = newHand.cardViewsForAnimation
      for cv in targetCardViews { cv.alpha = 0 }

      // Force layout so target positions are correct
      view.layoutIfNeeded()

      let targetFrame = newHand.getCardViewFrame(at: 0, in: view)
      let targetCenter = targetFrame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? sourceCenter

      UIView.animate(
        withDuration: 0.35, delay: 0.05, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.3,
        options: [.curveEaseInOut]
      ) {
        tempCard.center = targetCenter
      } completion: { _ in
        tempCard.removeFromSuperview()
        for cv in targetCardViews { cv.alpha = 1 }
      }

      HapticsHelper.superLightHaptic()
    }

    callPlayerAction(MultiplayerBlackjackKeys.Actions.split)
  }

  private func callPlayerAction(_ action: String) {
    guard !isActionInFlight else { return }
    isActionInFlight = true
    actionInFlightTimeoutWorkItem?.cancel()
    standButton.setDisabled(true)
    doubleButton.setDisabled(true)

    let serverHandIndex = activeHandIndex
    let deckCenter = view.convert(deckView.deckCenter, from: deckView)
    let seatHands = defaultSeat.hands
    let hand =
      activeHandIndex < seatHands.count ? seatHands[activeHandIndex] : defaultSeat.primaryHand

    // Capture original bet for rollback in case of double failure
    let originalBetForDouble =
      (action == MultiplayerBlackjackKeys.Actions.double) ? hand.betControl.betAmount : nil

    if action == MultiplayerBlackjackKeys.Actions.hit
      || action == MultiplayerBlackjackKeys.Actions.double
    {
      guard let provider = deckProvider,
        let card = provider.card(at: optimisticDeckIndex),
        let bjCard = blackjackCard(from: card)
      else {
        // Optimistic deck exhausted — skip optimistic animation but still send the
        // action to the server, which can reshuffle mid-hand if needed.
        print(
          "⚠️ [MultiplayerBlackjack] Optimistic deck exhausted at index \(optimisticDeckIndex), sending action to server without animation"
        )
        sendPlayerActionToServer(
          action: action, handIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
        return
      }
      optimisticDeckIndex += 1
      optimisticCardsForMyHand.append(bjCard)
      if action == MultiplayerBlackjackKeys.Actions.double {
        // Double card is ALWAYS dealt face up
        hand.dealCard(bjCard, from: deckCenter, in: view)
        let bet = originalBetForDouble ?? hand.betControl.betAmount
        print("BAL_BUG [double] deducting bet \(bet) from balance \(balance) → \(balance - bet)")
        balance -= bet
        hand.betControl.setBetAmount(bet * 2, animated: true)
        print("💰 [double] Optimistically updated bet to \(bet * 2)")
      } else {
        hand.dealCard(bjCard, from: deckCenter, in: view)
      }
      let newTotal = blackjackTotal(hand.currentCards)
      if newTotal > 21 {
        // Busted - turn is over
        hand.broadcastAction("Bust!")

        bustAnimatedSeatIndices.insert(mySeatIndex)
        let bustBet = hand.betControl.betAmount
        if bustBet > 0 {
          let bustResult = MPBlackjackTableState.HandResult(
            outcome: "lose", payout: 0, bet: bustBet)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, hand] in
            guard let self = self else { return }
            self.animateLocalBustForfeit(seat: self.defaultSeat, hand: hand, result: bustResult)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self, hand] in
              guard let self = self else { return }
              let topLeft = CGPoint(x: 0, y: 0)
              hand.discardCards(to: topLeft, in: self.view) {}
            }
          }
        }
        // Optimistically advance to next split hand if available
        let seatHands = defaultSeat.hands
        if activeHandIndex + 1 < seatHands.count {
          activeHandIndex += 1
          updateTurnIndicatorDot(for: mySeatIndex, handIndex: activeHandIndex)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, let snapshot = self.lastGameSnapshot else { return }
            self.isActionInFlight = false
            self.refreshButtonVisibility(for: snapshot)
          }
        }
      } else if newTotal == 21 {
        // Hit to 21: brief pause so player sees 21, then we send hit and backend auto-advances
        let seatHands = defaultSeat.hands
        let hasNextSplitHand = activeHandIndex + 1 < seatHands.count
        if hasNextSplitHand {
          activeHandIndex += 1
          updateTurnIndicatorDot(for: mySeatIndex, handIndex: activeHandIndex)
        } else {
          updateTurnIndicatorDot(for: nil)
          hideTurnIndicatorDot()
        }
        let delayForHitTo21: TimeInterval = hasNextSplitHand ? 0.4 : 1.0
        if hasNextSplitHand {
          isActionInFlight = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delayForHitTo21) { [weak self] in
          self?.sendPlayerActionToServer(
            action: action, handIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
          if hasNextSplitHand, let snapshot = self?.lastGameSnapshot {
            self?.refreshButtonVisibility(for: snapshot)
          }
        }
        return
      } else if action == MultiplayerBlackjackKeys.Actions.double {
        // Double - turn will end when backend confirms, but don't hide indicator yet
        // Keep isActionInFlight true so buttons stay disabled until backend responds
        // The Firebase listener will update the turn when backend confirms
      } else if action == MultiplayerBlackjackKeys.Actions.hit {
        // Re-enable buttons immediately after optimistic hit (hand not busted, still our turn)
        isActionInFlight = false
        // Double can only be done on first action (2 cards), so disable after hit
        standButton.setDisabled(false)
        doubleButton.setDisabled(true)
      }
    } else if action == MultiplayerBlackjackKeys.Actions.stand {
      let seatHands = defaultSeat.hands
      if activeHandIndex + 1 < seatHands.count {
        activeHandIndex += 1
        isActionInFlight = false
        updateTurnIndicatorDot(for: mySeatIndex, handIndex: activeHandIndex)
        if let snapshot = lastGameSnapshot {
          refreshButtonVisibility(for: snapshot)
        }
      } else {
        updateTurnIndicatorDot(for: nil)
        hideTurnIndicatorDot()
      }
    } else if action == MultiplayerBlackjackKeys.Actions.split {
      // Split is handled entirely by the server; no optimistic card dealing.
      // The Firebase seat listener will fire with the updated hands array
      // and applyCardsWithoutDealAnimation will create the new hand views.
    }

    sendPlayerActionToServer(
      action: action, handIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
  }

  private func sendPlayerActionToServer(
    action: String, handIndex serverHandIndex: Int? = nil, originalBetForDouble: Int?
  ) {
    let functions = Functions.functions()
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.seatIndex: mySeatIndex,
      MultiplayerBlackjackKeys.FirebaseParams.handIndex: serverHandIndex ?? activeHandIndex,
      MultiplayerBlackjackKeys.FirebaseParams.action: action,
    ]
    functions.httpsCallable("playerAction").call(params) {
      [weak self, originalBetForDouble] _, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let error = error {
          self.instructionLabel.showMessage("\(action.capitalized) failed", shouldFade: true)
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] playerAction(\(action)) failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
          if action == MultiplayerBlackjackKeys.Actions.split {
            let seatHands = self.defaultSeat.hands
            let hand =
              self.activeHandIndex < seatHands.count
              ? seatHands[self.activeHandIndex] : self.defaultSeat.primaryHand
            let betAmount = hand.betControl.betAmount
            self.balance += betAmount
            print("💰 [split rollback] Restored bet \(betAmount) to balance \(self.balance)")
          } else if !self.optimisticCardsForMyHand.isEmpty {
            let seatHands = self.defaultSeat.hands
            let hand =
              self.activeHandIndex < seatHands.count
              ? seatHands[self.activeHandIndex] : self.defaultSeat.primaryHand
            let rollback = Array(hand.currentCards.dropLast(self.optimisticCardsForMyHand.count))
            hand.setCardsWithoutAnimation(rollback)
            if action == MultiplayerBlackjackKeys.Actions.double,
              let originalBet = originalBetForDouble
            {
              print(
                "BAL_BUG [double rollback] restoring bet \(originalBet) to balance \(self.balance) → \(self.balance + originalBet)"
              )
              self.balance += originalBet
              hand.betControl.betAmount = originalBet
              print("💰 [double rollback] Restored bet to \(originalBet)")
            }
          }
          self.optimisticCardsForMyHand.removeAll()
          self.optimisticDeckIndex = self.lastGameSnapshot?.deckIndex ?? 0
          self.isActionInFlight = false
          self.actionInFlightTimeoutWorkItem?.cancel()
          if let s = self.lastGameSnapshot { self.refreshButtonVisibility(for: s) }
        } else {
          // Stand and split have no optimistic card state — unlock immediately on success
          let noOptimisticState =
            (action == MultiplayerBlackjackKeys.Actions.stand
              || action == MultiplayerBlackjackKeys.Actions.split)
          if noOptimisticState {
            self.isActionInFlight = false
            self.actionInFlightTimeoutWorkItem?.cancel()
            self.actionInFlightTimeoutWorkItem = nil
            if let s = self.lastGameSnapshot { self.refreshButtonVisibility(for: s) }
          }
        }
      }
    }

    let timeout = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      DispatchQueue.main.async {
        if self.isActionInFlight {
          self.isActionInFlight = false
          self.actionInFlightTimeoutWorkItem = nil
          if let s = self.lastGameSnapshot { self.refreshButtonVisibility(for: s) }
        }
      }
    }
    actionInFlightTimeoutWorkItem = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
  }

  @objc private func newHandTapped() {
    HapticsHelper.lightHaptic()
    instructionLabel.showMessage("New hand", shouldFade: true)
  }

  @objc private func nextHandTapped() {
    HapticsHelper.lightHaptic()
    nextHandButton.isEnabled = false
    callStartNextHand()
  }

  @objc private func dealTapped() {
    // Prevent double-tapping DEAL button
    guard !isDealInProgress else {
      HapticsHelper.lightHaptic()
      return
    }

    isDealInProgress = true
    dealButton.isEnabled = false
    HapticsHelper.lightHaptic()
    callStartDeal()
  }

  private static let placeBetRemoveBetMaxRetries = 2  // 3 total attempts (helps with cold start)

  private func callPlaceBet(amount: Int, seat: PlayerSeat, completion: @escaping (Bool) -> Void) {
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.seatIndex: mySeatIndex,
      MultiplayerBlackjackKeys.FirebaseParams.amount: amount,
    ]

    func attempt(_ tryIndex: Int) {
      let currentBetBeforeCall = seat.primaryHand.betControl.betAmount
      print(
        "🔵 [placeBet] CALLING attempt \(tryIndex + 1) amount=\(amount), currentBet=\(currentBetBeforeCall)"
      )
      let functions = Functions.functions()
      functions.httpsCallable("placeBet").call(params) { [weak self] result, error in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if let error = error {
            if tryIndex < Self.placeBetRemoveBetMaxRetries {
              let delay: TimeInterval = 2.0
              print(
                "⚠️ [MultiplayerBlackjack] placeBet attempt \(tryIndex + 1) failed (e.g. cold start), retrying in \(delay)s: \(error.localizedDescription)"
              )
              DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                attempt(tryIndex + 1)
              }
              return
            }
            self.instructionLabel.showMessage("Bet failed", shouldFade: true)
            print(
              "⚠️ [MultiplayerBlackjack] placeBet failed after \(Self.placeBetRemoveBetMaxRetries + 1) attempts: \(error.localizedDescription)"
            )
            completion(false)
            return
          }
          if let data = result?.data as? [String: Any],
            let newBalance = MPBlackjackTableState.intFromAny(
              data[MultiplayerBlackjackKeys.FirebaseResponse.newBalance]),
            let newBet = MPBlackjackTableState.intFromAny(
              data[MultiplayerBlackjackKeys.FirebaseResponse.newBet])
          {
            print("BAL_BUG [placeBet] bet=\(amount), balance \(self.balance) → \(newBalance)")
            print(
              "💰 [MultiplayerBlackjack] Bet placed: \(amount), new balance: \(newBalance), newBet from backend: \(newBet)"
            )
            print(
              "🔵 [placeBet] RESPONSE: backend says newBet=\(newBet), UI betAmount=\(seat.primaryHand.betControl.betAmount)"
            )
          }
          completion(true)
        }
      }
    }
    attempt(0)
  }

  private func callRemoveBet(
    amount: Int, seat: PlayerSeat, completion: @escaping (Bool, Int?) -> Void
  ) {
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.seatIndex: mySeatIndex,
      MultiplayerBlackjackKeys.FirebaseParams.amount: amount,
    ]

    func attempt(_ tryIndex: Int) {
      let currentBetBeforeCall = seat.primaryHand.betControl.betAmount
      print(
        "🔴 [removeBet] CALLING attempt \(tryIndex + 1) amount=\(amount), currentBet=\(currentBetBeforeCall)"
      )
      let functions = Functions.functions()
      functions.httpsCallable("removeBet").call(params) { [weak self] result, error in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if let error = error {
            if tryIndex < Self.placeBetRemoveBetMaxRetries {
              let delay: TimeInterval = 2.0
              print(
                "⚠️ [MultiplayerBlackjack] removeBet attempt \(tryIndex + 1) failed (e.g. cold start), retrying in \(delay)s: \(error.localizedDescription)"
              )
              DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                attempt(tryIndex + 1)
              }
              return
            }
            self.instructionLabel.showMessage("Could not return chips", shouldFade: true)
            print(
              "⚠️ [MultiplayerBlackjack] removeBet failed after \(Self.placeBetRemoveBetMaxRetries + 1) attempts: \(error.localizedDescription)"
            )
            completion(false, nil)
            return
          }
          var newBet: Int?
          if let data = result?.data as? [String: Any] {
            if let nb = MPBlackjackTableState.intFromAny(
              data[MultiplayerBlackjackKeys.FirebaseResponse.newBalance]),
              let bet = MPBlackjackTableState.intFromAny(
                data[MultiplayerBlackjackKeys.FirebaseResponse.newBet])
            {
              print("BAL_BUG [removeBet] amount=\(amount), balance \(self.balance) → \(nb)")
              print(
                "💰 [MultiplayerBlackjack] Bet removed: \(amount), new balance: \(nb), newBet from backend: \(bet)"
              )
              print(
                "🔴 [removeBet] RESPONSE: backend says newBet=\(bet), UI betAmount=\(seat.primaryHand.betControl.betAmount)"
              )
            }
            newBet = MPBlackjackTableState.intFromAny(
              data[MultiplayerBlackjackKeys.FirebaseResponse.newBet])
          }
          completion(true, newBet)
        }
      }
    }
    attempt(0)
  }

  // MARK: - Bonus Bet Cloud Function Calls

  private func setupBonusBetControlCallbacks() {
    mpBonusBetControl.onTapped = { [weak self] in
      self?.handleBonusBetTapped()
    }
    mpBonusBetControl.onBetDragRemoved = { [weak self] amount in
      self?.handleBonusBetDragRemoved(amount: amount)
    }
  }

  private func handleBonusBetTapped() {
    let phase = lastGameSnapshot?.phase ?? ""
    guard phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting else { return }
    let chipValue = selectedChipValue
    guard chipValue > 0 && balance >= chipValue else { return }

    let chipStyle = chipStyleForColorName(myChipColorName)

    isBalanceFrozenForBetOperation = true
    let expectedBal = balance - chipValue
    expectedBalanceAfterBetOperation = expectedBal
    balance -= chipValue
    localBonusBetAmount += chipValue

    // Don't show dot animation for local player - remote players will see it via Firebase listener
    mpBonusBetControl.addBet(amount: chipValue, chipStyle: chipStyle)

    callPlaceBonusBet(betIndex: 0, amount: chipValue) { [weak self] success in
      guard let self = self else { return }
      if success {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
          self?.isBalanceFrozenForBetOperation = false
          self?.expectedBalanceAfterBetOperation = nil
        }
      } else {
        self.balance += chipValue
        self.localBonusBetAmount = max(0, self.localBonusBetAmount - chipValue)
        self.mpBonusBetControl.removeBet(for: chipStyle)
        self.isBalanceFrozenForBetOperation = false
        self.expectedBalanceAfterBetOperation = nil
      }
    }
  }

  private func handleBonusBetDragRemoved(amount: Int) {
    let phase = lastGameSnapshot?.phase ?? ""
    guard phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting else { return }

    balance += amount
    localBonusBetAmount = max(0, localBonusBetAmount - amount)

    callRemoveBonusBet(betIndex: 0, amount: amount) { [weak self] success in
      guard let self = self else { return }
      if !success {
        self.balance -= amount
        self.localBonusBetAmount += amount
        let chipStyle = self.chipStyleForColorName(self.myChipColorName)
        self.mpBonusBetControl.addBet(amount: amount, chipStyle: chipStyle)
      }
    }
  }

  private func callPlaceBonusBet(betIndex: Int, amount: Int, completion: @escaping (Bool) -> Void) {
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.seatIndex: mySeatIndex,
      MultiplayerBlackjackKeys.BonusBets.betIndex: betIndex,
      MultiplayerBlackjackKeys.FirebaseParams.amount: amount,
    ]
    let functions = Functions.functions()
    functions.httpsCallable("placeBonusBet").call(params) { result, error in
      DispatchQueue.main.async {
        if let error = error {
          print("⚠️ [placeBonusBet] Failed: \(error.localizedDescription)")
          completion(false)
          return
        }
        completion(true)
      }
    }
  }

  private func callRemoveBonusBet(betIndex: Int, amount: Int, completion: @escaping (Bool) -> Void)
  {
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.seatIndex: mySeatIndex,
      MultiplayerBlackjackKeys.BonusBets.betIndex: betIndex,
      MultiplayerBlackjackKeys.FirebaseParams.amount: amount,
    ]
    let functions = Functions.functions()
    functions.httpsCallable("removeBonusBet").call(params) { result, error in
      DispatchQueue.main.async {
        if let error = error {
          print("⚠️ [removeBonusBet] Failed: \(error.localizedDescription)")
          completion(false)
          return
        }
        completion(true)
      }
    }
  }

  // MARK: - Bonus Bet Control Visibility

  private func showBonusBetControl(animated: Bool) {
    guard mpBonusBetControl.isHidden else { return }

    mpBonusBetControl.alpha = 0
    mpBonusBetControl.isHidden = false

    if animated {
      UIView.animate(withDuration: 0.3) {
        self.mpBonusBetControl.alpha = 1
      }
    } else {
      mpBonusBetControl.alpha = 1
    }
  }

  private func hideBonusBetControl(animated: Bool) {
    guard !mpBonusBetControl.isHidden else { return }

    if animated {
      UIView.animate(
        withDuration: 0.3,
        animations: {
          self.mpBonusBetControl.alpha = 0
        }
      ) { _ in
        self.mpBonusBetControl.isHidden = true
        self.mpBonusBetControl.clearAllBets()
      }
    } else {
      mpBonusBetControl.isHidden = true
      mpBonusBetControl.alpha = 0
      mpBonusBetControl.clearAllBets()
    }
  }

  // MARK: - Bonus Bet Resolution Animation

  private func animateBonusBetResults(
    _ results: [Int: [Int: MPBlackjackTableState.BonusBetResultData]],
    isDealerOutcome: Bool,
    completion: @escaping () -> Void
  ) {
    guard !results.isEmpty else {
      completion()
      return
    }

    isBonusBetResolutionAnimating = true

    var styleToSeat: [MPSmallBetChipStyle: Int] = [:]
    for (seatIndex, seatData) in currentSeatsData {
      let style = chipStyleForColorName(seatData.chipColorName)
      styleToSeat[style] = seatIndex
    }

    var winningSeatIndices: Set<Int> = []
    var losingSeatIndices: Set<Int> = []
    var winningsByIndex: [Int: Int] = [:]
    var descriptionsByIndex: [Int: String] = [:]
    for (seatIndex, betResults) in results {
      let hasWin = betResults.values.contains { $0.isWin }
      if hasWin {
        winningSeatIndices.insert(seatIndex)
        let totalWinnings = betResults.values.filter { $0.isWin }.reduce(0) { $0 + $1.payout }
        winningsByIndex[seatIndex] = totalWinnings
        // Get the first winning description (or combine if multiple)
        let winningDescriptions = betResults.values.filter { $0.isWin }.map { $0.description }
        descriptionsByIndex[seatIndex] = winningDescriptions.first ?? ""
      } else {
        losingSeatIndices.insert(seatIndex)
      }
    }

    animateBonusBetDots(
      styleToSeat: styleToSeat,
      winningSeatIndices: winningSeatIndices,
      losingSeatIndices: losingSeatIndices,
      winningsByIndex: winningsByIndex,
      descriptionsByIndex: descriptionsByIndex,
      results: results
    ) { [weak self] in
      guard let self = self else { return }
      self.mpBonusBetControl.clearAllBets()
      self.hideBonusBetControl(animated: true)
      self.isBonusBetResolutionAnimating = false
      completion()
    }
  }

  /// Animate bonus bet chips following the same paradigm as ChipAnimationHelper:
  /// - Losers: chip flies from bet position to house, shrinks, fades out (animateChipsAway).
  /// - Winners: winnings chip flies FROM house, scales up to 1.5x, lands next to bet chip,
  ///   pauses, then both winnings chip and bet chip fly to the player's balance (animateBonusBetWinningsWithOffset).
  private func animateBonusBetDots(
    styleToSeat: [MPSmallBetChipStyle: Int],
    winningSeatIndices: Set<Int>,
    losingSeatIndices: Set<Int>,
    winningsByIndex: [Int: Int],
    descriptionsByIndex: [Int: String],
    results: [Int: [Int: MPBlackjackTableState.BonusBetResultData]],
    completion: @escaping () -> Void
  ) {
    let chipPositions = mpBonusBetControl.chipPositions(in: view)
    guard !chipPositions.isEmpty else {
      completion()
      return
    }

    let housePoint = CGPoint(x: view.bounds.midX, y: 0)
    var longestDuration: TimeInterval = 0

    for entry in chipPositions {
      guard let seatIndex = styleToSeat[entry.style] else { continue }
      let isWinner = winningSeatIndices.contains(seatIndex)
      let isLoser = losingSeatIndices.contains(seatIndex)
      guard isWinner || isLoser else { continue }

      let chipCenter = entry.center
      let betAmount = mpBonusBetControl.betAmount(for: entry.style)

      if isLoser {
        // Loss: chip flies from bet position to house — matches ChipAnimationHelper.animateChipsAway
        mpBonusBetControl.setChipHidden(true, for: entry.style)

        let chipView = createRemoteMPChip(style: entry.style, amount: betAmount)
        chipView.center = chipCenter
        view.addSubview(chipView)

        let randomDelay = Double.random(in: 0...0.15)
        UIView.animate(
          withDuration: 0.5, delay: randomDelay, options: .curveEaseIn
        ) {
          chipView.center = housePoint
          chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        } completion: { _ in
          UIView.animate(withDuration: 0.2) {
            chipView.alpha = 0
          } completion: { _ in
            chipView.removeFromSuperview()
          }
        }
        longestDuration = max(longestDuration, 0.5 + randomDelay + 0.2)
      } else {
        // Win: matches ChipAnimationHelper.animateBonusBetWinningsWithOffset
        let isLocal = (seatIndex == mySeatIndex)
        let winnings = winningsByIndex[seatIndex] ?? 0
        let description = descriptionsByIndex[seatIndex] ?? ""
        let winningsOffset = CGPoint(x: -35, y: 0)
        let winningsPosition = CGPoint(
          x: chipCenter.x + winningsOffset.x, y: chipCenter.y + winningsOffset.y)

        // Step 1: Winnings chip flies from house, scales up to 1.5x, lands at offset position
        let winChip = createRemoteMPChip(style: entry.style, amount: winnings)
        winChip.center = housePoint
        winChip.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        view.addSubview(winChip)

        let step1 = UIViewPropertyAnimator(
          duration: 0.6, controlPoint1: CGPoint(x: 0.85, y: 0),
          controlPoint2: CGPoint(x: 0.15, y: 1)
        ) {
          winChip.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
          winChip.center = winningsPosition
        }

        step1.addCompletion { [weak self] _ in
          guard let self = self else { return }

          // Show bet result right after winnings chip lands (0.5 seconds sooner)
          if isLocal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              self.showBetResult(
                amount: winnings, isWin: true, showBonus: true,
                description: description.isEmpty ? nil : description
              )
            }
          }

          // Step 2: Brief pause, then both chips fly to balance
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }

            // Hide original chip and create animation clone at its position
            self.mpBonusBetControl.setChipHidden(true, for: entry.style)
            let betChip = self.createRemoteMPChip(style: entry.style, amount: betAmount)
            betChip.center = chipCenter
            self.view.addSubview(betChip)

            let destination: CGPoint
            var remoteSeat: PlayerSeat?

            if isLocal {
              destination = self.balanceView.convert(
                CGPoint(x: self.balanceView.bounds.maxX - 30, y: self.balanceView.bounds.midY),
                to: self.view
              )
            } else if let seat = self.seatViewsByIndex[seatIndex],
              let balView = seat.subviews.compactMap({ $0 as? MPPlayerBalanceView }).first
            {
              remoteSeat = seat
              destination = seat.convert(
                CGPoint(x: balView.frame.midX, y: balView.frame.midY),
                to: self.view
              )
            } else {
              winChip.removeFromSuperview()
              betChip.removeFromSuperview()
              return
            }

            // Calculate new balance for remote players
            // Backend adds payout + betAmount, so we need to add both
            let totalPayout = winnings + betAmount
            let newBalanceForRemote: Int?
            if !isLocal,
              let currentBalance = self.currentSeatsData[seatIndex]?.balance
            {
              newBalanceForRemote = currentBalance + totalPayout
            } else {
              newBalanceForRemote = nil
            }

            // Winnings chip flies to balance
            let fly1 = UIViewPropertyAnimator(
              duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0),
              controlPoint2: CGPoint(x: 0.15, y: 1)
            ) {
              winChip.center = destination
              winChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            }
            fly1.addCompletion { [weak self] _ in
              guard let self = self else { return }
              winChip.removeFromSuperview()

              // Update balance for local player
              // Backend adds payout + betAmount, so we add both here for optimistic update
              if isLocal {
                self.balance += totalPayout
              } else {
                // Update balance for remote player when animation completes
                // setBalance will read the current displayed balance and animate from there
                if let seat = remoteSeat, let newBalance = newBalanceForRemote {
                  seat.setBalance(newBalance, animated: true)
                }
              }
            }

            // Bet chip flies to balance (slightly offset)
            let fly2 = UIViewPropertyAnimator(
              duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0),
              controlPoint2: CGPoint(x: 0.15, y: 1)
            ) {
              betChip.center = CGPoint(x: destination.x - 10, y: destination.y)
              betChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            }
            fly2.addCompletion { _ in
              betChip.removeFromSuperview()
            }

            fly1.startAnimation()
            fly2.startAnimation(afterDelay: 0.1)
          }
        }
        step1.startAnimation()
        // 0.6 (fly in) + 0.4 (pause) + 0.5 (fly out) + 0.1 (stagger)
        longestDuration = max(longestDuration, 0.6 + 0.4 + 0.5 + 0.1)
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + longestDuration + 0.15) {
      completion()
    }
  }

  /// Re-add chips to the bonus bet control for seats that have dealer-outcome results,
  /// so the control has something to animate before hiding again.
  private func reconstructBonusChipsForDealerOutcome(
    results: [Int: [Int: MPBlackjackTableState.BonusBetResultData]]
  ) {
    mpBonusBetControl.clearAllBets()
    for (seatIndex, _) in results {
      guard let seatData = currentSeatsData[seatIndex] else { continue }
      let chipStyle = chipStyleForColorName(seatData.chipColorName)
      let totalBonusBet = seatData.bonusBets.values.reduce(0, +)
      if totalBonusBet > 0 {
        mpBonusBetControl.addBet(amount: totalBonusBet, chipStyle: chipStyle, animated: false)
      }
    }
  }

  private func callStartDeal(debugSeed: Int? = nil) {
    let functions = Functions.functions()
    var params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode
    ]
    if let debugSeed = debugSeed {
      params["debugSeed"] = debugSeed
      print("🐛 [Debug] callStartDeal with debugSeed=\(debugSeed)")
    }
    functions.httpsCallable("startDeal").call(params) { [weak self] _, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        // Re-enable deal button on error or when deal animation starts
        if let error = error {
          self.isDealInProgress = false
          self.dealButton.isEnabled = true
          self.instructionLabel.showMessage("Deal failed", shouldFade: true)
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] startDeal failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
        } else {
          self.instructionLabel.showMessage("Dealing...", shouldFade: true)
          // isDealInProgress will be reset when deal animation completes
        }
      }
    }
  }

  @objc private func showSettingsTapped() {
    showSettings()
  }

  @objc private func backButtonTapped() {
    showLeaveTableConfirmation(popToRootOnLeave: false)
  }

  private func showSettings() {
    let settingsVC = MPBlackjackSettingsViewController()
    settingsVC.tableCode = tableState.tableCode
    settingsVC.seats = currentSeatsData
    settingsVC.hostPlayerId = currentHostPlayerId
    settingsVC.tableState = tableState
    settingsVC.myPlayerId = MultiplayerPlayerIdKey.value

    settingsVC.onLeaveTable = { [weak self] in
      self?.dismiss(animated: true) {
        self?.showLeaveTableConfirmation()
      }
    }

    #if DEBUG
      settingsVC.onDebugHands = { [weak self] in
        self?.dismiss(animated: true) {
          self?.showDebugHandsSheet()
        }
      }
    #endif

    settingsVC.onPlayerRemoved = { [weak self, weak settingsVC] in
      guard let self = self else { return }
      // Refresh seats data in settings VC
      settingsVC?.seats = self.currentSeatsData
      settingsVC?.hostPlayerId = self.currentHostPlayerId
      settingsVC?.tableView.reloadData()
    }

    settingsVC.onHostTransferred = { [weak self, weak settingsVC] in
      guard let self = self else { return }
      // Refresh host status in settings VC
      settingsVC?.hostPlayerId = self.currentHostPlayerId
      settingsVC?.tableView.reloadData()
    }

    settingsVC.selectedSideBets = [currentSelectedSideBet]
    settingsVC.onSelectedSideBetsChanged = { [weak self] newSideBets in
      guard let self = self, let firstBet = newSideBets.first else { return }
      self.currentSelectedSideBet = firstBet
      let desc = self.descriptionsForSideBets([firstBet]).first ?? ""
      self.mpBonusBetControl.configure(title: firstBet, description: desc)
      self.previousBonusBetsBySeat.removeAll()
    }

    let nav = UINavigationController(rootViewController: settingsVC)
    if let sheet = nav.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
      sheet.largestUndimmedDetentIdentifier = .medium
    }
    present(nav, animated: true)
  }

  #if DEBUG
    private func showDebugHandsSheet() {
      let debugVC = DebugHandsViewController(style: .insetGrouped)
      debugVC.playerCount = currentSeatsData.values.filter { $0.playerId != nil }.count
      debugVC.onSeedSelected = { [weak self] seed in
        if let seed = seed {
          self?.callStartDeal(debugSeed: seed)
        } else {
          // nil seed means reset to random
          self?.callStartDeal(debugSeed: nil)
        }
      }
      let nav = UINavigationController(rootViewController: debugVC)
      if let sheet = nav.sheetPresentationController {
        sheet.detents = [.medium(), .large()]
        sheet.prefersGrabberVisible = true
      }
      present(nav, animated: true)
    }
  #endif

  /// Called when phase becomes dealer_turn so the backend runs dealer (reveal hole card, draw to 17+, resolve).
  private func callRunDealer() {
    let functions = Functions.functions()
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode
    ]
    functions.httpsCallable("runDealer").call(params) { _, error in
      DispatchQueue.main.async {
        if let error = error {
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] runDealer failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
        }
      }
    }
  }

  /// Called when dealer blackjack is detected during player_actions phase.
  /// Resolves all bets immediately and transitions game to between_hands.
  private func callResolveDealerBlackjack() {
    let functions = Functions.functions()
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode
    ]
    functions.httpsCallable("resolveDealerBlackjack").call(params) { _, error in
      DispatchQueue.main.async {
        if let error = error {
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] resolveDealerBlackjack failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
        }
      }
    }
  }

  private func callStartNextHand() {
    let functions = Functions.functions()
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.playerId: MultiplayerPlayerIdKey.value,
    ]
    functions.httpsCallable("startNextHand").call(params) { [weak self] _, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.nextHandButton.isEnabled = true
        if let error = error {
          self.instructionLabel.showMessage("Next hand failed", shouldFade: true)
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] startNextHand failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
        } else {
          // clearAllCardsForNewHand will be triggered by applyGameStateSnapshot
          // when Firebase confirms the phase has changed to betting.
          print("💰 [MP-VC] startNextHand succeeded — waiting for phase→betting to clear cards")
        }
      }
    }
  }

  private func clearAllCardsForNewHand(isForcedReset: Bool = false, isBettingPhase: Bool = false) {
    resetDealerCardQueue()

    // Collect all cards that need to be discarded
    let dealerCards = dealerHandView.currentCards
    var playerHandsToDiscard: [(hand: CompactPlayerHandView, cards: [BlackjackHandView.Card])] = []
    for (_, seatView) in seatViewsByIndex {
      for hand in seatView.hands {
        let cards = hand.handView.currentCards
        if !cards.isEmpty {
          playerHandsToDiscard.append((hand: hand, cards: cards))
        }
      }
    }

    // If no cards to discard, clear immediately
    guard !dealerCards.isEmpty || !playerHandsToDiscard.isEmpty else {
      performCardClearingCleanup(isForcedReset: isForcedReset, isBettingPhase: isBettingPhase)
      return
    }

    // Animate cards off screen (similar to BlackjackGameplayViewController)
    let topLeftPoint = CGPoint(x: 0, y: 0)
    var completedDiscards = 0
    let totalDiscards = (dealerCards.isEmpty ? 0 : 1) + playerHandsToDiscard.count

    func checkCompletion() {
      completedDiscards += 1
      if completedDiscards >= totalDiscards {
        // All cards discarded, now clear everything
        performCardClearingCleanup(isForcedReset: isForcedReset, isBettingPhase: isBettingPhase)
      }
    }

    // Discard dealer cards
    if !dealerCards.isEmpty {
      dealerHandView.discardCards(to: topLeftPoint, in: view) {
        checkCompletion()
      }
    } else {
      checkCompletion()
    }

    // Discard all player hands
    for (hand, _) in playerHandsToDiscard {
      hand.discardCards(to: topLeftPoint, in: view) {
        checkCompletion()
      }
    }
  }

  private func performCardClearingCleanup(isForcedReset: Bool = false, isBettingPhase: Bool = false) {
    resetDealerCardQueue()
    dealerHandView.setCardsWithoutAnimation([])

    // Collect seats that have split hands so we can animate their collapse
    var seatsWithSplitHands: [(seatView: PlayerSeat, seatIndex: Int)] = []

    for (seatIndex, seatView) in seatViewsByIndex {
      for hand in seatView.hands {
        hand.clearCards()
      }

      if seatView.hands.count > 1 {
        seatsWithSplitHands.append((seatView: seatView, seatIndex: seatIndex))
      } else {
        // No split hands — just reset bet immediately
        let primaryHand = seatView.primaryHand
        // During forced reset, clear all bets including push bets
        if isForcedReset {
          primaryHand.betControl.betAmount = 0
          pushBetsBySeatIndex.removeValue(forKey: seatIndex)
          print("💰 [MP-VC] Forced reset: clearing bet for seat \(seatIndex)")
        } else if let pushBet = pushBetsBySeatIndex[seatIndex], pushBet > 0 {
          primaryHand.betControl.setBetAmount(pushBet, animated: true)
          print("💰 [MP-VC] Restoring push bet \(pushBet) for seat \(seatIndex)")
          if seatIndex == mySeatIndex {
            syncHandsToFirebase(for: seatView)
          }
          pushBetsBySeatIndex.removeValue(forKey: seatIndex)
        } else {
          // Check if we're in betting phase and if there's a bet in Firebase
          // This prevents clearing bets that were quickly placed before cards finished animating
          let firebaseBet = currentSeatsData[seatIndex]?.hands.first?.bet ?? 0
          
          if isBettingPhase && firebaseBet > 0 {
            // Preserve bet from Firebase instead of clearing it
            primaryHand.betControl.setBetAmount(firebaseBet, animated: false)
            print("💰 [MP-VC] Preserving Firebase bet \(firebaseBet) for seat \(seatIndex) during card clearing")
          } else {
            primaryHand.betControl.betAmount = 0
          }
        }
      }
    }

    if seatsWithSplitHands.isEmpty {
      finishCardClearingCleanup(isForcedReset: isForcedReset)
    } else {
      animateSplitHandCollapse(seats: seatsWithSplitHands, isForcedReset: isForcedReset, isBettingPhase: isBettingPhase) {
        [weak self] in
        self?.finishCardClearingCleanup(isForcedReset: isForcedReset)
      }
    }
  }

  /// Animate split hands fading/shrinking out, then collapse the seat back to single-hand width.
  private func animateSplitHandCollapse(
    seats: [(seatView: PlayerSeat, seatIndex: Int)],
    isForcedReset: Bool = false,
    isBettingPhase: Bool = false,
    completion: @escaping () -> Void
  ) {
    // Step 1: Fade out and shrink additional hands
    let additionalHands = seats.flatMap { $0.seatView.hands.dropFirst() }
    UIView.animate(
      withDuration: 0.25, delay: 0, options: .curveEaseIn,
      animations: {
        for hand in additionalHands {
          hand.alpha = 0
          hand.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
      }
    ) { [weak self] _ in
      guard let self = self else {
        completion()
        return
      }

      // Step 2: Remove them and animate the seat collapsing back
      for (seatView, seatIndex) in seats {
        seatView.removeAllAdditionalHands()

        let primaryHand = seatView.primaryHand
        // During forced reset, clear all bets including push bets
        if isForcedReset {
          primaryHand.betControl.betAmount = 0
          self.pushBetsBySeatIndex.removeValue(forKey: seatIndex)
          print("💰 [MP-VC] Forced reset: clearing bet for seat \(seatIndex)")
        } else if let pushBet = self.pushBetsBySeatIndex[seatIndex], pushBet > 0 {
          primaryHand.betControl.setBetAmount(pushBet, animated: true)
          print("💰 [MP-VC] Restoring push bet \(pushBet) for seat \(seatIndex)")
          if seatIndex == self.mySeatIndex {
            self.syncHandsToFirebase(for: seatView)
          }
          self.pushBetsBySeatIndex.removeValue(forKey: seatIndex)
        } else {
          // Check if we're in betting phase and if there's a bet in Firebase
          // This prevents clearing bets that were quickly placed before cards finished animating
          let firebaseBet = self.currentSeatsData[seatIndex]?.hands.first?.bet ?? 0
          
          if isBettingPhase && firebaseBet > 0 {
            // Preserve bet from Firebase instead of clearing it
            primaryHand.betControl.setBetAmount(firebaseBet, animated: false)
            print("💰 [MP-VC] Preserving Firebase bet \(firebaseBet) for seat \(seatIndex) during split hand collapse")
          } else {
            primaryHand.betControl.betAmount = 0
          }
        }
      }

      UIView.animate(
        withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5,
        animations: {
          for (seatView, _) in seats {
            seatView.layoutIfNeeded()
            seatView.superview?.layoutIfNeeded()
          }
        }
      ) { _ in
        completion()
      }
    }
  }

  private func finishCardClearingCleanup(isForcedReset: Bool = false) {
    activeHandIndex = 0
    previousHandsByIndex.removeAll()
    previousBalanceByIndex.removeAll()
    previousCardCountsBySeat.removeAll()
    previousHasStoodBySeat.removeAll()
    previousHandCountsBySeat.removeAll()
    print(
      "BAL_BUG [clearAllCards] unfreezing balance — current balance: \(balance), preBetSettlementBalance: \(preBetSettlementBalance)"
    )
    isBalanceFrozenForSettlement = false
    preBetSettlementBalance = 0
    lastGameSnapshot = nil
    previousGameSnapshot = nil
    isBetReconciliationRunning = false
    optimisticCardsForMyHand.removeAll()
    isActionInFlight = false
    actionInFlightTimeoutWorkItem?.cancel()
    actionInFlightTimeoutWorkItem = nil

    // Reset insurance state
    mpInsuranceControl.clearAllBets()
    hideInsuranceControl(animated: false)
    isInsurancePhaseActive = false
    localInsuranceBetAmount = 0
    previousInsuranceBySeat.removeAll()
    pendingInsuranceSnapshot = nil
    pendingInsuranceHoleCard = nil
    pendingInsuranceUpCard = nil
    tableState?.clearInsuranceForAllSeats()

    // Reset bonus bet state and show the control for the new betting phase
    mpBonusBetControl.clearAllBets()
    localBonusBetAmount = 0
    previousBonusBetsBySeat.removeAll()
    isBonusBetResolutionAnimating = false
    bonusBetResultsProcessed = false
    tableState?.clearBonusBetsForAllSeats()
    showBonusBetControl(animated: false)

    // During forced reset, also clear push bets
    if isForcedReset {
      pushBetsBySeatIndex.removeAll()
      print("💰 [MP-VC] Forced reset: cleared all push bets")
    }
  }

  private func cardFromFirebase(_ dict: [String: Any]) -> BlackjackHandView.Card? {
    guard let rankRaw = dict[MultiplayerBlackjackKeys.CardData.rank] as? String,
      let suitRaw = dict[MultiplayerBlackjackKeys.CardData.suit] as? String
    else { return nil }
    let rank = PlayingCardView.Rank(rawValue: rankRaw) ?? .ace
    let suit: PlayingCardView.Suit
    switch suitRaw.lowercased() {
    case "hearts": suit = .hearts
    case "clubs": suit = .clubs
    case "diamonds": suit = .diamonds
    case "spades": suit = .spades
    default: suit = .spades
    }
    return BlackjackHandView.Card(
      rank: rank, suit: suit,
      isCutCard: (dict[MultiplayerBlackjackKeys.CardData.isCutCard] as? Bool) ?? false)
  }

  /// Convert deterministic deck card to hand view card for optimistic animation.
  private func blackjackCard(from providerCard: DeterministicDeckProvider.Card) -> BlackjackHandView
    .Card?
  {
    cardFromFirebase([
      MultiplayerBlackjackKeys.CardData.rank: providerCard.rank,
      MultiplayerBlackjackKeys.CardData.suit: providerCard.suit,
    ])
  }

  /// Get player hands from current seats data in the format expected by animation code
  private func getPlayerHandsFromSeats() -> [Int: [[String: Any]]] {
    var result: [Int: [[String: Any]]] = [:]
    for (seatIndex, seatData) in currentSeatsData {
      let hands = seatData.hands.map { $0.toDictionary() }
      if !hands.isEmpty {
        result[seatIndex] = hands
      }
    }
    return result
  }

  /// Helper to update instruction label only when message changes
  private func updateInstructionLabelIfNeeded(_ message: String, shouldFade: Bool = false) {
    if lastInstructionMessage != message {
      instructionLabel.showMessage(message, shouldFade: shouldFade)
      lastInstructionMessage = message
    }
  }

  private func refreshButtonVisibility(for snapshot: MPBlackjackTableState.GameStateSnapshot) {
    let phase = snapshot.phase ?? ""
    let isBetting = (phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting)
    let isBetweenHands =
      (phase == MultiplayerBlackjackKeys.Phases.betweenHands
        || phase == MultiplayerBlackjackKeys.Phases.gameOver)

    // Hide all first, then show the appropriate one
    dealButton.isHidden = true
    dealButton.alpha = 0
    rightButtonStack.isHidden = true
    rightButtonStack.alpha = 0
    nextHandButton.isHidden = true
    nextHandButton.alpha = 0
    continueButton.isHidden = true
    continueButton.alpha = 0
    // Always hide newHandButton - not used in multiplayer
    newHandButton.isHidden = true
    newHandButton.alpha = 0
    // Don't hide split button here - it will be shown/hidden based on conditions below

    if isInsurancePhaseActive {
      continueButton.isHidden = false
      continueButton.alpha = 1
      view.bringSubviewToFront(continueButton)
      return
    }

    if isBetting {
      hideSplitButton()
      if isHost {
        dealButton.isHidden = false
        dealButton.alpha = 1
        dealButton.isEnabled = !isDealInProgress
        view.bringSubviewToFront(dealButton)
        updateInstructionLabelIfNeeded("Place your bet, then tap Deal", shouldFade: false)
      } else {
        updateInstructionLabelIfNeeded(
          "Place your bet — waiting for host to deal", shouldFade: false)
      }
    } else if phase == MultiplayerBlackjackKeys.Phases.playerActions {
      let turn = snapshot.currentTurn
      let isMyTurn =
        (turn?.seatIndex == mySeatIndex) && !isActionInFlight
        && !isBlackjackPayoutAnimating

      // Debug: log turn info
      if let turn = turn {
        print(
          "🔍 [SPLIT DEBUG] Phase: playerActions, turn.seatIndex=\(turn.seatIndex), mySeatIndex=\(mySeatIndex), isMyTurn=\(isMyTurn), isActionInFlight=\(isActionInFlight), isBlackjackPayoutAnimating=\(isBlackjackPayoutAnimating)"
        )
      }

      if isMyTurn && !isDealAnimationRunning && !isBlackjackPayoutAnimating {
        // Update activeHandIndex to match the current turn's hand index
        if let turnHandIndex = turn?.handIndex {
          activeHandIndex = turnHandIndex
        }
        // Use turn.handIndex directly to ensure we're checking the correct hand
        let currentHandIndex = turn?.handIndex ?? activeHandIndex
        let seatHands = defaultSeat.hands

        // Debug: verify we're checking the right hand
        if currentHandIndex >= seatHands.count {
          print(
            "⚠️ [SPLIT DEBUG] Seat \(mySeatIndex): currentHandIndex \(currentHandIndex) >= seatHands.count \(seatHands.count), using primaryHand"
          )
        }

        let activeHand =
          currentHandIndex < seatHands.count ? seatHands[currentHandIndex] : defaultSeat.primaryHand
        let viewCards = activeHand.currentCards

        // Debug: log what we're checking
        print(
          "🔍 [SPLIT DEBUG] Seat \(mySeatIndex), handIndex \(currentHandIndex), view cards: \(viewCards.map { $0.rank.rawValue })"
        )
        let myHandsData = currentSeatsData[mySeatIndex]?.hands ?? []
        let myHandData =
          currentHandIndex < myHandsData.count ? myHandsData[currentHandIndex] : myHandsData.first

        // Use Firebase hand cards as source of truth for action eligibility.
        // Local hand views can briefly lag during deal/turn transitions.
        let serverCards = (myHandData?.cards ?? []).compactMap { cardFromFirebase($0) }
        let cardsForEligibility = serverCards.isEmpty ? viewCards : serverCards
        let hasTwoCards = cardsForEligibility.count == 2
        let cardsMatch = hasTwoCards && cardsForEligibility[0].rank == cardsForEligibility[1].rank
        // Prevent revealing a pair before the second card visibly lands in the UI.
        let hasTwoVisibleCards = viewCards.count >= 2
        let myActiveTotal = blackjackTotal(cardsForEligibility)
        let canStand = myActiveTotal <= 21
        let notAlreadyDoubled = myHandData == nil ? true : !(myHandData?.doubled ?? false)
        let betAmount = myHandData?.bet ?? activeHand.betControl.betAmount
        let hasBet = betAmount > 0
        let balanceForEligibility = currentSeatsData[mySeatIndex]?.balance ?? balance
        let hasEnoughBalance = balanceForEligibility >= betAmount
        let handCountForSplitLimit = myHandsData.isEmpty ? seatHands.count : myHandsData.count
        let canDouble = hasTwoCards && notAlreadyDoubled && hasBet && hasEnoughBalance

        rightButtonStack.isHidden = false
        rightButtonStack.alpha = 1
        view.bringSubviewToFront(rightButtonStack)
        standButton.setDisabled(!canStand)
        doubleButton.setDisabled(!canDouble)

        let notAlreadyStood = myHandData == nil ? true : !(myHandData?.stood ?? false)
        let notAlreadyBusted = myHandData == nil ? true : !(myHandData?.busted ?? false)
        let canSplit =
          hasTwoCards
          && cardsMatch
          && notAlreadyDoubled
          && notAlreadyStood
          && notAlreadyBusted
          && hasEnoughBalance
          && hasTwoVisibleCards
          && handCountForSplitLimit < PlayerSeat.maxHandsPerSeat

        // Debug logging to help diagnose split button issues
        print(
          "🔍 [SPLIT DEBUG] Seat \(mySeatIndex), hand \(currentHandIndex): serverCards=\(serverCards.map { $0.rank.rawValue }), viewCards=\(viewCards.map { $0.rank.rawValue }), hasTwoCards=\(hasTwoCards), hasTwoVisibleCards=\(hasTwoVisibleCards), cardsMatch=\(cardsMatch), betAmount=\(betAmount), balanceForEligibility=\(balanceForEligibility), handCountForSplitLimit=\(handCountForSplitLimit), canSplit=\(canSplit)"
        )
        if hasTwoCards {
          print(
            "🔍 [SPLIT DEBUG]   Card ranks: \(cardsForEligibility[0].rank.rawValue) == \(cardsForEligibility[1].rank.rawValue)? \(cardsForEligibility[0].rank == cardsForEligibility[1].rank)"
          )
          print(
            "🔍 [SPLIT DEBUG]   Conditions: notAlreadyDoubled=\(notAlreadyDoubled), notAlreadyStood=\(notAlreadyStood), notAlreadyBusted=\(notAlreadyBusted), hasEnoughBalance=\(hasEnoughBalance), hasTwoVisibleCards=\(hasTwoVisibleCards), handCountForSplitLimit=\(handCountForSplitLimit) < \(PlayerSeat.maxHandsPerSeat)"
          )
        }
        if hasTwoCards && !cardsMatch {
          print(
            "🔍 [SPLIT DEBUG] Seat \(mySeatIndex), hand \(currentHandIndex): Cards don't match - \(cardsForEligibility[0].rank.rawValue) vs \(cardsForEligibility[1].rank.rawValue)"
          )
        }
        if hasTwoCards && cardsMatch && !canSplit {
          print(
            "🔍 [SPLIT DEBUG] Seat \(mySeatIndex), hand \(currentHandIndex): Can't split - hasTwoCards=\(hasTwoCards), cardsMatch=\(cardsMatch), notAlreadyDoubled=\(notAlreadyDoubled), notAlreadyStood=\(notAlreadyStood), notAlreadyBusted=\(notAlreadyBusted), hasEnoughBalance=\(hasEnoughBalance), hasTwoVisibleCards=\(hasTwoVisibleCards), handCountForSplitLimit=\(handCountForSplitLimit), maxHands=\(PlayerSeat.maxHandsPerSeat)"
          )
        }

        if canSplit {
          print(
            "✅ [SPLIT DEBUG] Showing split button for seat \(mySeatIndex), hand \(currentHandIndex)"
          )
          showSplitButton(above: activeHand)
        } else {
          print(
            "❌ [SPLIT DEBUG] Hiding split button for seat \(mySeatIndex), hand \(currentHandIndex)")
          hideSplitButton()
        }
      } else {
        // Not player's turn or deal animation running - hide split button
        hideSplitButton()
      }

      let turnMessage: String
      if isMyTurn {
        turnMessage = "Tap your hand to Hit, or use Stand/Double"
      } else if let si = turn?.seatIndex, let name = currentSeatsData[si]?.displayLabel {
        turnMessage = "\(name)'s turn"
      } else {
        turnMessage = "Waiting for other players"
      }
      updateInstructionLabelIfNeeded(turnMessage, shouldFade: false)
      // Hide turn indicator during deal or blackjack payout animation - shown after animation completes
      if isDealAnimationRunning || isBlackjackPayoutAnimating {
        hideTurnIndicatorDot()
      } else {
        updateTurnIndicatorDot(for: turn?.seatIndex, handIndex: turn?.handIndex ?? 0)
      }
    } else if phase == MultiplayerBlackjackKeys.Phases.dealerTurn {
      hideSplitButton()
      updateInstructionLabelIfNeeded("Dealer's turn", shouldFade: false)
    } else if isBetweenHands {
      hideSplitButton()
      if isDealerCardAnimating || !dealerCardQueue.isEmpty {
        updateInstructionLabelIfNeeded("Dealer's turn", shouldFade: false)
      } else if isBetReconciliationRunning {
        updateInstructionLabelIfNeeded("Resolving bets...", shouldFade: false)
      } else if isHost {
        nextHandButton.isHidden = false
        nextHandButton.alpha = 1
        view.bringSubviewToFront(nextHandButton)
        updateInstructionLabelIfNeeded("Hand over — tap Next Hand when ready", shouldFade: false)
      } else {
        updateInstructionLabelIfNeeded(
          "Hand over — waiting for host to start next hand", shouldFade: false)
      }
    }

    // Hide turn indicator if not in player_actions phase OR if deal/blackjack payout animation is running
    if phase != MultiplayerBlackjackKeys.Phases.playerActions || isDealAnimationRunning
      || isBlackjackPayoutAnimating
    {
      hideTurnIndicatorDot()
    }

    // Disable bet control when hand has started (only allow during betting)
    let betControlEnabled = isBetting
    for handView in defaultSeat.hands {
      handView.betControl.isEnabled = betControlEnabled
      handView.betControl.setBetRemovalDisabled(!betControlEnabled)
    }

  }

  private func applyGameStateSnapshot(_ snapshot: MPBlackjackTableState.GameStateSnapshot) {
    let phase = snapshot.phase ?? ""
    let playerHands = getPlayerHandsFromSeats()
    print(
      "🎮 [MultiplayerBlackjack] applyGameStateSnapshot: phase=\(phase), playerHands.count=\(playerHands.count), dealerCards.count=\(snapshot.dealerCards.count)"
    )

    // Rebuild deck provider when seed or deck count changes (new hand or new deal).
    let prev = lastGameSnapshot
    let prevPhase = prev?.phase ?? ""
    // Reset instruction message tracking when phase changes
    if phase != prevPhase {
      lastInstructionMessage = nil
    }

    // On the very first snapshot ever, hide bonus control if not in betting phase (joined mid-game).
    // Use hasReceivedFirstGameSnapshot so this only fires once — not after finishCardClearingCleanup
    // resets lastGameSnapshot to nil between hands.
    if !hasReceivedFirstGameSnapshot {
      hasReceivedFirstGameSnapshot = true
      let isBettingPhase = phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting
      if !isBettingPhase {
        hideBonusBetControl(animated: false)
      }
    }

    // Reset auto-scroll flag when entering player_actions phase
    if phase == MultiplayerBlackjackKeys.Phases.playerActions
      && prevPhase != MultiplayerBlackjackKeys.Phases.playerActions
    {
      shouldIgnoreAutoScroll = false
    }

    // Track which hand is active for the local player
    if phase == MultiplayerBlackjackKeys.Phases.playerActions,
      let turn = snapshot.currentTurn, turn.seatIndex == mySeatIndex
    {
      activeHandIndex = turn.handIndex

      // Auto-resolve blackjack when it becomes the player's turn.
      // Don't call stand during the deal animation — runShowTurnUIAfterDeal handles that.
      if !isDealAnimationRunning {
        let myHandsData = currentSeatsData[mySeatIndex]?.hands ?? []
        let myHandData =
          turn.handIndex < myHandsData.count ? myHandsData[turn.handIndex] : myHandsData.first
        if let handData = myHandData,
          handData.cards.count == 2
        {
          let cards = handData.cards.compactMap { cardFromFirebase($0) }
          if cards.count == 2 && blackjackTotal(cards) == 21 {
            if !isActionInFlight && !isBlackjackPayoutAnimating {
              callPlayerAction(MultiplayerBlackjackKeys.Actions.stand)
            }
          }
        }
      }
    }

    // Reset auto-scroll flag when it becomes the user's turn
    if phase == MultiplayerBlackjackKeys.Phases.playerActions {
      let isMyTurn =
        (snapshot.currentTurn?.seatIndex == mySeatIndex) && !isActionInFlight
        && !isBlackjackPayoutAnimating
      let wasMyTurn = prev?.currentTurn?.seatIndex == mySeatIndex
      
      // Play success haptic when it becomes the local player's turn
      if isMyTurn && !wasMyTurn {
        HapticsHelper.successHaptic()
      }
      
      if isMyTurn {
        shouldIgnoreAutoScroll = false
      }
    }
    let seedChanged = prev != nil && snapshot.deckSeed != 0 && prev?.deckSeed != snapshot.deckSeed
    if prev?.deckSeed != snapshot.deckSeed || prev?.deckCount != snapshot.deckCount {
      deckProvider = DeterministicDeckProvider(
        seed: snapshot.deckSeed, deckCount: snapshot.deckCount)
    }
    if seedChanged {
      let totalCards = 52 * snapshot.deckCount
      deckView.setCardCount(totalCards, animated: true)
    }
    if optimisticCardsForMyHand.isEmpty {
      optimisticDeckIndex = snapshot.deckIndex
    }
    if phase != MultiplayerBlackjackKeys.Phases.playerActions {
      optimisticCardsForMyHand.removeAll()
      isActionInFlight = false
      actionInFlightTimeoutWorkItem?.cancel()
      actionInFlightTimeoutWorkItem = nil
    } else if snapshot.currentTurn?.seatIndex != mySeatIndex {
      // Turn moved to another player (e.g. we stood or doubled) — clear so we don't rely on timeout
      // If we just doubled, delay updating the turn indicator to let the card animation finish
      let wasMyTurn = prev?.currentTurn?.seatIndex == mySeatIndex
      let justDoubled = wasMyTurn && defaultSeat.primaryHand.currentCards.count == 3

      if justDoubled {
        // Delay turn indicator update to let card animation finish (card deal animation is ~0.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
          guard let self = self else { return }
          self.isActionInFlight = false
          self.actionInFlightTimeoutWorkItem?.cancel()
          self.actionInFlightTimeoutWorkItem = nil
          if let s = self.lastGameSnapshot { self.refreshButtonVisibility(for: s) }
        }
      } else {
        // Immediate update for stand or other actions
        isActionInFlight = false
        actionInFlightTimeoutWorkItem?.cancel()
        actionInFlightTimeoutWorkItem = nil
      }
    }

    // Scroll to the current player when turn changes during player_actions phase
    // Only if user hasn't manually scrolled (shouldIgnoreAutoScroll is false)
    // This handles both seat changes and hand changes (e.g., when a player splits)
    if phase == MultiplayerBlackjackKeys.Phases.playerActions && !isDealAnimationRunning
      && !shouldIgnoreAutoScroll
    {
      let currentTurnSeatIndex = snapshot.currentTurn?.seatIndex
      let prevTurnSeatIndex = prev?.currentTurn?.seatIndex
      let currentTurnHandIndex = snapshot.currentTurn?.handIndex ?? 0
      let prevTurnHandIndex = prev?.currentTurn?.handIndex ?? 0

      // Scroll if either the seat changed OR the hand changed (for split hands)
      if let seatIndex = currentTurnSeatIndex {
        if seatIndex != prevTurnSeatIndex || currentTurnHandIndex != prevTurnHandIndex {
          scrollToSeatHand(seatIndex, handIndex: currentTurnHandIndex, animated: true)
        }
      }
    }

    // Clear cards when transitioning to betting (new hand started by host)
    // This handles both normal flow (betweenHands/gameOver → betting) and recovery scenarios
    // (any phase → betting when host uses "Clear and Start New Hand")
    // Skip clearing on initial load (prev == nil) to avoid clearing when joining an already-active table
    if phase == MultiplayerBlackjackKeys.Phases.betting
      && prevPhase != MultiplayerBlackjackKeys.Phases.betting
      && prev != nil
    {
      bustAnimatedSeatIndices.removeAll()
      isBlackjackPayoutAnimating = false
      // If transitioning from a phase other than betweenHands/gameOver, this is a forced reset
      // and we should clear push bets instead of restoring them
      let isForcedReset =
        prevPhase != MultiplayerBlackjackKeys.Phases.betweenHands
        && prevPhase != MultiplayerBlackjackKeys.Phases.gameOver
      clearAllCardsForNewHand(isForcedReset: isForcedReset, isBettingPhase: true)
      showBonusBetControl(animated: true)
    }

    // Scroll to user's hand when entering the betting phase
    // This covers both: phase transitions to betting, and when user joins during betting phase
    if phase == MultiplayerBlackjackKeys.Phases.betting
      && prevPhase != MultiplayerBlackjackKeys.Phases.betting
    {
      // Log game started analytics event (only once per game session)
      if !hasLoggedGameStarted {
        hasLoggedGameStarted = true
        GameAnalyticsEvent.mpBlackjackGameStarted.log()
      }
      
      // If this is the first snapshot (user just joined), delay slightly to ensure seats are laid out
      if prev == nil {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          self?.scrollToSeat(self?.mySeatIndex ?? 0, animated: true)
        }
      } else {
        scrollToSeat(mySeatIndex, animated: true)
      }
    }

    refreshButtonVisibility(for: snapshot)

    let deckCenter = view.convert(deckView.deckCenter, from: deckView)
    let previous = lastGameSnapshot

    // When all players are done, phase becomes dealer_turn; after a short delay, trigger backend to run dealer (reveal hole card, draw to 17+, resolve)
    if phase == MultiplayerBlackjackKeys.Phases.dealerTurn,
      previous?.phase != MultiplayerBlackjackKeys.Phases.dealerTurn
    {
      // Freeze the balance NOW — before the server runs the dealer and writes the
      // post-payout balance to seats. observeSeats will arrive before observeGameState
      // delivers the end phase, so this is our last safe moment.
      if !isBalanceFrozenForSettlement {
        isBalanceFrozenForSettlement = true
        preBetSettlementBalance = balance
        print("BAL_BUG [dealer_turn] freezing balance at \(balance) for settlement")
      }

      dealerCardsRenderedCount = dealerHandView.currentCards.count
      dealerHoleRevealed = false
      isDealerCardAnimating = false
      dealerCardQueue.removeAll()
      // When coming directly from betting (all blackjacks), wait for deal + payout animation
      let fromBetting = (previous?.phase ?? "") == MultiplayerBlackjackKeys.Phases.betting
      let delayBeforeDealer: TimeInterval = fromBetting ? 5.0 : 0.3
      DispatchQueue.main.asyncAfter(deadline: .now() + delayBeforeDealer) { [weak self] in
        self?.callRunDealer()
      }
    }

    // Reconcile bets when transitioning to between_hands (hand results are available).
    // Skip when dealerHasBlackjack: animateServerResolvedDealerBlackjack handles settlement after deal animation.
    let isEndPhase =
      (phase == MultiplayerBlackjackKeys.Phases.gameOver
        || phase == MultiplayerBlackjackKeys.Phases.betweenHands)
    let wasEndPhase =
      (previous?.phase == MultiplayerBlackjackKeys.Phases.gameOver
        || previous?.phase == MultiplayerBlackjackKeys.Phases.betweenHands)
    let skipReconcileForDealerBJ =
      snapshot.dealerHasBlackjack && isInitialDealSnapshot(snapshot, previous: previous)
    print(
      "💰 [MP-VC] reconcile check: phase='\(phase)' prevPhase='\(previous?.phase ?? "nil")' isEnd=\(isEndPhase) wasEnd=\(wasEndPhase) handResults.count=\(snapshot.handResults.count) keys=\(snapshot.handResults.keys.sorted()) isRunning=\(isBetReconciliationRunning) skipForDealerBJ=\(skipReconcileForDealerBJ)"
    )
    if isEndPhase && !wasEndPhase && !skipReconcileForDealerBJ {
      // If we skipped dealer_turn (e.g. all players busted), freeze wasn't set yet.
      // In that case the balance may already be contaminated by observeSeats, so fall
      // back to computing the pre-settlement balance from the bet amounts in the results.
      if !isBalanceFrozenForSettlement {
        isBalanceFrozenForSettlement = true
        // observeSeats may have already applied the post-payout balance, so we can't
        // trust self.balance. Instead, reverse-compute: for the local player's hand,
        // the pre-settlement balance = (current Firebase balance) - payout.
        // But even that's fragile. Safest: use the balance the server reports minus the
        // return. We know the server balance at this point = preBet + returnAmount.
        // preBet = serverBalance - returnAmount. For the local seat:
        let myResults = snapshot.handResults[mySeatIndex] ?? []
        let totalPayout = myResults.reduce(0) { $0 + $1.payout }
        // self.balance may already be the post-payout value from observeSeats
        preBetSettlementBalance = balance - totalPayout
        print(
          "BAL_BUG [endPhase-fallback] computed preBetSettlementBalance=\(preBetSettlementBalance) (balance=\(balance) - totalPayout=\(totalPayout))"
        )
      }
      print(
        "BAL_BUG [endPhase] preBetSettlementBalance=\(preBetSettlementBalance), current balance=\(balance)"
      )

      if !snapshot.handResults.isEmpty {
        let dealerAnimDelay: TimeInterval =
          dealerCardQueue.isEmpty ? 0.5 : Double(dealerCardQueue.count) * 0.8 + 0.5
        print(
          "💰 [MP-VC] scheduling reconcileBets with delay \(dealerAnimDelay)s (dealerCardQueue.count=\(dealerCardQueue.count))"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + dealerAnimDelay) { [weak self] in
          guard let self = self else { return }

          // Animate dealer-outcome bonus bet results (Buster, Lucky 7) before main bet reconciliation
          let dealerBonusResults = snapshot.bonusBetResults.filter { seatResults in
            seatResults.value.values.contains {
              $0.description.hasPrefix("BUSTER") || $0.description.hasPrefix("LUCKY 7")
            }
          }
          if !dealerBonusResults.isEmpty {
            self.reconstructBonusChipsForDealerOutcome(results: dealerBonusResults)
            self.showBonusBetControl(animated: true)
            self.animateBonusBetResults(dealerBonusResults, isDealerOutcome: true) { [weak self] in
              guard let self = self else { return }
              self.reconcileBets(snapshot: snapshot)
            }
          } else {
            self.reconcileBets(snapshot: snapshot)
          }
        }
      } else {
        print("⚠️ [MP-VC] End phase reached but handResults is EMPTY — computing from seat data")
        let dealerAnimDelay: TimeInterval =
          dealerCardQueue.isEmpty ? 0.5 : Double(dealerCardQueue.count) * 0.8 + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + dealerAnimDelay) { [weak self] in
          guard let self = self else { return }
          let computed = self.computeHandResultsFromSeats(snapshot: snapshot)
          if !computed.isEmpty {
            self.reconcileBetsWithResults(computed)
          }
        }
      }
    }

    let isInitialDeal = isInitialDealSnapshot(snapshot, previous: previous)
    print(
      "🎮 [MultiplayerBlackjack] isInitialDeal=\(isInitialDeal), previous phase=\(previous?.phase ?? "nil"), isDealAnimationRunning=\(isDealAnimationRunning)"
    )
    if isInitialDeal {
      // Freeze balance before deal animation when dealer has blackjack (server already resolved).
      // observeSeats may deliver the post-payout balance during the animation; freezing prevents contamination.
      if snapshot.dealerHasBlackjack && !isBalanceFrozenForSettlement {
        isBalanceFrozenForSettlement = true
        preBetSettlementBalance = balance
        print(
          "BAL_BUG [dealerBJ-preDeal] freezing balance at \(balance) for dealer blackjack settlement"
        )
      }
      print("🎮 [MultiplayerBlackjack] CALLING runInitialDealAnimation")
      runInitialDealAnimation(snapshot: snapshot, deckCenter: deckCenter)
    } else if isDealAnimationRunning {
      print(
        "🎮 [MultiplayerBlackjack] Skipping applyCardsWithoutDealAnimation — deal animation still running"
      )
    } else {
      print("🎮 [MultiplayerBlackjack] CALLING applyCardsWithoutDealAnimation")
      applyCardsWithoutDealAnimation(snapshot: snapshot, deckCenter: deckCenter)
    }

    // Update snapshot tracking for phase transition detection
    previousGameSnapshot = lastGameSnapshot
    lastGameSnapshot = snapshot
  }

  /// True when we just transitioned to player_actions (or dealer_turn when all have blackjack,
  /// or between_hands when dealer has blackjack) with 2 cards per hand and 2 dealer cards.
  private func isInitialDealSnapshot(
    _ snapshot: MPBlackjackTableState.GameStateSnapshot,
    previous: MPBlackjackTableState.GameStateSnapshot?
  ) -> Bool {
    let phase = snapshot.phase ?? ""
    let prevPhase = previous?.phase ?? ""
    let fromBetting = (prevPhase == MultiplayerBlackjackKeys.Phases.betting || prevPhase == "")
    let isDealerBJFromBetting =
      (phase == MultiplayerBlackjackKeys.Phases.betweenHands && fromBetting
        && snapshot.dealerHasBlackjack)
    guard
      phase == MultiplayerBlackjackKeys.Phases.playerActions
        || (phase == MultiplayerBlackjackKeys.Phases.dealerTurn && fromBetting)
        || isDealerBJFromBetting
    else {
      return false
    }
    guard
      prevPhase != MultiplayerBlackjackKeys.Phases.playerActions
        && prevPhase != MultiplayerBlackjackKeys.Phases.dealerTurn
    else { return false }
    guard snapshot.dealerCards.count == 2 else { return false }
    let playerHands = getPlayerHandsFromSeats()
    let seatIndices = playerHands.keys.sorted()
    guard !seatIndices.isEmpty else { return false }
    for seatIndex in seatIndices {
      guard let hands = playerHands[seatIndex], !hands.isEmpty else { return false }
      let cards = hands[0][MultiplayerBlackjackKeys.HandData.cards] as? [[String: Any]] ?? []
      guard cards.count == 2 else { return false }
    }
    return true
  }

  /// Deal order: each player first card, dealer first (face down), each player second card, dealer second (face up). Uses 0.3s delay between cards like BlackjackGameplayViewController.
  /// Uses self.view as container (like single-player) so dealCard can correctly convert coordinates from deck to cardContainer.
  private func runInitialDealAnimation(
    snapshot: MPBlackjackTableState.GameStateSnapshot, deckCenter: CGPoint
  ) {
    isDealAnimationRunning = true
    hideTurnIndicatorDot()
    cardApplyGeneration += 1
    updateInstructionLabelIfNeeded("Dealing cards...", shouldFade: false)

    // Ensure bonus bet control remains visible during dealing (will be hidden after resolution)
    if mpBonusBetControl.isHidden && mpBonusBetControl.chipCount > 0 {
      showBonusBetControl(animated: false)
    }

    // Clear placeholder cards so real cards can be dealt in their place
    let playerHands = getPlayerHandsFromSeats()
    for (seatIndex, hands) in playerHands {
      guard let seatView = seatViewsByIndex[seatIndex] else { continue }
      for (handIndex, _) in hands.enumerated() {
        let handView =
          handIndex == 0
          ? seatView.primaryHand
          : (seatView.hands.count > handIndex ? seatView.hands[handIndex] : nil)
        handView?.handView.clearCards()
        // clearCards() already clears faceDownCardIndices, so cards will be face up when dealt
      }
    }
    dealerHandView.setCardsWithoutAnimation([])

    // Force layout so each hand's cardContainer has a valid frame before we animate
    view.setNeedsLayout()
    view.layoutIfNeeded()

    // Scroll the first seat into view if needed so its hand has a valid frame
    if let firstSeatIndex = playerHands.keys.sorted().first,
      let firstSeatView = seatViewsByIndex[firstSeatIndex]
    {
      let seatRect = firstSeatView.convert(firstSeatView.bounds, to: seatsScrollView)
      seatsScrollView.scrollRectToVisible(seatRect, animated: false)
    }

    // One more layout pass after scrolling to ensure cardContainer frames are correct
    view.layoutIfNeeded()

    // Small delay to ensure layout is fully complete before starting animations
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      guard let self = self else { return }
      self.startDealAnimationSteps(snapshot: snapshot)
    }
  }

  private func startDealAnimationSteps(snapshot: MPBlackjackTableState.GameStateSnapshot) {
    let playerHands = getPlayerHandsFromSeats()
    let seatIndices = playerHands.keys.sorted()

    // Scroll to user's seat at the start of dealing so they can see their cards
    if playerHands.keys.contains(mySeatIndex) {
      scrollToSeat(mySeatIndex, animated: true)
    }

    // Extract cards in deal order: each player first card, dealer first, each player second card, dealer second
    var playerFirstCards:
      [(card: BlackjackHandView.Card, hand: CompactPlayerHandView, seatIndex: Int)] = []
    var playerSecondCards:
      [(card: BlackjackHandView.Card, hand: CompactPlayerHandView, seatIndex: Int)] = []

    for seatIndex in seatIndices {
      guard let hands = playerHands[seatIndex], !hands.isEmpty,
        let cardsRaw = hands[0][MultiplayerBlackjackKeys.HandData.cards] as? [[String: Any]],
        let seatView = seatViewsByIndex[seatIndex]
      else {
        print("⚠️ [MultiplayerBlackjack] Skipping seat \(seatIndex) - no hands or seatView")
        continue
      }
      let hand = seatView.primaryHand
      if cardsRaw.count >= 1, let card = cardFromFirebase(cardsRaw[0]) {
        playerFirstCards.append((card, hand, seatIndex))
      }
      if cardsRaw.count >= 2, let card = cardFromFirebase(cardsRaw[1]) {
        playerSecondCards.append((card, hand, seatIndex))
      }
    }

    let dealerCard1: BlackjackHandView.Card? = snapshot.dealerCards.first.flatMap {
      cardFromFirebase($0)
    }
    let dealerCard2: BlackjackHandView.Card? =
      (snapshot.dealerCards.count >= 2) ? cardFromFirebase(snapshot.dealerCards[1]) : nil

    // Deal player's first cards (recalculate deck center for each card like single-player)
    for (idx, step) in playerFirstCards.enumerated() {
      let delay = Double(idx) * 0.3
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self = self else { return }
        // Scroll to user's seat right before their first card is dealt
        if step.seatIndex == self.mySeatIndex {
          self.scrollToSeat(self.mySeatIndex, animated: true)
        }
        let deckCenter = self.view.convert(self.deckView.deckCenter, from: self.deckView)
        step.hand.dealCard(step.card, from: deckCenter, in: self.view)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          // Ensure card is face up (reveal if it was dealt face down)
          let cardCount = step.hand.currentCards.count
          if cardCount > 0 {
            step.hand.revealCard(at: cardCount - 1, animated: false)
          }
          if step.hand.currentCards.isEmpty {
            print("❌ [MultiplayerBlackjack] Card not set after deal animation, setting directly")
            step.hand.setCardsWithoutAnimation([step.card])
          }
        }
      }
    }

    // Deal dealer's first card (face down) after all player first cards
    if let card = dealerCard1 {
      let delay = Double(playerFirstCards.count) * 0.3
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self = self else { return }
        let deckCenter = self.view.convert(self.deckView.deckCenter, from: self.deckView)
        self.dealerHandView.dealCardFaceDown(card, from: deckCenter, in: self.view)
      }
    }

    // Deal player's second cards
    for (idx, step) in playerSecondCards.enumerated() {
      let delay = Double(playerFirstCards.count + 1 + idx) * 0.3
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self = self else { return }
        // Scroll to user's seat right before their second card is dealt
        if step.seatIndex == self.mySeatIndex {
          self.scrollToSeat(self.mySeatIndex, animated: true)
        }
        print(
          "🎴 [MultiplayerBlackjack] Dealing second card to seat \(step.seatIndex) at delay \(delay)"
        )
        let deckCenter = self.view.convert(self.deckView.deckCenter, from: self.deckView)
        print(
          "🎴 [MultiplayerBlackjack] Hand before deal: \(step.hand.currentCards.count) cards, card: \(step.card.rank) \(step.card.suit)"
        )
        step.hand.dealCard(step.card, from: deckCenter, in: self.view)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          print(
            "🎴 [MultiplayerBlackjack] Hand after deal animation: \(step.hand.currentCards.count) cards"
          )
          // Ensure card is face up (reveal if it was dealt face down)
          let cardCount = step.hand.currentCards.count
          if cardCount > 0 {
            step.hand.revealCard(at: cardCount - 1, animated: false)
          }
          if step.hand.currentCards.count < 2 {
            // Fallback: if second card wasn't set, get all cards from Firebase and set directly
            let playerHands = self.getPlayerHandsFromSeats()
            if let hands = playerHands[step.seatIndex], !hands.isEmpty,
              let cardsRaw = hands[0][MultiplayerBlackjackKeys.HandData.cards] as? [[String: Any]]
            {
              let allCards = cardsRaw.compactMap { self.cardFromFirebase($0) }
              step.hand.setCardsWithoutAnimation(allCards)
              // Reveal all cards to ensure they're face up
              for i in 0..<allCards.count {
                step.hand.revealCard(at: i, animated: false)
              }
            }
          }
        }
      }
    }

    // Deal dealer's second card (face up) after all player second cards
    let lastCardDelay: Double
    if let card = dealerCard2 {
      lastCardDelay = Double(playerFirstCards.count + 1 + playerSecondCards.count) * 0.3
      DispatchQueue.main.asyncAfter(deadline: .now() + lastCardDelay) { [weak self] in
        guard let self = self else { return }
        let deckCenter = self.view.convert(self.deckView.deckCenter, from: self.deckView)
        self.dealerHandView.dealCard(card, from: deckCenter, in: self.view)
      }
    } else {
      lastCardDelay = Double(playerFirstCards.count + 1 + playerSecondCards.count - 1) * 0.3
    }

    // After all cards are dealt, check for dealer blackjack, then detect player blackjacks and show turn UI
    let completionDelay = lastCardDelay + 0.5
    DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) { [weak self] in
      guard let self = self else { return }
      self.isDealAnimationRunning = false
      self.isDealInProgress = false
      self.dealButton.isEnabled = true
      guard let snapshot = self.lastGameSnapshot else { return }

      // Seed tracking BEFORE applying cards so that stood-transition detection works
      // correctly. Every hand starts the deal as not-stood with 2 cards; if the server
      // has already auto-resolved a blackjack by the time the deal animation finishes,
      // applyCardsWithoutDealAnimation will see the stood transition and trigger payout.
      let dealtHands = self.getPlayerHandsFromSeats()
      for (seatIdx, hands) in dealtHands {
        for (handIdx, handDict) in hands.enumerated() {
          let cards = (handDict[MultiplayerBlackjackKeys.HandData.cards] as? [[String: Any]] ?? [])
          let trackingKey = seatIdx * 10 + handIdx
          self.previousCardCountsBySeat[trackingKey] = cards.count
          // Always seed as not-stood so we detect the stood transition
          self.previousHasStoodBySeat[trackingKey] = false
        }
      }

      // Re-apply the latest snapshot's cards now that the animation is done.
      // Snapshots that arrived during the deal animation were skipped to prevent
      // duplicate cards; this catches up on any card changes (e.g. a fast player
      // who acted while the deal animation was still running).
      let deckCenter = self.view.convert(self.deckView.deckCenter, from: self.deckView)
      self.applyCardsWithoutDealAnimation(snapshot: snapshot, deckCenter: deckCenter)

      // Server already resolved dealer blackjack — animate the reveal without calling Cloud Function
      if snapshot.dealerHasBlackjack {
        self.animateServerResolvedDealerBlackjack(snapshot: snapshot)
        return
      }

      let dealerCards = self.dealerHandView.currentCards
      if dealerCards.count >= 2 {
        let holeCard = dealerCards[0]
        let upCard = dealerCards[1]
        if upCard.rank == .ace {
          self.resolvePairBonusBetsAfterDealIfNeeded(snapshot: snapshot) { [weak self] in
            guard let self = self else { return }
            self.startInsurancePhase(snapshot: snapshot, holeCard: holeCard, upCard: upCard)
          }
          return
        }
        if self.isTenValueRank(upCard.rank) {
          self.peekForDealerBlackjack(
            holeCard: holeCard,
            upCard: upCard,
            snapshot: snapshot
          ) { [weak self] in
            guard let self = self else { return }
            // Blackjacks are now resolved when it's the player's turn, not immediately after dealing
            self.runShowTurnUIAfterDeal(bjAnimDuration: 0)
          }
          return
        }
      }

      // Normal flow (no peek-eligible upcard)
      // Blackjacks are now resolved when it's the player's turn, not immediately after dealing
      self.runShowTurnUIAfterDeal(bjAnimDuration: 0)
    }
  }

  private func runShowTurnUIAfterDeal(bjAnimDuration: TimeInterval) {
    let showTurnUI = { [weak self] in
      guard let self = self else { return }
      guard let snapshot = self.lastGameSnapshot else { return }
      let phase = snapshot.phase ?? ""
      let turn = snapshot.currentTurn
      let isMyTurn = (turn?.seatIndex == self.mySeatIndex)

      // After deal animation completes, check if current player has blackjack
      // This ensures we wait for deal animation before calling stand (normal cadence)
      if phase == MultiplayerBlackjackKeys.Phases.playerActions,
        let turn = turn,
        turn.seatIndex == self.mySeatIndex,
        !self.isActionInFlight,
        !self.isBlackjackPayoutAnimating
      {
        let myHandsData = self.currentSeatsData[self.mySeatIndex]?.hands ?? []
        let myHandData =
          turn.handIndex < myHandsData.count ? myHandsData[turn.handIndex] : myHandsData.first
        if let handData = myHandData,
          handData.cards.count == 2
        {
          let cards = handData.cards.compactMap { self.cardFromFirebase($0) }
          if cards.count == 2 && self.blackjackTotal(cards) == 21 {
            // Deal animation is done, player has blackjack - wait a moment for normal cadence, then call stand
            // The payout will happen when the hand becomes stood (normal flow)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
              guard let self = self else { return }
              // Double-check it's still our turn and we still have blackjack
              if let currentSnapshot = self.lastGameSnapshot,
                let currentTurn = currentSnapshot.currentTurn,
                currentTurn.seatIndex == self.mySeatIndex,
                currentTurn.handIndex == turn.handIndex,
                !self.isActionInFlight,
                !self.isBlackjackPayoutAnimating
              {
                self.callPlayerAction(MultiplayerBlackjackKeys.Actions.stand)
              }
            }
          }
        }
      }

      if phase == MultiplayerBlackjackKeys.Phases.playerActions {
        let turnMessage: String
        if isMyTurn {
          turnMessage = "Tap your hand to Hit"
        } else if let si = turn?.seatIndex, let name = self.currentSeatsData[si]?.displayLabel {
          turnMessage = "\(name)'s turn"
        } else {
          turnMessage = "Waiting for other players"
        }
        self.updateInstructionLabelIfNeeded(turnMessage, shouldFade: false)
        if let seatIndex = turn?.seatIndex {
          let handIndex = turn?.handIndex ?? 0
          self.scrollToSeatHand(seatIndex, handIndex: handIndex, animated: true)
        }
        self.updateTurnIndicatorDot(for: turn?.seatIndex, handIndex: turn?.handIndex ?? 0)
        self.refreshButtonVisibility(for: snapshot)
      } else if phase == MultiplayerBlackjackKeys.Phases.dealerTurn {
        self.refreshButtonVisibility(for: snapshot)
      } else if phase == MultiplayerBlackjackKeys.Phases.betweenHands {
        self.refreshButtonVisibility(for: snapshot)
      }
    }

    // Animate pair-based bonus bet results before showing turn UI
    let afterBjDelay = max(bjAnimDuration, 0)
    let runAfterBonusBets = { [weak self] in
      guard let self = self else { return }
      guard let snapshot = self.lastGameSnapshot else {
        showTurnUI()
        return
      }

      // Check if anyone placed a bonus bet - if not, hide the control
      let totalBonusBets = self.currentSeatsData.values.reduce(0) { total, seatData in
        total + (seatData.bonusBets[0] ?? 0)
      }
      if totalBonusBets == 0 {
        self.hideBonusBetControl(animated: true)
      }

      if !snapshot.bonusBetResults.isEmpty && !self.bonusBetResultsProcessed {
        self.bonusBetResultsProcessed = true
        self.animateBonusBetResults(snapshot.bonusBetResults, isDealerOutcome: false) {
          showTurnUI()
        }
      } else {
        showTurnUI()
      }
    }

    if afterBjDelay > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + afterBjDelay, execute: runAfterBonusBets)
    } else {
      runAfterBonusBets()
    }
  }

  /// Resolve pair-based bonus bets after initial deal before progressing to insurance/turn UI.
  private func resolvePairBonusBetsAfterDealIfNeeded(
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    completion: @escaping () -> Void
  ) {
    // Check if anyone placed a bonus bet - if not, hide the control
    let totalBonusBets = currentSeatsData.values.reduce(0) { total, seatData in
      total + (seatData.bonusBets[0] ?? 0)
    }
    if totalBonusBets == 0 {
      hideBonusBetControl(animated: true)
    }

    if !snapshot.bonusBetResults.isEmpty && !bonusBetResultsProcessed {
      bonusBetResultsProcessed = true
      animateBonusBetResults(snapshot.bonusBetResults, isDealerOutcome: false) {
        completion()
      }
    } else {
      completion()
    }
  }

  /// Animate dealer blackjack that was already resolved server-side in startDeal.
  /// Reveals the hole card, animates bet losses/pushes, discards hands, then refreshes UI.
  /// Does NOT call callResolveDealerBlackjack() since the server already set phase to between_hands.
  private func animateServerResolvedDealerBlackjack(
    snapshot: MPBlackjackTableState.GameStateSnapshot
  ) {
    dealerHandView.revealHoleCard(animated: true)
    updateInstructionLabelIfNeeded("Dealer Blackjack!", shouldFade: false)
    dealerCardsRenderedCount = dealerHandView.currentCards.count

    // Check if anyone placed a bonus bet - if not, hide the control
    let totalBonusBets = currentSeatsData.values.reduce(0) { total, seatData in
      total + (seatData.bonusBets[0] ?? 0)
    }
    if totalBonusBets == 0 {
      hideBonusBetControl(animated: true)
    }

    if !isBalanceFrozenForSettlement {
      isBalanceFrozenForSettlement = true
      preBetSettlementBalance = balance
    }

    var animationDelay: TimeInterval = 0.6
    let topLeft = CGPoint(x: 0, y: 0)
    var maxDelay: TimeInterval = 0.6

    for (seatIndex, seatData) in currentSeatsData {
      guard let hand = seatData.hands.first, hand.bet > 0 else { continue }
      guard let seatView = seatViewsByIndex[seatIndex] else { continue }
      let cards = hand.cards.compactMap { cardFromFirebase($0) }
      let playerIsBlackjack = cards.count == 2 && blackjackTotal(cards) == 21
      if playerIsBlackjack {
        seatView.primaryHand.broadcastAction("Blackjack!")
      }
      let bet = hand.bet
      let result: MPBlackjackTableState.HandResult =
        playerIsBlackjack
        ? MPBlackjackTableState.HandResult(outcome: "push", payout: bet, bet: bet)
        : MPBlackjackTableState.HandResult(outcome: "lose", payout: 0, bet: bet)

      bustAnimatedSeatIndices.insert(seatIndex)
      let isLocal = (seatIndex == mySeatIndex)
      let delay = animationDelay

      if result.isPush {
        pushBetsBySeatIndex[seatIndex] = result.bet
        // Broadcast "Push" message to the table
        seatView.primaryHand.broadcastAction("Push")
        if isLocal {
          animateLocalPlayerPush(seat: seatView, result: result, delay: delay)
        }
      } else {
        if isLocal {
          animateLocalPlayerLoss(seat: seatView, result: result, delay: delay)
          DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) { [weak self] in
            self?.showBetResult(amount: result.bet, isWin: false)
          }
        } else {
          animateRemotePlayerLoss(seat: seatView, result: result, delay: delay)
        }
      }

      let discardDelay = delay + 1.2
      DispatchQueue.main.asyncAfter(deadline: .now() + discardDelay) { [weak self] in
        guard let self = self else { return }
        seatView.primaryHand.discardCards(to: topLeft, in: self.view) {}
      }
      maxDelay = max(maxDelay, discardDelay + 0.5)
      animationDelay += 0.15
    }

    // After all animations, show the between_hands UI and auto-advance if host
    DispatchQueue.main.asyncAfter(deadline: .now() + maxDelay) { [weak self] in
      guard let self = self else { return }
      guard let snapshot = self.lastGameSnapshot else { return }
      self.refreshButtonVisibility(for: snapshot)
      self.scrollToSeat(self.mySeatIndex, animated: true)
      if self.isHost {
        self.callStartNextHand()
      }
    }
  }

  /// When dealer's upcard is a 10-value card or Ace, check the hole card for a complementary blackjack card.
  /// If dealer has blackjack: reveal hole card, resolve all bets (losses/pushes), discard hands.
  /// If not: play spread animation then continue with normal post-deal flow.
  private func peekForDealerBlackjack(
    holeCard: BlackjackHandView.Card,
    upCard: BlackjackHandView.Card,
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    continueWithNormalFlow: @escaping () -> Void
  ) {
    let hasDealerBlackjack = blackjackTotal([holeCard, upCard]) == 21

    if hasDealerBlackjack {
      dealerHandView.revealHoleCard(animated: true)

      // Pay insurance (2:1) for the local player if they took insurance
      let localSeatData = currentSeatsData[mySeatIndex]
      let insuranceBet = max(localInsuranceBetAmount, localSeatData?.insuranceBet ?? 0)
      let anyInsuranceBets = mpInsuranceControl.chipCount > 0 || insuranceBet > 0

      if insuranceBet > 0 {
        let insuranceWin = insuranceBet * 2
        balance += insuranceWin
        tableState.updateBalance(playerId: MultiplayerPlayerIdKey.value, balance: balance)
      }
      localInsuranceBetAmount = 0

      // Sync rendered count so the observer doesn't re-deal existing cards
      dealerCardsRenderedCount = dealerHandView.currentCards.count
      callResolveDealerBlackjack()

      if !isBalanceFrozenForSettlement {
        isBalanceFrozenForSettlement = true
        preBetSettlementBalance = balance
      }

      // Capture which seats have insurance bets before async work changes state
      var styleToSeat: [MPSmallBetChipStyle: Int] = [:]
      for (seatIndex, seatData) in currentSeatsData {
        if seatData.insuranceBet > 0 {
          styleToSeat[chipStyleForColorName(seatData.chipColorName)] = seatIndex
        }
      }

      // Mark all seats as already-animated NOW so the observer-driven reconcileBets
      // (which fires when between_hands arrives) skips them instead of double-animating.
      for (seatIndex, seatData) in currentSeatsData {
        guard seatData.hands.first?.bet ?? 0 > 0 else { continue }
        bustAnimatedSeatIndices.insert(seatIndex)
      }

      // --- Phase 1: Insurance payout (visible to all players) ---
      let insuranceDisplayDuration: TimeInterval
      if anyInsuranceBets {
        mpInsuranceControl.updateTitle("Insurance Pays!")
        updateInstructionLabelIfNeeded("Dealer Blackjack! Insurance pays 2:1", shouldFade: false)
        mpInsuranceControl.playWinAnimation()
        if insuranceBet > 0 {
          showBetResult(amount: insuranceBet * 2, isWin: true, description: "INSURANCE")
        }
        insuranceDisplayDuration = 2.0
      } else {
        updateInstructionLabelIfNeeded("Dealer Blackjack!", shouldFade: false)
        insuranceDisplayDuration = 0.8
      }

      // --- Phase 2: Animate dots from chips to player balances, then hide control ---
      DispatchQueue.main.asyncAfter(deadline: .now() + insuranceDisplayDuration) { [weak self] in
        guard let self = self else { return }

        self.animateInsurancePayoutDots(styleToSeat: styleToSeat) { [weak self] in
          guard let self = self else { return }
          self.mpInsuranceControl.animateChipsAway { [weak self] in
            self?.hideInsuranceControl(animated: true)
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.resolveMainBetsAfterDealerBlackjack()
          }
        }
      }
    } else {
      // No dealer blackjack — play spread animation first, then handle insurance loss
      dealerHandView.playSpreadAnimation()

      if localInsuranceBetAmount > 0 || mpInsuranceControl.chipCount > 0 {
        instructionLabel.showMessage("No dealer blackjack. Insurance lost.", shouldFade: true)
        localInsuranceBetAmount = 0
        // Wait for spread to be visible, then animate chips away
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
          self?.mpInsuranceControl.animateChipsAway {
            self?.hideInsuranceControl(animated: true)
          }
        }
      } else {
        hideInsuranceControl(animated: true)
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        continueWithNormalFlow()
      }
    }
  }

  /// Resolve main bets (losses / pushes / discards) after dealer blackjack.
  /// Called AFTER the insurance payout has been displayed and the control is hiding.
  private func resolveMainBetsAfterDealerBlackjack() {
    var animationDelay: TimeInterval = 0.3
    let topLeft = CGPoint(x: 0, y: 0)

    for (seatIndex, seatData) in currentSeatsData {
      guard let hand = seatData.hands.first, hand.bet > 0 else { continue }
      guard let seatView = seatViewsByIndex[seatIndex] else { continue }
      let cards = hand.cards.compactMap { cardFromFirebase($0) }
      let playerIsBlackjack = cards.count == 2 && blackjackTotal(cards) == 21
      if playerIsBlackjack {
        seatView.primaryHand.broadcastAction("Blackjack!")
      }
      let bet = hand.bet
      let result: MPBlackjackTableState.HandResult =
        playerIsBlackjack
        ? MPBlackjackTableState.HandResult(outcome: "push", payout: bet, bet: bet)
        : MPBlackjackTableState.HandResult(outcome: "lose", payout: 0, bet: bet)

      bustAnimatedSeatIndices.insert(seatIndex)
      let isLocal = (seatIndex == mySeatIndex)
      let delay = animationDelay

      if result.isPush {
        pushBetsBySeatIndex[seatIndex] = result.bet
        // Broadcast "Push" message to the table
        seatView.primaryHand.broadcastAction("Push")
        if isLocal {
          animateLocalPlayerPush(seat: seatView, result: result, delay: delay)
        }
      } else {
        if isLocal {
          animateLocalPlayerLoss(seat: seatView, result: result, delay: delay)
          DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) { [weak self] in
            self?.showBetResult(amount: result.bet, isWin: false)
          }
        } else {
          animateRemotePlayerLoss(seat: seatView, result: result, delay: delay)
        }
      }

      let discardDelay = delay + 1.2
      DispatchQueue.main.asyncAfter(deadline: .now() + discardDelay) { [weak self] in
        guard let self = self else { return }
        seatView.primaryHand.discardCards(to: topLeft, in: self.view) {}
      }
      animationDelay += 0.15
    }
  }

  /// Animate colored dots from each insurance chip on the control down to the
  /// corresponding player's balance area, then call completion.
  private func animateInsurancePayoutDots(
    styleToSeat: [MPSmallBetChipStyle: Int],
    completion: @escaping () -> Void
  ) {
    let chipPositions = mpInsuranceControl.chipPositions(in: view)
    guard !chipPositions.isEmpty else {
      completion()
      return
    }

    var longestFlight: TimeInterval = 0

    for entry in chipPositions {
      guard let seatIndex = styleToSeat[entry.style] else { continue }
      let dotColor = entry.style.strokeColor
      let isLocal = (seatIndex == mySeatIndex)

      let destination: CGPoint
      if isLocal {
        destination = balanceView.convert(
          CGPoint(x: balanceView.bounds.maxX - 30, y: balanceView.bounds.midY),
          to: view
        )
      } else if let seat = seatViewsByIndex[seatIndex],
        let balView = seat.subviews.compactMap({ $0 as? MPPlayerBalanceView }).first
      {
        destination = seat.convert(
          CGPoint(x: balView.frame.midX, y: balView.frame.midY),
          to: view
        )
      } else {
        continue
      }

      let dot = createRemoteDot(color: dotColor)
      dot.center = entry.center
      dot.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
      view.addSubview(dot)

      let flightDuration: TimeInterval = 0.4
      let fly = UIViewPropertyAnimator(
        duration: flightDuration,
        controlPoint1: CGPoint(x: 0.85, y: 0),
        controlPoint2: CGPoint(x: 0.15, y: 1)
      ) {
        dot.center = destination
        dot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
      }
      fly.addCompletion { _ in
        dot.removeFromSuperview()
      }
      fly.startAnimation()
      longestFlight = max(longestFlight, flightDuration)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + longestFlight + 0.1) {
      completion()
    }
  }

  // MARK: - Insurance Phase

  private func startInsurancePhase(
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    holeCard: BlackjackHandView.Card,
    upCard: BlackjackHandView.Card
  ) {
    isInsurancePhaseActive = true
    // Reset button color when insurance phase becomes active
    continueButton.setTitleColor(.white, for: .normal)
    localInsuranceBetAmount = 0
    previousInsuranceBySeat.removeAll()
    pendingInsuranceSnapshot = snapshot
    pendingInsuranceHoleCard = holeCard
    pendingInsuranceUpCard = upCard

    // Check if anyone placed a bonus bet - if not, hide the control
    let totalBonusBets = currentSeatsData.values.reduce(0) { total, seatData in
      total + (seatData.bonusBets[0] ?? 0)
    }
    if totalBonusBets == 0 {
      hideBonusBetControl(animated: true)
    }

    mpInsuranceControl.onTapped = { [weak self] in
      self?.handleInsuranceControlTapped()
    }

    mpInsuranceControl.isHidden = false
    mpInsuranceControl.alpha = 0
    UIView.animate(withDuration: 0.3) {
      self.mpInsuranceControl.alpha = 1
      self.view.layoutIfNeeded()
    }

    updateInsuranceStatusLabel()
    refreshButtonVisibility(for: snapshot)
    updateInstructionLabelIfNeeded("Insurance? Tap the shield, or Continue", shouldFade: false)
  }

  private func handleInsuranceControlTapped() {
    guard isInsurancePhaseActive else { return }

    if localInsuranceBetAmount > 0 {
      let refund = localInsuranceBetAmount
      balance += refund
      localInsuranceBetAmount = 0
      let myStyle = chipStyleForColorName(myChipColorName)
      mpInsuranceControl.removeInsuranceBet(for: myStyle)
      previousInsuranceBySeat[mySeatIndex] = 0
      tableState.placeInsuranceBet(seatIndex: mySeatIndex, amount: 0)
      tableState.updateBalance(playerId: MultiplayerPlayerIdKey.value, balance: balance)
      updateInsuranceStatusLabel()
      return
    }

    let mainBet = defaultSeat.primaryHand.betControl.betAmount
    let insuranceAmount = mainBet / 2
    guard insuranceAmount > 0, balance >= insuranceAmount else {
      HapticsHelper.lightHaptic()
      return
    }

    balance -= insuranceAmount
    localInsuranceBetAmount = insuranceAmount
    let myStyle = chipStyleForColorName(myChipColorName)
    mpInsuranceControl.addInsuranceBet(amount: insuranceAmount, chipStyle: myStyle)
    previousInsuranceBySeat[mySeatIndex] = insuranceAmount
    tableState.placeInsuranceBet(seatIndex: mySeatIndex, amount: insuranceAmount)
    tableState.updateBalance(playerId: MultiplayerPlayerIdKey.value, balance: balance)
    updateInsuranceStatusLabel()
  }

  @objc private func continueButtonTapped() {
    guard isInsurancePhaseActive else { return }
    HapticsHelper.lightHaptic()

    if localInsuranceBetAmount > 0 {
      tableState.placeInsuranceBet(seatIndex: mySeatIndex, amount: localInsuranceBetAmount)
    } else {
      tableState.declineInsurance(seatIndex: mySeatIndex)
    }

    // Change button color to systemBlue to show selection state
    UIView.animate(withDuration: 0.2) {
      self.continueButton.setTitleColor(.systemBlue, for: .normal)
    }

    updateInsuranceStatusLabel()
    checkIfAllPlayersDecidedInsurance()
  }

  /// Check if every occupied seat has decided on insurance. If so, resolve after a brief pause.
  private func checkIfAllPlayersDecidedInsurance() {
    guard isInsurancePhaseActive else { return }

    let allDecided = currentSeatsData.allSatisfy { $0.value.insuranceDecided }
    guard allDecided else { return }

    // Brief pause so the last decision is visible before the reveal
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.resolveInsurancePhase()
    }
  }

  private func resolveInsurancePhase() {
    guard isInsurancePhaseActive else { return }
    guard let snapshot = pendingInsuranceSnapshot,
      let holeCard = pendingInsuranceHoleCard,
      let upCard = pendingInsuranceUpCard
    else { return }

    isInsurancePhaseActive = false

    // Reset button color when insurance phase resolves
    continueButton.setTitleColor(.white, for: .normal)
    continueButton.isHidden = true
    continueButton.alpha = 0

    // Peek first (reveal / spread), THEN hide the insurance control afterward
    peekForDealerBlackjack(
      holeCard: holeCard,
      upCard: upCard,
      snapshot: snapshot
    ) { [weak self] in
      guard let self = self else { return }
      // Delay hiding the insurance control so the reveal/spread is visible first
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
        guard let self = self else { return }
        self.hideInsuranceControl(animated: true)
        // Blackjacks are now resolved when it's the player's turn, not immediately after dealing
        self.runShowTurnUIAfterDeal(bjAnimDuration: 0)
      }
    }

    pendingInsuranceSnapshot = nil
    pendingInsuranceHoleCard = nil
    pendingInsuranceUpCard = nil
  }

  private func hideInsuranceControl(animated: Bool) {
    guard !mpInsuranceControl.isHidden else { return }

    if animated {
      UIView.animate(
        withDuration: 0.3,
        animations: {
          self.mpInsuranceControl.alpha = 0
          self.view.layoutIfNeeded()
        }
      ) { _ in
        self.mpInsuranceControl.isHidden = true
        self.mpInsuranceControl.clearAllBets()
        self.mpInsuranceControl.updateTitle("Insurance")
      }
    } else {
      mpInsuranceControl.isHidden = true
      mpInsuranceControl.alpha = 0
      mpInsuranceControl.clearAllBets()
      mpInsuranceControl.updateTitle("Insurance")
    }
  }

  private func updateInsuranceStatusLabel() {
    guard let label = continueButton?.viewWithTag(999) as? UILabel else { return }
    if isInsurancePhaseActive {
      let hasInsurance = localInsuranceBetAmount > 0
      label.text = hasInsurance ? "Insured" : "Not Insured"
      label.textColor =
        hasInsurance
        ? HardwayColors.label.withAlphaComponent(0.9)
        : HardwayColors.label.withAlphaComponent(0.5)
    } else {
      label.text = ""
    }
  }

  /// Handle blackjack payout for a specific seat (called when a hand becomes stood with blackjack or when turn starts).
  /// Returns the total animation duration.
  @discardableResult
  private func handleBlackjackPayoutForSeat(
    seatIndex: Int, snapshot: MPBlackjackTableState.GameStateSnapshot, handIndex: Int = 0
  ) -> TimeInterval {
    guard let seatData = currentSeatsData[seatIndex],
      handIndex < seatData.hands.count
    else { return 0 }
    let hand = seatData.hands[handIndex]
    guard hand.cards.count == 2 else { return 0 }
    let cards = hand.cards.compactMap { cardFromFirebase($0) }
    guard cards.count == 2, blackjackTotal(cards) == 21 else { return 0 }
    guard let seatView = seatViewsByIndex[seatIndex] else { return 0 }

    // Skip if already animated
    if bustAnimatedSeatIndices.contains(seatIndex) {
      return 0
    }

    // Get the correct hand view (for split hands)
    let handView =
      handIndex < seatView.hands.count ? seatView.hands[handIndex] : seatView.primaryHand

    handView.broadcastAction("Blackjack!")

    bustAnimatedSeatIndices.insert(seatIndex)

    let isLocal = (seatIndex == mySeatIndex)
    let bet = hand.bet
    let bjWin = Int(Double(bet) * 1.5)
    let payout = bet + bjWin
    let result = MPBlackjackTableState.HandResult(outcome: "blackjack", payout: payout, bet: bet)
    let delay: TimeInterval = 0.3

    if isLocal {
      // Freeze balance for this early payout
      if !isBalanceFrozenForSettlement {
        isBalanceFrozenForSettlement = true
        preBetSettlementBalance = balance
      }
      animateLocalPlayerWin(seat: seatView, result: result, delay: delay)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) { [weak self] in
        self?.showBetResult(
          amount: result.netWinnings, isWin: true, showBonus: true, description: "BLACKJACK")
      }
    } else {
      animateRemotePlayerWin(seat: seatView, result: result, delay: delay)
    }

    // Discard the blackjack hand's cards after payout animation lands
    let discardDelay = delay + 1.8
    DispatchQueue.main.asyncAfter(deadline: .now() + discardDelay) { [weak self] in
      guard let self = self else { return }
      let topLeft = CGPoint(x: 0, y: 0)
      handView.discardCards(to: topLeft, in: self.view) {}
    }

    let totalDuration = discardDelay + 0.5
    isBlackjackPayoutAnimating = true
    DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
      self?.isBlackjackPayoutAnimating = false
    }

    return totalDuration
  }

  /// After the deal animation, detect seats with natural blackjack (2 cards, total 21, stood by server).
  /// Immediately pay them out and discard their cards so the table moves on visually.
  /// Returns the total animation duration (0 when no blackjacks were found).
  @discardableResult
  private func handlePostDealBlackjacks(snapshot: MPBlackjackTableState.GameStateSnapshot)
    -> TimeInterval
  {
    var bjDelay: TimeInterval = 0.3
    var totalDuration: TimeInterval = 0
    var foundBlackjack = false
    for (seatIndex, seatData) in currentSeatsData {
      guard let hand = seatData.hands.first,
        hand.stood,
        hand.cards.count == 2
      else { continue }
      let cards = hand.cards.compactMap { cardFromFirebase($0) }
      guard cards.count == 2, blackjackTotal(cards) == 21 else { continue }
      guard let seatView = seatViewsByIndex[seatIndex] else { continue }

      // Broadcast "Blackjack!" message
      seatView.primaryHand.broadcastAction("Blackjack!")

      bustAnimatedSeatIndices.insert(seatIndex)

      let isLocal = (seatIndex == mySeatIndex)
      let bet = hand.bet
      let bjWin = Int(Double(bet) * 1.5)
      let payout = bet + bjWin
      let result = MPBlackjackTableState.HandResult(outcome: "blackjack", payout: payout, bet: bet)
      let delay = bjDelay

      if isLocal {
        // Freeze balance for this early payout
        if !isBalanceFrozenForSettlement {
          isBalanceFrozenForSettlement = true
          preBetSettlementBalance = balance
        }
        animateLocalPlayerWin(seat: seatView, result: result, delay: delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) { [weak self] in
          self?.showBetResult(
            amount: result.netWinnings, isWin: true, showBonus: true, description: "BLACKJACK")
        }
      } else {
        animateRemotePlayerWin(seat: seatView, result: result, delay: delay)
      }

      // Discard the blackjack hand's cards after payout animation lands
      let discardDelay = delay + 1.8
      DispatchQueue.main.asyncAfter(deadline: .now() + discardDelay) { [weak self] in
        guard let self = self else { return }
        let topLeft = CGPoint(x: 0, y: 0)
        seatView.primaryHand.discardCards(to: topLeft, in: self.view) {}
      }

      // discard animation takes ~0.5s after the discardDelay
      totalDuration = discardDelay + 0.5
      bjDelay += 0.3
      foundBlackjack = true
    }
    if foundBlackjack {
      isBlackjackPayoutAnimating = true
      DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
        self?.isBlackjackPayoutAnimating = false
      }
    }
    return totalDuration
  }

  private func applyCardsWithoutDealAnimation(
    snapshot: MPBlackjackTableState.GameStateSnapshot, deckCenter: CGPoint
  ) {
    cardApplyGeneration += 1
    let generation = cardApplyGeneration
    let phase = snapshot.phase ?? ""
    let playerHands = getPlayerHandsFromSeats()
    for (seatIndex, hands) in playerHands {
      guard let seatView = seatViewsByIndex[seatIndex] else { continue }
      if bustAnimatedSeatIndices.contains(seatIndex) { continue }

      // Reconcile hand view count: add or remove views to match Firebase data
      let previousHandCount = previousHandCountsBySeat[seatIndex] ?? seatView.hands.count
      reconcileHandViews(seat: seatView, seatIndex: seatIndex, firebaseHandCount: hands.count)
      
      // Detect and broadcast split actions for remote players
      if seatIndex != mySeatIndex && phase == MultiplayerBlackjackKeys.Phases.playerActions {
        let currentHandCount = hands.count
        if currentHandCount > previousHandCount {
          // Hand count increased - this indicates a split occurred
          // Broadcast on the primary hand (the one that was split)
          seatView.primaryHand.broadcastAction("Split!")
        }
      }
      
      // Update previous hand count for this seat
      previousHandCountsBySeat[seatIndex] = hands.count

      for (handIndex, handDict) in hands.enumerated() {
        let cardsRaw = handDict[MultiplayerBlackjackKeys.HandData.cards] as? [[String: Any]] ?? []
        let newCards = cardsRaw.compactMap { cardFromFirebase($0) }
        let handView =
          handIndex < seatView.hands.count ? seatView.hands[handIndex] : nil
        guard let hand = handView else { continue }
        let currentCount = hand.currentCards.count
        let isMySeat = (seatIndex == mySeatIndex && handIndex == activeHandIndex)
        let isMySeatAnyHand = (seatIndex == mySeatIndex)

        if seatIndex != mySeatIndex {
          let trackingKey = seatIndex * 10 + handIndex
          let previousCardCount = previousCardCountsBySeat[trackingKey] ?? 0
          let previousStood = previousHasStoodBySeat[trackingKey] ?? false
          let stood = (handDict[MultiplayerBlackjackKeys.HandData.stood] as? Bool) ?? false
          let doubled = (handDict[MultiplayerBlackjackKeys.HandData.doubled] as? Bool) ?? false
          let busted = (handDict[MultiplayerBlackjackKeys.HandData.busted] as? Bool) ?? false

          if phase == MultiplayerBlackjackKeys.Phases.playerActions {
            // Blackjack detection: hand became stood with 2 cards totaling 21
            if stood && !previousStood && !doubled && newCards.count == 2
              && blackjackTotal(newCards) == 21
            {
              if !bustAnimatedSeatIndices.contains(seatIndex) {
                print(
                  "🃏 [BJ-PAYOUT] Remote seat \(seatIndex) blackjack detected (previousStood=\(previousStood), stood=\(stood))"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                  guard let self = self else { return }
                  guard let snapshot = self.lastGameSnapshot else { return }
                  self.handleBlackjackPayoutForSeat(
                    seatIndex: seatIndex, snapshot: snapshot, handIndex: handIndex)
                }
              }
              previousCardCountsBySeat[trackingKey] = newCards.count
              previousHasStoodBySeat[trackingKey] = stood
              continue
            }

            if previousCardCount >= 2 {
              if stood && !previousStood && !doubled {
                hand.broadcastAction("Stand")
              }

              if newCards.count > previousCardCount {
                if doubled && newCards.count == 3 {
                  hand.broadcastAction("Double!")
                }
              }

              if busted && !bustAnimatedSeatIndices.contains(seatIndex) {
                let cardDealDelay = Double(max(0, newCards.count - currentCount)) * 0.25 + 0.3
                DispatchQueue.main.asyncAfter(deadline: .now() + cardDealDelay) { [weak hand] in
                  hand?.broadcastAction("Bust!")
                }
              }
            }
          }

          previousCardCountsBySeat[trackingKey] = newCards.count
          previousHasStoodBySeat[trackingKey] = stood
        }

        // Check if local player's hand became stood with blackjack
        if isMySeatAnyHand && phase == MultiplayerBlackjackKeys.Phases.playerActions {
          let trackingKey = seatIndex * 10 + handIndex
          let previousStood = previousHasStoodBySeat[trackingKey] ?? false
          let stood = (handDict[MultiplayerBlackjackKeys.HandData.stood] as? Bool) ?? false
          let doubled = (handDict[MultiplayerBlackjackKeys.HandData.doubled] as? Bool) ?? false
          if stood && !previousStood && !doubled && newCards.count == 2
            && blackjackTotal(newCards) == 21
          {
            if !bustAnimatedSeatIndices.contains(seatIndex) {
              print(
                "🃏 [BJ-PAYOUT] Local seat \(seatIndex) blackjack detected (previousStood=\(previousStood), stood=\(stood))"
              )
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                guard let snapshot = self.lastGameSnapshot else { return }
                self.handleBlackjackPayoutForSeat(
                  seatIndex: seatIndex, snapshot: snapshot, handIndex: handIndex)
              }
            }
            previousCardCountsBySeat[trackingKey] = newCards.count
            previousHasStoodBySeat[trackingKey] = stood
            continue
          }
          previousCardCountsBySeat[trackingKey] = newCards.count
          previousHasStoodBySeat[trackingKey] = stood
        }

        if isMySeat && !optimisticCardsForMyHand.isEmpty {
          let serverMatchesOptimistic =
            (newCards.count == hand.currentCards.count
              && zip(newCards, hand.currentCards).allSatisfy {
                $0.rank == $1.rank && $0.suit == $1.suit
              })
          if serverMatchesOptimistic {
            optimisticCardsForMyHand.removeAll()
            optimisticDeckIndex = snapshot.deckIndex
            isActionInFlight = false
            actionInFlightTimeoutWorkItem?.cancel()
            actionInFlightTimeoutWorkItem = nil
            refreshButtonVisibility(for: snapshot)
            continue
          }
          if newCards.count < hand.currentCards.count {
            continue
          }
          optimisticCardsForMyHand.removeAll()
          isActionInFlight = false
          actionInFlightTimeoutWorkItem?.cancel()
          actionInFlightTimeoutWorkItem = nil
        }
        if newCards.isEmpty {
          hand.setCardsWithoutAnimation([])
        } else if newCards.count > currentCount {
          if currentCount > 0 {
            hand.setCardsWithoutAnimation(Array(newCards.prefix(currentCount)))
          }
          for i in currentCount..<newCards.count {
            let card = newCards[i]
            let delay = Double(i - currentCount) * 0.25
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
              guard let self = self, self.cardApplyGeneration == generation else { return }
              let center = self.view.convert(self.deckView.deckCenter, from: self.deckView)
              hand.dealCard(card, from: center, in: self.view)
            }
          }
        } else {
          hand.setCardsWithoutAnimation(newCards)
        }

        let isBusted = (handDict[MultiplayerBlackjackKeys.HandData.busted] as? Bool) ?? false
        if isBusted && !bustAnimatedSeatIndices.contains(seatIndex) && seatIndex != mySeatIndex {
          bustAnimatedSeatIndices.insert(seatIndex)
          let bet = (handDict[MultiplayerBlackjackKeys.HandData.bet] as? Int) ?? 0
          let cardDealDelay = Double(max(0, newCards.count - currentCount)) * 0.25 + 0.6
          DispatchQueue.main.asyncAfter(deadline: .now() + cardDealDelay) { [weak self, hand] in
            guard let self = self else { return }
            if bet > 0 {
              let bustResult = MPBlackjackTableState.HandResult(
                outcome: "lose", payout: 0, bet: bet)
              self.animateRemotePlayerLoss(seat: seatView, result: bustResult, delay: 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self, hand] in
              guard let self = self else { return }
              let topLeft = CGPoint(x: 0, y: 0)
              hand.discardCards(to: topLeft, in: self.view) {}
            }
          }
        }
      }
    }

    let dealerCardsRaw = snapshot.dealerCards
    let newDealerCards = dealerCardsRaw.compactMap { cardFromFirebase($0) }

    let isDealerPhase =
      (phase == MultiplayerBlackjackKeys.Phases.dealerTurn
        || phase == MultiplayerBlackjackKeys.Phases.gameOver
        || phase == MultiplayerBlackjackKeys.Phases.betweenHands)

    if isDealerPhase && !newDealerCards.isEmpty {
      enqueueDealerCards(newDealerCards, holeRevealed: snapshot.dealerHoleRevealed)
    }
    if isDealerPhase {
      if snapshot.dealerHoleRevealed && dealerHandView.isHoleCardHidden() && !isDealerCardAnimating
      {
        dealerHandView.revealHoleCard(animated: true)
      }
    } else if !isDealerPhase {
      // During player actions phase, sync dealer cards but keep hole card hidden
      let currentDealerCount = dealerHandView.currentCards.count
      if newDealerCards.count > currentDealerCount {
        // Deal new cards (shouldn't happen during player actions, but handle gracefully)
        for i in currentDealerCount..<newDealerCards.count {
          let card = newDealerCards[i]
          // First card (index 0) should always be face down during player actions
          let faceDown = i == 0
          let delay = Double(i - currentDealerCount) * 0.5
          DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.cardApplyGeneration == generation else { return }
            let center = self.view.convert(self.deckView.deckCenter, from: self.deckView)
            if faceDown {
              self.dealerHandView.dealCardFaceDown(card, from: center, in: self.view)
            } else {
              self.dealerHandView.dealCard(card, from: center, in: self.view)
            }
          }
        }
      } else if !newDealerCards.isEmpty {
        // Sync existing cards but ensure hole card stays hidden
        dealerHandView.setCardsWithoutAnimation(newDealerCards)
      }
      // Do NOT reveal hole card during player actions phase - it should only be revealed
      // during dealer phase or when dealer has blackjack (handled separately)
    }
  }

  // MARK: - Bet reconciliation (payout / collect after dealer resolves)

  /// True while bet reconciliation animations are running (prevents duplicate triggers).
  private var isBetReconciliationRunning = false

  /// Reconcile bets using pre-parsed handResults from the snapshot.
  private func reconcileBets(snapshot: MPBlackjackTableState.GameStateSnapshot) {
    reconcileBetsWithResults(snapshot.handResults)
  }

  /// Reconcile bets after the dealer has resolved all hands.
  /// Animates wins (chips fly from house to player) and losses (chips fly from player to house).
  private func reconcileBetsWithResults(_ results: [Int: [MPBlackjackTableState.HandResult]]) {
    guard !isBetReconciliationRunning else { return }
    guard !results.isEmpty else { return }
    isBetReconciliationRunning = true
    print(
      "BAL_BUG [reconcileBets] settlement started — preBetSettlementBalance=\(preBetSettlementBalance), current balance=\(balance)"
    )
    print("💰 [MP-VC] reconcileBets: \(results.count) seats with results")

    // Scroll to user's hand when bet resolution begins so they can see their payout
    scrollToSeat(mySeatIndex, animated: true)

    var animationDelay: TimeInterval = 0.4

    for (seatIndex, handResults) in results {
      guard let seatView = seatViewsByIndex[seatIndex] else { continue }
      let isLocal = (seatIndex == mySeatIndex)

      for (handIdx, result) in handResults.enumerated() {
        let handView =
          handIdx < seatView.hands.count ? seatView.hands[handIdx] : seatView.primaryHand
        let alreadyAnimatedBust = bustAnimatedSeatIndices.contains(seatIndex) && result.isLoss

        if alreadyAnimatedBust {
          print("💰 [MP-VC] seat \(seatIndex) hand \(handIdx): SKIP (already animated bust)")
          continue
        }

        // Skip blackjack results that were already paid out during player turn
        if result.isBlackjack && bustAnimatedSeatIndices.contains(seatIndex) {
          // Verify it's actually a blackjack (2 cards, stood) and not a bust
          if let seatData = currentSeatsData[seatIndex],
            handIdx < seatData.hands.count,
            seatData.hands[handIdx].stood,
            seatData.hands[handIdx].cards.count == 2
          {
            print("💰 [MP-VC] seat \(seatIndex) hand \(handIdx): SKIP (blackjack already paid out)")
            continue
          }
        }

        if result.isWin || result.isBlackjack {
          let winnings = result.netWinnings
          if isLocal {
            animateLocalPlayerWin(
              seat: seatView, hand: handView, result: result, delay: animationDelay)
            let capturedDelay = animationDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + capturedDelay + 0.3) { [weak self] in
              self?.showBetResult(
                amount: winnings, isWin: true, showBonus: result.isBlackjack,
                description: result.isBlackjack ? "BLACKJACK" : nil)
            }
          } else {
            animateRemotePlayerWin(
              seat: seatView, hand: handView, result: result, delay: animationDelay)
          }
          print(
            "💰 [MP-VC] seat \(seatIndex) hand \(handIdx): WIN +\(winnings) (bet=\(result.bet), payout=\(result.payout))"
          )
        } else if result.isLoss {
          if isLocal {
            animateLocalPlayerLoss(
              seat: seatView, hand: handView, result: result, delay: animationDelay)
            let capturedDelay = animationDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + capturedDelay + 0.3) { [weak self] in
              self?.showBetResult(amount: result.bet, isWin: false)
            }
          } else {
            animateRemotePlayerLoss(
              seat: seatView, hand: handView, result: result, delay: animationDelay)
          }
          print("💰 [MP-VC] seat \(seatIndex) hand \(handIdx): LOSS -\(result.bet)")
        } else if result.isPush {
          pushBetsBySeatIndex[seatIndex] = result.bet
          handView.broadcastAction("Push")
          if isLocal {
            animateLocalPlayerPush(
              seat: seatView, hand: handView, result: result, delay: animationDelay)
          }
          print(
            "💰 [MP-VC] seat \(seatIndex) hand \(handIdx): PUSH (bet returned: \(result.bet))")
        }

        animationDelay += 0.15
      }

      // If ALL hands in this seat were already animated (bust), finalize balance
      if isLocal
        && handResults.allSatisfy({ bustAnimatedSeatIndices.contains(seatIndex) && $0.isLoss })
      {
        balance = preBetSettlementBalance
        isBalanceFrozenForSettlement = false
        print("💰 [MP-VC] seat \(seatIndex): all hands busted, finalizing balance")
      }
    }

    let totalAnimDuration = animationDelay + 1.5
    DispatchQueue.main.asyncAfter(deadline: .now() + totalAnimDuration) { [weak self] in
      guard let self = self else { return }
      self.isBetReconciliationRunning = false

      // Scroll back to user's hand so they can place bets for next hand
      self.scrollToSeat(self.mySeatIndex, animated: true)

      // Refresh UI to update instruction message now that bet reconciliation is complete
      if let snapshot = self.lastGameSnapshot {
        self.refreshButtonVisibility(for: snapshot)
      }

      if self.isHost {
        self.callStartNextHand()
      }
    }
  }

  /// Fallback: compute hand results client-side from seat data + dealer cards when Firebase handResults is missing.
  private func computeHandResultsFromSeats(snapshot: MPBlackjackTableState.GameStateSnapshot)
    -> [Int: [MPBlackjackTableState.HandResult]]
  {
    let dealerCards = snapshot.dealerCards.compactMap { cardFromFirebase($0) }
    let dealerTotal = blackjackTotal(dealerCards)
    let dealerBusted = dealerTotal > 21
    let dealerIsBlackjack = dealerCards.count == 2 && dealerTotal == 21
    var results: [Int: [MPBlackjackTableState.HandResult]] = [:]

    for (seatIndex, seatData) in currentSeatsData {
      guard let hand = seatData.hands.first, hand.bet > 0 else { continue }
      let playerCards = hand.cards.compactMap { cardFromFirebase($0) }
      let playerTotal = blackjackTotal(playerCards)
      let playerBusted = hand.busted || playerTotal > 21
      let playerIsBlackjack = playerCards.count == 2 && playerTotal == 21
      let bet = hand.bet

      let result: MPBlackjackTableState.HandResult
      if playerBusted {
        result = MPBlackjackTableState.HandResult(outcome: "lose", payout: 0, bet: bet)
      } else if playerIsBlackjack && !dealerIsBlackjack {
        let bjWin = Int(Double(bet) * 1.5)
        result = MPBlackjackTableState.HandResult(
          outcome: "blackjack", payout: bet + bjWin, bet: bet)
      } else if playerIsBlackjack && dealerIsBlackjack {
        result = MPBlackjackTableState.HandResult(outcome: "push", payout: bet, bet: bet)
      } else if dealerBusted {
        result = MPBlackjackTableState.HandResult(outcome: "win", payout: bet * 2, bet: bet)
      } else if playerTotal > dealerTotal {
        result = MPBlackjackTableState.HandResult(outcome: "win", payout: bet * 2, bet: bet)
      } else if playerTotal < dealerTotal {
        result = MPBlackjackTableState.HandResult(outcome: "lose", payout: 0, bet: bet)
      } else {
        result = MPBlackjackTableState.HandResult(outcome: "push", payout: bet, bet: bet)
      }
      results[seatIndex] = [result]
      print(
        "💰 [MP-VC] computed result for seat \(seatIndex): \(result.outcome) bet=\(bet) payout=\(result.payout)"
      )
    }
    return results
  }

  private func isTenValueRank(_ rank: PlayingCardView.Rank) -> Bool {
    return rank == .ten || rank == .king || rank == .queen || rank == .jack
  }

  private func blackjackTotal(_ cards: [BlackjackHandView.Card]) -> Int {
    var total = 0
    var aces = 0
    for card in cards {
      switch card.rank {
      case .ace:
        aces += 1
        total += 11
      case .king, .queen, .jack, .ten: total += 10
      case .nine: total += 9
      case .eight: total += 8
      case .seven: total += 7
      case .six: total += 6
      case .five: total += 5
      case .four: total += 4
      case .three: total += 3
      case .two: total += 2
      }
    }
    while total > 21 && aces > 0 {
      total -= 10
      aces -= 1
    }
    return total
  }

  // MARK: - Local player win/loss animations
  // Local player uses the same MPSmallBetChip / dot visual language as remote players,
  // but targets the bottom-left balanceView instead of the seat's MPPlayerBalanceView.

  private func animateLocalPlayerWin(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    let hand = targetHand ?? seat.primaryHand
    let winnings = result.netWinnings
    let payout = result.payout
    guard payout > 0 else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      let housePoint = CGPoint(x: self.view.bounds.midX, y: 0)
      let betPosition = hand.betControl.getBetViewPosition(in: self.view)
      let dotColor = seat.chipStyle.textColor

      let winChip = self.createRemoteMPChip(style: seat.chipStyle, amount: winnings)
      winChip.center = housePoint
      winChip.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
      self.view.addSubview(winChip)

      let step1 = UIViewPropertyAnimator(
        duration: 0.6, controlPoint1: CGPoint(x: 0.85, y: 0),
        controlPoint2: CGPoint(x: 0.15, y: 1)
      ) {
        winChip.center = CGPoint(x: betPosition.x + 25, y: betPosition.y)
        winChip.transform = .identity
      }

      step1.addCompletion { _ in
        winChip.playChipShimmer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
          guard let self = self else { return }
          let balanceCenter = self.balanceView.convert(
            CGPoint(x: self.balanceView.bounds.maxX - 30, y: self.balanceView.bounds.midY),
            to: self.view
          )

          let winDot = self.createRemoteDot(color: dotColor)
          winDot.center = winChip.center
          self.view.addSubview(winDot)
          winChip.removeFromSuperview()

          hand.betControl.betView.alpha = 0
          let betDot = self.createRemoteDot(color: dotColor)
          betDot.center = betPosition
          self.view.addSubview(betDot)

          let fly1 = UIViewPropertyAnimator(
            duration: 0.35, controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1)
          ) {
            winDot.center = balanceCenter
            winDot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
          }
          fly1.addCompletion { _ in
            winDot.removeFromSuperview()
          }

          let fly2 = UIViewPropertyAnimator(
            duration: 0.35, controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1)
          ) {
            betDot.center = balanceCenter
            betDot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
          }
          fly2.addCompletion { [weak self] _ in
            betDot.removeFromSuperview()
            hand.betControl.betAmount = 0
            hand.betControl.betView.alpha = 1
            if let self = self {
              let finalBalance = self.preBetSettlementBalance + payout
              print(
                "BAL_BUG [win animation] payout=\(payout) (bet=\(result.bet)), preBetSettlementBalance=\(self.preBetSettlementBalance) → finalBalance=\(finalBalance)"
              )
              self.balance = finalBalance
              self.isBalanceFrozenForSettlement = false
            }
          }

          fly1.startAnimation()
          fly2.startAnimation(afterDelay: 0.06)
        }
      }
      step1.startAnimation()
    }
  }

  private func animateLocalPlayerLoss(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    let hand = targetHand ?? seat.primaryHand
    guard result.bet > 0 else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      let betPosition = hand.betControl.getBetViewPosition(in: self.view)
      let housePoint = CGPoint(x: self.view.bounds.midX, y: 0)

      hand.betControl.betView.alpha = 0
      let dot = self.createRemoteDot(color: seat.chipStyle.textColor)
      dot.center = betPosition
      self.view.addSubview(dot)

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
        hand.betControl.betAmount = 0
      }

      let animator = UIViewPropertyAnimator(
        duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0),
        controlPoint2: CGPoint(x: 0.15, y: 1)
      ) {
        dot.center = housePoint
        dot.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
      }

      animator.addCompletion { [weak self] _ in
        UIView.animate(withDuration: 0.15) {
          dot.alpha = 0
        } completion: { [weak self] _ in
          dot.removeFromSuperview()
          hand.betControl.betView.alpha = 1
          if let self = self {
            print(
              "BAL_BUG [loss animation] restoring preBetSettlementBalance=\(self.preBetSettlementBalance) (current=\(self.balance))"
            )
            self.balance = self.preBetSettlementBalance
            self.isBalanceFrozenForSettlement = false
          }
        }
      }
      animator.startAnimation()
    }
  }

  /// Animate the local player's bet chip flying to the house on a bust.
  /// Unlike animateLocalPlayerLoss, this runs during player_actions (not settlement),
  /// so it only handles the visual — end-of-hand reconciliation manages the balance.
  private func animateLocalBustForfeit(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult
  ) {
    let hand = targetHand ?? seat.primaryHand
    guard result.bet > 0 else { return }

    let betPosition = hand.betControl.getBetViewPosition(in: view)
    let housePoint = CGPoint(x: view.bounds.midX, y: 0)

    hand.betControl.betView.alpha = 0
    let dot = createRemoteDot(color: seat.chipStyle.textColor)
    dot.center = betPosition
    view.addSubview(dot)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
      hand.betControl.betAmount = 0
    }

    let animator = UIViewPropertyAnimator(
      duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0),
      controlPoint2: CGPoint(x: 0.15, y: 1)
    ) {
      dot.center = housePoint
      dot.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
    }

    animator.addCompletion { _ in
      UIView.animate(withDuration: 0.15) {
        dot.alpha = 0
      } completion: { _ in
        dot.removeFromSuperview()
        hand.betControl.betView.alpha = 1
      }
    }
    animator.startAnimation()

    showBetResult(amount: result.bet, isWin: false)
  }

  private func animateLocalPlayerPush(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    guard result.bet > 0 else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      // Push: the bet stays exactly where it is — no chip movement animation.
      // Just restore the balance (it was deducted when the bet was placed).
      let finalBalance = self.preBetSettlementBalance + result.payout
      print(
        "BAL_BUG [push settle] payout=\(result.payout) (bet=\(result.bet)), preBetSettlementBalance=\(self.preBetSettlementBalance) → finalBalance=\(finalBalance)"
      )
      self.balance = finalBalance
      self.isBalanceFrozenForSettlement = false
    }
  }

  // MARK: - Remote player win/loss animations

  private func animateRemotePlayerWin(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    let hand = targetHand ?? seat.primaryHand
    let winnings = result.netWinnings
    guard winnings > 0 else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      let housePoint = CGPoint(x: self.view.bounds.midX, y: 0)
      let betPosition = hand.betControl.getBetViewPosition(in: self.view)
      let dotColor = seat.chipStyle.textColor

      let winChip = self.createRemoteMPChip(style: seat.chipStyle, amount: winnings)
      winChip.center = housePoint
      winChip.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
      self.view.addSubview(winChip)

      let step1 = UIViewPropertyAnimator(
        duration: 0.6, controlPoint1: CGPoint(x: 0.85, y: 0),
        controlPoint2: CGPoint(x: 0.15, y: 1)
      ) {
        winChip.center = CGPoint(x: betPosition.x + 25, y: betPosition.y)
        winChip.transform = .identity
      }

      step1.addCompletion { _ in
        winChip.playChipShimmer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
          guard let self = self else { return }
          guard let balView = seat.subviews.compactMap({ $0 as? MPPlayerBalanceView }).first else {
            winChip.removeFromSuperview()
            return
          }
          let balanceCenter = seat.convert(
            CGPoint(x: balView.frame.midX, y: balView.frame.midY),
            to: self.view
          )

          let winDot = self.createRemoteDot(color: dotColor)
          winDot.center = winChip.center
          self.view.addSubview(winDot)
          winChip.removeFromSuperview()

          hand.betControl.betView.alpha = 0
          let betDot = self.createRemoteDot(color: dotColor)
          betDot.center = betPosition
          self.view.addSubview(betDot)

          let fly1 = UIViewPropertyAnimator(
            duration: 0.35, controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1)
          ) {
            winDot.center = balanceCenter
            winDot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
          }
          fly1.addCompletion { _ in
            winDot.removeFromSuperview()
          }

          let fly2 = UIViewPropertyAnimator(
            duration: 0.35, controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1)
          ) {
            betDot.center = balanceCenter
            betDot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
          }
          fly2.addCompletion { _ in
            betDot.removeFromSuperview()
            hand.betControl.betAmount = 0
            hand.betControl.betView.alpha = 1
          }

          fly1.startAnimation()
          fly2.startAnimation(afterDelay: 0.06)
        }
      }
      step1.startAnimation()
    }
  }

  private func animateRemotePlayerLoss(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    let hand = targetHand ?? seat.primaryHand
    guard result.bet > 0 else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      let betPosition = hand.betControl.getBetViewPosition(in: self.view)
      let housePoint = CGPoint(x: self.view.bounds.midX, y: 0)

      hand.betControl.betView.alpha = 0
      let dot = self.createRemoteDot(color: seat.chipStyle.textColor)
      dot.center = betPosition
      self.view.addSubview(dot)

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
        hand.betControl.betAmount = 0
      }

      let animator = UIViewPropertyAnimator(
        duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0),
        controlPoint2: CGPoint(x: 0.15, y: 1)
      ) {
        dot.center = housePoint
        dot.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
      }

      animator.addCompletion { _ in
        UIView.animate(withDuration: 0.15) {
          dot.alpha = 0
        } completion: { _ in
          dot.removeFromSuperview()
          hand.betControl.betView.alpha = 1
        }
      }
      animator.startAnimation()
    }
  }

  // MARK: - Animation helpers

  private func createAnimationChip(amount: Int) -> SmallBetChip {
    let chip = SmallBetChip()
    chip.amount = amount
    chip.translatesAutoresizingMaskIntoConstraints = true
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    let size: CGFloat = isIPad ? 30 * 1.25 : 30
    chip.frame = CGRect(x: 0, y: 0, width: size, height: size)
    chip.isHidden = false
    return chip
  }

  private func createRemoteMPChip(style: MPSmallBetChipStyle, amount: Int) -> MPSmallBetChip {
    let chip = MPSmallBetChip(style: style)
    chip.translatesAutoresizingMaskIntoConstraints = true
    let chipSize: CGFloat = 30
    chip.frame = CGRect(x: 0, y: 0, width: chipSize, height: chipSize)
    chip.amount = amount
    chip.isHidden = false
    return chip
  }

  private func createRemoteDot(color: UIColor) -> UIView {
    let dot = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
    dot.backgroundColor = color
    dot.layer.cornerRadius = 4
    dot.layer.shadowColor = UIColor.black.cgColor
    dot.layer.shadowOpacity = 0.3
    dot.layer.shadowRadius = 2
    dot.layer.shadowOffset = CGSize(width: 0, height: 1)
    return dot
  }

  // MARK: - Dealer card queue animation

  /// Enqueue new dealer cards discovered from a snapshot and kick off sequential dealing.
  /// Only appends cards not already rendered or already in the queue (avoids duplicate cards when multiple snapshots arrive).
  private func enqueueDealerCards(_ allCards: [BlackjackHandView.Card], holeRevealed: Bool) {
    let newCount = allCards.count
    let committedCount = dealerCardsRenderedCount + dealerCardQueue.count
    if newCount > committedCount {
      let newCards = Array(allCards[committedCount..<newCount])
      dealerCardQueue.append(contentsOf: newCards)
    }
    // Only set dealerHoleRevealed during dealer phase to prevent premature reveals
    let phase = lastGameSnapshot?.phase ?? ""
    let isDealerPhase =
      (phase == MultiplayerBlackjackKeys.Phases.dealerTurn
        || phase == MultiplayerBlackjackKeys.Phases.gameOver
        || phase == MultiplayerBlackjackKeys.Phases.betweenHands)
    if holeRevealed && !dealerHoleRevealed && isDealerPhase {
      dealerHoleRevealed = true
    }
    processNextDealerCard()
  }

  /// Pop the next card from the queue, animate it, then schedule the next one after a delay.
  private func processNextDealerCard() {
    guard !isDealerCardAnimating else { return }

    // Only reveal hole card during dealer phase (dealerTurn, gameOver, or betweenHands)
    let phase = lastGameSnapshot?.phase ?? ""
    let isDealerPhase =
      (phase == MultiplayerBlackjackKeys.Phases.dealerTurn
        || phase == MultiplayerBlackjackKeys.Phases.gameOver
        || phase == MultiplayerBlackjackKeys.Phases.betweenHands)

    if dealerHoleRevealed && dealerHandView.isHoleCardHidden() && isDealerPhase {
      isDealerCardAnimating = true
      dealerHandView.revealHoleCard(animated: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        guard let self = self else { return }
        self.isDealerCardAnimating = false
        self.processNextDealerCard()
      }
      return
    }

    guard !dealerCardQueue.isEmpty else {
      // Dealer card queue drained; if we're between hands, refresh instruction so it updates from "Dealer's turn" to "Hand over..."
      if lastGameSnapshot?.phase == MultiplayerBlackjackKeys.Phases.betweenHands
        || lastGameSnapshot?.phase == MultiplayerBlackjackKeys.Phases.gameOver
      {
        if let s = lastGameSnapshot { refreshButtonVisibility(for: s) }
      }
      return
    }
    let card = dealerCardQueue.removeFirst()
    isDealerCardAnimating = true
    dealerCardsRenderedCount += 1

    let center = self.view.convert(self.deckView.deckCenter, from: self.deckView)
    dealerHandView.dealCard(card, from: center, in: self.view)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      guard let self = self else { return }
      self.isDealerCardAnimating = false
      self.processNextDealerCard()
    }
  }

  /// Reset dealer queue state when starting a new hand.
  private func resetDealerCardQueue() {
    dealerCardQueue.removeAll()
    isDealerCardAnimating = false
    dealerCardsRenderedCount = 0
    dealerHoleRevealed = false
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    if scrollView === seatsScrollView,
      lastGameSnapshot?.phase == MultiplayerBlackjackKeys.Phases.playerActions
    {
      updateTurnIndicatorDot(
        for: lastGameSnapshot?.currentTurn?.seatIndex,
        handIndex: lastGameSnapshot?.currentTurn?.handIndex ?? 0, animated: false)

      // If this is user-initiated scrolling (not programmatic), disable auto-scroll
      // until it's the user's turn
      if !isProgrammaticScroll {
        shouldIgnoreAutoScroll = true
      }
    }
  }

  private func handlePlayerRemoved() {
    // Remove observers to prevent further updates
    if let handle = seatsObserverHandle {
      tableState?.removeSeatsObserver(handle: handle)
      seatsObserverHandle = nil
    }
    if let handle = gameStateObserverHandle {
      tableState?.removeGameStateObserver(handle: handle)
      gameStateObserverHandle = nil
    }
    if let handle = hostPlayerIdObserverHandle {
      tableState?.removeHostPlayerIdObserver(handle: handle)
      hostPlayerIdObserverHandle = nil
    }
    removeConnectionObserver()

    // Show alert and dismiss
    let alert = UIAlertController(
      title: "Removed from Table",
      message: "You have been removed from the table by the host.",
      preferredStyle: .alert
    )

    alert.addAction(
      UIAlertAction(title: "OK", style: .default) { [weak self] _ in
        self?.navigationController?.popToRootViewController(animated: true)
      })

    present(alert, animated: true)
  }

  private func showLeaveTableConfirmation(popToRootOnLeave: Bool = true) {
    let alert = UIAlertController(
      title: "Leave Table?",
      message:
        "Are you sure you want to leave the table? Your seat will be freed for other players.",
      preferredStyle: .alert
    )

    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "Leave", style: .destructive) { [weak self] _ in
        self?.leaveTable(popToRoot: popToRootOnLeave)
      })

    present(alert, animated: true)
  }

  private func leaveTable(popToRoot: Bool = true) {
    // Remove observers
    if let handle = seatsObserverHandle {
      tableState?.removeSeatsObserver(handle: handle)
      seatsObserverHandle = nil
    }
    if let handle = hostPlayerIdObserverHandle {
      tableState?.removeHostPlayerIdObserver(handle: handle)
      hostPlayerIdObserverHandle = nil
    }
    removeConnectionObserver()

    // Leave the table in Firebase
    let playerId = MultiplayerPlayerIdKey.value
    tableState?.leaveTable(playerId: playerId) { [weak self] result in
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch result {
        case .success:
          print("✅ [MultiplayerBlackjack] Successfully left table")
        case .failure(let error):
          print("⚠️ [MultiplayerBlackjack] Error leaving table: \(error)")
        }
        if popToRoot {
          self.navigationController?.popToRootViewController(animated: true)
        } else {
          self.navigationController?.popViewController(animated: true)
        }
      }
    }
  }

}

// MARK: - ChipSelectorDelegate

extension MultiplayerBlackjackViewController: ChipSelectorDelegate {
  func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {}
}
