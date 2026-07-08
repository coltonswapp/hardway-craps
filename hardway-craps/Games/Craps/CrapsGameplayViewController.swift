//
//  CrapsGameplayViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class CrapsGameplayViewController: UIViewController {

  private typealias Timing = CrapsAnimationTiming

  // MARK: - Managers

  var settingsManager: CrapsSettingsManager!
  var sessionManager: CrapsSessionManager!
  var gameStateManager: CrapsGameStateManager!
  var passLineManager: CrapsPassLineManager!
  var specialBetsManager: CrapsSpecialBetsManager!
  var bonusBetResolver: BonusBetResolutionManager!
  var chipAnimator: ChipAnimationHelper!

  // MARK: - Variant
  let variant: CrapsVariant
  var rules: CrapsVariantRules
  var instructionTextProvider: CrapsInstructionTextProvider
  var isCrapless: Bool { variant == .crapless }

  private var gameplayNavigationTitle: String {
    switch variant {
    case .standard:
      return "Craps"
    case .crapless:
      return "Crapless"
    }
  }

  var topBar: UIStackView { topStackView }
  var bottomBar: UIStackView { bottomStackView }

  // MARK: - Constants

  private var startingBalance: Int {
    return AppSettingsViewController.startingBankroll
  }

  var chipSelector: ChipSelector!
  var passLineControl: PlainControl!
  var passLineControlWidthConstraint: NSLayoutConstraint!
  var fieldControl: PlainControl!
  var comeBetControl: ComeBetControl!
  /// One-roll Any 7 proposition (standard craps only), between Come and C&E.
  var anySevenControl: PlainControl?
  /// Horizontal C / C&E / E proposition zones (standard craps only), beside Come.
  var cAndETriZoneControl: TriZoneBetControl?
  var dontPassControl: DontPassControl?
  var pointStack: PointStack!
  var gameContainerView: UIView!
  // Spacing constraints for controls inside gameContainerView (adjustable per layout mode)
  var gameContainerSpacingConstraints: [NSLayoutConstraint] = []
  var flipDiceContainer: FlipDiceContainer!
  var crapsAutoplayer: CrapsAutoplayer?
  /// Dispatched `CrapsTableCommand`s for staggered autoplay placement (cancelled when autoplay stops).
  var crapsAutoplayQueuedWorkItems: [DispatchWorkItem] = []
  private var balanceView: BalanceView!
  var instructionLabel: InstructionLabel!
  var hardwayView: QuadBetView?
  private var makeEmView: UIView?
  var hornView: QuadBetView?
  private var actionsView: UIView!
  var scrollContentView: UIView!
  private var scrollContentWidthConstraint: NSLayoutConstraint?
  private var activeBetViewConstraints: [NSLayoutConstraint] = []
  private var previousBonusBetSettings: (hardways: Bool, makeEm: Bool, horn: Bool)?
  var betsScrollView: UIScrollView!
  var pageControl: UIPageControl!
  var betsContainerView: UIView!
  var bottomStackView: UIStackView!
  var topStackView: UIStackView!
  var currentBetView: CurrentBetView!
  var topStackTopConstraint: NSLayoutConstraint!

  // Track if bets were placed during point phase (before first roll) - lock after next roll
  var passLineBetPlacedDuringPointPhase: Bool = false
  var dontPassBetPlacedDuringPointPhase: Bool = false

  // Track whether bets are currently enabled or disabled
  var betsAreOn: Bool = true

  // Come bet: read comeBetControl.betAmount directly (no cached state needed)

  // Tip tracking
  private var hasShownTapToBetTip: Bool = false
  private var hasShownComeOutRollTip: Bool = false
  private var hasShownBetBoxNumbersTip: Bool = false
  private var hasShownHitPointToWinTip: Bool = false
  private var hasShownDragChipTip: Bool = false

  // Optional session to resume from
  private var resumingSession: GameSession?

  // MARK: - Computed Properties (Backward Compatibility)

  /// Backward compatibility: Access game through game state manager
  var game: CrapsGameStateManager {
    return gameStateManager
  }

  /// Backward compatibility: Access session properties through session manager
  private var sessionId: String? { sessionManager?.sessionId }
  private var sessionStartTime: Date? { sessionManager?.sessionStartTime }
  private var rollCount: Int { sessionManager?.rollCount ?? 0 }
  private var sevensRolled: Int { sessionManager?.sevensRolled ?? 0 }
  private var pointsHit: Int { sessionManager?.pointsHit ?? 0 }
  private var balanceHistory: [Int] { sessionManager?.balanceHistory ?? [] }
  private var betSizeHistory: [Int] { sessionManager?.betSizeHistory ?? [] }
  private var gameplayMetrics: GameplayMetrics {
    sessionManager?.gameplayMetrics ?? GameplayMetrics()
  }
  var pendingBetSizeSnapshot: Int {
    get { 0 }  // Read-only, managed internally by session manager
    set { sessionManager?.snapshotBetSize(newValue) }
  }

  var balance: Int {
    get {
      if let sessionManager = sessionManager {
        return sessionManager.currentBalance
      }
      return balanceView?.balance ?? startingBalance
    }
    set {
      balanceView?.balance = newValue
      chipSelector?.updateBalance(newValue)
      sessionManager?.currentBalance = newValue
    }
  }

  var selectedChipValue: Int {
    return chipSelector?.selectedValue ?? 5
  }

  init(variant: CrapsVariant = .standard, resumingSession: GameSession? = nil) {
    self.variant = variant
    self.rules = CrapsVariantRulesFactory.makeRules(for: variant)
    self.instructionTextProvider = CrapsInstructionTextProvider(variant: variant)
    self.resumingSession = resumingSession
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    title = gameplayNavigationTitle

    // Setup managers first
    setupManagers()

    // Disable interactive pop gesture to prevent accidental dismissal when dragging bets
    navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    if #available(iOS 26.0, *) {
      navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = false
    }

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

    // 1. Setup bottom components first (chip selector and dice container)
    setupBalanceView()
    setupChipSelector()
    setupBottomStackView()
    setupFlipDice()

    // 2. Setup top stack view (instruction label and current bet)
    setupTopStackView()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAutoplayStoppedNotification(_:)),
      name: .crapsAutoplayDidStopFromUserInteraction,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAutoplayStoppedNotification(_:)),
      name: .crapsAutoplayDidStopBankrupt,
      object: nil
    )

    // 4. Setup pass line control and odds control
    setupPassLineControls()

    if !isCrapless {
      setupDontPassControl()
    }

    setupHardwayStack()

    // 7. Setup PointStack (below Quad bets)
    setupPointStack()

    // 8. Setup FieldControl (below PointStack)
    setupFieldControl()

    setupComeBetControl()
    if !isCrapless {
      setupAnySevenControl()
      setupCAndETriZoneControl()
    }

    // 10. Setup game container view (holds all gameplay controls with internal constraints)
    setupGameContainerView()

    // Come + C&E are created after the first `updatePassLineOddsVisibility()` (from pass line setup).
    // Refresh so C&E is not left in the initial disabled state.
    updatePassLineOddsVisibility()

    setupDebugMenu()

    // Z-order: dice at back, then bottom bar (balance + chips) on top of dice, then top bar on top
    view.bringSubviewToFront(flipDiceContainer)
    view.bringSubviewToFront(bottomStackView)
    view.bringSubviewToFront(topStackView)

    // Set balance from session manager (after UI is set up)
    // For new sessions, this ensures balanceView is initialized with the correct startingBalance
    // For resuming sessions, this restores the saved balance
    balance = sessionManager.currentBalance

    // Initialize chip availability and set based on starting balance
    chipSelector.updateBalance(balance)

    // Apply initial layout based on device and orientation
    applyLayout(for: currentLayoutMode)
  }

  // MARK: - Manager Setup

  private func startSession() {
    // Session is already initialized in setupManagers
    // Just start it if it's a new session
    if resumingSession == nil {
      sessionManager.startSession()
      if !UITestLaunchConfiguration.suppressGameplaySessionRecording {
        GameAnalyticsEvent.crapsGameStarted.log()
      }
    }
  }

  private func setupManagers() {
    settingsManager = CrapsSettingsManager(variant: variant)
    settingsManager.delegate = self
    settingsManager.loadSettings()

    let gameType: GameType = isCrapless ? .craplessCraps : .craps
    sessionManager = CrapsSessionManager(
      startingBalance: startingBalance,
      resumingSession: resumingSession,
      gameType: gameType
    )
    sessionManager.delegate = self

    gameStateManager = CrapsGameStateManager(variant: variant)
    gameStateManager.delegate = self

    passLineManager = CrapsPassLineManager()
    passLineManager.delegate = self

    specialBetsManager = CrapsSpecialBetsManager()
    specialBetsManager.delegate = self
    bonusBetResolver = BonusBetResolutionManager(specialBetsManager: specialBetsManager)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func handleAutoplayStoppedNotification(_ notification: Notification) {
    refreshAutoplayNavigationChrome()
    if notification.name == .crapsAutoplayDidStopBankrupt {
      instructionLabel.showMessage(
        "Autoplay stopped — not enough balance for minimum bets.", shouldFade: true)
    } else if notification.name == .crapsAutoplayDidStopFromUserInteraction {
      instructionLabel.showMessage("Autoplay stopped.", shouldFade: true)
    }
  }

  @objc private func handleAppWillResignActive() {
    // Pause the session timer when app becomes inactive
    pauseSessionTimer()
  }

  @objc private func handleAppDidEnterBackground() {
    // Pause the session timer when app enters background
    pauseSessionTimer()
  }

  @objc private func handleAppDidBecomeActive() {
    // Resume the session timer when app becomes active
    resumeSessionTimer()
  }

  @objc private func handleAppWillTerminate() {
    // Save session when app is about to terminate
    if hasActiveSession() {
      pauseSessionTimer()  // Ensure we capture final active time
      saveCurrentSessionForced()
    }
  }

  private func pauseSessionTimer() {
    sessionManager.pauseSessionTimer()
  }

  private func resumeSessionTimer() {
    sessionManager.resumeSessionTimer()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Track screen visit for tip rules
    NNTipManager.shared.trackScreenVisit("CrapsGameplay")
    // Show tips if appropriate
    showTips()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopCrapsAutoplaySilently()
    // Stop all tip observations
    NNTipManager.shared.stopAllTipObservations()
    // Save session if view controller is being dismissed (e.g., popped from navigation)
    if isMovingFromParent && hasActiveSession() {
      saveCurrentSessionForced()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    // Control widths are now handled internally by gameContainerView

    // DEBUG: Print layout information
    if let gameContainer = gameContainerView, let pointStack = pointStack {
      print("=== LAYOUT DEBUG ===")
      print("Layout Mode: \(currentLayoutMode)")
      print("gameContainerView frame: \(gameContainer.frame)")
      print("gameContainerView bounds: \(gameContainer.bounds)")
      print("pointStack frame: \(pointStack.frame)")
      print("pointStack bounds: \(pointStack.bounds)")
      print(
        "pointStack contentHuggingPriority (vertical): \(pointStack.contentHuggingPriority(for: .vertical).rawValue)"
      )
      print(
        "pointStack compressionResistancePriority (vertical): \(pointStack.contentCompressionResistancePriority(for: .vertical).rawValue)"
      )
      print("comeBetControl frame: \(comeBetControl.frame)")
      print("fieldControl frame: \(fieldControl.frame)")
      print("passLineControl frame: \(passLineControl.frame)")
      print("dontPassControl frame: \(dontPassControl?.frame ?? .zero)")

      // Check constraints
      let pointStackConstraints = pointStack.constraintsAffectingLayout(for: .vertical)
      print("pointStack vertical constraints count: \(pointStackConstraints.count)")
      for constraint in pointStackConstraints {
        print("  - \(constraint.description) priority: \(constraint.priority.rawValue)")
      }

      let containerConstraints = gameContainer.constraintsAffectingLayout(for: .vertical)
      print("gameContainerView vertical constraints count: \(containerConstraints.count)")
      for constraint in containerConstraints {
        if constraint.firstItem === pointStack || constraint.secondItem === pointStack {
          print(
            "  - PointStack related: \(constraint.description) priority: \(constraint.priority.rawValue)"
          )
        }
      }
      print("===================")
    }

    // Initialize chip selector indicator position after layout
    // Force chipSelector to layout its subviews first, then initialize indicator
    if let chipSelector = chipSelector {
      chipSelector.layoutIfNeeded()
      DispatchQueue.main.async { [weak self] in
        self?.chipSelector?.initializeIndicatorPosition()
      }
    }
  }

  override func viewWillTransition(
    to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator
  ) {
    super.viewWillTransition(to: size, with: coordinator)
    guard UIDevice.current.userInterfaceIdiom == .pad else { return }

    let newMode: LayoutMode = size.width > size.height ? .iPadLandscape : .iPadPortrait

    coordinator.animate(alongsideTransition: { _ in
      self.applyLayout(for: newMode)
      self.view.layoutIfNeeded()
    })
  }

  func recordBalanceSnapshot() {
    sessionManager.recordBalanceSnapshot()
  }

  private func trackBet(amount: Int, type: BetType) {
    sessionManager.trackBet(amount: amount, type: type)

    // Track concurrent bets
    updateConcurrentBets()
  }

  private func updateConcurrentBets() {
    var concurrentCount = 0
    if passLineControl.betAmount > 0 { concurrentCount += 1 }
    if passLineControl.oddsAmount > 0 { concurrentCount += 1 }
    if fieldControl.betAmount > 0 { concurrentCount += 1 }
    if let dp = dontPassControl, dp.betAmount > 0 { concurrentCount += 1 }
    if comeBetControl != nil && comeBetControl.betAmount > 0 { concurrentCount += 1 }
    if let anySeven = anySevenControl, anySeven.betAmount > 0 { concurrentCount += 1 }
    if let cAndE = cAndETriZoneControl {
      for zone in TriZoneBetControl.Zone.allCases {
        if cAndE.betAmount(for: zone) > 0 {
          concurrentCount += 1
        }
      }
    }

    // Check point bets
    if let pointStack = pointStack {
      for pointNumber in pointStack.pointNumbers {
        if let pointControl = pointStack.getPointControl(for: pointNumber),
          pointControl.betAmount > 0
        {
          concurrentCount += 1
        }
      }
    }

    // Check hardway bets
    if let hardwayView = hardwayView {
      for arrangedSubview in hardwayView.betStack.arrangedSubviews {
        if let columnStack = arrangedSubview as? UIStackView {
          for columnSubview in columnStack.arrangedSubviews {
            if let hardwayControl = columnSubview as? SmallControl,
              hardwayControl.betAmount > 0
            {
              concurrentCount += 1
            }
          }
        }
      }
    }

    // Check horn bets
    if let hornView = hornView {
      for arrangedSubview in hornView.betStack.arrangedSubviews {
        if let columnStack = arrangedSubview as? UIStackView {
          for columnSubview in columnStack.arrangedSubviews {
            if let hornControl = columnSubview as? SmallControl,
              hornControl.betAmount > 0
            {
              concurrentCount += 1
            } else if let anyHorn = columnSubview as? AnyHornControl,
              anyHorn.betAmount > 0
            {
              concurrentCount += 1
            }
          }
        }
      }
    }

    sessionManager.updateConcurrentBets(count: concurrentCount)
  }

  private func saveCurrentSession() -> GameSession? {
    return sessionManager.saveCurrentSession()
  }

  private func saveCurrentSessionForced() -> GameSession? {
    return sessionManager.saveCurrentSessionForced()
  }

  private func hasActiveSession() -> Bool {
    return sessionId != nil && sessionStartTime != nil
  }

  func setupDebugMenu() {
    let settingsButton = UIBarButtonItem(
      image: UIImage(systemName: "gearshape"),
      style: .plain,
      target: self,
      action: #selector(showSettings)
    )
    navigationItem.rightBarButtonItem = settingsButton
  }

  @objc private func showSettings() {
    let settingsVC: BaseSettingsViewController

    if isCrapless {
      let vc = CraplessSettingsViewController()
      vc.onFixedRoll = { [weak self] total in
        self?.flipDiceContainer.rollFixedTotal(total)
      }
      vc.autoplayInitiallyEnabled = crapsAutoplayer?.isRunning ?? false
      vc.onAutoplayChanged = { [weak self] enabled in
        self?.handleCrapsAutoplaySettingChanged(enabled: enabled)
      }
      settingsVC = vc
    } else {
      let vc = CrapsSettingsViewController()
      vc.onFixedRoll = { [weak self] total in
        self?.flipDiceContainer.rollFixedTotal(total)
      }
      vc.autoplayInitiallyEnabled = crapsAutoplayer?.isRunning ?? false
      vc.onAutoplayChanged = { [weak self] enabled in
        self?.handleCrapsAutoplaySettingChanged(enabled: enabled)
      }
      settingsVC = vc
    }

    settingsVC.onSettingsChanged = { [weak self] in
      guard let self = self else { return }
      let oldSettings = self.settingsManager.currentSettings
      self.settingsManager.loadSettings()
      let newSettings = self.settingsManager.currentSettings

      if newSettings.hardwaysEnabled != oldSettings.hardwaysEnabled
        || newSettings.makeEmEnabled != oldSettings.makeEmEnabled
        || newSettings.hornEnabled != oldSettings.hornEnabled
      {
        self.rebuildBetViews(for: self.currentLayoutMode)
      }
    }

    settingsVC.onShowGameDetails = { [weak self] in
      self?.showCurrentGameDetails()
    }

    let navigationController = UINavigationController(rootViewController: settingsVC)

    if let sheet = navigationController.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
      sheet.largestUndimmedDetentIdentifier = .medium
    }
    present(navigationController, animated: true)
  }

  private func showCurrentGameDetails() {
    guard let snapshot = currentSessionSnapshot() else { return }
    let detailViewController = GameDetailViewController(session: snapshot)
    navigationController?.pushViewController(detailViewController, animated: true)
  }

  private func currentSessionSnapshot() -> GameSession? {
    return sessionManager.currentSessionSnapshot()
  }

  func setupPointStack() {
    pointStack = PointStack(pointNumbers: rules.orderedPointNumbers)
    pointStack.translatesAutoresizingMaskIntoConstraints = false
    pointStack.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 1
    }
    pointStack.getBalance = { [weak self] in
      return self?.balance ?? 200
    }
    pointStack.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      self.trackBet(amount: amount, type: .place)
      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()
      // Dismiss bet box numbers tip once user places their first point bet (with delay)
      NNTipManager.shared.dismissTip(CrapsTips.betBoxNumbersTip, afterDelay: 1.0)
      // Show tips after bet box numbers tip is dismissed (e.g., hit point to win tip)
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + 0.5) { [weak self] in
        self?.showTips()
      }
    }

    pointStack.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
      // Dismiss drag chip tip once user removes a bet (with delay to let them see it)
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
    }

    pointStack.onComeBetOddsPlaced = { [weak self] amount, previousOddsAmount, pointNumber in
      guard let self = self else { return }
      // Find the PointControl for this point number to get the come bet amount
      guard let pointControl = self.pointStack.getPointControl(for: pointNumber) else {
        // Fallback: just track and deduct if we can't find the control
        self.trackBet(amount: amount, type: .odds)
        self.balance -= amount
        self.updateCurrentBet()
        return
      }

      // Check if this bet exceeds the maximum odds for this point (3-4-5x rule)
      let comeBetAmount = pointControl.comeBetAmount
      let maxMultiplier = self.maxOddsMultiplier(for: pointNumber)
      let maxOddsBet = comeBetAmount * maxMultiplier
      let newOddsBet = pointControl.comeBetOddsAmount

      if newOddsBet > maxOddsBet {
        // Reverse the bet - remove the excess amount
        // Use the previousOddsAmount passed from OddsBetStack (captured BEFORE addition)
        let actualAmountAdded = maxOddsBet - previousOddsAmount  // Amount that was actually added (could be 0 if already at max)
        pointControl.setComeBetOddsAmount(maxOddsBet)
        HapticsHelper.lightHaptic()
        // Only track and deduct the amount that was actually added (not the full amount)
        if actualAmountAdded > 0 {
          self.trackBet(amount: actualAmountAdded, type: .odds)
          self.balance -= actualAmountAdded
        }
        // Don't add excess to balance - it was never deducted in the first place
      } else {
        self.trackBet(amount: amount, type: .odds)
        self.balance -= amount
      }
      self.updateCurrentBet()
    }

    pointStack.onComeBetOddsRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
    }

    pointStack.onLayBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      self.trackBet(amount: amount, type: .lay)
      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()
    }

    pointStack.onLayBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
    }

    // Control will be added to gameContainerView in setupGameContainerView()

    // Set content hugging priority very low to allow pointStack to expand and fill available space
    // Use .fittingSizeLevel (50) instead of .defaultLow (250) to allow more growth
    pointStack.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
    // Set compression resistance to low so it can expand to fill available space
    pointStack.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
  }

  func setupPassLineControls() {
    // Create pass line control
    passLineControl = PassLineControl(title: "Pass Line")
    passLineControl.translatesAutoresizingMaskIntoConstraints = false
    passLineControl.accessibilityIdentifier = "passLineControl"
    passLineControl.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 1
    }
    passLineControl.getBalance = { [weak self] in
      return self?.balance ?? 200
    }
    passLineControl.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      self.trackBet(amount: amount, type: .passLine)

      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()

      // Track if bet was placed during point phase (before first roll)
      // This bet will be locked after the next roll
      if self.game.isPointPhase {
        self.passLineBetPlacedDuringPointPhase = true
      }

      self.updatePassLineOddsVisibility()

      // Dismiss tap to bet tip once user places their first bet (with delay)
      NNTipManager.shared.dismissTip(CrapsTips.tapToBetTip, afterDelay: 1.5)
      // Show tips based on new state (e.g., come out roll tip) after tap to bet tip is dismissed + 0.5s delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + 0.5) { [weak self] in
        self?.showTips()
      }
    }

    passLineControl.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
      // Dismiss drag chip tip once user removes a bet (with delay to let them see it)
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
      self.updatePassLineOddsVisibility()
    }

    passLineControl.addedBetCompletionHandler = { [weak self] in
      guard let self = self else { return }
      // Stop shimmer on both controls when bet is added to pass line
      self.passLineControl.stopTitleShimmer()
      self.dontPassControl?.stopTitleShimmer()
    }

    passLineControl.canRemoveBet = { [weak self] in
      // Pass line bet cannot be removed once the point is set
      guard let self = self else { return true }
      return !self.game.isPointPhase
    }

    // Enable odds support on pass line control
    passLineControl.supportsOdds = true
    passLineControl.winningsAnimationDirection = .leading
    passLineControl.onOddsPlaced = { [weak self] amount, previousOddsAmount in
      guard let self = self else { return }
      // Check if this bet exceeds the maximum odds for the current point (3-4-5x rule)
      let currentPoint = self.game.currentPoint ?? 0
      let maxMultiplier = self.maxOddsMultiplier(for: currentPoint)
      let maxOddsBet = self.passLineControl.betAmount * maxMultiplier
      let newOddsBet = self.passLineControl.oddsAmount

      if newOddsBet > maxOddsBet {
        // Reverse the bet - remove the excess amount
        // Use the previousOddsAmount passed from OddsBetStack (captured BEFORE addition)
        let actualAmountAdded = maxOddsBet - previousOddsAmount  // Amount that was actually added (could be 0 if already at max)
        self.passLineControl.oddsAmount = maxOddsBet
        HapticsHelper.lightHaptic()
        // Only track and deduct the amount that was actually added (not the full amount)
        if actualAmountAdded > 0 {
          self.trackBet(amount: actualAmountAdded, type: .odds)
          self.balance -= actualAmountAdded
        }
        // Don't add excess to balance - it was never deducted in the first place
      } else {
        self.trackBet(amount: amount, type: .odds)
        self.balance -= amount
      }
      self.updateCurrentBet()
    }

    passLineControl.onOddsRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      // Dismiss drag chip tip once user removes a bet (with delay to let them see it)
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
    }

    // Control will be added to gameContainerView in setupGameContainerView()
    // Width constraints will be set up in setupGameContainerView()

    // Initially update visibility/disabled state
    updatePassLineOddsVisibility()
  }

  func updatePassLineOddsVisibility() {
    // Determine if pass line bet should be locked (only after first roll after placing bet during point phase)
    let shouldLockPassLine =
      passLineBetPlacedDuringPointPhase == false && game.isPointPhase
      && passLineControl.betAmount > 0

    passLineManager.updateControlStates(
      isPointPhase: game.isPointPhase,
      hasPassLineBet: passLineControl.betAmount > 0,
      passLineControl: passLineControl,
      shouldLock: shouldLockPassLine
    )

    // Update don't pass control state
    // Keep control enabled at all times - use locking instead of disabling
    // This allows adding odds when point is set
    // Check if dontPassControl is initialized (it may not be during initial setup)
    if let dontPass = dontPassControl {
      // Keep control enabled so odds can be added
      dontPass.isEnabled = true

      // Determine if don't pass bet should be locked (only after first roll after placing bet during point phase)
      let shouldLockDontPass =
        dontPassBetPlacedDuringPointPhase == false && game.isPointPhase && dontPass.betAmount > 0

      // Update disabled state for don't pass control (visual locked appearance)
      // Only show locked/greyed out appearance when bet is actually locked (after first roll)
      dontPass.setBetRemovalDisabled(shouldLockDontPass)

      // Lock/unlock bet for odds support (similar to pass line)
      if shouldLockDontPass {
        // Point is set, bet exists, and roll has occurred - lock the bet so odds can be added
        dontPass.lockBet()
      } else if !game.isPointPhase || dontPass.betAmount == 0 {
        // Not in point phase or no bet - unlock (will clear odds if any)
        // Only unlock when we're actually leaving point phase or removing bet
        dontPass.unlockBet(clearOdds: true)
      } else {
        // We're in point phase with a bet but not locked yet - ensure unlocked state without clearing odds
        // This prevents clearing odds when we're just updating state after adding to bet
        dontPass.unlockBet(clearOdds: false)
      }
    }

    // Come: point phase only. C & E tri-zone: any roll while bets are on (one-roll props).
    updateComeBetControlState()
  }

  private func updateComeBetControlState() {
    let shouldEnableCome = game.isPointPhase && betsAreOn
    let shouldEnablePropositionBets = betsAreOn

    UIView.animate(withDuration: 0.2) {
      if let comeBet = self.comeBetControl {
        comeBet.isUserInteractionEnabled = shouldEnableCome
        comeBet.alpha = shouldEnableCome ? 1.0 : 0.5
      }
      self.anySevenControl?.isUserInteractionEnabled = shouldEnablePropositionBets
      self.anySevenControl?.alpha = shouldEnablePropositionBets ? 1.0 : 0.5
      self.cAndETriZoneControl?.isUserInteractionEnabled = shouldEnablePropositionBets
      self.cAndETriZoneControl?.alpha = shouldEnablePropositionBets ? 1.0 : 0.5
    }
  }

  func setupFieldControl() {
    fieldControl = PlainControl(title: "2 • 3 • 4 • 9 • 10 • 11 • 12")
    fieldControl.translatesAutoresizingMaskIntoConstraints = false
    fieldControl.isPerpetualBet = false  // Field is a one-time bet
    fieldControl.winningsAnimationDirection = .leading  // Animate winnings to the leading edge
    fieldControl.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 1
    }
    fieldControl.getBalance = { [weak self] in
      return self?.balance ?? 200
    }
    fieldControl.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      self.trackBet(amount: amount, type: .field)
      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()
      // Dismiss tap to bet tip once user places their first bet (with delay)
      NNTipManager.shared.dismissTip(CrapsTips.tapToBetTip, afterDelay: 1.5)
      // Show tips based on new state (e.g., come out roll tip) after tap to bet tip is dismissed + 0.5s delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + 0.5) { [weak self] in
        self?.showTips()
      }
    }

    fieldControl.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
      // Dismiss drag chip tip once user removes a bet (with delay to let them see it)
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
    }

    // Control will be added to gameContainerView in setupGameContainerView()
  }

  func setupComeBetControl() {
    comeBetControl = ComeBetControl(title: "Come")
    comeBetControl.translatesAutoresizingMaskIntoConstraints = false

    comeBetControl.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 1
    }
    comeBetControl.getBalance = { [weak self] in
      return self?.balance ?? 200
    }
    comeBetControl.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      self.trackBet(amount: amount, type: .comeBet)
      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()
    }
    comeBetControl.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
    }

    // Come bet cannot have odds while on the come line (odds only after moving to a number)
    // The ComeBetControl already has odds support but we don't need it here
    // Odds will be handled by the OddsBetStack on the PointControl after the bet moves

    // Come bet can only be placed during point phase - starts disabled
    comeBetControl.isUserInteractionEnabled = false
    comeBetControl.alpha = 0.5

    // Control will be added to gameContainerView in setupGameContainerView()
  }

  func setupAnySevenControl() {
    let control = PlainControl(title: "Any 7", usesTopCenterChipLayout: true)
    control.translatesAutoresizingMaskIntoConstraints = false
    control.isPerpetualBet = false
    control.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 1
    }
    control.getBalance = { [weak self] in
      return self?.balance ?? 200
    }
    control.onBetPlaced = { [weak self] amount in
      guard let self else { return }
      self.trackBet(amount: amount, type: .anySeven)
      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()
    }
    control.onBetRemoved = { [weak self] amount in
      guard let self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
    }
    control.isUserInteractionEnabled = false
    control.alpha = 0.5
    anySevenControl = control
  }

  func setupCAndETriZoneControl() {
    cAndETriZoneControl = TriZoneBetControl(
      zones: [
        .init(title: "C"),
        .init(title: "C&E"),
        .init(title: "E"),
      ],
      axis: .horizontal
    )
    cAndETriZoneControl?.translatesAutoresizingMaskIntoConstraints = false
    cAndETriZoneControl?.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 1
    }
    cAndETriZoneControl?.getBalance = { [weak self] in
      return self?.balance ?? 200
    }
    cAndETriZoneControl?.onBetPlaced = { [weak self] amount, _ in
      guard let self else { return }
      self.trackBet(amount: amount, type: .cAndE)
      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()
    }
    cAndETriZoneControl?.onBetRemoved = { [weak self] amount, _ in
      guard let self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
    }
    cAndETriZoneControl?.isUserInteractionEnabled = false
    cAndETriZoneControl?.alpha = 0.5
  }

  func setupDontPassControl() {
    let dp = DontPassControl(title: "Don't Pass")
    dontPassControl = dp
    dp.translatesAutoresizingMaskIntoConstraints = false
    dp.isPerpetualBet = true
    dp.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 1
    }
    dp.getBalance = { [weak self] in
      return self?.balance ?? 200
    }
    dp.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      self.trackBet(amount: amount, type: .dontPass)

      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()

      if self.game.isPointPhase {
        self.dontPassBetPlacedDuringPointPhase = true
      }

      self.updatePassLineOddsVisibility()

      NNTipManager.shared.dismissTip(CrapsTips.tapToBetTip, afterDelay: 1.5)
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + 0.5) { [weak self] in
        self?.showTips()
      }
    }

    dp.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
      self.updatePassLineOddsVisibility()
    }

    dp.addedBetCompletionHandler = { [weak self] in
      guard let self = self else { return }
      self.passLineControl.stopTitleShimmer()
      dp.stopTitleShimmer()
    }

    dp.canRemoveBet = { [weak self] in
      guard let self = self else { return true }
      return !self.gameStateManager.isPointPhase
    }

    dp.supportsOdds = true
    dp.winningsAnimationDirection = .leading
    dp.onOddsPlaced = { [weak self] amount, previousOddsAmount in
      guard let self = self else { return }
      let currentPoint = self.game.currentPoint ?? 0
      let maxMultiplier = self.maxOddsMultiplier(for: currentPoint)
      let maxOddsBet = dp.betAmount * maxMultiplier
      let newOddsBet = dp.oddsAmount

      if newOddsBet > maxOddsBet {
        let actualAmountAdded = maxOddsBet - previousOddsAmount
        dp.oddsAmount = maxOddsBet
        HapticsHelper.lightHaptic()
        if actualAmountAdded > 0 {
          self.trackBet(amount: actualAmountAdded, type: .odds)
          self.balance -= actualAmountAdded
        }
      } else {
        self.trackBet(amount: amount, type: .odds)
        self.balance -= amount
      }
      self.updateCurrentBet()
    }

    dp.onOddsRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      // Dismiss drag chip tip once user removes a bet (with delay to let them see it)
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
    }

    // Control will be added to gameContainerView in setupGameContainerView()
    // Width constraints will be set up in setupGameContainerView()
  }

  func setupGameContainerView() {
    // Create container view that holds all gameplay controls
    gameContainerView = UIView()
    gameContainerView.translatesAutoresizingMaskIntoConstraints = false

    // Add all controls to the container
    gameContainerView.addSubview(pointStack)
    gameContainerView.addSubview(fieldControl)
    gameContainerView.addSubview(comeBetControl)
    if let anySeven = anySevenControl {
      gameContainerView.addSubview(anySeven)
    }
    if let cAndE = cAndETriZoneControl {
      gameContainerView.addSubview(cAndE)
    }
    gameContainerView.addSubview(passLineControl)
    if let dontPass = dontPassControl {
      gameContainerView.addSubview(dontPass)
    }

    let spacing: CGFloat = 6

    comeBetControl.setContentHuggingPriority(.required, for: .vertical)
    comeBetControl.setContentCompressionResistancePriority(.required, for: .vertical)
    anySevenControl?.setContentHuggingPriority(.required, for: .vertical)
    anySevenControl?.setContentCompressionResistancePriority(.required, for: .vertical)
    cAndETriZoneControl?.setContentHuggingPriority(.required, for: .vertical)
    cAndETriZoneControl?.setContentCompressionResistancePriority(.required, for: .vertical)
    fieldControl.setContentHuggingPriority(.required, for: .vertical)
    fieldControl.setContentCompressionResistancePriority(.required, for: .vertical)
    passLineControl.setContentHuggingPriority(.required, for: .vertical)
    passLineControl.setContentCompressionResistancePriority(.required, for: .vertical)
    dontPassControl?.setContentHuggingPriority(.required, for: .vertical)
    dontPassControl?.setContentCompressionResistancePriority(.required, for: .vertical)

    var constraints: [NSLayoutConstraint] = [
      pointStack.topAnchor.constraint(equalTo: gameContainerView.topAnchor),
      pointStack.leadingAnchor.constraint(equalTo: gameContainerView.leadingAnchor, constant: 16),
      pointStack.trailingAnchor.constraint(
        equalTo: gameContainerView.trailingAnchor, constant: -16),
      pointStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
    ]

    if isCrapless {
      // Crapless: point boxes → field (full width) → pass (leading) + come (trailing) on one row
      let pointToFieldSpacing = pointStack.bottomAnchor.constraint(
        equalTo: fieldControl.topAnchor, constant: -60)
      let fieldToPassRowSpacing = fieldControl.bottomAnchor.constraint(
        equalTo: passLineControl.topAnchor, constant: -20)
      let passRowToBottom = passLineControl.bottomAnchor.constraint(
        equalTo: gameContainerView.bottomAnchor)
      gameContainerSpacingConstraints = [
        pointToFieldSpacing, fieldToPassRowSpacing, passRowToBottom,
      ]

      constraints += [
        pointToFieldSpacing,
        fieldControl.leadingAnchor.constraint(
          equalTo: gameContainerView.leadingAnchor, constant: 16),
        fieldControl.trailingAnchor.constraint(
          equalTo: gameContainerView.trailingAnchor, constant: -16),
        fieldToPassRowSpacing,
        passLineControl.leadingAnchor.constraint(
          equalTo: gameContainerView.leadingAnchor, constant: 16),
        passLineControl.trailingAnchor.constraint(
          equalTo: comeBetControl.leadingAnchor, constant: -spacing),
        comeBetControl.trailingAnchor.constraint(
          equalTo: gameContainerView.trailingAnchor, constant: -16),
        passLineControl.widthAnchor.constraint(equalTo: comeBetControl.widthAnchor),
        passLineControl.topAnchor.constraint(equalTo: comeBetControl.topAnchor),
        passLineControl.bottomAnchor.constraint(equalTo: comeBetControl.bottomAnchor),
        passRowToBottom,
      ]
    } else {
      let pointToComeSpacing = pointStack.bottomAnchor.constraint(
        equalTo: comeBetControl.topAnchor, constant: -60)
      let comeToFieldSpacing = comeBetControl.bottomAnchor.constraint(
        equalTo: fieldControl.topAnchor, constant: -20)
      let fieldToPassDontSpacing = fieldControl.bottomAnchor.constraint(
        equalTo: passLineControl.topAnchor, constant: -20)
      gameContainerSpacingConstraints = [
        pointToComeSpacing, comeToFieldSpacing, fieldToPassDontSpacing,
      ]

      constraints += [pointToComeSpacing]

      if let cAndE = cAndETriZoneControl, let anySeven = anySevenControl {
        constraints += [
          comeBetControl.leadingAnchor.constraint(
            equalTo: gameContainerView.leadingAnchor, constant: 16),
          anySeven.leadingAnchor.constraint(
            equalTo: comeBetControl.trailingAnchor, constant: spacing),
          anySeven.trailingAnchor.constraint(
            equalTo: cAndE.leadingAnchor, constant: -spacing),
          comeBetControl.topAnchor.constraint(equalTo: cAndE.topAnchor),
          comeBetControl.bottomAnchor.constraint(equalTo: cAndE.bottomAnchor),
          anySeven.topAnchor.constraint(equalTo: cAndE.topAnchor),
          anySeven.bottomAnchor.constraint(equalTo: cAndE.bottomAnchor),
          comeBetControl.widthAnchor.constraint(equalTo: cAndE.widthAnchor, multiplier: 0.85),
          anySeven.widthAnchor.constraint(equalTo: cAndE.widthAnchor, multiplier: 0.5),
          cAndE.trailingAnchor.constraint(equalTo: gameContainerView.trailingAnchor, constant: -16),
          comeToFieldSpacing,
        ]
      } else {
        constraints += [
          comeBetControl.leadingAnchor.constraint(
            equalTo: gameContainerView.leadingAnchor, constant: 16),
          comeBetControl.trailingAnchor.constraint(
            equalTo: gameContainerView.trailingAnchor, constant: -16),
          comeToFieldSpacing,
        ]
      }

      constraints += [
        fieldControl.leadingAnchor.constraint(
          equalTo: gameContainerView.leadingAnchor, constant: 16),
        fieldControl.trailingAnchor.constraint(
          equalTo: gameContainerView.trailingAnchor, constant: -16),
        fieldToPassDontSpacing,
      ]

      if let dontPass = dontPassControl {
        passLineControlWidthConstraint = passLineControl.widthAnchor.constraint(
          equalTo: dontPass.widthAnchor)
        constraints += [
          passLineControl.leadingAnchor.constraint(
            equalTo: gameContainerView.leadingAnchor, constant: 16),
          passLineControl.trailingAnchor.constraint(
            equalTo: dontPass.leadingAnchor, constant: -spacing),
          passLineControl.topAnchor.constraint(equalTo: dontPass.topAnchor),
          passLineControl.bottomAnchor.constraint(equalTo: dontPass.bottomAnchor),
          passLineControlWidthConstraint!,
          dontPass.trailingAnchor.constraint(
            equalTo: gameContainerView.trailingAnchor, constant: -16),
          passLineControl.bottomAnchor.constraint(equalTo: gameContainerView.bottomAnchor),
        ]
      } else {
        constraints += [
          passLineControl.leadingAnchor.constraint(
            equalTo: gameContainerView.leadingAnchor, constant: 16),
          passLineControl.trailingAnchor.constraint(
            equalTo: gameContainerView.trailingAnchor, constant: -16),
          passLineControl.bottomAnchor.constraint(equalTo: gameContainerView.bottomAnchor),
        ]
      }
    }

    NSLayoutConstraint.activate(constraints)

    // Add container to view - positioning constraints will be set in applyLayout()
    view.addSubview(gameContainerView)
  }

  /// Updates the internal spacing inside gameContainerView based on layout mode.
  /// In landscape there is less vertical space, so spacing adjusts to give pointStack more room.
  func updateGameContainerHeights(for mode: LayoutMode) {
    let spacing: CGFloat
    let pointStackSpacing: CGFloat  // Larger spacing for pointStack

    switch mode {
    case .iPhonePortrait:
      spacing = 4
      pointStackSpacing = 20  // More space between pointStack and controls
    case .iPadPortrait:
      spacing = 12
      pointStackSpacing = 44  // More space between pointStack and controls
    case .iPadLandscape:
      spacing = 12
      pointStackSpacing = 44
    }

    // Standard: [0] point→come, [1] come→field, [2] field→pass row.
    // Crapless: [0] point→field, [1] field→pass row, [2] pass row→bottom (0).
    if gameContainerSpacingConstraints.count >= 3 {
      gameContainerSpacingConstraints[0].constant = -pointStackSpacing
      gameContainerSpacingConstraints[1].constant = -spacing
      gameContainerSpacingConstraints[2].constant = isCrapless ? 0 : -spacing
    }
  }

  func setupBalanceView() {
    balanceView = BalanceView()
    balanceView.accessibilityIdentifier = "balanceView"

    // Initialize chip animation helper after balanceView is created
    chipAnimator = ChipAnimationHelper(containerView: view, balanceView: balanceView)
  }

  func setupChipSelector() {
    chipSelector = ChipSelector()
    chipSelector.delegate = self
    chipSelector.onBetReturned = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      // Delay updateCurrentBet() to ensure it runs after the bet is cleared in BetDragManager
      // The animation takes 0.2s, so delay by slightly more to ensure bet is cleared first
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        self.updateCurrentBet()
      }
    }
  }

  func setupBottomStackView() {
    // Create stack view with BalanceView on top and ChipSelector below
    bottomStackView = UIStackView()
    bottomStackView.translatesAutoresizingMaskIntoConstraints = false
    bottomStackView.axis = .vertical
    bottomStackView.distribution = .fill
    bottomStackView.alignment = .leading
    bottomStackView.spacing = 8

    // Add views to stack
    bottomStackView.addArrangedSubview(balanceView)
    bottomStackView.addArrangedSubview(chipSelector)

    view.addSubview(bottomStackView)

    // Set high content hugging priority so bottomStackView stays at its intrinsic size
    bottomStackView.setContentHuggingPriority(.required, for: .vertical)
    bottomStackView.setContentCompressionResistancePriority(.required, for: .vertical)

    // Constraints will be activated in applyLayout()
  }

  func setupFlipDice() {
    flipDiceContainer = FlipDiceContainer()
    flipDiceContainer.translatesAutoresizingMaskIntoConstraints = false
    flipDiceContainer.accessibilityIdentifier = "flipDiceContainer"

    view.addSubview(flipDiceContainer)

    // Constraints will be activated in applyLayout()

    flipDiceContainer.onRollStarted = { [weak self] in
      // Do something when roll starts
    }

    flipDiceContainer.onUserInitiatedRollAttempt = { [weak self] in
      self?.crapsAutoplayer?.cancelDueToUserInteraction()
      self?.refreshAutoplayNavigationChrome()
    }

    flipDiceContainer.onRollComplete = { [weak self] die1, die2, total in
      guard let self else { return }
      // Snapshot before resolution — `handleRollResult` applies `game.processRoll`.
      let hadPoint = self.game.isPointPhase
      let pointBefore = self.game.currentPoint
      let passBetBeforeResolution = self.passLineControl.betAmount

      let passLineLostThisRoll: Bool
      if hadPoint, let pointNumber = pointBefore {
        passLineLostThisRoll =
          self.game.rules.passLinePointEvent(for: total, pointNumber: pointNumber) == .sevenOut
      } else {
        passLineLostThisRoll =
          passBetBeforeResolution > 0
          && self.game.rules.passLineComeOutEvent(for: total) == .passLineLoss
      }

      self.handleRollResult(die1: die1, die2: die2, total: total)

      let hitPassLinePoint = hadPoint && pointBefore == total
      self.crapsAutoplayer?.notifyRollResolved(
        hitPassLinePoint: hitPassLinePoint,
        passLineLost: passLineLostThisRoll)
    }

    flipDiceContainer.onDisabledTap = { [weak self] in
      self?.handleDisabledRollTap()
    }

    // Initially disable rolling until pass line bet is placed
    flipDiceContainer.disableRolling()
  }

  private func handleDisabledRollTap() {
    // Determine why rolling is disabled and show appropriate message
    if game.isPointPhase {
      // Shouldn't happen - rolling should be enabled in point phase
      // But if it does, show generic message
      instructionLabel.showMessage(
        "Please wait for the current roll to complete.", shouldFade: true)
    } else if !hasAnyBetPlaced() {
      // No bets placed - need to place any bet to roll
      instructionLabel.showMessage("Place a bet to roll the dice.", shouldFade: true)
    } else {
      // Rolling is disabled for some other reason (animations, etc.)
      instructionLabel.showMessage("Please wait...", shouldFade: true)
    }
  }

  func updateRollingState() {
    gameStateManager.updateRollingState(hasAnyBetPlaced: hasAnyBetPlaced())
  }

  func setupHardwayStack() {
    // Create container view for bets section (scroll view + page control)
    betsContainerView = UIView()
    betsContainerView.translatesAutoresizingMaskIntoConstraints = false

    // Create scroll view with paging enabled
    betsScrollView = UIScrollView()
    betsScrollView.translatesAutoresizingMaskIntoConstraints = false
    betsScrollView.isPagingEnabled = true
    betsScrollView.showsHorizontalScrollIndicator = false
    betsScrollView.showsVerticalScrollIndicator = false
    betsScrollView.bounces = true
    betsScrollView.delegate = self

    // Create page control
    pageControl = UIPageControl()
    pageControl.translatesAutoresizingMaskIntoConstraints = false
    pageControl.currentPage = 0
    pageControl.pageIndicatorTintColor = HardwayColors.label.withAlphaComponent(0.3)
    pageControl.currentPageIndicatorTintColor = HardwayColors.label
    pageControl.isUserInteractionEnabled = false  // We'll handle scrolling via the scroll view

    // Create container view for both stacks (content inside scroll view)
    scrollContentView = UIView()
    scrollContentView.translatesAutoresizingMaskIntoConstraints = false

    // Create actions view (always present)
    actionsView = createActionsView()

    // Add scroll content view to scroll view
    betsScrollView.addSubview(scrollContentView)

    // Add scroll view and page control to container view
    betsContainerView.addSubview(betsScrollView)
    betsContainerView.addSubview(pageControl)

    // Add container view to main view
    view.addSubview(betsContainerView)

    // Constraints will be activated in applyLayout()
    // Store width constraint for later updates (will be configured per layout mode)
    scrollContentWidthConstraint = scrollContentView.widthAnchor.constraint(
      equalTo: betsScrollView.widthAnchor, multiplier: 1)
  }

  func rebuildBetViews(for layoutMode: LayoutMode) {
    // Get settings
    let settings = settingsManager.currentSettings

    // Check if bonus bet settings actually changed
    let currentSettings = (
      hardways: settings.hardwaysEnabled, makeEm: settings.makeEmEnabled, horn: settings.hornEnabled
    )
    let settingsChanged = previousBonusBetSettings.map { $0 != currentSettings } ?? true

    // Update previous settings
    previousBonusBetSettings = currentSettings

    // Deactivate any constraints from a previous rebuildBetViews call
    NSLayoutConstraint.deactivate(activeBetViewConstraints)
    activeBetViewConstraints = []

    // Clear content from scroll view
    scrollContentView.subviews.forEach { $0.removeFromSuperview() }

    // Remove dynamically-added subviews from betsContainerView,
    // but NEVER remove betsScrollView or pageControl (they must stay for cached constraints)
    for subview in betsContainerView.subviews {
      if subview === betsScrollView || subview === pageControl {
        continue  // Always keep these as subviews
      }
      subview.removeFromSuperview()
    }

    // Clear references
    hardwayView = nil
    makeEmView = nil
    hornView = nil

    var betViews: [UIView] = []

    // Add enabled bonus bet views in the correct order: hardways, make em, horn, actions
    if settings.hardwaysEnabled {
      let hardway = createBetView(
        title: "Hardways",
        controls: [
          (dieValue1: 3, dieValue2: 3, odds: "9:1"),
          (dieValue1: 4, dieValue2: 4, odds: "9:1"),
          (dieValue1: 2, dieValue2: 2, odds: "7:1"),
          (dieValue1: 5, dieValue2: 5, odds: "7:1"),
        ], isPerpetual: true, betType: .hardway)
      hardwayView = hardway
      betViews.append(hardway)
    }

    if settings.makeEmEnabled {
      let makeEm = createMakeEmView()
      makeEmView = makeEm
      betViews.append(makeEm)
    }

    if settings.hornEnabled {
      let horn = createBetView(
        title: "Horn",
        controls: [
          (dieValue1: 1, dieValue2: 1, odds: "30:1"),  // Snake eyes
          (dieValue1: 6, dieValue2: 6, odds: "30:1"),  // Boxcars
          (dieValue1: 1, dieValue2: 2, odds: "15:1"),  // Ace-deuce
          (dieValue1: 5, dieValue2: 6, odds: "15:1"),  // Five-six
        ], isPerpetual: false, betType: .horn)
      hornView = horn
      betViews.append(horn)
    }

    // Separate actions view (always visible in landscape, included in scroll for other modes)
    var actionsViewSeparate: UIView? = nil

    var constraints: [NSLayoutConstraint] = []

    switch layoutMode {
    case .iPhonePortrait:
      // iPhone: Use scroll view with horizontal paging
      betsScrollView.isHidden = false
      pageControl.isHidden = false

      // Include actions in scroll
      betViews.append(actionsView)

      // Build pages (1 item per page)
      let pages = betViews.map { $0 }
      pageControl.numberOfPages = pages.count

      // Update scroll content width
      scrollContentWidthConstraint?.isActive = false
      scrollContentWidthConstraint = scrollContentView.widthAnchor.constraint(
        equalTo: betsScrollView.widthAnchor,
        multiplier: CGFloat(pages.count)
      )
      scrollContentWidthConstraint?.isActive = true

      // Add pages to scroll content
      var previousPage: UIView?
      for (index, page) in pages.enumerated() {
        scrollContentView.addSubview(page)
        page.translatesAutoresizingMaskIntoConstraints = false

        if let previous = previousPage {
          constraints.append(
            page.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 48))
        } else {
          constraints.append(
            page.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor, constant: 24))
        }

        constraints.append(contentsOf: [
          page.widthAnchor.constraint(equalTo: betsScrollView.widthAnchor, constant: -48),
          page.topAnchor.constraint(equalTo: scrollContentView.topAnchor),
          page.bottomAnchor.constraint(equalTo: scrollContentView.bottomAnchor),
        ])

        previousPage = page
      }

    case .iPadPortrait:
      // iPad Portrait: 2x2 grid - Top row: Hardways + Make Em, Bottom row: Horn + Actions
      betsScrollView.isHidden = true
      pageControl.isHidden = true

      // Create 2x2 grid
      let gridStack = UIStackView()
      gridStack.translatesAutoresizingMaskIntoConstraints = false
      gridStack.axis = .vertical
      gridStack.distribution = .fillEqually
      gridStack.alignment = .fill
      gridStack.spacing = 16

      // Build top row: Hardways (left) + Make Em (right)
      var row1Views: [UIView] = []
      if let hardway = hardwayView {
        row1Views.append(hardway)
      }
      if let makeEm = makeEmView {
        row1Views.append(makeEm)
      }

      // Build bottom row: Horn (left) + Actions (right)
      var row2Views: [UIView] = []
      if let horn = hornView {
        row2Views.append(horn)
      }
      row2Views.append(actionsView)

      // Create row stacks
      if !row1Views.isEmpty {
        let row1 = UIStackView(arrangedSubviews: row1Views)
        row1.translatesAutoresizingMaskIntoConstraints = false
        row1.axis = .horizontal
        row1.distribution = .fillEqually
        row1.spacing = 16
        gridStack.addArrangedSubview(row1)
      }

      if !row2Views.isEmpty {
        let row2 = UIStackView(arrangedSubviews: row2Views)
        row2.translatesAutoresizingMaskIntoConstraints = false
        row2.axis = .horizontal
        row2.distribution = .fillEqually
        row2.spacing = 16
        gridStack.addArrangedSubview(row2)
      }

      betsContainerView.addSubview(gridStack)

      constraints.append(contentsOf: [
        gridStack.topAnchor.constraint(equalTo: betsContainerView.topAnchor),
        gridStack.leadingAnchor.constraint(equalTo: betsContainerView.leadingAnchor),
        gridStack.trailingAnchor.constraint(equalTo: betsContainerView.trailingAnchor),
        gridStack.bottomAnchor.constraint(equalTo: betsContainerView.bottomAnchor),
      ])

    case .iPadLandscape:
      // iPad Landscape: Vertical column with Make Em and Actions side-by-side at bottom
      betsScrollView.isHidden = true
      pageControl.isHidden = true

      // NO actions in landscape scroll (will be placed separately)
      actionsViewSeparate = nil

      // Build vertical column views
      var columnViews: [UIView] = []

      // Add in order: Hardways first
      if let hardway = hardwayView {
        columnViews.append(hardway)
      }

      // Then Horn
      if let horn = hornView {
        columnViews.append(horn)
      }

      // Build horizontal stack for Make Em and Actions
      var bottomHorizontalViews: [UIView] = []

      // Add Make Em on the left
      if let makeEm = makeEmView {
        bottomHorizontalViews.append(makeEm)
      }

      // Add Actions on the right
      bottomHorizontalViews.append(actionsView)

      // Create horizontal stack for Make Em and Actions
      let makeEmActionsStack = UIStackView(arrangedSubviews: bottomHorizontalViews)
      makeEmActionsStack.translatesAutoresizingMaskIntoConstraints = false
      makeEmActionsStack.axis = .horizontal
      makeEmActionsStack.distribution = .fillEqually
      makeEmActionsStack.spacing = 16
      makeEmActionsStack.alignment = .fill

      // Add the horizontal stack to column views
      columnViews.append(makeEmActionsStack)

      // Create single vertical stack with all items
      let columnStack = UIStackView(arrangedSubviews: columnViews)
      columnStack.translatesAutoresizingMaskIntoConstraints = false
      columnStack.axis = .vertical
      columnStack.distribution = .fillEqually
      columnStack.spacing = 16
      columnStack.alignment = .fill

      betsContainerView.addSubview(columnStack)

      // Constrain column stack to fill container
      constraints.append(contentsOf: [
        columnStack.topAnchor.constraint(equalTo: betsContainerView.topAnchor),
        columnStack.leadingAnchor.constraint(equalTo: betsContainerView.leadingAnchor),
        columnStack.trailingAnchor.constraint(equalTo: betsContainerView.trailingAnchor),
        columnStack.bottomAnchor.constraint(equalTo: betsContainerView.bottomAnchor),
      ])
    }

    NSLayoutConstraint.activate(constraints)
    activeBetViewConstraints = constraints

    // Force layout update
    view.layoutIfNeeded()
  }

  private func createBetView(
    title: String, controls: [(dieValue1: Int, dieValue2: Int, odds: String)], isPerpetual: Bool,
    betType: BetType
  ) -> QuadBetView {
    // Create QuadBetView with title
    let quadBetView = QuadBetView(title: title)

    // Create left column stack
    let leftColumn = UIStackView()
    leftColumn.translatesAutoresizingMaskIntoConstraints = false
    leftColumn.axis = .vertical
    leftColumn.distribution = .fillEqually
    leftColumn.spacing = 8

    // Create right column stack
    let rightColumn = UIStackView()
    rightColumn.translatesAutoresizingMaskIntoConstraints = false
    rightColumn.axis = .vertical
    rightColumn.distribution = .fillEqually
    rightColumn.spacing = 8

    // Create controls
    var betControls: [SmallControl] = []
    for controlInfo in controls {
      let control = SmallControl(
        dieValue1: controlInfo.dieValue1, dieValue2: controlInfo.dieValue2, odds: controlInfo.odds,
        hidesOddsWhileBetting: betType == .horn)
      control.translatesAutoresizingMaskIntoConstraints = false
      control.isPerpetualBet = isPerpetual
      control.getSelectedChipValue = { [weak self] in
        return self?.selectedChipValue ?? 1
      }
      control.getBalance = { [weak self] in
        return self?.balance ?? 200
      }
      control.onBetPlaced = { [weak self] amount in
        guard let self = self else { return }
        self.trackBet(amount: amount, type: betType)
        self.balance -= amount
        self.updateCurrentBet()
        self.updateRollingState()
      }
      control.onBetRemoved = { [weak self] amount in
        guard let self = self else { return }
        self.balance += amount
        self.updateCurrentBet()
        self.updateRollingState()
        // Dismiss drag chip tip once user removes a bet
        NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
      }
      betControls.append(control)
    }

    // Horn: 2 & 3 left, 11 & 12 right, Any Horn narrow column in the middle (full row height).
    if betType == .horn {
      leftColumn.addArrangedSubview(betControls[0])
      leftColumn.addArrangedSubview(betControls[2])
      rightColumn.addArrangedSubview(betControls[3])
      rightColumn.addArrangedSubview(betControls[1])
    } else {
      leftColumn.addArrangedSubview(betControls[0])
      leftColumn.addArrangedSubview(betControls[1])
      rightColumn.addArrangedSubview(betControls[2])
      rightColumn.addArrangedSubview(betControls[3])
    }

    if betType == .horn {
      quadBetView.betStack.distribution = .fill
      quadBetView.betStack.spacing = 6
      quadBetView.betStack.alignment = .fill

      let anyHornControl = AnyHornControl()
      anyHornControl.translatesAutoresizingMaskIntoConstraints = false
      anyHornControl.winningsAnimationDirection = .leading
      anyHornControl.getSelectedChipValue = { [weak self] in
        return self?.selectedChipValue ?? 1
      }
      anyHornControl.getBalance = { [weak self] in
        return self?.balance ?? 200
      }
      anyHornControl.onBetPlaced = { [weak self] amount in
        guard let self = self else { return }
        self.trackBet(amount: amount, type: .horn)
        self.balance -= amount
        self.updateCurrentBet()
        self.updateRollingState()
      }
      anyHornControl.onBetRemoved = { [weak self] amount in
        guard let self = self else { return }
        self.balance += amount
        self.updateCurrentBet()
        self.updateRollingState()
        NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
      }

      let centerColumn = UIStackView()
      centerColumn.translatesAutoresizingMaskIntoConstraints = false
      centerColumn.axis = .vertical
      centerColumn.alignment = .center
      centerColumn.distribution = .fill
      centerColumn.addArrangedSubview(anyHornControl)
      centerColumn.setContentHuggingPriority(.required, for: .horizontal)
      centerColumn.setContentCompressionResistancePriority(.required, for: .horizontal)

      quadBetView.betStack.addArrangedSubview(leftColumn)
      quadBetView.betStack.addArrangedSubview(centerColumn)
      quadBetView.betStack.addArrangedSubview(rightColumn)

      NSLayoutConstraint.activate([
        leftColumn.widthAnchor.constraint(equalTo: rightColumn.widthAnchor),
        anyHornControl.widthAnchor.constraint(equalTo: leftColumn.widthAnchor, multiplier: 0.5),
        anyHornControl.heightAnchor.constraint(equalTo: leftColumn.heightAnchor),
      ])
      return quadBetView
    }

    quadBetView.betStack.addArrangedSubview(leftColumn)
    quadBetView.betStack.addArrangedSubview(rightColumn)

    return quadBetView
  }

  /// Adjusts height constraints on SmallControls based on layout mode
  /// In landscape mode, lowers priority to allow expansion in vertical stacks
  private func adjustSmallControlHeights(in view: UIView, forLandscape: Bool) {
    // Recursively find all SmallControls
    func findSmallControls(in view: UIView) -> [SmallControl] {
      var controls: [SmallControl] = []
      if let smallControl = view as? SmallControl {
        controls.append(smallControl)
      }
      for subview in view.subviews {
        controls.append(contentsOf: findSmallControls(in: subview))
      }
      return controls
    }

    let smallControls = findSmallControls(in: view)
    for control in smallControls {
      // Find height constraint
      for constraint in control.constraints {
        if constraint.firstAttribute == .height && constraint.firstItem === control {
          if forLandscape {
            // Lower priority to allow expansion in vertical stack
            constraint.priority = .defaultLow
          } else {
            // Restore normal priority
            constraint.priority = .defaultHigh
          }
        }
      }
    }
  }

  private func createMakeEmView() -> UIView {
    // Create container view with title
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false

    // Create title label
    let titleLabel = UILabel()
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "Make Em'"
    titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = HardwayColors.label
    titleLabel.textAlignment = .center
    container.addSubview(titleLabel)

    // Create Make Em Small control (2, 3, 4, 5, 6)
    let makeEmSmallControl = MultiBetControl(
      title: "Small",
      numbers: [2, 3, 4, 5, 6],
      odds: "34:1"
    )
    makeEmSmallControl.translatesAutoresizingMaskIntoConstraints = false
    makeEmSmallControl.winningsAnimationDirection = .leading  // Animate winnings to the leading edge
    makeEmSmallControl.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 1
    }
    makeEmSmallControl.getBalance = { [weak self] in
      return self?.balance ?? 200
    }
    makeEmSmallControl.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      // Prevent bet placement if more than 3/5 numbers are already hit
      if makeEmSmallControl.hitNumbers.count >= 4 {
        // Revert the bet addition by removing it
        makeEmSmallControl.betAmount -= amount
        HapticsHelper.lightHaptic()
        return
      }
      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()
    }
    makeEmSmallControl.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
      // Dismiss drag chip tip once user removes a bet (with delay to let them see it)
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
    }

    let makeEmAllControl = MakeEmAllControl()
    makeEmAllControl.translatesAutoresizingMaskIntoConstraints = false
    makeEmAllControl.winningsAnimationDirection = .leading
    makeEmAllControl.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 1
    }
    makeEmAllControl.getBalance = { [weak self] in
      return self?.balance ?? 200
    }
    makeEmAllControl.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      if makeEmAllControl.hitNumbers.count >= 9 {
        makeEmAllControl.betAmount -= amount
        HapticsHelper.lightHaptic()
        return
      }
      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()
    }
    makeEmAllControl.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
    }

    // Create Make Em Tall control (8, 9, 10, 11, 12)
    let makeEmTallControl = MultiBetControl(
      title: "Tall",
      numbers: [8, 9, 10, 11, 12],
      odds: "34:1"
    )
    makeEmTallControl.translatesAutoresizingMaskIntoConstraints = false
    makeEmTallControl.winningsAnimationDirection = .leading  // Animate winnings to the leading edge
    makeEmTallControl.getSelectedChipValue = { [weak self] in
      return self?.selectedChipValue ?? 1
    }
    makeEmTallControl.getBalance = { [weak self] in
      return self?.balance ?? 200
    }
    makeEmTallControl.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      // Prevent bet placement if more than 3/5 numbers are already hit
      if makeEmTallControl.hitNumbers.count >= 4 {
        // Revert the bet addition by removing it
        makeEmTallControl.betAmount -= amount
        HapticsHelper.lightHaptic()
        return
      }
      self.balance -= amount
      self.updateCurrentBet()
      self.updateRollingState()
    }
    makeEmTallControl.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
      // Dismiss drag chip tip once user removes a bet (with delay to let them see it)
      NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
    }

    let makeEmStack = UIStackView(arrangedSubviews: [
      makeEmSmallControl, makeEmAllControl, makeEmTallControl,
    ])
    makeEmStack.translatesAutoresizingMaskIntoConstraints = false
    makeEmStack.axis = .horizontal
    makeEmStack.distribution = .fill
    makeEmStack.alignment = .fill
    makeEmStack.spacing = 8
    container.addSubview(makeEmStack)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      titleLabel.heightAnchor.constraint(equalToConstant: 16),

      makeEmStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
      makeEmStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      makeEmStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      makeEmStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),

      makeEmSmallControl.widthAnchor.constraint(equalTo: makeEmTallControl.widthAnchor),
      makeEmAllControl.widthAnchor.constraint(
        equalTo: makeEmSmallControl.widthAnchor, multiplier: 0.6),
    ])

    return container
  }

  private func createActionsView() -> UIView {
    // Create container view with title
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false

    // Create title label
    let titleLabel = UILabel()
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "Actions"
    titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = HardwayColors.label
    titleLabel.textAlignment = .center
    container.addSubview(titleLabel)

    // Create toggle bets button
    let toggleBetsButton = UIButton(type: .system)
    toggleBetsButton.translatesAutoresizingMaskIntoConstraints = false
    toggleBetsButton.setTitle("Bets are ON", for: .normal)
    toggleBetsButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    toggleBetsButton.backgroundColor = HardwayColors.green
    toggleBetsButton.setTitleColor(.white, for: .normal)
    toggleBetsButton.layer.cornerRadius = 16
    toggleBetsButton.layer.borderWidth = 1.5
    toggleBetsButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
    toggleBetsButton.tag = 1001  // Tag to identify button later
    toggleBetsButton.addTarget(self, action: #selector(toggleBetsTapped), for: .touchUpInside)

    // Create collect bets button
    let collectBetsButton = UIButton(type: .system)
    collectBetsButton.translatesAutoresizingMaskIntoConstraints = false
    collectBetsButton.setTitle("Collect Bets", for: .normal)
    collectBetsButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    collectBetsButton.backgroundColor = HardwayColors.surfaceGray
    collectBetsButton.setTitleColor(.white, for: .normal)
    collectBetsButton.layer.cornerRadius = 16
    collectBetsButton.layer.borderWidth = 1.5
    collectBetsButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
    collectBetsButton.addTarget(self, action: #selector(collectBetsTapped), for: .touchUpInside)

    // Create horizontal stack for top buttons
    let topButtonStack = UIStackView(arrangedSubviews: [toggleBetsButton, collectBetsButton])
    topButtonStack.translatesAutoresizingMaskIntoConstraints = false
    topButtonStack.axis = .horizontal
    topButtonStack.distribution = .fillEqually
    topButtonStack.spacing = 8

    // Create refresh bankroll button
    let refreshBankrollButton = UIButton(type: .system)
    refreshBankrollButton.translatesAutoresizingMaskIntoConstraints = false
    refreshBankrollButton.setTitle("Hit the ATM", for: .normal)
    refreshBankrollButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    refreshBankrollButton.backgroundColor = HardwayColors.surfaceGray
    refreshBankrollButton.setTitleColor(.white, for: .normal)
    refreshBankrollButton.layer.cornerRadius = 16
    refreshBankrollButton.layer.borderWidth = 1.5
    refreshBankrollButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
    ATMWithdrawalPresenter.configureButton(refreshBankrollButton) { [weak self] amount in
      self?.hitATM(amount: amount)
    }
    refreshBankrollButton.setValue(false, forKey: "showsMenuFromSource")
    refreshBankrollButton.titleLabel?.numberOfLines = 2
    refreshBankrollButton.titleLabel?.adjustsFontSizeToFitWidth = true
    refreshBankrollButton.titleLabel?.minimumScaleFactor = 0.72
    refreshBankrollButton.titleLabel?.textAlignment = .center

    let placeAcrossButton = UIButton(type: .system)
    placeAcrossButton.translatesAutoresizingMaskIntoConstraints = false
    placeAcrossButton.setTitle("Place across", for: .normal)
    placeAcrossButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    placeAcrossButton.titleLabel?.numberOfLines = 2
    placeAcrossButton.titleLabel?.adjustsFontSizeToFitWidth = true
    placeAcrossButton.titleLabel?.minimumScaleFactor = 0.72
    placeAcrossButton.titleLabel?.textAlignment = .center
    placeAcrossButton.backgroundColor = HardwayColors.surfaceGray
    placeAcrossButton.setTitleColor(.white, for: .normal)
    placeAcrossButton.layer.cornerRadius = 16
    placeAcrossButton.layer.borderWidth = 1.5
    placeAcrossButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
    placeAcrossButton.tag = 1002
    placeAcrossButton.accessibilityIdentifier = "placeAcrossButton"
    placeAcrossButton.isEnabled = betsAreOn
    PlaceAcrossMenuPresenter.configureButton(
      placeAcrossButton,
      variant: variant,
      balanceProvider: { [weak self] in self?.balance ?? 0 },
      selectedChipProvider: { [weak self] in self?.selectedChipValue ?? 5 }
    ) { [weak self] allocation in
      self?.applyPlaceAcross(allocation)
    }
    placeAcrossButton.setValue(false, forKey: "showsMenuFromSource")

    let bankRowStack = UIStackView(arrangedSubviews: [refreshBankrollButton, placeAcrossButton])
    bankRowStack.translatesAutoresizingMaskIntoConstraints = false
    bankRowStack.axis = .horizontal
    bankRowStack.distribution = .fillEqually
    bankRowStack.spacing = 8

    // Create vertical stack for all buttons
    let buttonStack = UIStackView(arrangedSubviews: [topButtonStack, bankRowStack])
    buttonStack.translatesAutoresizingMaskIntoConstraints = false
    buttonStack.axis = .vertical
    buttonStack.distribution = .fillEqually
    buttonStack.spacing = 8
    container.addSubview(buttonStack)

    // Layout constraints
    NSLayoutConstraint.activate([
      // Title label
      titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      titleLabel.heightAnchor.constraint(equalToConstant: 20),

      // Button stack
      buttonStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
      buttonStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),

      // Height for top button row and individual buttons (all 50pt)
      topButtonStack.heightAnchor.constraint(equalToConstant: 50),
      toggleBetsButton.heightAnchor.constraint(equalToConstant: 50),
      collectBetsButton.heightAnchor.constraint(equalToConstant: 50),
      bankRowStack.heightAnchor.constraint(equalToConstant: 50),
      refreshBankrollButton.heightAnchor.constraint(equalToConstant: 50),
      placeAcrossButton.heightAnchor.constraint(equalToConstant: 50),
    ])

    return container
  }

  func setupTopStackView() {
    // Create instruction label
    instructionLabel = InstructionLabel()
    // Give instructionLabel lower horizontal priority so it compresses before currentBetView
    instructionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    // Allow vertical expansion to accommodate 2 lines
    instructionLabel.setContentHuggingPriority(.defaultLow, for: .vertical)

    // Create current bet view
    currentBetView = CurrentBetView()
    // Give currentBetView higher horizontal priority so it doesn't compress
    currentBetView.setContentCompressionResistancePriority(.required, for: .horizontal)
    // Set a fixed width to ensure it never gets compressed (wide enough for "$999999")
    currentBetView.setContentHuggingPriority(.required, for: .horizontal)

    // Create horizontal stack view
    topStackView = UIStackView()
    topStackView.translatesAutoresizingMaskIntoConstraints = false
    topStackView.axis = .horizontal
    topStackView.distribution = .fill
    topStackView.alignment = .top
    topStackView.spacing = 16

    // Add views to stack
    topStackView.addArrangedSubview(instructionLabel)
    topStackView.addArrangedSubview(currentBetView)

    view.addSubview(topStackView)

    // Create constraint that will be updated based on playstyle visibility
    topStackTopConstraint = topStackView.topAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)

    // Show initial message
    instructionLabel.showMessage("Place a Pass Line bet to begin!", shouldFade: false)

    // Update current bet initially
    updateCurrentBet()
  }

  func updateCurrentBet() {
    // Sum all bet amounts from controls
    var totalBet = getAllBettingControls().reduce(0) { $0 + $1.betAmount }

    // Add pending come bet amount (on come line)
    totalBet += comeBetControl?.betAmount ?? 0
    totalBet += cAndETriZoneControl?.totalBetAmount ?? 0

    // Add come bet amounts on points
    if let pointStack = pointStack {
      totalBet += pointStack.getPointControlsWithComeBets().reduce(0) { $0 + $1.comeBetAmount }
      totalBet += pointStack.getLayBetTotal()
    }

    // Add odds amounts from pass line and don't pass controls
    var totalOdds: Int = 0
    if let passLine = passLineControl {
      totalOdds += passLine.oddsAmount
    }
    if let dontPass = dontPassControl {
      totalOdds += dontPass.oddsAmount
    }

    // Add come bet odds amounts from point controls
    if let pointStack = pointStack {
      for pointNumber in pointStack.pointNumbers {
        if let pointControl = pointStack.getPointControl(for: pointNumber) as? PointControl {
          totalOdds += pointControl.comeBetOddsAmount
        }
      }
    }

    // Total bet includes both regular bets and odds bets
    currentBetView?.currentBet = totalBet + totalOdds
  }

  private func animateChipsAway(to destination: CGPoint, shouldFadeOut: Bool) {
    let allControls = getAllBettingControls()
    animateChipsAway(from: allControls, to: destination, shouldFadeOut: shouldFadeOut)
  }

  private func animateChipsAway(
    from controls: [PlainControl], to destination: CGPoint, shouldFadeOut: Bool
  ) {
    let targets = controls.filter { $0.betAmount > 0 }
    guard !targets.isEmpty else {
      updateCurrentBet()
      return
    }

    let group = DispatchGroup()
    for control in targets {
      if let stack = control.oddsBetStack, control.betAmount > 0, control.oddsAmount > 0 {
        stack.endPayoutAnimation()
        stack.startBetCollection()
        group.enter()
        chipAnimator.animateChipsAwayFromOddsStack(from: control) { [weak stack] in
          stack?.endBetCollection()
          group.leave()
        }
        continue
      }

      guard control.betAmount > 0 else { continue }

      let betAmount = control.betAmount
      let basePosition = control.getBaseBetViewPosition(in: view)
      let chipView = SmallBetChip()
      chipView.amount = betAmount
      chipView.translatesAutoresizingMaskIntoConstraints = true
      let isIPad = UIDevice.current.userInterfaceIdiom == .pad
      let chipSize: CGFloat = isIPad ? 30 * 1.25 : 30
      chipView.frame = CGRect(x: 0, y: 0, width: chipSize, height: chipSize)
      chipView.isHidden = false
      view.addSubview(chipView)
      chipView.center = basePosition

      control.betAmount = 0
      if let makeEmControl = control as? MultiBetControl {
        makeEmControl.resetHitNumbers()
      } else if let makeEmAll = control as? MakeEmAllControl {
        makeEmAll.resetHitNumbers()
      }

      let randomDelay = Double.random(in: Timing.Shared.staggerRange)
      group.enter()
      UIView.animate(
        withDuration: Timing.Shared.flyDuration, delay: randomDelay, options: .curveEaseIn,
        animations: {
          chipView.center = destination
          chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        },
        completion: { _ in
          UIView.animate(withDuration: Timing.Shared.fadeDuration) {
            if shouldFadeOut {
              chipView.alpha = 0
            }
          } completion: { _ in
            chipView.removeFromSuperview()
            group.leave()
          }
        })
    }

    group.notify(queue: .main) { [weak self] in
      self?.updateCurrentBet()
    }
  }

  // Structure to track winning bets
  struct WinningBet {
    let control: AnyObject  // Changed to AnyObject to support both PlainControl and ComeBetControl
    let winAmount: Int
    let odds: Double
    let isBonus: Bool
    let description: String?
  }

  /// Variant-aware max free odds (standard 3-4-5×; crapless includes 2,3,11,12 per `CrapsVariantRules`).
  func maxOddsMultiplier(for pointNumber: Int) -> Int {
    rules.maxOddsMultiplier(for: pointNumber)
  }

  // handleRollResult is defined in CrapsGameplayViewController+RollPipeline.swift

  private func animateWinnings(for control: PlainControl, odds: Double) {
    guard control.betAmount > 0 else {
      return
    }

    let winAmount = Int(Double(control.betAmount) * odds)

    // Use ChipAnimationHelper for consistent animations with control-specific offsets
    // This creates ONE SmallBetChip for the pass line bet winnings (1:1 payout)
    // Use separate offset for original bet winnings
    let offset = control.originalBetWinningsOffset
    chipAnimator.animateWinningsWithOffset(
      for: control,
      winAmount: winAmount,
      offset: offset
    ) { [weak self] amount in
      self?.balance += amount
      self?.updateCurrentBet()
      self?.updateRollingState()
    }
  }

  func handlePassLineWin() {
    guard passLineControl.betAmount > 0 else { return }

    // If bets are OFF, don't process the win
    guard betsAreOn else {
      return
    }

    // Process win through manager
    let result = passLineManager.processPassLineWin(betAmount: passLineControl.betAmount)

    // 1. Animate pass line winnings from house (1:1 payout)
    // This creates ONE SmallBetChip for the pass line bet winnings
    Timing.after(Timing.BottomControls.lineWinDelay) { [weak self] in
      guard let self else { return }
      self.animateWinnings(for: self.passLineControl, odds: result.oddsMultiplier)
    }
    // 2. Animate original bet being collected (after slight delay)
    Timing.after(Timing.BottomControls.lineBetCollectionDelay) { [weak self] in
      guard let self else { return }
      self.animateBetCollection(for: self.passLineControl)
    }
  }

  func handlePassLineOddsWin(pointNumber: Int?, capturedBetAmount: Int) {
    guard capturedBetAmount > 0 else {
      return
    }
    guard let pointNumber = pointNumber else {
      return
    }

    // If bets are OFF, don't process the win
    guard betsAreOn else {
      return
    }

    // Process win through manager
    let result = passLineManager.processPassLineOddsWin(
      betAmount: capturedBetAmount, point: pointNumber)
    // Calculate profit only (winnings chip shows profit, original bet is returned separately)
    let profit = Int(Double(capturedBetAmount) * result.oddsMultiplier)

    // Ensure odds amount is set before animations start (so we can get position)
    // Make sure payout animation flag is still set (it should be from before processRoll)
    if !passLineControl.oddsBetStack!.isAnimatingPayout {
      passLineControl.oddsBetStack!.startPayoutAnimation()
    }
    passLineControl.oddsAmount = capturedBetAmount

    // Animate odds winnings (odds bet should be cleared, pass line bet stays)
    // Delay slightly after pass line winnings to ensure both chips are clearly visible as separate
    // NOTE: winAmount parameter is for the winnings chip display (profit only)
    // The total payout (result.winnings) is added to balance in the animation callback
    Timing.after(Timing.BottomControls.oddsWinDelay) { [weak self] in
      guard let self = self else { return }
      self.animateOddsWinnings(
        for: self.passLineControl, oddsBetAmount: capturedBetAmount, winAmount: profit,
        totalPayout: result.winnings, odds: result.oddsMultiplier)
    }
  }

  private func handlePassLineOddsLoss() {
    guard passLineControl.oddsAmount > 0 else { return }

    // If bets are OFF, don't process the loss
    guard betsAreOn else {
      return
    }

    // Process loss through manager
    let betAmount = passLineControl.oddsAmount
    passLineManager.processPassLineOddsLoss(betAmount: betAmount)

    // Disable rolling immediately to prevent re-rolling before bet is cleared
    flipDiceContainer.disableRolling()

    // Use animateChipsAway pattern - keep stack layout as-is, just animate chip away
    guard let oddsStack = passLineControl.oddsBetStack else { return }
    let oddsPosition = oddsStack.getOddsPosition(in: view)

    // DON'T hide the original odds chip yet - wait until animation starts
    // This ensures the chip remains visible during animation

    // Create animation chip at odds position
    let chipView = SmallBetChip()
    chipView.amount = betAmount
    chipView.translatesAutoresizingMaskIntoConstraints = true
    chipView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
    chipView.isHidden = false
    view.addSubview(chipView)
    chipView.center = oddsPosition

    // Animate chip away after the normal delay (like other chip away animations)
    // Clear the odds amount AFTER animation starts (not before)
    Timing.after(Timing.BottomControls.oddsLossDelay) { [weak self] in
      guard let self else { return }
      let randomDelay = Double.random(in: Timing.Shared.staggerRange)

      // Hide and clear the odds chip AFTER animation starts
      oddsStack.oddsChip.alpha = 0
      // Use removeOddsSilently to avoid triggering layout changes
      oddsStack.removeOddsSilently(betAmount)
      self.updateCurrentBet()

      UIView.animate(
        withDuration: Timing.Shared.flyDuration, delay: randomDelay, options: .curveEaseIn,
        animations: {
          chipView.center = CGPoint(x: self.view.bounds.width / 2, y: 0)
          chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        },
        completion: { [weak self] _ in
          guard let self else { return }
          UIView.animate(withDuration: Timing.Shared.fadeDuration) {
            chipView.alpha = 0
          } completion: { _ in
            chipView.removeFromSuperview()
            // Restore alpha for future bets
            oddsStack.oddsChip.alpha = 1
            // Reset title alignment to center after loss
            self.passLineControl.titleAlignment = .centered
          }
        })
    }
  }

  func handlePassLineLoss() {
    guard passLineControl.betAmount > 0 else { return }

    // If bets are OFF, don't process the loss
    guard betsAreOn else {
      return
    }

    // Process loss through manager
    let betAmount = passLineControl.betAmount
    passLineManager.processPassLineLoss(betAmount: betAmount)

    // Disable rolling immediately to prevent re-rolling before bet is cleared
    flipDiceContainer.disableRolling()

    // Main line bet chip (not free-odds position when odds are on the board)
    let betPosition = passLineControl.getBaseBetViewPosition(in: view)

    // DON'T hide or clear the bet yet - wait until animation starts
    // This ensures the chip remains visible during animation

    // Create the animation chip immediately (before clearing bet amount)
    // This ensures seamless transition - chip appears exactly where betView was
    let chipView = SmallBetChip()
    chipView.amount = betAmount
    chipView.translatesAutoresizingMaskIntoConstraints = true

    // Match SmallBetChip's scaling behavior - 25% larger on iPad
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    let chipSize: CGFloat = isIPad ? 30 * 1.25 : 30
    chipView.frame = CGRect(x: 0, y: 0, width: chipSize, height: chipSize)
    chipView.isHidden = false
    view.addSubview(chipView)
    chipView.center = betPosition

    // Animate chip away after the normal delay
    Timing.after(Timing.BottomControls.lineLossDelay) { [weak self] in
      guard let self else { return }
      let randomDelay = Double.random(in: Timing.Shared.staggerRange)

      // Hide and clear bet AFTER animation starts (so chip remains visible until animation takes over)
      Timing.after(randomDelay) { [weak self] in
        self?.passLineControl.betView.alpha = 0
        self?.passLineControl.betAmount = 0
      }

      UIView.animate(
        withDuration: Timing.Shared.flyDuration, delay: randomDelay, options: .curveEaseIn,
        animations: {
          chipView.center = CGPoint(x: self.view.bounds.width / 2, y: 0)
          chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        },
        completion: { [weak self] _ in
          guard let self else { return }
          UIView.animate(withDuration: Timing.Shared.fadeDuration) {
            chipView.alpha = 0
          } completion: { [weak self] _ in
            guard let self else { return }
            chipView.removeFromSuperview()
            // Restore betView alpha for future bets
            self.passLineControl.betView.alpha = 1
            // Only reset title alignment if there's no odds bet (odds loss will handle it)
            if self.passLineControl.oddsAmount == 0 {
              self.passLineControl.titleAlignment = .centered
            }
            self.updateCurrentBet()
            self.updateRollingState()
          }
        })
    }
  }

  func handleDontPassBet(
    total: Int, event: GameEvent, wasInPointPhase: Bool, currentPoint: Int?,
    capturedOddsBetAmount: Int
  ) -> (message: String?, winningBet: WinningBet?, didLose: Bool) {
    guard let dp = dontPassControl, dp.betAmount > 0 else { return (nil, nil, false) }

    let betAmount = dp.betAmount

    // Come-out roll logic
    if !wasInPointPhase {
      let result = specialBetsManager.evaluateDontPassComeOutRoll(
        total: total, betAmount: betAmount)

      if result.isWin {
        // If bets are OFF, don't process the win
        guard betsAreOn else {
          return (nil, nil, false)
        }

        // Don't Pass wins on 2 or 3 (pays 1:1)
        let winAmount = result.winAmount

        // 1. Animate winnings from house
        Timing.after(Timing.BottomControls.lineWinDelay) { [weak self] in
          guard let self = self else { return }
          self.animateWinnings(for: dp, odds: result.oddsMultiplier)
        }

        // 2. Animate original bet being collected (after slight delay)
        Timing.after(Timing.BottomControls.lineBetCollectionDelay) { [weak self] in
          guard let self = self else { return }
          self.animateBetCollection(for: dp)
        }

        let message = "Don't Pass wins on \(total)!"
        let winningBet = WinningBet(
          control: dp, winAmount: winAmount, odds: result.oddsMultiplier, isBonus: false,
          description: nil)
        return (message, winningBet, false)

      } else if result.isPush {
        // Push on 12 - return bet to player
        let message = "Push! 12 is a tie for Don't Pass."
        return (message, nil, false)

      } else if total == 7 || total == 11 {
        // Don't Pass loses on 7 or 11 during come-out
        handleDontPassLoss(betAmount: betAmount, oddsBetAmount: 0)
        return (nil, nil, true)  // Return true to indicate loss
      }
      // Point established (4, 5, 6, 8, 9, 10) - no action yet
      return (nil, nil, false)
    }

    // Point phase logic
    if let point = currentPoint {
      let result = specialBetsManager.evaluateDontPassPointPhase(
        total: total, point: point, betAmount: betAmount)

      if result.isWin {
        // If bets are OFF, don't process the win
        guard betsAreOn else {
          return (nil, nil, false)
        }

        // Don't Pass wins on 7 before point (pays 1:1)
        let winAmount = result.winAmount

        // 1. Animate winnings from house
        Timing.after(Timing.BottomControls.lineWinDelay) { [weak self] in
          guard let self = self else { return }
          self.animateWinnings(for: dp, odds: result.oddsMultiplier)
        }

        // 2. Animate original bet being collected (after slight delay)
        Timing.after(Timing.BottomControls.lineBetCollectionDelay) { [weak self] in
          guard let self = self else { return }
          self.animateBetCollection(for: dp)
        }

        // 3. Handle odds winnings if any (Don't Pass odds pay at lay odds)
        if capturedOddsBetAmount > 0 {
          handleDontPassOddsWin(pointNumber: point, capturedBetAmount: capturedOddsBetAmount)
        } else {
          // No odds, end the payout animation flag
          dp.oddsBetStack?.endPayoutAnimation()
        }

        let message = "Don't Pass wins on 7!"
        let winningBet = WinningBet(
          control: dp, winAmount: winAmount, odds: result.oddsMultiplier, isBonus: false,
          description: nil)
        return (message, winningBet, false)

      } else if total == point {
        // Don't Pass loses when point is made
        handleDontPassLoss(betAmount: betAmount, oddsBetAmount: capturedOddsBetAmount)
        return (nil, nil, true)  // Return true to indicate loss
      }
    }

    // No action
    return (nil, nil, false)
  }

  private func handleDontPassLoss(betAmount: Int, oddsBetAmount: Int) {
    guard betAmount > 0, let dp = dontPassControl else { return }
    guard betsAreOn else { return }

    flipDiceContainer.disableRolling()

    dp.oddsBetStack?.endPayoutAnimation()

    if oddsBetAmount > 0 {
      dp.oddsBetStack?.startBetCollection()

      Timing.after(Timing.BottomControls.oddsLossDelay) { [weak self] in
        guard let self else { return }
        self.chipAnimator.animateChipsAwayFromOddsStack(from: dp) {
          dp.oddsBetStack?.endBetCollection()
          dp.titleAlignment = .centered
          self.updateCurrentBet()
          self.updateRollingState()
        }
      }
    } else {
      chipAnimator.animateChipsAway(from: dp) { [weak self] in
        dp.titleAlignment = .centered
        self?.updateCurrentBet()
      }
    }
  }

  private func handleDontPassOddsWin(pointNumber: Int, capturedBetAmount: Int) {
    guard let dp = dontPassControl else { return }
    guard capturedBetAmount > 0 else {
      dp.oddsBetStack?.endPayoutAnimation()
      return
    }

    guard betsAreOn else {
      dp.oddsBetStack?.endPayoutAnimation()
      return
    }

    let result = passLineManager.calculateDontPassOddsPayout(
      betAmount: capturedBetAmount, point: pointNumber)
    let profit = Int(Double(capturedBetAmount) * result.oddsMultiplier)

    if !(dp.oddsBetStack?.isAnimatingPayout ?? false) {
      dp.oddsBetStack?.startPayoutAnimation()
    }
    dp.oddsAmount = capturedBetAmount

    // Animate odds winnings (odds bet should be cleared, don't pass bet stays)
    // Delay slightly after don't pass winnings to ensure both chips are clearly visible as separate
    // NOTE: winAmount parameter is for the winnings chip display (profit only)
    // The total payout (result.winnings) is added to balance in the animation callback
    Timing.after(Timing.BottomControls.oddsWinDelay) { [weak self] in
      guard let self = self else { return }
      self.animateDontPassOddsWinnings(
        oddsBetAmount: capturedBetAmount, winAmount: profit, totalPayout: result.winnings,
        odds: result.oddsMultiplier)
    }
  }

  private func animateDontPassOddsWinnings(
    oddsBetAmount: Int, winAmount: Int, totalPayout: Int, odds: Double
  ) {
    guard let containerView = view else {
      return
    }
    guard let dp = dontPassControl else { return }
    guard let oddsStack = dp.oddsBetStack else {
      return
    }

    // CRITICAL: Get odds chip position BEFORE hiding it
    if !oddsStack.isAnimatingPayout {
      oddsStack.startPayoutAnimation()
    }

    let oddsPosition = oddsStack.getOddsPosition(in: containerView)
    // Use separate offset for odds bet winnings (Y only, no X offset)
    let offset = dp.oddsBetWinningsOffset

    // Use animateOddsBetWinningsWithOffset pattern - winnings come down, then both animate together
    // winAmount is profit only (for display), totalPayout is total (for balance)
    chipAnimator.animateOddsBetWinningsWithOffset(
      for: dp,
      oddsBetAmount: oddsBetAmount,
      winAmount: winAmount,  // Profit only for display
      offset: offset
    ) { [weak self] _ in
      guard let self = self else {
        oddsStack.endPayoutAnimation()
        return
      }
      // Add the total odds payout to balance (bet + profit)
      // winAmount parameter is profit only for display, but we need to add totalPayout to balance
      self.balance += totalPayout  // Add total payout (bet + profit)

      // End the payout animation flag AFTER balance is updated
      oddsStack.endPayoutAnimation()

      self.updateCurrentBet()
      self.updateRollingState()
    }
  }

  func handleSevenOut() {
    // If bets are OFF, don't process losses for place bets or Make Em bets
    guard betsAreOn else { return }

    // Collect all point controls with bets
    var controlsWithBets: [PlainControl] = []
    for pointNumber in pointStack.pointNumbers {
      if let pointControl = pointStack.getPointControl(for: pointNumber),
        pointControl.betAmount > 0
      {
        controlsWithBets.append(pointControl)
      }
    }

    // Collect all Make Em controls with bets
    if let makeEmStack = makeEmView?.subviews.first(where: { $0 is UIStackView }) as? UIStackView {
      for arrangedSubview in makeEmStack.arrangedSubviews {
        if let plain = arrangedSubview as? PlainControl, plain.betAmount > 0,
          plain is MultiBetControl || plain is MakeEmAllControl
        {
          controlsWithBets.append(plain)
        }
      }
    }

    guard !controlsWithBets.isEmpty else { return }

    // Animate all place bets and Make Em bets flying away (losing)
    Timing.after(Timing.BonusBets.sevenOutSweepDelay) { [weak self] in
      guard let self else { return }
      animateChipsAway(
        from: controlsWithBets,
        to: CGPoint(x: view.bounds.width / 2, y: 0),
        shouldFadeOut: true
      )
    }
  }

  /// Natural 7 on the come-out wins pass line but loses Make Em bets (same wipe as seven-out).
  func handleMakeEmLossOnComeOutSeven() {
    guard betsAreOn else { return }
    guard let makeEmStack = makeEmView?.subviews.first(where: { $0 is UIStackView }) as? UIStackView
    else { return }

    var makeEmWithBets: [PlainControl] = []
    for arrangedSubview in makeEmStack.arrangedSubviews {
      if let plain = arrangedSubview as? PlainControl, plain.betAmount > 0,
        plain is MultiBetControl || plain is MakeEmAllControl
      {
        makeEmWithBets.append(plain)
      }
    }

    guard !makeEmWithBets.isEmpty else { return }

    Timing.after(Timing.BonusBets.sevenOutSweepDelay) { [weak self] in
      guard let self else { return }
      animateChipsAway(
        from: makeEmWithBets,
        to: CGPoint(x: view.bounds.width / 2, y: 0),
        shouldFadeOut: true
      )
    }
  }

  func handleHardwayLoss() {
    // If bets are OFF, don't process hardway losses
    guard betsAreOn else { return }

    // Collect all hardway controls with bets
    // Note: hardwayView.betStack has 2 columns (UIStackViews), each containing hardway controls
    guard let hardwayView = hardwayView else { return }

    var hardwayControlsWithBets: [PlainControl] = []
    for arrangedSubview in hardwayView.betStack.arrangedSubviews {
      if let columnStack = arrangedSubview as? UIStackView {
        for columnSubview in columnStack.arrangedSubviews {
          if let hardwayControl = columnSubview as? SmallControl,
            hardwayControl.betAmount > 0
          {
            hardwayControlsWithBets.append(hardwayControl)
          }
        }
      }
    }

    guard !hardwayControlsWithBets.isEmpty else { return }

    // Animate all hardway bets flying away (losing on 7)
    Timing.after(Timing.BonusBets.lossDelay) { [weak self] in
      guard let self else { return }
      self.animateChipsAway(
        from: hardwayControlsWithBets,
        to: CGPoint(x: view.bounds.width / 2, y: 0),
        shouldFadeOut: true
      )
    }
  }

  func handleHardwayBets(die1: Int, die2: Int, total: Int) -> ([String], [WinningBet]) {
    var winMessages: [String] = []
    var winningBets: [WinningBet] = []
    var losingControls: [SmallControl] = []

    guard let hardwayView = hardwayView else { return (winMessages, winningBets) }

    // Check each hardway bet
    // Note: hardwayView.betStack has 2 columns (UIStackViews), each containing hardway controls
    for arrangedSubview in hardwayView.betStack.arrangedSubviews {
      guard let columnStack = arrangedSubview as? UIStackView else { continue }
      for columnSubview in columnStack.arrangedSubviews {
        guard let hardwayControl = columnSubview as? SmallControl,
          hardwayControl.betAmount > 0
        else { continue }

        // Evaluate hardway bet using manager
        let result = specialBetsManager.evaluateHardwayBet(
          die1: die1,
          die2: die2,
          hardwayDieValue: hardwayControl.dieValue1,
          betAmount: hardwayControl.betAmount,
          oddsString: hardwayControl.odds
        )

        if result.isWin {
          // If bets are OFF, don't process hardway wins
          guard betsAreOn else { continue }

          // Hardway wins!
          // Collect bet for winnings container
          winningBets.append(
            WinningBet(
              control: hardwayControl,
              winAmount: result.winAmount!,
              odds: result.oddsMultiplier!,
              isBonus: true,
              description: "Hard \(result.total)"
            ))

          Timing.after(Timing.BonusBets.winDelay) { [weak self] in
            guard let self else { return }
            self.animateWinningsAndBetTogether(for: hardwayControl, odds: result.oddsMultiplier!)
          }

          winMessages.append("Hard \(result.total) wins! You won $\(result.winAmount!)!")

        } else if result.isSoftWayLoss {
          // Same total but soft way - hardway loses
          losingControls.append(hardwayControl)
        }
      }
    }

    // Animate losing hardway bets (soft way)
    // Only process losses if bets are ON
    if !losingControls.isEmpty && betsAreOn {
      Timing.after(Timing.BonusBets.lossDelay) { [weak self] in
        guard let self else { return }
        self.animateChipsAway(
          from: losingControls,
          to: CGPoint(x: view.bounds.width / 2, y: 0),
          shouldFadeOut: true
        )
      }
    }

    // Return win messages and winning bets
    return (winMessages, winningBets)
  }

  func handleHornBets(die1: Int, die2: Int, total: Int) -> ([String], [WinningBet]) {
    var winMessages: [String] = []
    var winningBets: [WinningBet] = []

    guard let hornView = hornView else { return (winMessages, winningBets) }

    for arrangedSubview in hornView.betStack.arrangedSubviews {
      guard let columnStack = arrangedSubview as? UIStackView else { continue }
      for columnSubview in columnStack.arrangedSubviews {
        if let anyHorn = columnSubview as? AnyHornControl, anyHorn.betAmount > 0 {
          guard
            let result = specialBetsManager.evaluateAnyHornBet(
              die1: die1, die2: die2, betAmount: anyHorn.betAmount
            )
          else { continue }
          guard betsAreOn else { continue }
          winningBets.append(
            WinningBet(
              control: anyHorn,
              winAmount: result.winAmount!,
              odds: result.oddsMultiplier!,
              isBonus: true,
              description: result.hornName
            ))
          Timing.after(Timing.BonusBets.winDelay) { [weak self] in
            guard let self else { return }
            self.animateWinningsAndBetTogether(for: anyHorn, odds: result.oddsMultiplier!)
          }
          winMessages.append("\(result.hornName) wins! You won $\(result.winAmount!)!")
          continue
        }

        guard let hornControl = columnSubview as? SmallControl,
          hornControl.betAmount > 0
        else { continue }

        let result = specialBetsManager.evaluateHornBet(
          die1: die1,
          die2: die2,
          hornDieValue1: hornControl.dieValue1,
          hornDieValue2: hornControl.dieValue2,
          betAmount: hornControl.betAmount,
          oddsString: hornControl.odds
        )

        if result.isWin {
          guard betsAreOn else { continue }

          winningBets.append(
            WinningBet(
              control: hornControl,
              winAmount: result.winAmount!,
              odds: result.oddsMultiplier!,
              isBonus: true,
              description: result.hornName
            ))

          Timing.after(Timing.BonusBets.winDelay) { [weak self] in
            guard let self else { return }
            self.animateWinningsAndBetTogether(for: hornControl, odds: result.oddsMultiplier!)
          }

          winMessages.append("\(result.hornName) wins! You won $\(result.winAmount!)!")
        }
      }
    }

    // Return win messages and winning bets
    return (winMessages, winningBets)
  }

  func handleMakeEmBets(total: Int) -> ([String], [WinningBet]) {
    var winMessages: [String] = []
    var winningBets: [WinningBet] = []

    guard let makeEmView = makeEmView else { return (winMessages, winningBets) }

    // Find the Make Em stack within makeEmView
    guard let makeEmStack = makeEmView.subviews.first(where: { $0 is UIStackView }) as? UIStackView
    else {
      return (winMessages, winningBets)
    }

    for arrangedSubview in makeEmStack.arrangedSubviews {
      if let makeEmAll = arrangedSubview as? MakeEmAllControl, makeEmAll.betAmount > 0 {
        let betName = "Make Em All"
        let result = specialBetsManager.evaluateMakeEmBet(
          total: total,
          betName: betName,
          targetNumbers: makeEmAll.numbers,
          hitNumbers: makeEmAll.hitNumbers,
          betAmount: makeEmAll.betAmount,
          oddsString: makeEmAll.odds
        )
        if result.isNewNumber {
          makeEmAll.markNumberAsHit(total)
        }
        if result.isWin {
          guard betsAreOn else { continue }
          winningBets.append(
            WinningBet(
              control: makeEmAll,
              winAmount: result.winAmount!,
              odds: result.oddsMultiplier!,
              isBonus: true,
              description: betName
            ))
          Timing.after(Timing.BonusBets.winDelay) { [weak self] in
            guard let self else { return }
            self.animateWinningsAndBetTogether(for: makeEmAll, odds: result.oddsMultiplier!)
          }
          Timing.after(Timing.BonusBets.makeEmResetDelay) { [weak makeEmAll] in
            makeEmAll?.resetHitNumbers()
          }
          winMessages.append("\(betName) wins! You won $\(result.winAmount!)!")
        }
        continue
      }

      guard let makeEmControl = arrangedSubview as? MultiBetControl,
        makeEmControl.betAmount > 0
      else { continue }

      let isMakeEmSmall = makeEmControl.numbers == [2, 3, 4, 5, 6]
      let betName = isMakeEmSmall ? "Small" : "Tall"

      let result = specialBetsManager.evaluateMakeEmBet(
        total: total,
        betName: betName,
        targetNumbers: makeEmControl.numbers,
        hitNumbers: makeEmControl.hitNumbers,
        betAmount: makeEmControl.betAmount,
        oddsString: makeEmControl.odds
      )

      if result.isNewNumber {
        makeEmControl.markNumberAsHit(total)
      }

      if result.isWin {
        guard betsAreOn else { continue }

        winningBets.append(
          WinningBet(
            control: makeEmControl,
            winAmount: result.winAmount!,
            odds: result.oddsMultiplier!,
            isBonus: true,
            description: betName
          ))

        Timing.after(Timing.BonusBets.winDelay) { [weak self] in
          guard let self else { return }
          self.animateWinningsAndBetTogether(for: makeEmControl, odds: result.oddsMultiplier!)
        }

        Timing.after(Timing.BonusBets.makeEmResetDelay) { [weak makeEmControl] in
          makeEmControl?.resetHitNumbers()
        }

        winMessages.append("\(betName) wins! You won $\(result.winAmount!)!")
      }
    }

    return (winMessages, winningBets)
  }

  /// Bet chips live under `TriZoneBetControl`, not inside each `ZoneView` — convert from the tri-zone.
  private func cAndEChipPosition(for zone: TriZoneBetControl.Zone) -> CGPoint {
    guard let tri = cAndETriZoneControl else { return .zero }
    tri.layoutIfNeeded()
    let chip = tri.zoneViews[zone.rawValue].betChip
    chip.layoutIfNeeded()
    return tri.convert(chip.center, to: view)
  }

  private func animateCAndEZoneLoss(zone: TriZoneBetControl.Zone, betAmount: Int) {
    guard betAmount > 0, let tri = cAndETriZoneControl else { return }
    let chip = tri.zoneViews[zone.rawValue].betChip
    tri.layoutIfNeeded()
    chip.layoutIfNeeded()

    let betPosition = cAndEChipPosition(for: zone)
    let side = max(chip.bounds.width, chip.bounds.height)
    let chipSide: CGFloat =
      side > 1
      ? side
      : (UIDevice.current.userInterfaceIdiom == .pad ? 30 * 1.25 : 30)

    let chipView = SmallBetChip()
    chipView.amount = betAmount
    chipView.translatesAutoresizingMaskIntoConstraints = true
    chipView.frame = CGRect(x: 0, y: 0, width: chipSide, height: chipSide)
    chipView.layer.cornerRadius = chipSide / 2
    view.addSubview(chipView)
    chipView.center = betPosition

    chip.alpha = 0
    tri.removeBetFromZoneSilently(betAmount, zone: zone)
    updateCurrentBet()

    let destination = CGPoint(x: view.bounds.width / 2, y: 0)
    let randomDelay = Double.random(in: Timing.BonusBets.cAndEStaggerRange)
    HapticsHelper.lightHaptic()
    UIView.animate(
      withDuration: Timing.BonusBets.cAndEFlyDuration, delay: randomDelay, options: [.curveEaseIn],
      animations: {
        chipView.center = destination
        chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
      },
      completion: { [weak self] _ in
        UIView.animate(withDuration: Timing.BonusBets.cAndEFadeDuration) {
          chipView.alpha = 0
        } completion: { _ in
          chipView.removeFromSuperview()
          chip.alpha = 1
          self?.updateRollingState()
        }
      })
  }

  func handleCAndEBets(total: Int) -> ([String], [WinningBet]) {
    var winMessages: [String] = []
    var winningBets: [WinningBet] = []
    guard let tri = cAndETriZoneControl else { return (winMessages, winningBets) }

    for zone in TriZoneBetControl.Zone.allCases {
      let bet = tri.betAmount(for: zone)
      guard bet > 0 else { continue }

      let result: CrapsSpecialBetsManager.CAndEZoneEvalResult
      switch zone {
      case .top:
        result = specialBetsManager.evaluateCAndECrapsZone(total: total, betAmount: bet)
      case .middle:
        result = specialBetsManager.evaluateCAndEMiddleSplitZone(total: total, betAmount: bet)
      case .bottom:
        result = specialBetsManager.evaluateCAndEElevenZone(total: total, betAmount: bet)
      }

      if result.isWin {
        guard betsAreOn else { continue }
        let oddsForDisplay = bet > 0 ? Double(result.profitDisplayAmount) / Double(bet) : 0
        winningBets.append(
          WinningBet(
            control: tri,
            winAmount: result.profitDisplayAmount,
            odds: oddsForDisplay,
            isBonus: true,
            description: result.description
          ))
        Timing.after(Timing.BonusBets.winDelay) { [weak self] in
          guard let self else { return }
          tri.layoutIfNeeded()
          let betPosition = self.cAndEChipPosition(for: zone)
          let chip = tri.zoneViews[zone.rawValue].betChip
          self.chipAnimator.animateBonusBetWinningsAtPosition(
            betPosition: betPosition,
            betAmount: bet,
            winAmount: result.profitDisplayAmount,
            offset: CGPoint(x: -30, y: 0),
            prepareBetDuplicate: { [weak tri] in
              chip.alpha = 0
              tri?.removeBetFromZoneSilently(bet, zone: zone)
              self.updateCurrentBet()
            },
            restoreSourceChip: { [weak self] in
              chip.alpha = 1
              self?.updateCurrentBet()
              self?.updateRollingState()
            },
            onBalanceUpdate: { [weak self] amt in
              self?.balance += amt
            }
          )
        }
        winMessages.append("\(result.description) wins! You collected $\(result.totalReturn).")
      } else {
        guard betsAreOn else { continue }
        let lostAmount = bet
        Timing.after(Timing.BonusBets.cAndELossDelay) { [weak self] in
          guard let self else { return }
          if tri.betAmount(for: zone) == lostAmount {
            self.animateCAndEZoneLoss(zone: zone, betAmount: lostAmount)
          }
        }
      }
    }

    return (winMessages, winningBets)
  }

  func clearOneTimeBets(excludingWinningControls: [PlainControl] = []) {
    // If bets are OFF, don't clear losing one-time bets
    guard betsAreOn else { return }

    // Get all controls and clear any one-time bets that didn't win
    let allControls = getAllBettingControls()

    for control in allControls {
      // Skip if perpetual bet or no bet placed
      guard !control.isPerpetualBet && control.betAmount > 0 else { continue }

      // Skip if this control is a winning bet (will be handled by its own animation)
      guard !excludingWinningControls.contains(where: { $0 === control }) else { continue }

      // Animate losing one-time bet
      Timing.after(Timing.BonusBets.oneTimeBetLossDelay) { [weak self] in
        guard let self else { return }

        // Only clear if bet is still there (wasn't already won/cleared)
        if control.betAmount > 0 {
          self.animateChipsAway(
            from: [control],
            to: CGPoint(x: view.bounds.width / 2, y: 0),
            shouldFadeOut: true
          )
        }
      }
    }
  }

  // MARK: - Come Bet Handling

  func handleComeBets(total: Int, event: GameEvent, wasInPointPhase: Bool) -> (
    [String], [WinningBet]
  ) {
    var winMessages: [String] = []
    var winningBets: [WinningBet] = []

    // Track if an existing come bet won (used to delay pending come bet handling)
    var existingComeBetWon = false

    // --- 1. Handle EXISTING come bets on point numbers ---
    // These should pay regardless of phase (e.g., if point is made and then rolled again)
    // Must process before pending come bet so that if a number is hit,
    // the existing come bet on that number pays out before a new one arrives

    if total == 7 {
      // Seven out: All existing come bets on points LOSE on any 7 (unless bets are OFF)
      if betsAreOn {
        let comeBetPointControls = pointStack.getPointControlsWithComeBets()
        for pointControl in comeBetPointControls {
          let comeBetAmount = pointControl.comeBetAmount
          let comeBetOdds = pointControl.comeBetOddsAmount
          let totalLoss = comeBetAmount + comeBetOdds
          if totalLoss > 0 {
            // Animate come bet chips flying away (to house), then clear
            animateComeBetLoss(
              pointControl: pointControl, comeBetAmount: comeBetAmount, comeBetOdds: comeBetOdds)
          }
        }
      }
    } else {
      // Check if any existing come bet's number was hit
      // Pay regardless of phase - come bets on numbers pay whenever that number is rolled
      if let hitPointControl = pointStack.getPointControl(for: total), hitPointControl.hasComeBet {
        let comeBetAmount = hitPointControl.comeBetAmount
        let comeBetOdds = hitPointControl.comeBetOddsAmount

        // Come bet wins at 1:1
        let comeBetWinnings = comeBetAmount

        // Come bet odds win at true odds (same as pass line odds)
        var oddsWinnings = 0
        if comeBetOdds > 0 {
          let oddsMultiplier = hitPointControl.oddsMultiplier
          oddsWinnings = Int(Double(comeBetOdds) * oddsMultiplier)
        }

        let totalWinnings = comeBetWinnings + oddsWinnings

        winMessages.append("Come bet on \(total) wins!")

        // Mark that an existing come bet won (so we can delay pending come bet handling)
        existingComeBetWon = true

        // Add to winning bets so winningsContainer displays
        winningBets.append(
          WinningBet(
            control: hitPointControl,
            winAmount: totalWinnings,
            odds: oddsWinnings > 0 ? hitPointControl.oddsMultiplier : 1.0,
            isBonus: false,
            description: nil
          ))

        // Animate come bet win: chips fly to balance with winnings
        animateComeBetWin(
          pointControl: hitPointControl,
          comeBetAmount: comeBetAmount,
          comeBetOdds: comeBetOdds,
          comeBetWinnings: comeBetWinnings,
          oddsWinnings: oddsWinnings
        )
      }
    }

    // --- 2. Handle PENDING come bet (on come line) ---
    // Only process pending come bets if we were in point phase when the roll happened
    guard wasInPointPhase else { return (winMessages, winningBets) }

    let pendingComeBet = comeBetControl?.betAmount ?? 0
    if pendingComeBet > 0 {
      // If an existing come bet won on this number (4-10), delay pending come bet handling
      // to allow the win animation to complete first (~1.6 seconds total animation time)
      // For 7/11/2/3/12, handle immediately (no conflict with existing come bets)
      let needsDelay = existingComeBetWon && rules.pointNumbers.contains(total)
      let delay: TimeInterval = needsDelay ? Timing.PointStack.comePendingMoveDelay : 0.0

      if delay > 0 {
        // Delayed handling for number rolls when existing come bet won
        Timing.after(delay) { [weak self] in
          guard let self = self else { return }

          // Re-check pending bet amount (might have changed during delay)
          let currentPendingBet = self.comeBetControl?.betAmount ?? 0
          guard currentPendingBet > 0 else { return }

          // Come bet moves to the rolled number
          // The win animation should have cleared the existing bet by now
          self.animateComeBetToPoint(amount: currentPendingBet, pointNumber: total)
        }
      } else {
        // Immediate handling for 7/11/2/3/12 or when no existing come bet won
        switch total {
        case 7, 11:
          // Come bet wins on natural (7 or 11)
          // Note: 7 also triggers sevenOut for pass line, but come bet still wins
          let winAmount = pendingComeBet  // 1:1 payout
          winMessages.append("Come bet wins on \(total)!")

          // Add to winning bets so winningsContainer displays
          // Use comeBetControl as the control since this is a pending come bet
          if let comeBetControl = comeBetControl {
            winningBets.append(
              WinningBet(
                control: comeBetControl,
                winAmount: winAmount,
                odds: 1.0,
                isBonus: false,
                description: nil
              ))
          }

          // Animate: winnings fly down from house to bet, then both fly to balance
          animatePendingComeBetWin(betAmount: pendingComeBet, winAmount: winAmount)

        case 2, 3, 12:
          // Come bet loses (craps)
          // Balance was already deducted when bet was placed

          // Animate: chip flies away to house
          animatePendingComeBetLoss(betAmount: pendingComeBet)

        case 4, 5, 6, 8, 9, 10:
          // Come bet moves to the rolled number (no existing come bet won, so no delay needed)
          animateComeBetToPoint(amount: pendingComeBet, pointNumber: total)

        default:
          break
        }
      }
    }

    return (winMessages, winningBets)
  }

  /// Animate a come bet chip from the ComeBetControl to the target PointControl
  private func animateComeBetToPoint(amount: Int, pointNumber: Int) {
    guard let targetPointControl = pointStack.getPointControl(for: pointNumber) else {
      // Fallback: just place the bet without animation
      placeComeBetOnPoint(amount: amount, pointNumber: pointNumber)
      return
    }

    // Get source position (main come bet chip, not free-odds)
    let sourcePosition = comeBetControl.getBaseBetViewPosition(in: view)

    // Place the bet first so we can get the actual destination position
    // This ensures the animation goes to the exact spot where the chip will be
    placeComeBetOnPoint(amount: amount, pointNumber: pointNumber)

    // Force layout to ensure the come bet stack is positioned correctly
    view.layoutIfNeeded()

    // Verify the bet was actually placed (might have been cleared if timing was off)
    if !targetPointControl.hasComeBet {
      // Bet wasn't placed - try again (shouldn't happen, but handle gracefully)
      placeComeBetOnPoint(amount: amount, pointNumber: pointNumber)
      view.layoutIfNeeded()
      // If still no bet, just place it without animation
      if !targetPointControl.hasComeBet {
        comeBetControl.betAmount = 0
        return
      }
    }

    // Get the actual destination position from the newly created come bet stack
    let destinationPosition = targetPointControl.getComeBetPosition(in: view)

    // Ensure we have a valid destination (not .zero)
    guard destinationPosition != .zero else {
      // Invalid position - just place without animation
      comeBetControl.betAmount = 0
      return
    }

    // Hide the come bet chip on the PointControl during animation
    targetPointControl.hideComeBetChip()

    // Create animation chip using the same helper pattern as ChipAnimationHelper
    let animationChip = SmallBetChip()
    animationChip.translatesAutoresizingMaskIntoConstraints = true
    animationChip.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
    animationChip.amount = amount
    animationChip.isHidden = false
    animationChip.alpha = 1.0
    view.addSubview(animationChip)
    animationChip.center = sourcePosition

    // Hide the original bet chip on the ComeBetControl
    comeBetControl.betView.alpha = 0

    // Simple, smooth animation to destination
    let animator = UIViewPropertyAnimator(
      duration: Timing.PointStack.comeMoveDuration,
      controlPoint1: CGPoint(x: 0.25, y: 0.1),
      controlPoint2: CGPoint(x: 0.25, y: 1.0)
    ) {
      animationChip.center = destinationPosition
    }

    animator.addCompletion { [weak self] _ in
      guard let self = self else { return }

      animationChip.removeFromSuperview()

      // Clear the bet amount and restore alpha for future bets
      self.comeBetControl.betAmount = 0
      self.comeBetControl.betView.alpha = 1

      // Show the come bet chip on the PointControl (it was hidden during animation)
      // Only show if the bet still exists (it might have been cleared if timing was off)
      if targetPointControl.hasComeBet {
        targetPointControl.showComeBetChip()
      } else {
        // Bet was cleared - re-place it (this shouldn't happen, but handle gracefully)
        self.placeComeBetOnPoint(amount: amount, pointNumber: pointNumber)
      }
    }

    animator.startAnimation(afterDelay: Timing.PointStack.comeMoveDelay)
  }

  /// Place a come bet on a PointControl (called after animation completes)
  private func placeComeBetOnPoint(amount: Int, pointNumber: Int) {
    guard let targetPointControl = pointStack.getPointControl(for: pointNumber) else { return }

    targetPointControl.addComeBet(
      amount: amount,
      getSelectedChipValue: { [weak self] in
        return self?.selectedChipValue ?? 5
      },
      getBalance: { [weak self] in
        return self?.balance ?? 200
      }
    )
  }

  // MARK: - Come Bet Animations

  /// Animate come bet win on a point number: winnings fly down, then all chips fly to balance
  private func animateComeBetWin(
    pointControl: PointControl, comeBetAmount: Int, comeBetOdds: Int, comeBetWinnings: Int,
    oddsWinnings: Int
  ) {
    guard let balanceCenter = chipAnimator.getBalanceCenter(in: view) else {
      // Fallback: just add to balance directly
      balance += comeBetAmount + comeBetOdds + comeBetWinnings + oddsWinnings
      pointControl.clearComeBet()
      updateCurrentBet()
      return
    }

    let betPosition = pointControl.getComeBetPosition(in: view)
    let totalWinnings = comeBetWinnings + oddsWinnings

    // Winnings chip position (offset above the bet)
    let winningsTargetPosition = CGPoint(x: betPosition.x, y: betPosition.y - 30)

    // Step 1: Create winnings chip, animate from house to bet area
    let winningsChip = SmallBetChip()
    winningsChip.translatesAutoresizingMaskIntoConstraints = true
    winningsChip.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
    winningsChip.amount = totalWinnings
    winningsChip.isHidden = false
    view.addSubview(winningsChip)
    winningsChip.center = CGPoint(x: view.bounds.midX, y: 0)
    winningsChip.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)

    let animator1 = UIViewPropertyAnimator(
      duration: Timing.PointStack.comeWinApproachDuration,
      controlPoint1: CGPoint(x: 0.85, y: 0),
      controlPoint2: CGPoint(x: 0.15, y: 1)
    ) {
      winningsChip.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
      winningsChip.center = winningsTargetPosition
    }

    animator1.addCompletion { [weak self] _ in
      guard let self = self else { return }

      // Step 2: Brief pause, then animate all chips to balance
      Timing.after(Timing.PointStack.comeWinPause) { [weak self] in
        guard let self = self else { return }

        // Create bet chip overlay (hide original)
        let betChip = SmallBetChip()
        betChip.translatesAutoresizingMaskIntoConstraints = true
        betChip.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        betChip.amount = comeBetAmount
        betChip.isHidden = false
        self.view.addSubview(betChip)
        betChip.center = betPosition
        pointControl.hideComeBetChip()

        // Create odds chip overlay if odds exist
        var oddsChip: SmallBetChip?
        if comeBetOdds > 0 {
          let oddsPosition = pointControl.getComeBetOddsPosition(in: self.view)
          let chip = SmallBetChip()
          chip.translatesAutoresizingMaskIntoConstraints = true
          chip.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
          chip.amount = comeBetOdds
          chip.isHidden = false
          self.view.addSubview(chip)
          chip.center = oddsPosition
          pointControl.hideComeBetOddsChip()
          oddsChip = chip
        }

        // Animate winnings chip to balance
        let animWin = UIViewPropertyAnimator(
          duration: Timing.PointStack.comeWinToBalanceDuration,
          controlPoint1: CGPoint(x: 0.85, y: 0),
          controlPoint2: CGPoint(x: 0.15, y: 1)
        ) {
          winningsChip.center = balanceCenter
          winningsChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        }
        animWin.addCompletion { [weak self] _ in
          self?.balance += totalWinnings
          self?.updateCurrentBet()
          winningsChip.removeFromSuperview()
        }

        // Animate bet chip to balance
        let animBet = UIViewPropertyAnimator(
          duration: Timing.PointStack.comeWinToBalanceDuration,
          controlPoint1: CGPoint(x: 0.85, y: 0),
          controlPoint2: CGPoint(x: 0.15, y: 1)
        ) {
          betChip.center = CGPoint(x: balanceCenter.x - 8, y: balanceCenter.y)
          betChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        }
        animBet.addCompletion { [weak self] _ in
          self?.balance += comeBetAmount
          self?.updateCurrentBet()
          betChip.removeFromSuperview()
        }

        animWin.startAnimation()
        animBet.startAnimation(afterDelay: Timing.PointStack.comeWinBetStagger)

        // Animate odds chip to balance if present
        if let oddsChip = oddsChip {
          let animOdds = UIViewPropertyAnimator(
            duration: Timing.PointStack.comeWinToBalanceDuration,
            controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1)
          ) {
            oddsChip.center = CGPoint(x: balanceCenter.x + 8, y: balanceCenter.y)
            oddsChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
          }
          animOdds.addCompletion { [weak self] _ in
            self?.balance += comeBetOdds
            self?.updateCurrentBet()
            oddsChip.removeFromSuperview()

            // Clear come bet after all animations complete
            pointControl.clearComeBetSilently()
          }
          animOdds.startAnimation(afterDelay: Timing.PointStack.comeWinOddsStagger)
        } else {
          // No odds - clear come bet after bet chip animation
          animBet.addCompletion { _ in
            pointControl.clearComeBetSilently()
          }
        }
      }
    }

    animator1.startAnimation(afterDelay: Timing.PointStack.comeWinDescendDelay)
  }

  /// Animate come bet loss on seven-out: chips fly away to house
  private func animateComeBetLoss(pointControl: PointControl, comeBetAmount: Int, comeBetOdds: Int)
  {
    let betPosition = pointControl.getComeBetPosition(in: view)
    let housePosition = CGPoint(x: view.bounds.width / 2, y: 0)

    // Create bet chip overlay
    let betChip = SmallBetChip()
    betChip.translatesAutoresizingMaskIntoConstraints = true
    betChip.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
    betChip.amount = comeBetAmount
    betChip.isHidden = false
    view.addSubview(betChip)
    betChip.center = betPosition
    pointControl.hideComeBetChip()

    // Create odds chip overlay if odds exist
    var oddsChip: SmallBetChip?
    if comeBetOdds > 0 {
      let oddsPosition = pointControl.getComeBetOddsPosition(in: view)
      let chip = SmallBetChip()
      chip.translatesAutoresizingMaskIntoConstraints = true
      chip.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
      chip.amount = comeBetOdds
      chip.isHidden = false
      view.addSubview(chip)
      chip.center = oddsPosition
      pointControl.hideComeBetOddsChip()
      oddsChip = chip
    }

    // Animate bet chip away with slight random delay for cascading effect
    let delay1 = Double.random(in: Timing.Shared.staggerRange)
    Timing.after(Timing.Shared.flyDuration + delay1) { [weak self] in
      guard let self = self else { return }
      UIView.animate(withDuration: Timing.Shared.flyDuration, delay: 0, options: .curveEaseIn) {
        betChip.center = housePosition
        betChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
      } completion: { _ in
        UIView.animate(withDuration: Timing.Shared.fadeDuration) {
          betChip.alpha = 0
        } completion: { _ in
          betChip.removeFromSuperview()
        }
      }
    }

    // Animate odds chip away if present
    if let oddsChip = oddsChip {
      let delay2 = Double.random(in: Timing.Shared.staggerRange)
      Timing.after(Timing.Shared.flyDuration + delay2) {
        UIView.animate(withDuration: Timing.Shared.flyDuration, delay: 0, options: .curveEaseIn) {
          oddsChip.center = housePosition
          oddsChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        } completion: { _ in
          UIView.animate(withDuration: Timing.Shared.fadeDuration) {
            oddsChip.alpha = 0
          } completion: { _ in
            oddsChip.removeFromSuperview()
          }
        }
      }
    }

    // Clear come bet after animations are underway
    Timing.after(Timing.PointStack.comeLossClearDelay) {
      pointControl.clearComeBetSilently()
    }
  }

  /// Animate pending come bet win on the come line: winnings fly down, then both fly to balance
  private func animatePendingComeBetWin(betAmount: Int, winAmount: Int) {
    guard let balanceCenter = chipAnimator.getBalanceCenter(in: view) else {
      // Fallback: just add to balance
      balance += betAmount + winAmount
      comeBetControl.betAmount = 0
      updateCurrentBet()
      return
    }

    let betPosition = comeBetControl.getBaseBetViewPosition(in: view)
    let winningsTargetPosition = CGPoint(x: betPosition.x - 35, y: betPosition.y)

    // Step 1: Create winnings chip, animate from house to bet area
    let winningsChip = SmallBetChip()
    winningsChip.translatesAutoresizingMaskIntoConstraints = true
    winningsChip.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
    winningsChip.amount = winAmount
    winningsChip.isHidden = false
    view.addSubview(winningsChip)
    winningsChip.center = CGPoint(x: view.bounds.midX, y: 0)
    winningsChip.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)

    let animator1 = UIViewPropertyAnimator(
      duration: Timing.PointStack.comeWinApproachDuration,
      controlPoint1: CGPoint(x: 0.85, y: 0),
      controlPoint2: CGPoint(x: 0.15, y: 1)
    ) {
      winningsChip.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
      winningsChip.center = winningsTargetPosition
    }

    animator1.addCompletion { [weak self] _ in
      guard let self = self else { return }

      Timing.after(Timing.PointStack.comeWinPause) { [weak self] in
        guard let self = self else { return }

        // Create bet chip overlay (hide original)
        let betChip = SmallBetChip()
        betChip.translatesAutoresizingMaskIntoConstraints = true
        betChip.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        betChip.amount = betAmount
        betChip.isHidden = false
        self.view.addSubview(betChip)
        betChip.center = betPosition
        self.comeBetControl.betView.alpha = 0

        // Animate winnings to balance
        let animWin = UIViewPropertyAnimator(
          duration: Timing.PointStack.comeWinToBalanceDuration,
          controlPoint1: CGPoint(x: 0.85, y: 0),
          controlPoint2: CGPoint(x: 0.15, y: 1)
        ) {
          winningsChip.center = balanceCenter
          winningsChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        }
        animWin.addCompletion { [weak self] _ in
          self?.balance += winAmount
          self?.updateCurrentBet()
          winningsChip.removeFromSuperview()
        }

        // Animate bet chip to balance
        let animBet = UIViewPropertyAnimator(
          duration: Timing.PointStack.comeWinToBalanceDuration,
          controlPoint1: CGPoint(x: 0.85, y: 0),
          controlPoint2: CGPoint(x: 0.15, y: 1)
        ) {
          betChip.center = CGPoint(x: balanceCenter.x - 8, y: balanceCenter.y)
          betChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        }
        animBet.addCompletion { [weak self] _ in
          self?.balance += betAmount
          self?.updateCurrentBet()
          betChip.removeFromSuperview()
          self?.comeBetControl.betAmount = 0
          self?.comeBetControl.betView.alpha = 1
        }

        animWin.startAnimation()
        animBet.startAnimation(afterDelay: Timing.PointStack.comeWinBetStagger)
      }
    }

    animator1.startAnimation(afterDelay: Timing.BottomControls.pendingComeWinDelay)
  }

  /// Animate pending come bet loss on the come line: chip flies away to house
  private func animatePendingComeBetLoss(betAmount: Int) {
    let betPosition = comeBetControl.getBaseBetViewPosition(in: view)
    let housePosition = CGPoint(x: view.bounds.width / 2, y: 0)

    // Create chip overlay (hide original)
    let betChip = SmallBetChip()
    betChip.translatesAutoresizingMaskIntoConstraints = true

    // Match SmallBetChip's scaling behavior - 25% larger on iPad
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    let chipSize: CGFloat = isIPad ? 30 * 1.25 : 30
    betChip.frame = CGRect(x: 0, y: 0, width: chipSize, height: chipSize)
    betChip.amount = betAmount
    betChip.isHidden = false
    view.addSubview(betChip)
    betChip.center = betPosition
    comeBetControl.betView.alpha = 0

    // Animate chip flying away
    Timing.after(Timing.BottomControls.pendingComeLossDelay) { [weak self] in
      guard let self = self else { return }

      UIView.animate(withDuration: Timing.Shared.flyDuration, delay: 0, options: .curveEaseIn) {
        betChip.center = housePosition
        betChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
      } completion: { _ in
        UIView.animate(withDuration: Timing.Shared.fadeDuration) {
          betChip.alpha = 0
        } completion: { [weak self] _ in
          guard let self = self else { return }
          betChip.removeFromSuperview()
          // Only clear bet if it's still the same amount (user hasn't placed a new bet)
          if self.comeBetControl.betAmount == betAmount {
            self.comeBetControl.betAmount = 0
          }
          // Always restore alpha if still 0 (ensure new bets are visible)
          if self.comeBetControl.betView.alpha == 0 {
            self.comeBetControl.betView.alpha = 1
          }
        }
      }
    }
  }

  func handleOtherBets(_ total: Int, event: GameEvent, wasInPointPhase: Bool) -> (
    [String], [WinningBet]
  ) {
    var winMessages: [String] = []
    var winningBets: [WinningBet] = []

    // Check field bet using manager
    if fieldControl.betAmount > 0 {
      let result = specialBetsManager.evaluateFieldBet(
        total: total, betAmount: fieldControl.betAmount)

      if result.isWin {
        // If bets are OFF, don't process the win
        guard betsAreOn else {
          return (winMessages, winningBets)
        }

        // Collect bet for winnings container
        winningBets.append(
          WinningBet(
            control: fieldControl, winAmount: result.winAmount, odds: result.oddsMultiplier,
            isBonus: false, description: nil))

        // Animate winnings and original bet together (field is a one-time bet)
        Timing.after(Timing.BottomControls.fieldWinDelay) { [weak self] in
          guard let self else { return }
          animateWinningsAndBetTogether(for: fieldControl, odds: result.oddsMultiplier)
        }

        // Add field win message if appropriate
        if case .none = event {
          if result.oddsMultiplier == 2.0 {
            winMessages.append("Field wins! \(total) pays 2:1! You won $\(result.winAmount).")
          } else {
            winMessages.append("Field wins! You won $\(result.winAmount).")
          }
        }
      }
    }

    // Any 7: one-roll proposition; bet stays on table after a win until manually removed or a miss
    if let anySeven = anySevenControl, anySeven.betAmount > 0 {
      let result = specialBetsManager.evaluateAnySevenBet(
        total: total, betAmount: anySeven.betAmount)

      if result.isWin {
        guard betsAreOn else {
          return (winMessages, winningBets)
        }

        winningBets.append(
          WinningBet(
            control: anySeven, winAmount: result.winAmount, odds: result.oddsMultiplier,
            isBonus: false, description: "Any 7"))

        Timing.after(Timing.BottomControls.fieldWinDelay) { [weak self] in
          guard let self else { return }
          self.animateWinningsAndBetTogether(
            for: anySeven, odds: result.oddsMultiplier, keepBetOnControl: true)
        }

        if case .none = event {
          winMessages.append("Any 7 wins! You won $\(result.winAmount).")
        }
      }
    }

    // Lay bets win on 7 during point phase (seven-out); off on come-out, matching place-bet working rules.
    if total == 7 && wasInPointPhase && betsAreOn {
      let layWinners = pointStack.getPointControlsWithLayBets()
      for (index, pointControl) in layWinners.enumerated() {
        let layAmount = pointControl.layBetAmount
        guard layAmount > 0 else { continue }
        let mult = pointControl.layOddsMultiplier
        let profit = Int(Double(layAmount) * mult)
        let totalPayout = layAmount + profit
        winningBets.append(
          WinningBet(
            control: pointControl,
            winAmount: totalPayout,
            odds: mult,
            isBonus: false,
            description: "Lay \(pointControl.pointNumber)"
          ))
        let delay =
          Timing.PointStack.layWinBaseDelay + Double(index) * Timing.PointStack.layWinStagger
        Timing.after(delay) { [weak self] in
          self?.animateLayBetWin(pointControl: pointControl)
        }
        winMessages.append("Lay against \(pointControl.pointNumber) wins! You won $\(totalPayout)!")
      }
    }

    // Check point bets (4, 5, 6, 8, 9, 10)
    // Pay if we're in point phase AND this roll didn't just establish the point
    // OR if this roll made the point (place bets on the point number also win)
    let shouldPayPointBet: Bool
    switch event {
    case .pointEstablished:
      // Don't pay if this roll just established the point
      shouldPayPointBet = false
    case .pointMade:
      // When point is made, place bets on that number also win
      shouldPayPointBet = true
    default:
      // Pay if we're in point phase for any other roll
      shouldPayPointBet = game.isPointPhase
    }

    if shouldPayPointBet,
      let pointControl = pointStack.getPointControl(for: total) as? PointControl,
      pointControl.betAmount > 0
    {
      // If bets are OFF, don't process the win
      guard betsAreOn else {
        return (winMessages, winningBets)
      }

      let betAmount = pointControl.betAmount
      let winAmount = Int(Double(betAmount) * pointControl.oddsMultiplier)

      // Collect bet for winnings container
      winningBets.append(
        WinningBet(
          control: pointControl, winAmount: winAmount, odds: pointControl.oddsMultiplier,
          isBonus: false, description: nil))

      Timing.after(Timing.PointStack.placeWinDelay) { [weak self] in
        guard let self else { return }
        self.animateWinnings(for: pointControl, odds: pointControl.oddsMultiplier)
      }

      // Add place bet win message
      winMessages.append("Place bet on \(total) wins! You won $\(winAmount)!")
    }

    // Lay bets lose when the laid number is rolled (including come-out when that number becomes the point).
    if betsAreOn {
      for pointNumber in pointStack.pointNumbers {
        guard total == pointNumber,
          let pointControl = pointStack.getPointControl(for: pointNumber) as? PointControl,
          pointControl.hasLayBet
        else { continue }

        Timing.after(Timing.PointStack.layLossDelay) { [weak self] in
          self?.animateLayBetLoss(pointControl: pointControl)
        }
      }
    }

    // Return win messages and winning bets
    return (winMessages, winningBets)
  }

  // MARK: - Bet Result Display

  /// Group winning bets by type and show separate containers
  /// - Pass Line + Odds: Combined into one container
  /// - Come Bets: Combined into one container
  /// - Each Horn bet: Separate container
  /// - Each Hardway bet: Separate container
  /// - Each Make Em bet: Separate container
  /// - Field + Point bets: Combined into one container
  internal func showGroupedBetResults(winningBets: [WinningBet]) {
    // Group bets by type
    var passLineOddsBets: [WinningBet] = []
    var dontPassBets: [WinningBet] = []
    var comeBetBets: [WinningBet] = []
    var hornBets: [WinningBet] = []
    var hardwayBets: [WinningBet] = []
    var makeEmBets: [WinningBet] = []
    var fieldPointBets: [WinningBet] = []

    for bet in winningBets {
      // Check if it's pass line or odds (both are now on passLineControl)
      if bet.control === passLineControl {
        passLineOddsBets.append(bet)
      }
      // Check if it's don't pass
      else if bet.control === dontPassControl {
        dontPassBets.append(bet)
      }
      // Check if it's a come bet (ComeBetControl or PointControl with come bet)
      else if bet.control === comeBetControl {
        comeBetBets.append(bet)
      }
      // Check if it's a PointControl - could be come bet win or place bet win
      // Come bet wins on points: added in handleComeBets, use PointControl
      // Place bet wins: added in handleOtherBets, also use PointControl
      // Try to distinguish: if the PointControl currently has a come bet (hasComeBet), it's likely a come bet win
      // Note: This check happens after the bet may have been cleared, so it's not 100% reliable
      // but it's the best heuristic we have without additional metadata
      else if bet.control is PointControl {
        if bet.description?.hasPrefix("Lay ") == true {
          fieldPointBets.append(bet)
        } else if let pointControl = bet.control as? PointControl, pointControl.hasComeBet {
          // Likely a come bet win
          comeBetBets.append(bet)
        } else {
          // Likely a place bet win
          fieldPointBets.append(bet)
        }
      } else if bet.control is MultiBetControl || bet.control is MakeEmAllControl {
        makeEmBets.append(bet)
      } else if bet.control === cAndETriZoneControl {
        hornBets.append(bet)
      } else if bet.control === anySevenControl {
        hornBets.append(bet)
      } else if bet.control is AnyHornControl {
        hornBets.append(bet)
      }
      // Check if it's a horn bet (SmallControl that's a bonus)
      // Horn bets are: (1,1), (6,6), (1,2), (5,6) - not doubles except for 1,1 and 6,6
      // Hardway bets are always doubles: (2,2), (3,3), (4,4), (5,5)
      else if bet.isBonus && bet.control is SmallControl {
        if let smallControl = bet.control as? SmallControl {
          let die1 = smallControl.dieValue1
          let die2 = smallControl.dieValue2
          // Horn bets: (1,1), (6,6), (1,2), (5,6) - check for these specific combinations
          let isHornBet =
            (die1 == 1 && die2 == 1) || (die1 == 6 && die2 == 6) || (die1 == 1 && die2 == 2)
            || (die1 == 2 && die2 == 1) || (die1 == 5 && die2 == 6) || (die1 == 6 && die2 == 5)
          if isHornBet {
            hornBets.append(bet)
          } else {
            // Must be hardway (doubles: 2,2 or 3,3 or 4,4 or 5,5)
            hardwayBets.append(bet)
          }
        }
      }
      // Check if it's field bet (not PointControl, since those are handled above)
      else if bet.control === fieldControl {
        fieldPointBets.append(bet)
      }
    }

    var delay: TimeInterval = Timing.UIFeedback.betResultInitialDelay

    // Show Pass Line + Odds combined
    if !passLineOddsBets.isEmpty {
      let totalWinnings = passLineOddsBets.reduce(0) { $0 + $1.winAmount }
      let hasBonus = passLineOddsBets.contains { $0.isBonus }
      let description =
        passLineOddsBets.first(where: { $0.isBonus })?.description
        ?? passLineOddsBets.first(where: { $0.description != nil })?.description
      Timing.after(delay) { [weak self] in
        self?.showBetResult(
          amount: totalWinnings, isWin: true, showBonus: hasBonus, description: description)
      }
      delay += Timing.UIFeedback.betResultGroupSpacing
    }

    // Show Don't Pass wins
    if !dontPassBets.isEmpty {
      let totalWinnings = dontPassBets.reduce(0) { $0 + $1.winAmount }
      let hasBonus = dontPassBets.contains { $0.isBonus }
      let description =
        dontPassBets.first(where: { $0.isBonus })?.description
        ?? dontPassBets.first(where: { $0.description != nil })?.description
      Timing.after(delay) { [weak self] in
        self?.showBetResult(
          amount: totalWinnings, isWin: true, showBonus: hasBonus, description: description)
      }
      delay += Timing.UIFeedback.betResultGroupSpacing
    }

    // Show Come Bet wins combined
    if !comeBetBets.isEmpty {
      let totalWinnings = comeBetBets.reduce(0) { $0 + $1.winAmount }
      let hasBonus = comeBetBets.contains { $0.isBonus }
      let description =
        comeBetBets.first(where: { $0.isBonus })?.description
        ?? comeBetBets.first(where: { $0.description != nil })?.description
      Timing.after(delay) { [weak self] in
        self?.showBetResult(
          amount: totalWinnings, isWin: true, showBonus: hasBonus, description: description)
      }
      delay += Timing.UIFeedback.betResultGroupSpacing
    }

    // Show each Horn bet separately
    for hornBet in hornBets {
      Timing.after(delay) { [weak self] in
        self?.showBetResult(
          amount: hornBet.winAmount, isWin: true, showBonus: true, description: hornBet.description)
      }
      delay += Timing.UIFeedback.betResultGroupSpacing
    }

    // Show each Hardway bet separately
    for hardwayBet in hardwayBets {
      Timing.after(delay) { [weak self] in
        self?.showBetResult(
          amount: hardwayBet.winAmount, isWin: true, showBonus: true,
          description: hardwayBet.description)
      }
      delay += Timing.UIFeedback.betResultGroupSpacing
    }

    // Show each Make Em bet separately
    for makeEmBet in makeEmBets {
      Timing.after(delay) { [weak self] in
        self?.showBetResult(
          amount: makeEmBet.winAmount, isWin: true, showBonus: true,
          description: makeEmBet.description)
      }
      delay += Timing.UIFeedback.betResultGroupSpacing
    }

    // Show Field + Point bets combined
    if !fieldPointBets.isEmpty {
      let totalWinnings = fieldPointBets.reduce(0) { $0 + $1.winAmount }
      let hasBonus = fieldPointBets.contains { $0.isBonus }
      let description =
        fieldPointBets.first(where: { $0.isBonus })?.description
        ?? fieldPointBets.first(where: { $0.description != nil })?.description
      Timing.after(delay) { [weak self] in
        self?.showBetResult(
          amount: totalWinnings, isWin: true, showBonus: hasBonus, description: description)
      }
    }
  }

  // MARK: - Animation Methods

  /// Animate winnings and original bet together (for one-time bets like field)
  /// Uses ChipAnimationHelper for consistent animations
  private func animateWinningsAndBetTogether(
    for control: PlainControl, odds: Double, keepBetOnControl: Bool = false
  ) {
    guard control.betAmount > 0 else { return }

    let betAmount = control.betAmount
    let winAmount = Int(Double(betAmount) * odds)
    // Use separate offset for original bet winnings
    let offset = control.originalBetWinningsOffset

    chipAnimator.animateBonusBetWinningsWithOffset(
      for: control,
      betAmount: betAmount,
      winAmount: winAmount,
      offset: offset,
      keepBetOnControl: keepBetOnControl
    ) { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
    }
  }

  private func animateLayBetWin(pointControl: PointControl) {
    guard let containerView = view else { return }
    let layAmount = pointControl.layBetAmount
    guard layAmount > 0, betsAreOn else { return }

    let profit = Int(Double(layAmount) * pointControl.layOddsMultiplier)
    let layPosition = pointControl.getLayBetChipPosition(in: containerView)
    let offset = pointControl.originalBetWinningsOffset

    chipAnimator.animateBonusBetWinningsAtPosition(
      betPosition: layPosition,
      betAmount: layAmount,
      winAmount: profit,
      offset: offset,
      prepareBetDuplicate: { [weak pointControl] in
        pointControl?.hideLayBetChip()
      },
      restoreSourceChip: { [weak self, weak pointControl] in
        pointControl?.clearLayBetSilently()
        pointControl?.showLayBetChip()
        self?.updateCurrentBet()
      },
      onBalanceUpdate: { [weak self] amount in
        guard let self else { return }
        self.balance += amount
        self.updateCurrentBet()
        self.updateRollingState()
      }
    )
  }

  private func animateLayBetLoss(pointControl: PointControl) {
    guard betsAreOn else { return }
    let amount = pointControl.layBetAmount
    guard amount > 0 else { return }

    let destination = CGPoint(x: view.bounds.width / 2, y: 0)
    let chipView = SmallBetChip()
    chipView.amount = amount
    chipView.translatesAutoresizingMaskIntoConstraints = true
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    let chipSize: CGFloat = isIPad ? 30 * 1.25 : 30
    chipView.frame = CGRect(x: 0, y: 0, width: chipSize, height: chipSize)
    chipView.isHidden = false
    view.addSubview(chipView)

    let start = pointControl.getLayBetChipPosition(in: view)
    chipView.center = start
    pointControl.hideLayBetChip()

    let randomDelay = Double.random(in: Timing.PointStack.layLossStaggerRange)
    UIView.animate(
      withDuration: Timing.Shared.flyDuration, delay: randomDelay, options: .curveEaseIn,
      animations: {
        chipView.center = destination
        chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
      },
      completion: { [weak self] _ in
        UIView.animate(withDuration: Timing.Shared.fadeDuration) {
          chipView.alpha = 0
        } completion: { _ in
          chipView.removeFromSuperview()
          pointControl.clearLayBetSilently()
          pointControl.showLayBetChip()
          self?.updateCurrentBet()
        }
      })
  }

  /// Animate odds winnings and bet together (like fieldControl)
  /// Winnings come down, then both winnings and odds bet animate together to balance
  /// IMPORTANT: winAmount is the PROFIT only (for display on winnings chip)
  /// totalPayout is the TOTAL payout (bet + profit) that gets added to balance
  /// For example: $20 bet on point 6 (1.2x) = $24 profit, $44 total
  /// We animate: winnings chip ($24 profit) + original bet chip ($20) together, add $44 to balance
  private func animateOddsWinnings(
    for control: PlainControl, oddsBetAmount: Int, winAmount: Int, totalPayout: Int, odds: Double
  ) {
    guard let containerView = view else {
      return
    }
    guard let oddsStack = control.oddsBetStack else {
      return
    }

    // winAmount is the PROFIT only (for display on winnings chip)
    // totalPayout is the TOTAL payout (bet + profit) that gets added to balance
    // Example: $20 bet on point 6 (1.2x) = $24 profit, $44 total ($20 bet + $24 profit)
    // We'll animate: winnings chip ($24 profit) + original bet chip ($20) together, add $44 to balance

    // CRITICAL: Get odds chip position BEFORE hiding it
    // Note: isAnimatingPayout flag should already be set (set before processRoll)
    if !oddsStack.isAnimatingPayout {
      oddsStack.startPayoutAnimation()
    }

    let oddsPosition = oddsStack.getOddsPosition(in: containerView)
    // Use separate offset for odds bet winnings (Y only, no X offset)
    let offset = control.oddsBetWinningsOffset

    // Use animateOddsBetWinningsWithOffset pattern - winnings come down, then both animate together
    // winAmount is profit only (for display), totalPayout is total (for balance)
    chipAnimator.animateOddsBetWinningsWithOffset(
      for: control,
      oddsBetAmount: oddsBetAmount,
      winAmount: winAmount,  // Profit only for display
      offset: offset
    ) { [weak self] _ in
      guard let self = self else {
        oddsStack.endPayoutAnimation()
        return
      }
      // Add the total odds payout to balance (bet + profit)
      // winAmount parameter is profit only for display, but we need to add totalPayout to balance
      // NOTE: This callback is called AFTER both chips have animated to balance
      // The odds amount has already been cleared in the helper's completion handler
      // (control.oddsAmount = 0 was called BEFORE onBalanceUpdate)
      self.balance += totalPayout  // Add total payout (bet + profit)

      // CRITICAL: End the payout animation flag AFTER balance is updated
      // The odds amount was already cleared in animateOddsBetWinningsWithOffset completion
      // (before onBalanceUpdate was called), so the flag can now be safely cleared
      oddsStack.endPayoutAnimation()

      self.updateCurrentBet()
      self.updateRollingState()
    }
  }

  private func animateBetCollection(for control: PlainControl) {
    guard control.betAmount > 0 else { return }

    // Pass line and don't pass bets always stay on the control when winning
    // (This is standard craps behavior - the bet continues for the next come-out roll)
    if control === passLineControl || control === dontPassControl {
      // Don't add to balance - the bet stays on the control for the next hand
      return
    }

    // Use ChipAnimationHelper for consistent animations with control-specific offset
    let offset = control.originalBetCollectionOffset
    chipAnimator.animateBetCollectionWithOffset(
      for: control,
      offset: offset
    ) { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
    }
  }

  /// Animate odds bet collection: odds position + offset → balance
  private func animateOddsBetCollection(for control: PlainControl, oddsBetAmount: Int) {
    guard oddsBetAmount > 0 else { return }

    // Use control-specific offset for odds bet collection
    let offset = control.oddsBetCollectionOffset
    chipAnimator.animateOddsBetCollection(
      for: control,
      oddsBetAmount: oddsBetAmount,
      offset: offset
    ) { [weak self] amount in
      guard let self = self else { return }
      self.balance += amount
      self.updateCurrentBet()
      self.updateRollingState()
    }
  }

  func getAllBettingControls() -> [PlainControl] {
    var controls: [PlainControl] = []

    // Add plain controls (check for nil to handle initialization order)
    if let passLine = passLineControl {
      controls.append(passLine)
    }
    if let field = fieldControl {
      controls.append(field)
    }
    if let anySeven = anySevenControl {
      controls.append(anySeven)
    }
    if let dontPass = dontPassControl {
      controls.append(dontPass)
    }

    // Add point controls from stack
    if let pointStack = pointStack {
      for pointNumber in pointStack.pointNumbers {
        if let pointControl = pointStack.getPointControl(for: pointNumber) {
          controls.append(pointControl)
        }
      }
    }

    // Add hardway controls from bet stack
    if let hardwayView = hardwayView {
      for arrangedSubview in hardwayView.betStack.arrangedSubviews {
        if let columnStack = arrangedSubview as? UIStackView {
          for columnSubview in columnStack.arrangedSubviews {
            if let hardwayControl = columnSubview as? SmallControl {
              controls.append(hardwayControl)
            }
          }
        }
      }
    }

    // Add horn controls from bet stack
    if let hornView = hornView {
      for arrangedSubview in hornView.betStack.arrangedSubviews {
        if let columnStack = arrangedSubview as? UIStackView {
          for columnSubview in columnStack.arrangedSubviews {
            if let hornControl = columnSubview as? SmallControl {
              controls.append(hornControl)
            } else if let anyHorn = columnSubview as? AnyHornControl {
              controls.append(anyHorn)
            }
          }
        }
      }
    }

    // Add Make Em controls from makeEmView
    if let makeEmView = makeEmView,
      let makeEmStack = makeEmView.subviews.first(where: { $0 is UIStackView }) as? UIStackView
    {
      for arrangedSubview in makeEmStack.arrangedSubviews {
        if let makeEmControl = arrangedSubview as? MultiBetControl {
          controls.append(makeEmControl)
        } else if let makeEmAll = arrangedSubview as? MakeEmAllControl {
          controls.append(makeEmAll)
        }
      }
    }

    return controls
  }

  /// Check if any betting control has a bet placed
  func hasAnyBetPlaced() -> Bool {
    let allControls = getAllBettingControls()
    if allControls.contains(where: { $0.betAmount > 0 }) { return true }
    if comeBetControl != nil && comeBetControl.betAmount > 0 { return true }
    if let anySeven = anySevenControl, anySeven.betAmount > 0 { return true }
    if let cAndE = cAndETriZoneControl, cAndE.totalBetAmount > 0 { return true }
    return false
  }

  // MARK: - Action Methods

  @objc func toggleBetsTapped() {
    betsAreOn.toggle()

    // Find the toggle button in the actions view to update its appearance
    if let actionsView = actionsView {
      // Recursively search for the button with tag 1001
      if let toggleButton = findButtonWithTag(1001, in: actionsView) {
        if betsAreOn {
          // Bets are ON - show green button
          toggleButton.setTitle("Bets are ON", for: .normal)
          toggleButton.backgroundColor = HardwayColors.green
        } else {
          // Bets are OFF - show gray button
          toggleButton.setTitle("Bets are OFF", for: .normal)
          toggleButton.backgroundColor = HardwayColors.surfaceGray
        }
      }
      if let acrossButton = findButtonWithTag(1002, in: actionsView) {
        acrossButton.isEnabled = betsAreOn
      }
    }

    // Enable/disable all betting controls (except pass line and don't pass - they're always enabled)
    let allControls = getAllBettingControls()
    for control in allControls {
      // Never disable pass line and don't pass - they can be placed at any phase
      if control === passLineControl || control === dontPassControl {
        continue
      }
      control.isEnabled = betsAreOn
    }

    // Provide haptic feedback
    HapticsHelper.lightHaptic()

    updateComeBetControlState()
  }

  @objc func collectBetsTapped() {
    // Collect all bets, but skip pass line and don't pass only when point is ON
    let allControls = getAllBettingControls()
    var controlsToCollect: [PlainControl] = []
    var totalCollected = 0
    let isPointOn = gameStateManager.isPointPhase

    for control in allControls {
      // If point is ON, skip pass line and don't pass
      if isPointOn {
        if control === passLineControl || control === dontPassControl {
          continue
        }
      }

      let betAmount = control.betAmount
      if betAmount > 0 {
        totalCollected += betAmount
        controlsToCollect.append(control)
      }
    }

    if let cAndE = cAndETriZoneControl {
      for zone in TriZoneBetControl.Zone.allCases {
        let zBet = cAndE.betAmount(for: zone)
        if zBet > 0 {
          totalCollected += zBet
        }
      }
    }

    if totalCollected > 0 {
      instructionLabel.showMessage("Collected $\(totalCollected) in bets.", shouldFade: true)
      HapticsHelper.successHaptic()

      var delay: TimeInterval = 0.0
      for control in controlsToCollect {
        Timing.after(delay) { [weak self] in
          guard let self = self else { return }

          if let makeEmControl = control as? MultiBetControl {
            makeEmControl.resetHitNumbers()
          } else if let makeEmAll = control as? MakeEmAllControl {
            makeEmAll.resetHitNumbers()
          }

          self.chipAnimator.animateBetCollection(for: control) { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
            self.updateCurrentBet()
          }
        }
        delay += Timing.Collect.controlStagger
      }

      if let cAndE = cAndETriZoneControl {
        for zone in TriZoneBetControl.Zone.allCases {
          let zBet = cAndE.betAmount(for: zone)
          guard zBet > 0 else { continue }
          Timing.after(delay) { [weak self] in
            self?.cAndETriZoneControl?.clearZone(zone)
          }
          delay += Timing.Collect.controlStagger
        }
      }
    } else {
      instructionLabel.showMessage("No bets to collect.", shouldFade: true)
      HapticsHelper.lightHaptic()
    }
  }

  private func hitATM(amount: Int) {
    balance += amount
    sessionManager.trackATMVisit(amount: amount)
    instructionLabel.showMessage(
      ATMWithdrawalPresenter.randomMessage(for: amount), shouldFade: true)
    HapticsHelper.successHaptic()
  }

  func applyPlaceAcross(_ allocation: PlaceAcrossAllocation) {
    guard betsAreOn else { return }
    guard allocation.variant == variant else { return }
    guard let pointStack = pointStack else { return }

    let skipNumber = game.currentPoint
    let chipCost = allocation.chipCostSkipping(pointNumber: skipNumber)

    guard balance >= chipCost else {
      instructionLabel.showMessage("Not enough balance for this spread.", shouldFade: true)
      HapticsHelper.lightHaptic()
      return
    }

    let insideBoxes: Set<Int> = [6, 8]
    let outsidePoints = rules.orderedPointNumbers.filter { !insideBoxes.contains($0) }
    let insidePoints = rules.orderedPointNumbers.filter { insideBoxes.contains($0) }

    var placedTotal = 0

    for n in outsidePoints {
      if let skipNumber, n == skipNumber { continue }
      guard let control = pointStack.getPointControl(for: n) else { continue }
      control.addBetWithAnimation(allocation.outsideEach)
      placedTotal += allocation.outsideEach
    }
    for n in insidePoints {
      if let skipNumber, n == skipNumber { continue }
      guard let control = pointStack.getPointControl(for: n) else { continue }
      control.addBetWithAnimation(allocation.insideEach)
      placedTotal += allocation.insideEach
    }

    let outsideLabel = PlaceAcrossAllocator.outsideBoxesInstructionLabel(for: variant)
    let skipNote: String
    if let pn = skipNumber {
      skipNote = " Skipping \(pn) (point)."
    } else {
      skipNote = ""
    }
    instructionLabel.showMessage(
      "Across $\(placedTotal): $\(allocation.outsideEach) on \(outsideLabel), $\(allocation.insideEach) on 6 & 8.\(skipNote)",
      shouldFade: true
    )
    HapticsHelper.successHaptic()
  }

  private func findButtonWithTag(_ tag: Int, in view: UIView) -> UIButton? {
    if let button = view as? UIButton, button.tag == tag {
      return button
    }
    for subview in view.subviews {
      if let found = findButtonWithTag(tag, in: subview) {
        return found
      }
    }
    return nil
  }

  // MARK: - Tips

  func showTips() {
    // Priority 1: Tap to bet tip (highest priority - first thing users need to do)
    if NNTipManager.shared.shouldShowTip(CrapsTips.tapToBetTip),
      !hasShownTapToBetTip,
      !game.isPointPhase,
      passLineControl.betAmount == 0
    {

      hasShownTapToBetTip = true

      // Show tip anchored to the pass line control
      NNTipManager.shared.showTip(
        CrapsTips.tapToBetTip,
        sourceView: passLineControl,
        in: self,
        pinToEdge: .top,
        offset: CGPoint(x: 0, y: -8),
        centerHorizontally: true
      )
      return  // Always return after attempting to show this highest priority tip
    }

    // Priority 2: Come out roll tip (show when user has placed a bet and can roll)
    // Don't show if tap to bet tip is still showing - wait for it to be dismissed first
    if NNTipManager.shared.shouldShowTip(CrapsTips.comeOutRollTip),
      !hasShownComeOutRollTip,
      !game.isPointPhase,
      !NNTipManager.shared.isShowingTip(CrapsTips.tapToBetTip),
      passLineControl.betAmount > 0 || (dontPassControl?.betAmount ?? 0) > 0
    {

      hasShownComeOutRollTip = true

      // Show tip anchored to the dice container
      NNTipManager.shared.showTip(
        CrapsTips.comeOutRollTip,
        sourceView: flipDiceContainer,
        in: self,
        pinToEdge: .top,
        offset: CGPoint(x: 0, y: -8),
        centerHorizontally: true
      )
      return  // Return after successfully showing the tip
    }

    // Priority 3: Bet box numbers tip (show when point is established)
    if NNTipManager.shared.shouldShowTip(CrapsTips.betBoxNumbersTip),
      !hasShownBetBoxNumbersTip,
      game.isPointPhase,
      let pointNumber = game.currentPoint,
      pointStack != nil
    {

      hasShownBetBoxNumbersTip = true

      // Show tip anchored to the point stack
      NNTipManager.shared.showTip(
        CrapsTips.betBoxNumbersTip,
        sourceView: pointStack,
        in: self,
        pinToEdge: .top,
        offset: CGPoint(x: 0, y: -8),
        centerHorizontally: true
      )
      return  // Return after successfully showing the tip
    }

    // Priority 4: Hit point to win tip (show when point is established)
    // Don't show if bet box numbers tip is still showing - wait for it to be dismissed first
    if NNTipManager.shared.shouldShowTip(CrapsTips.hitPointToWinTip),
      !hasShownHitPointToWinTip,
      game.isPointPhase,
      let pointNumber = game.currentPoint,
      !NNTipManager.shared.isShowingTip(CrapsTips.betBoxNumbersTip)
    {

      hasShownHitPointToWinTip = true

      // Show tip anchored to the dice container
      NNTipManager.shared.showTip(
        CrapsTips.hitPointToWinTip,
        sourceView: pointStack.getPointControl(for: pointNumber) ?? pointStack,
        in: self,
        pinToEdge: .top,
        offset: CGPoint(x: 0, y: -8),
        centerHorizontally: true
      )
      return  // Return after successfully showing the tip
    }

    // Priority 5: Drag chip tip (show after several rolls when user has bets placed)
    // Don't show if higher priority tips are still showing
    if NNTipManager.shared.shouldShowTip(CrapsTips.dragChipTip),
      !hasShownDragChipTip,
      rollCount >= 3,
      !flipDiceContainer.isRolling,
      !NNTipManager.shared.isShowingTip(CrapsTips.tapToBetTip),
      !NNTipManager.shared.isShowingTip(CrapsTips.comeOutRollTip),
      !NNTipManager.shared.isShowingTip(CrapsTips.betBoxNumbersTip),
      !NNTipManager.shared.isShowingTip(CrapsTips.hitPointToWinTip)
    {

      // Find a control with a bet to anchor the tip
      let allControls = getAllBettingControls()
      if let controlWithBet = allControls.first(where: { $0.betAmount > 0 }) {
        hasShownDragChipTip = true

        // Show tip centered horizontally, anchored to the control with bet
        NNTipManager.shared.showTip(
          CrapsTips.dragChipTip,
          sourceView: controlWithBet,
          in: self,
          pinToEdge: .top,
          offset: CGPoint(x: 0, y: -8),
          centerHorizontally: true
        )
        return  // Return after successfully showing the tip
      }
    }
  }
}

extension CrapsGameplayViewController: ChipSelectorDelegate {
  func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {
    crapsAutoplayer?.cancelDueToUserInteraction()
    refreshAutoplayNavigationChrome()
  }
}

extension CrapsGameplayViewController: UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    // Update page control based on scroll position
    guard scrollView == betsScrollView else { return }
    guard let pageControl = pageControl else { return }

    let pageWidth = scrollView.bounds.width
    guard pageWidth > 0 else { return }  // Prevent division by zero

    let currentPage = Int((scrollView.contentOffset.x + pageWidth / 2) / pageWidth)
    pageControl.currentPage = currentPage
  }
}

// MARK: - CrapsSettingsManagerDelegate

extension CrapsGameplayViewController: CrapsSettingsManagerDelegate {
  func settingsDidChange(_ settings: CrapsSettings) {
    // Only rebuild bet views if bonus bet settings actually changed
    let currentBonusSettings = (
      hardways: settings.hardwaysEnabled, makeEm: settings.makeEmEnabled, horn: settings.hornEnabled
    )
    let bonusSettingsChanged =
      previousBonusBetSettings.map {
        $0 != currentBonusSettings
      } ?? true

    if bonusSettingsChanged {
      rebuildBetViews(for: currentLayoutMode)
    }
  }
}

// MARK: - CrapsSessionManagerDelegate

extension CrapsGameplayViewController: CrapsSessionManagerDelegate {
  func sessionDidStart(id: String) {
    // Session started - could be used for analytics
  }

  func sessionWasSaved(session: GameSession) {
    // Session saved - could show confirmation or update UI
  }

  func metricsDidUpdate(metrics: GameplayMetrics) {
    // Metrics updated
  }

  func balanceDidChange(from oldBalance: Int, to newBalance: Int) {
    // Balance changed - already handled by balance setter
  }

  func rollCountDidChange(count: Int) {
    // Roll count changed - could be used for UI updates
  }

  func sevenWasRolled(total: Int) {
    // Seven was rolled - could be used for analytics
  }

  func pointWasMade(number: Int) {
    // Point was made - could be used for analytics
  }
}

// MARK: - CrapsGameStateManagerDelegate

extension CrapsGameplayViewController: CrapsGameStateManagerDelegate {
  func gamePhaseDidChange(from: CrapsGame.Phase, to: CrapsGame.Phase) {
    // Game phase changed - update UI if needed
    updatePassLineOddsVisibility()
    // Show tips based on new game phase
    showTips()
  }

  func rollingStateDidChange(enabled: Bool) {
    if enabled {
      flipDiceContainer.enableRolling()
    } else {
      flipDiceContainer.disableRolling()
    }
  }

  func pointWasEstablished(number: Int) {
    // Point established - UI already updates in handleRollResult
  }

  // Note: pointWasMade(number:) is implemented in CrapsSessionManagerDelegate extension
  // and satisfies this protocol requirement as well

  func sevenOut() {
    // Seven out - UI already updates in handleRollResult
  }
}

// MARK: - CrapsPassLineManagerDelegate

extension CrapsGameplayViewController: CrapsPassLineManagerDelegate {
  func passLineWinProcessed(originalBet: Int, winnings: Int) {
    // Win processed - animations handled in handlePassLineWin
  }

  func passLineOddsWinProcessed(originalBet: Int, winnings: Int, point: Int, multiplier: Double) {
    // Odds win processed - animations handled in handlePassLineOddsWin
  }

  func passLineLossProcessed(lostAmount: Int) {
    // Loss processed - animations handled in handlePassLineLoss
  }

  func passLineOddsLossProcessed(lostAmount: Int) {
    // Odds loss processed - animations handled in handlePassLineOddsLoss
  }
}

// MARK: - CrapsSpecialBetsManagerDelegate

extension CrapsGameplayViewController: CrapsSpecialBetsManagerDelegate {
  func hardwayWinEvaluated(total: Int, betAmount: Int, multiplier: Double, winAmount: Int) {
    // Hardway win evaluated - animations handled in handleHardwayBets
  }

  func hardwayLossEvaluated(total: Int, betAmount: Int, isSoftWay: Bool) {
    // Hardway loss evaluated - animations handled in handleHardwayBets
  }

  func hornWinEvaluated(hornName: String, betAmount: Int, multiplier: Double, winAmount: Int) {
    // Horn win evaluated - animations handled in handleHornBets
  }

  func fieldWinEvaluated(total: Int, betAmount: Int, multiplier: Double, winAmount: Int) {
    // Field win evaluated - animations already handled via evaluateFieldBet
  }

  func dontPassWinEvaluated(
    total: Int, betAmount: Int, multiplier: Double, winAmount: Int, isPointPhase: Bool
  ) {
    // Don't Pass win evaluated - animations handled in handleDontPassBet
  }

  func dontPassPushEvaluated(total: Int, betAmount: Int) {
    // Don't Pass push on 12 - no win or loss, bet stays
  }

  func makeEmWinEvaluated(betName: String, betAmount: Int, multiplier: Double, winAmount: Int) {
    // Make Em bet win evaluated - animations handled in handleMakeEmBets
  }

  func makeEmNumberHit(betName: String, number: Int) {
    // Make Em number hit - UI updates handled in handleMakeEmBets
  }
}
