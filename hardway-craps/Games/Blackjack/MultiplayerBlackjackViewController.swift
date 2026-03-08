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
  private var seatViewsByIndex: [Int: PlayerSeat] {
    get { gameContext.seatViewsByIndex }
    set { gameContext.seatViewsByIndex = newValue }
  }
  /// Current seats data (updated by observeSeats)
  private var currentSeatsData: [Int: MPBlackjackTableState.SeatData] {
    get { gameContext.currentSeatsData }
    set { gameContext.currentSeatsData = newValue }
  }
  private var isDealAnimationRunning: Bool {
    get { gameContext.isDealAnimationRunning }
    set { gameContext.isDealAnimationRunning = newValue }
  }
  private var isDealInProgress: Bool {
    get { gameContext.isDealInProgress }
    set { gameContext.isDealInProgress = newValue }
  }
  private var isBlackjackPayoutAnimating: Bool {
    get { gameContext.isBlackjackPayoutAnimating }
    set { gameContext.isBlackjackPayoutAnimating = newValue }
  }
  private var cardApplyGeneration: Int {
    get { gameContext.cardApplyGeneration }
    set { gameContext.cardApplyGeneration = newValue }
  }
  private var previousHandsByIndex: [Int: [MPBlackjackTableState.HandData]] {
    get { handResetManager.previousHandsByIndex }
    set { handResetManager.previousHandsByIndex = newValue }
  }
  private var previousBalanceByIndex: [Int: Int] {
    get { handResetManager.previousBalanceByIndex }
    set { handResetManager.previousBalanceByIndex = newValue }
  }
  /// Track previous card counts and hasStood flags per seat to detect action changes
  private var previousCardCountsBySeat: [Int: Int] {
    get { dealAnimationController.previousCardCountsBySeat }
    set { dealAnimationController.previousCardCountsBySeat = newValue }
  }
  private var previousHasStoodBySeat: [Int: Bool] {
    get { dealAnimationController.previousHasStoodBySeat }
    set { dealAnimationController.previousHasStoodBySeat = newValue }
  }
  private var previousHandCountsBySeat: [Int: Int] {
    get { handResetManager.previousHandCountsBySeat }
    set { handResetManager.previousHandCountsBySeat = newValue }
  }
  private var isBalanceFrozenForSettlement: Bool {
    get { gameContext.isBalanceFrozenForSettlement }
    set { gameContext.isBalanceFrozenForSettlement = newValue }
  }
  private var preBetSettlementBalance: Int {
    get { gameContext.preBetSettlementBalance }
    set { gameContext.preBetSettlementBalance = newValue }
  }
  private var isBalanceFrozenForBetOperation: Bool {
    get { gameContext.isBalanceFrozenForBetOperation }
    set { gameContext.isBalanceFrozenForBetOperation = newValue }
  }
  private var expectedBalanceAfterBetOperation: Int? {
    get { gameContext.expectedBalanceAfterBetOperation }
    set { gameContext.expectedBalanceAfterBetOperation = newValue }
  }
  private var pushBetsBySeatIndex: [Int: Int] {
    get { gameContext.pushBetsBySeatIndex }
    set { gameContext.pushBetsBySeatIndex = newValue }
  }
  private var bustAnimatedSeatIndices: Set<Int> {
    get { gameContext.bustAnimatedSeatIndices }
    set { gameContext.bustAnimatedSeatIndices = newValue }
  }
  /// Track the last instruction message shown to prevent unnecessary animation restarts
  private var lastInstructionMessage: String?
  private let seatWidth: CGFloat = 180
  private let maxSeats = 5
  private var activeHandIndex: Int {
    get { gameContext.activeHandIndex }
    set { gameContext.activeHandIndex = newValue }
  }
  /// Small yellow dot above the current player's hand during player_actions; animated left/right when turn changes.
  private var turnIndicatorDot: UIView!
  private var turnIndicatorDotCenterXConstraint: NSLayoutConstraint?
  private var seatsObserverHandle: DatabaseHandle? {
    get { gameContext.seatsObserverHandle }
    set { gameContext.seatsObserverHandle = newValue }
  }
  private var gameStateObserverHandle: DatabaseHandle? {
    get { gameContext.gameStateObserverHandle }
    set { gameContext.gameStateObserverHandle = newValue }
  }
  private var hostPlayerIdObserverHandle: DatabaseHandle? {
    get { gameContext.hostPlayerIdObserverHandle }
    set { gameContext.hostPlayerIdObserverHandle = newValue }
  }
  /// The playerId of the current host as stored in Firebase. Authoritative source of host status.
  private var currentHostPlayerId: String?
  private var lastGameSnapshot: MPBlackjackTableState.GameStateSnapshot? {
    get { gameContext.lastGameSnapshot }
    set { gameContext.lastGameSnapshot = newValue }
  }
  private var previousGameSnapshot: MPBlackjackTableState.GameStateSnapshot? {
    get { gameContext.previousGameSnapshot }
    set { gameContext.previousGameSnapshot = newValue }
  }

  // MARK: - Shared Context

  private let gameContext = MPGameContext()

  // MARK: - Player Action Handler

  private lazy var playerActionHandler = MPPlayerActionHandler(context: gameContext)

  private var deckProvider: DeterministicDeckProvider? {
    get { playerActionHandler.deckProvider }
    set { playerActionHandler.setDeckProvider(newValue) }
  }
  private var optimisticDeckIndex: Int {
    get { playerActionHandler.optimisticDeckIndex }
    set { playerActionHandler.setOptimisticDeckIndex(newValue) }
  }
  private var optimisticCardsForMyHand: [BlackjackHandView.Card] {
    get { playerActionHandler.optimisticCardsForMyHand }
    set {
      if newValue.isEmpty { playerActionHandler.clearOptimisticCards() }
    }
  }
  private var isActionInFlight: Bool {
    get { playerActionHandler.isActionInFlight }
    set { playerActionHandler.setIsActionInFlight(newValue) }
  }
  private var actionInFlightTimeoutWorkItem: DispatchWorkItem? {
    get { playerActionHandler.actionInFlightTimeoutWorkItem }
    set { playerActionHandler.cancelTimeout() }
  }
  /// True after the initial seat reconciliation completes, used to distinguish initial host assignment from a host transfer.
  private var hasCompletedInitialJoin: Bool = false

  // MARK: - Dealer card queue (delegated to dealerCardQueue manager)

  private lazy var dealerCardQueueManager = MPDealerCardQueue(context: gameContext)

  private var dealerCardQueue: [BlackjackHandView.Card] {
    dealerCardQueueManager.dealerCardQueue
  }
  private var isDealerCardAnimating: Bool {
    get { dealerCardQueueManager.isDealerCardAnimating }
    set { dealerCardQueueManager.setIsDealerCardAnimating(newValue) }
  }
  private var dealerCardsRenderedCount: Int {
    get { dealerCardQueueManager.dealerCardsRenderedCount }
    set { dealerCardQueueManager.setDealerCardsRenderedCount(newValue) }
  }
  private var dealerHoleRevealed: Bool {
    get { dealerCardQueueManager.dealerHoleRevealed }
    set { dealerCardQueueManager.setDealerHoleRevealed(newValue) }
  }

  // MARK: - Chip Animation Helper

  private lazy var chipAnimator = MPChipAnimationHelper(context: gameContext)

  private var isBetReconciliationRunning: Bool {
    get { chipAnimator.isBetReconciliationRunning }
    set { chipAnimator.setIsBetReconciliationRunning(newValue) }
  }

  private var isBonusBetResolutionAnimating: Bool {
    get { chipAnimator.isBonusBetResolutionAnimating }
    set { chipAnimator.setIsBonusBetResolutionAnimating(newValue) }
  }

  private var bonusBetResultsProcessed: Bool {
    get { gameContext.bonusBetResultsProcessed }
    set {
      gameContext.bonusBetResultsProcessed = newValue
      chipAnimator.setBonusBetResultsProcessed(newValue)
    }
  }

  // MARK: - Bonus Bets

  private let mpBonusBetControl = MPBonusBetControl()
  private var previousBonusBetsBySeat: [Int: Int] {
    get { handResetManager.previousBonusBetsBySeat }
    set { handResetManager.previousBonusBetsBySeat = newValue }
  }
  private var localBonusBetAmount: Int {
    get { handResetManager.localBonusBetAmount }
    set { handResetManager.localBonusBetAmount = newValue }
  }
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
  private lazy var insuranceManager = MPInsuranceManager(context: gameContext)

  private var isInsurancePhaseActive: Bool { insuranceManager.isInsurancePhaseActive }
  private var localInsuranceBetAmount: Int {
    get { insuranceManager.localInsuranceBetAmount }
    set { insuranceManager.setLocalInsuranceBetAmount(newValue) }
  }
  private var pendingInsuranceSnapshot: MPBlackjackTableState.GameStateSnapshot? {
    insuranceManager.pendingInsuranceSnapshot
  }
  private var pendingInsuranceHoleCard: BlackjackHandView.Card? {
    insuranceManager.pendingInsuranceHoleCard
  }
  private var pendingInsuranceUpCard: BlackjackHandView.Card? {
    insuranceManager.pendingInsuranceUpCard
  }
  private var previousInsuranceBySeat: [Int: Int] {
    get { insuranceManager.previousInsuranceBySeat }
    set { insuranceManager.previousInsuranceBySeat = newValue }
  }
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

  // MARK: - Deal Animation Controller

  private lazy var dealAnimationController = MPDealAnimationController(context: gameContext)

  // MARK: - Betting Manager

  private lazy var bettingManager = MPBettingManager(context: gameContext)

  // MARK: - Hand Reset Manager

  private lazy var handResetManager = MPHandResetManager(context: gameContext)

  // MARK: - Table Session Manager

  private lazy var tableSessionManager = MPTableSessionManager(context: gameContext)

  // MARK: - Local Session Manager (for tracking gameplay stats)

  private var sessionManager: MPBlackjackSessionManager!

  // MARK: - Table state (set after join)

  private var tableState: MPBlackjackTableState!
  private var mySeatIndex: Int {
    get { gameContext.mySeatIndex }
    set { gameContext.mySeatIndex = newValue }
  }
  private var myDisplayName: String = "Player"
  private var myChipColorName: String {
    get { gameContext.myChipColorName }
    set { gameContext.myChipColorName = newValue }
  }
  private var joinedBalance: Int = 200
  private var isHost: Bool {
    get { gameContext.isHost }
    set { gameContext.isHost = newValue }
  }

  // MARK: - State

  private var balance: Int {
    get { gameContext.balance }
    set { gameContext.balance = newValue }
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

    // Register for app lifecycle notifications to pause/resume session timer
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

    attemptJoin()
  }

  @objc private func handleAppWillResignActive() {
    sessionManager?.pauseSessionTimer()
  }

  @objc private func handleAppDidEnterBackground() {
    sessionManager?.pauseSessionTimer()
  }

  @objc private func handleAppDidBecomeActive() {
    sessionManager?.resumeSessionTimer()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // Re-enable interactive pop gesture when leaving this view controller
    navigationController?.interactivePopGestureRecognizer?.isEnabled = true

    // Save session when leaving (if leaving the navigation stack)
    if isMovingFromParent {
      sessionManager?.pauseSessionTimer()
      sessionManager?.saveCurrentSessionForced()
    }
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

  private func setupManagers() {
    gameContext.playerId = MultiplayerPlayerIdKey.value
    gameContext.tableCode = tableState.tableCode
    gameContext.containerView = view
    gameContext.dealerHandView = dealerHandView
    gameContext.defaultSeat = defaultSeat
    gameContext.balanceView = balanceView
    gameContext.deckView = deckView
    gameContext.insuranceControl = mpInsuranceControl
    gameContext.bonusBetControl = mpBonusBetControl
    gameContext.continueButton = continueButton
    gameContext.instructionLabel = instructionLabel

    // Initialize local session manager for tracking gameplay stats
    sessionManager = MPBlackjackSessionManager(startingBalance: joinedBalance)
    sessionManager.delegate = self
    gameContext.sessionManager = sessionManager

    gameContext.onBalanceChanged = { [weak self] newBalance in
      guard let self = self else { return }
      self.balanceView?.balance = newBalance
      self.chipSelector?.updateAvailableChips(balance: newBalance)
      self.defaultSeat?.setBalance(newBalance, animated: false)
      // Update session manager balance
      self.sessionManager?.currentBalance = newBalance
    }

    gameContext.isActionInFlightProvider = { [weak self] in
      self?.playerActionHandler.isActionInFlight ?? false
    }

    chipAnimator.delegate = self
    insuranceManager.delegate = self
    insuranceManager.tableState = tableState
    insuranceManager.onDealerCardsRenderedCountChanged = { [weak self] count in
      self?.dealerCardQueueManager.setDealerCardsRenderedCount(count)
    }
    playerActionHandler.delegate = self
    dealerCardQueueManager.delegate = self
    tableSessionManager.delegate = self
    tableSessionManager.tableState = tableState
    dealAnimationController.delegate = self
    bettingManager.delegate = self
    bettingManager.tableState = tableState
    handResetManager.delegate = self
    handResetManager.onResetBetReconciliation = { [weak self] in
      self?.isBetReconciliationRunning = false
      self?.isBonusBetResolutionAnimating = false
    }
    handResetManager.onResetOptimisticState = { [weak self] in
      self?.optimisticCardsForMyHand.removeAll()
      self?.isActionInFlight = false
      self?.actionInFlightTimeoutWorkItem?.cancel()
      self?.actionInFlightTimeoutWorkItem = nil
    }
    handResetManager.onResetPreviousCardCounts = { [weak self] in
      self?.previousCardCountsBySeat.removeAll()
      self?.previousHasStoodBySeat.removeAll()
    }
  }

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

    setupManagers()

    // Start tracking the gameplay session
    sessionManager.startSession()

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
    NotificationCenter.default.removeObserver(self)
      
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
            handView.betControl.setBetAmount(newBet, animated: false)
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
    bettingManager.syncHandsToFirebase(for: seat)
  }

  private func setupBetControlCallbacks(for seat: PlayerSeat) {
    bettingManager.setupBetControlCallbacks(for: seat)
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

    updateSeatReadyIndicators()
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

    newHandButton = UIButton.createActionButton(
      title: "New Hand",
      target: self,
      action: #selector(newHandTapped),
      isInitiallyHidden: true,
      initialAlpha: 0
    )

    dealButton = UIButton.createActionButton(
      title: "Deal",
      target: self,
      action: #selector(dealTapped)
    )

    nextHandButton = UIButton.createActionButton(
      title: "Next Hand",
      target: self,
      action: #selector(nextHandTapped)
    )

    continueButton = UIButton.createActionButton(
      title: "Continue",
      target: self,
      action: #selector(continueButtonTapped)
    )

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
      // Recompute host status after reconnecting (in case it changed or needs refresh)
      recomputeHostStatus()
      // Restore button visibility based on current game state
      // Always refresh if we have a snapshot (recomputeHostStatus may not refresh if host status didn't change)
      if let snapshot = lastGameSnapshot {
        refreshButtonVisibility(for: snapshot)
      } else if isHost {
        // If we're the host but don't have a snapshot, fetch it to show deal button
        tableState?.fetchGameState { [weak self] snapshot in
          guard let self = self else { return }
          self.lastGameSnapshot = snapshot
          self.refreshButtonVisibility(for: snapshot)
        }
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

    // Track double down in session manager
    sessionManager?.recordDoubleDown()

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

    // Track split in session manager
    sessionManager?.recordSplit()

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
    playerActionHandler.cancelTimeout()
    standButton.setDisabled(true)
    doubleButton.setDisabled(true)

    let serverHandIndex = activeHandIndex
    let seatHands = defaultSeat.hands
    let hand =
      activeHandIndex < seatHands.count ? seatHands[activeHandIndex] : defaultSeat.primaryHand

    let originalBetForDouble =
      (action == MultiplayerBlackjackKeys.Actions.double) ? hand.betControl.betAmount : nil

    if action == MultiplayerBlackjackKeys.Actions.hit
      || action == MultiplayerBlackjackKeys.Actions.double
    {
      playerActionHandler.predictAndDealCard(
        action: action,
        hand: hand,
        serverHandIndex: serverHandIndex,
        originalBetForDouble: originalBetForDouble
      )
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
      sendPlayerActionToServer(
        action: action, handIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
    } else if action == MultiplayerBlackjackKeys.Actions.split {
      sendPlayerActionToServer(
        action: action, handIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
    }
  }

  private func sendPlayerActionToServer(
    action: String, handIndex serverHandIndex: Int? = nil, originalBetForDouble: Int?
  ) {
    playerActionHandler.sendPlayerActionToServer(
      action: action, handIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
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
    if !isHost {
      readyUpTapped()
      return
    }

    // Prevent double-tapping DEAL button
    guard !isDealInProgress else {
      HapticsHelper.lightHaptic()
      return
    }

    let notReadyPlayers = nonHostPlayersNotReady()
    guard notReadyPlayers.isEmpty else {
      HapticsHelper.lightHaptic()
      presentDealWithoutAllReadyAlert(notReadyPlayers: notReadyPlayers)
      return
    }

    startDealFromHost()
  }

  private func readyUpTapped() {
    let phase = lastGameSnapshot?.phase ?? ""
    let isBetting = phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting
    guard isBetting else {
      HapticsHelper.lightHaptic()
      return
    }
    guard !(currentSeatsData[mySeatIndex]?.ready ?? false) else {
      HapticsHelper.lightHaptic()
      return
    }

    dealButton.isEnabled = false
    HapticsHelper.lightHaptic()
    bettingManager.callSetReady { [weak self] success in
      guard let self = self else { return }
      if !success {
        self.dealButton.isEnabled = true
      } else {
        self.applyReadyUpButtonAppearance(isReady: true)
      }
    }
  }

  private func startDealFromHost() {
    isDealInProgress = true
    dealButton.isEnabled = false
    HapticsHelper.lightHaptic()
    callStartDeal()
  }

  private func nonHostPlayersNotReady() -> [String] {
    let hostId = currentHostPlayerId
    let myPlayerId = MultiplayerPlayerIdKey.value
    let notReady = currentSeatsData
      .sorted { $0.key < $1.key }
      .compactMap { _, seatData -> String? in
        guard let playerId = seatData.playerId, !playerId.isEmpty else { return nil }
        if let hostId = hostId, playerId == hostId { return nil }
        if isHost && playerId == myPlayerId { return nil }
        return seatData.ready ? nil : seatData.displayLabel
      }
    return notReady
  }

  private func presentDealWithoutAllReadyAlert(notReadyPlayers: [String]) {
    let message: String
    if notReadyPlayers.count <= 3 {
      message =
        "The following players are not ready yet:\n\(notReadyPlayers.joined(separator: ", "))\n\nDeal anyway?"
    } else {
      message =
        "\(notReadyPlayers.count) players are not ready yet.\n\nDeal anyway?"
    }
    let alert = UIAlertController(
      title: "Not Everyone Is Ready",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Deal Anyway", style: .destructive) { [weak self] _ in
      self?.startDealFromHost()
    })
    present(alert, animated: true)
  }

  private func callPlaceBet(amount: Int, seat: PlayerSeat, completion: @escaping (Bool) -> Void) {
    bettingManager.callPlaceBet(amount: amount, seat: seat, completion: completion)
  }

  private func callRemoveBet(
    amount: Int, seat: PlayerSeat, completion: @escaping (Bool, Int?) -> Void
  ) {
    bettingManager.callRemoveBet(amount: amount, seat: seat, completion: completion)
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

  // MARK: - Bonus Bet Resolution Animation (delegated to chipAnimator)

  private func animateBonusBetResults(
    _ results: [Int: [Int: MPBlackjackTableState.BonusBetResultData]],
    isDealerOutcome: Bool,
    completion: @escaping () -> Void
  ) {
    chipAnimator.animateBonusBetResults(results, isDealerOutcome: isDealerOutcome) { [weak self] in
      self?.hideBonusBetControl(animated: true)
      completion()
    }
  }

  private func reconstructBonusChipsForDealerOutcome(
    results: [Int: [Int: MPBlackjackTableState.BonusBetResultData]]
  ) {
    chipAnimator.reconstructBonusChipsForDealerOutcome(results: results)
  }

  private func callStartDeal(debugSeed: Int? = nil) {
    bettingManager.callStartDeal(debugSeed: debugSeed)
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

  private func callRunDealer() {
    bettingManager.callRunDealer()
  }

  private func callResolveDealerBlackjack() {
    bettingManager.callResolveDealerBlackjack()
  }

  private func callStartNextHand() {
    bettingManager.callStartNextHand()
  }

  private func clearAllCardsForNewHand(isForcedReset: Bool = false, isBettingPhase: Bool = false) {
    handResetManager.clearAllCardsForNewHand(isForcedReset: isForcedReset, isBettingPhase: isBettingPhase)
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

  private func shouldShowSeatReadyIndicators(for phase: String) -> Bool {
    phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting
  }

  private func updateSeatReadyIndicators(for phase: String? = nil) {
    let phaseToUse = phase ?? (lastGameSnapshot?.phase ?? "")
    let shouldShow = shouldShowSeatReadyIndicators(for: phaseToUse)
    for (seatIndex, seatView) in seatViewsByIndex {
      let isReady = currentSeatsData[seatIndex]?.ready ?? false
      seatView.showReadyCheckmark(shouldShow && isReady, animated: false)
    }
  }

  private func applyReadyUpButtonAppearance(isReady: Bool) {
    dealButton.tintColor = .white
    if isReady {
      dealButton.setTitle("", for: .normal)
      let image = UIImage(systemName: "checkmark.circle.fill")
      dealButton.setImage(image, for: .normal)
      dealButton.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.3)
    } else {
      dealButton.setTitle("Ready Up", for: .normal)
      dealButton.setImage(nil, for: .normal)
      dealButton.backgroundColor = HardwayColors.surfaceGray
    }
    dealButton.semanticContentAttribute = .forceLeftToRight
    dealButton.imageView?.contentMode = .scaleAspectFit
    dealButton.contentHorizontalAlignment = .center
    dealButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
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
      updateSeatReadyIndicators(for: phase)
      continueButton.isHidden = false
      continueButton.alpha = 1
      view.bringSubviewToFront(continueButton)
      return
    }

    if isBetting {
      hideSplitButton()
      updateSeatReadyIndicators(for: phase)
      if isHost {
        let notReadyCount = nonHostPlayersNotReady().count
        dealButton.isHidden = false
        dealButton.alpha = 1
        dealButton.setTitle("Deal", for: .normal)
        dealButton.setImage(nil, for: .normal)
        dealButton.backgroundColor = HardwayColors.surfaceGray
        dealButton.isEnabled = !isDealInProgress
        view.bringSubviewToFront(dealButton)
        if notReadyCount == 0 {
          updateInstructionLabelIfNeeded("Place your bet, then tap Deal", shouldFade: false)
        } else {
          updateInstructionLabelIfNeeded(
            "\(notReadyCount) player\(notReadyCount == 1 ? "" : "s") not ready — tap Deal to continue",
            shouldFade: false)
        }
      } else {
        let amReady = currentSeatsData[mySeatIndex]?.ready ?? false
        dealButton.isHidden = false
        dealButton.alpha = 1
        applyReadyUpButtonAppearance(isReady: amReady)
        dealButton.isEnabled = !amReady
        view.bringSubviewToFront(dealButton)
        updateInstructionLabelIfNeeded(
          amReady
            ? "You are ready — waiting for host to deal"
            : "Place your bet, then tap Ready Up",
          shouldFade: false)
      }
    } else if phase == MultiplayerBlackjackKeys.Phases.playerActions {
      updateSeatReadyIndicators(for: phase)
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
      updateSeatReadyIndicators(for: phase)
      hideSplitButton()
      updateInstructionLabelIfNeeded("Dealer's turn", shouldFade: false)
    } else if isBetweenHands {
      updateSeatReadyIndicators(for: phase)
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
    } else {
      updateSeatReadyIndicators(for: phase)
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

      // Track hand completion (transitioning from end/betweenHands to betting = new hand starting)
      sessionManager?.incrementHandCount()
      sessionManager?.recordBalanceSnapshot()
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

      dealerCardQueueManager.reset()
      dealerCardQueueManager.setDealerCardsRenderedCount(dealerHandView.currentCards.count)
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
            self.chipAnimator.reconcileBetsWithResults(computed)
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
    dealAnimationController.runInitialDealAnimation(snapshot: snapshot, deckCenter: deckCenter)
  }

  private func runShowTurnUIAfterDeal(bjAnimDuration: TimeInterval) {
    dealAnimationController.runShowTurnUIAfterDeal(bjAnimDuration: bjAnimDuration)
  }

  /// Animate dealer blackjack that was already resolved server-side in startDeal.
  /// Reveals the hole card, animates bet losses/pushes, discards hands, then refreshes UI.
  /// Does NOT call callResolveDealerBlackjack() since the server already set phase to between_hands.
  private func animateServerResolvedDealerBlackjack(
    snapshot: MPBlackjackTableState.GameStateSnapshot
  ) {
    insuranceManager.animateServerResolvedDealerBlackjack(snapshot: snapshot)
  }

  private func peekForDealerBlackjack(
    holeCard: BlackjackHandView.Card,
    upCard: BlackjackHandView.Card,
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    completion: @escaping () -> Void
  ) {
    insuranceManager.peekForDealerBlackjack(
      holeCard: holeCard, upCard: upCard, snapshot: snapshot,
      continueWithNormalFlow: completion)
  }

  // MARK: - Insurance Phase (delegated to insuranceManager)

  private func startInsurancePhase(
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    holeCard: BlackjackHandView.Card,
    upCard: BlackjackHandView.Card
  ) {
    let totalBonusBets = currentSeatsData.values.reduce(0) { total, seatData in
      total + (seatData.bonusBets[0] ?? 0)
    }
    if totalBonusBets == 0 {
      hideBonusBetControl(animated: true)
    }
    insuranceManager.startInsurancePhase(snapshot: snapshot, holeCard: holeCard, upCard: upCard)
  }

  @objc private func continueButtonTapped() {
    insuranceManager.handleContinueButtonTapped()
  }

  private func checkIfAllPlayersDecidedInsurance() {
    insuranceManager.checkIfAllPlayersDecidedInsurance()
  }

  private func hideInsuranceControl(animated: Bool) {
    insuranceManager.hideInsuranceControl(animated: animated)
  }


  @discardableResult
  private func handleBlackjackPayoutForSeat(
    seatIndex: Int, snapshot: MPBlackjackTableState.GameStateSnapshot, handIndex: Int = 0
  ) -> TimeInterval {
    chipAnimator.handleBlackjackPayoutForSeat(seatIndex: seatIndex, snapshot: snapshot, handIndex: handIndex)
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

  // MARK: - Bet reconciliation (delegated to chipAnimator)

  private func reconcileBets(snapshot: MPBlackjackTableState.GameStateSnapshot) {
    chipAnimator.reconcileBets(snapshot: snapshot)
  }

  private func computeHandResultsFromSeats(snapshot: MPBlackjackTableState.GameStateSnapshot)
    -> [Int: [MPBlackjackTableState.HandResult]]
  {
    chipAnimator.computeHandResultsFromSeats(snapshot: snapshot)
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

  // MARK: - Local/Remote player animation forwarding (delegated to chipAnimator)

  private func animateLocalPlayerLoss(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    chipAnimator.animateLocalPlayerLoss(seat: seat, hand: targetHand, result: result, delay: delay)
  }

  private func animateLocalBustForfeit(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult
  ) {
    chipAnimator.animateLocalBustForfeit(seat: seat, hand: targetHand, result: result)
  }

  private func animateLocalPlayerPush(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    chipAnimator.animateLocalPlayerPush(seat: seat, hand: targetHand, result: result, delay: delay)
  }

  private func animateRemotePlayerLoss(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    chipAnimator.animateRemotePlayerLoss(
      seat: seat, hand: targetHand, result: result, delay: delay)
  }

  // MARK: - Animation helpers (delegated to chipAnimator)

  private func createRemoteDot(color: UIColor) -> UIView {
    chipAnimator.createRemoteDot(color: color)
  }

  // MARK: - Dealer card queue animation (delegated to dealerCardQueueManager)

  private func enqueueDealerCards(_ allCards: [BlackjackHandView.Card], holeRevealed: Bool) {
    dealerCardQueueManager.enqueueDealerCards(allCards, holeRevealed: holeRevealed)
  }

  private func resetDealerCardQueue() {
    dealerCardQueueManager.reset()
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
    tableSessionManager.handlePlayerRemoved()
  }

  private func showLeaveTableConfirmation(popToRootOnLeave: Bool = true) {
    tableSessionManager.showLeaveTableConfirmation(popToRootOnLeave: popToRootOnLeave)
  }

  private func leaveTable(popToRoot: Bool = true) {
    tableSessionManager.leaveTable(popToRoot: popToRoot)
  }

}

// MARK: - MPTableSessionManagerDelegate

extension MultiplayerBlackjackViewController: MPTableSessionManagerDelegate {
  func sessionManagerRemoveConnectionObserver() { removeConnectionObserver() }
  func sessionManagerPresentAlert(_ alert: UIAlertController, animated: Bool) {
    present(alert, animated: animated)
  }
  func sessionManagerPopToRoot(animated: Bool) {
    navigationController?.popToRootViewController(animated: animated)
  }
  func sessionManagerPopViewController(animated: Bool) {
    navigationController?.popViewController(animated: animated)
  }
}

// MARK: - MPDealerCardQueueDelegate

extension MultiplayerBlackjackViewController: MPDealerCardQueueDelegate {
  func dealerCardQueueRefreshButtonVisibility() {
    if let s = lastGameSnapshot { refreshButtonVisibility(for: s) }
  }
}

// MARK: - MPPlayerActionHandlerDelegate

extension MultiplayerBlackjackViewController: MPPlayerActionHandlerDelegate {
  func actionHandlerRefreshButtonVisibility(
    for snapshot: MPBlackjackTableState.GameStateSnapshot
  ) {
    refreshButtonVisibility(for: snapshot)
  }
  func actionHandlerUpdateTurnIndicatorDot(forSeatIndex: Int?, handIndex: Int) {
    updateTurnIndicatorDot(for: forSeatIndex, handIndex: handIndex)
  }
  func actionHandlerHideTurnIndicatorDot() { hideTurnIndicatorDot() }
  func actionHandlerSetStandButtonDisabled(_ disabled: Bool) { standButton.setDisabled(disabled) }
  func actionHandlerSetDoubleButtonDisabled(_ disabled: Bool) { doubleButton.setDisabled(disabled) }
  func actionHandlerHideSplitButton() { hideSplitButton() }
  func actionHandlerShowInstructionMessage(_ message: String, shouldFade: Bool) {
    instructionLabel.showMessage(message, shouldFade: shouldFade)
  }
  func actionHandlerAnimateLocalBustForfeit(
    seat: PlayerSeat, hand: CompactPlayerHandView, result: MPBlackjackTableState.HandResult
  ) {
    animateLocalBustForfeit(seat: seat, hand: hand, result: result)
  }
  func actionHandlerWireHandTapHandlers(for hand: CompactPlayerHandView, handIndex: Int) {
    wireHandTapHandlers(for: hand, handIndex: handIndex)
  }
}

// MARK: - MPInsuranceManagerDelegate

extension MultiplayerBlackjackViewController: MPInsuranceManagerDelegate {
  func insuranceUpdateInstructionLabel(_ text: String, shouldFade: Bool) {
    updateInstructionLabelIfNeeded(text, shouldFade: shouldFade)
  }
  func insuranceRefreshButtonVisibility(
    for snapshot: MPBlackjackTableState.GameStateSnapshot
  ) {
    refreshButtonVisibility(for: snapshot)
  }
  func insuranceHideBonusBetControl(animated: Bool) {
    hideBonusBetControl(animated: animated)
  }
  func insuranceCallResolveDealerBlackjack() { callResolveDealerBlackjack() }
  func insuranceCallStartNextHand() { callStartNextHand() }
  func insuranceScrollToSeat(_ index: Int, animated: Bool) {
    scrollToSeat(index, animated: animated)
  }
  func insuranceShowBetResult(amount: Int, isWin: Bool, showBonus: Bool, description: String?) {
    showBetResult(amount: amount, isWin: isWin, showBonus: showBonus, description: description)
  }
  func insuranceAnimateLocalPlayerLoss(
    seat: PlayerSeat, result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    animateLocalPlayerLoss(seat: seat, result: result, delay: delay)
  }
  func insuranceAnimateLocalPlayerPush(
    seat: PlayerSeat, result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    animateLocalPlayerPush(seat: seat, result: result, delay: delay)
  }
  func insuranceAnimateRemotePlayerLoss(
    seat: PlayerSeat, result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    animateRemotePlayerLoss(seat: seat, result: result, delay: delay)
  }
  func insuranceCreateRemoteDot(color: UIColor) -> UIView {
    createRemoteDot(color: color)
  }
  func insurancePhaseResolved(
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    holeCard: BlackjackHandView.Card,
    upCard: BlackjackHandView.Card
  ) {
    peekForDealerBlackjack(holeCard: holeCard, upCard: upCard, snapshot: snapshot) { [weak self] in
      guard let self = self else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
        guard let self = self else { return }
        self.insuranceManager.hideInsuranceControl(animated: true)
        self.runShowTurnUIAfterDeal(bjAnimDuration: 0)
      }
    }
  }
}

// MARK: - MPChipAnimationHelperDelegate

extension MultiplayerBlackjackViewController: MPChipAnimationHelperDelegate {
  func chipAnimationShowBetResult(amount: Int, isWin: Bool, showBonus: Bool, description: String?) {
    showBetResult(amount: amount, isWin: isWin, showBonus: showBonus, description: description)
  }
  func chipAnimationScrollToSeat(_ index: Int, animated: Bool) {
    scrollToSeat(index, animated: animated)
  }
  func chipAnimationRefreshButtonVisibility(
    for snapshot: MPBlackjackTableState.GameStateSnapshot
  ) {
    refreshButtonVisibility(for: snapshot)
  }
  func chipAnimationCallStartNextHand() { callStartNextHand() }
}

// MARK: - MPBettingManagerDelegate

extension MultiplayerBlackjackViewController: MPBettingManagerDelegate {
  func bettingManagerShowInstructionMessage(_ message: String, shouldFade: Bool) {
    instructionLabel.showMessage(message, shouldFade: shouldFade)
  }
  func bettingManagerRefreshButtonVisibility(
    for snapshot: MPBlackjackTableState.GameStateSnapshot
  ) {
    refreshButtonVisibility(for: snapshot)
  }
  func bettingManagerDealButton() -> UIButton { dealButton }
  func bettingManagerNextHandButton() -> UIButton { nextHandButton }
  func bettingManagerSelectedChipValue() -> Int { selectedChipValue }
  func bettingManagerShowDebugHandsSheet() {
    #if DEBUG
      showDebugHandsSheet()
    #endif
  }
}

// MARK: - MPHandResetManagerDelegate

extension MultiplayerBlackjackViewController: MPHandResetManagerDelegate {
  func handResetResetDealerCardQueue() { resetDealerCardQueue() }
  func handResetSyncHandsToFirebase(for seatView: PlayerSeat) { syncHandsToFirebase(for: seatView) }
  func handResetHideInsuranceControl(animated: Bool) { hideInsuranceControl(animated: animated) }
  func handResetShowBonusBetControl(animated: Bool) { showBonusBetControl(animated: animated) }
  func handResetResetInsuranceManager() { insuranceManager.resetForNewHand() }
  func handResetClearTableInsurance() { tableState?.clearInsuranceForAllSeats() }
  func handResetClearTableBonusBets() { tableState?.clearBonusBetsForAllSeats() }
}

// MARK: - MPDealAnimationControllerDelegate

extension MultiplayerBlackjackViewController: MPDealAnimationControllerDelegate {
  func dealAnimationHideTurnIndicatorDot() { hideTurnIndicatorDot() }
  func dealAnimationUpdateTurnIndicatorDot(forSeatIndex: Int?, handIndex: Int) {
    updateTurnIndicatorDot(for: forSeatIndex, handIndex: handIndex)
  }
  func dealAnimationUpdateInstructionLabel(_ message: String, shouldFade: Bool) {
    updateInstructionLabelIfNeeded(message, shouldFade: shouldFade)
  }
  func dealAnimationShowBonusBetControl(animated: Bool) { showBonusBetControl(animated: animated) }
  func dealAnimationHideBonusBetControl(animated: Bool) { hideBonusBetControl(animated: animated) }
  func dealAnimationRefreshButtonVisibility(
    for snapshot: MPBlackjackTableState.GameStateSnapshot
  ) {
    refreshButtonVisibility(for: snapshot)
  }
  func dealAnimationScrollToSeat(_ index: Int, animated: Bool) {
    scrollToSeat(index, animated: animated)
  }
  func dealAnimationScrollToSeatHand(_ index: Int, handIndex: Int, animated: Bool) {
    scrollToSeatHand(index, handIndex: handIndex, animated: animated)
  }
  func dealAnimationCallPlayerAction(_ action: String) { callPlayerAction(action) }
  func dealAnimationStartInsurancePhase(
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    holeCard: BlackjackHandView.Card, upCard: BlackjackHandView.Card
  ) {
    startInsurancePhase(snapshot: snapshot, holeCard: holeCard, upCard: upCard)
  }
  func dealAnimationPeekForDealerBlackjack(
    holeCard: BlackjackHandView.Card, upCard: BlackjackHandView.Card,
    snapshot: MPBlackjackTableState.GameStateSnapshot, completion: @escaping () -> Void
  ) {
    peekForDealerBlackjack(holeCard: holeCard, upCard: upCard, snapshot: snapshot, completion: completion)
  }
  func dealAnimationAnimateServerResolvedDealerBlackjack(
    snapshot: MPBlackjackTableState.GameStateSnapshot
  ) {
    animateServerResolvedDealerBlackjack(snapshot: snapshot)
  }
  func dealAnimationApplyCardsWithoutDealAnimation(
    snapshot: MPBlackjackTableState.GameStateSnapshot, deckCenter: CGPoint
  ) {
    applyCardsWithoutDealAnimation(snapshot: snapshot, deckCenter: deckCenter)
  }
  func dealAnimationAnimateBonusBetResults(
    _ results: [Int: [Int: MPBlackjackTableState.BonusBetResultData]],
    isDealerOutcome: Bool, completion: @escaping () -> Void
  ) {
    animateBonusBetResults(results, isDealerOutcome: isDealerOutcome, completion: completion)
  }
  func dealAnimationGetPlayerHandsFromSeats() -> [Int: [[String: Any]]] {
    getPlayerHandsFromSeats()
  }
  func dealAnimationSeatsScrollView() -> UIScrollView { seatsScrollView }
  func dealAnimationDealButton() -> UIButton { dealButton }
}

// MARK: - ChipSelectorDelegate

extension MultiplayerBlackjackViewController: ChipSelectorDelegate {
  func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {}
}

// MARK: - MPBlackjackSessionManagerDelegate

extension MultiplayerBlackjackViewController: MPBlackjackSessionManagerDelegate {
  func mpSessionDidStart(id: String) {
    print("📊 [MP Session] Started session with ID: \(id)")
  }

  func mpSessionWasSaved(session: GameSession) {
    print("📊 [MP Session] Session saved - Duration: \(session.formattedDuration), Hands: \(session.handCountValue), Net: \(session.netResult > 0 ? "+" : "")\(session.netResult)")
  }

  func mpMetricsDidUpdate(metrics: BlackjackGameplayMetrics) {
    // Metrics updated - could update UI here if needed
  }

  func mpBalanceDidChange(from oldBalance: Int, to newBalance: Int) {
    // Balance change tracked
  }

  func mpHandCountDidChange(count: Int) {
    // Hand count updated
  }
}
