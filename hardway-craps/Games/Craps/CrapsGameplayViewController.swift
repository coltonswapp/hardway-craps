//
//  CrapsGameplayViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class CrapsGameplayViewController: UIViewController {

    // MARK: - Managers

    private var settingsManager: CrapsSettingsManager!
    private var sessionManager: CrapsSessionManager!
    private var gameStateManager: CrapsGameStateManager!
    private var passLineManager: CrapsPassLineManager!
    private var specialBetsManager: CrapsSpecialBetsManager!
    private var chipAnimator: ChipAnimationHelper!

    // MARK: - Constants

    private let startingBalance: Int = 200

    private var chipSelector: ChipSelector!
    private var passLineControl: PlainControl!
    private var passLineOddsControl: PlainControl!
    private var passLineControlWidthConstraint: NSLayoutConstraint!
    private var passLineOddsControlWidthConstraint: NSLayoutConstraint!
    private var passLineOddsControlLeadingConstraint: NSLayoutConstraint!
    private var fieldControl: PlainControl!
    private var dontPassControl: DontPassControl!
    private var pointStack: PointStack!
    private var flipDiceContainer: FlipDiceContainer!
    private var balanceView: BalanceView!
    private var instructionLabel: InstructionLabel!
    private var hardwayView: QuadBetView?
    private var makeEmView: UIView?
    private var hornView: QuadBetView?
    private var actionsView: UIView!
    private var scrollContentView: UIView!
    private var scrollContentWidthConstraint: NSLayoutConstraint?
    private var previousBonusBetSettings: (hardways: Bool, makeEm: Bool, horn: Bool)?
    private var betsScrollView: UIScrollView!
    private var pageControl: UIPageControl!
    private var betsContainerView: UIView!
    private var bottomStackView: UIStackView!
    private var topStackView: UIStackView!
    private var currentBetView: CurrentBetView!
    private var topStackTopConstraint: NSLayoutConstraint!

    // Track which line control (Pass or Don't Pass) was last used for rebet
    private var lastLineControlUsed: PlainControl?
    
    // Track if bets were manually removed (to prevent rebet)
    private var passLineManuallyRemoved: Bool = false
    private var dontPassManuallyRemoved: Bool = false

    // Track whether bets are currently enabled or disabled
    private var betsAreOn: Bool = true
    
    // Tip tracking
    private var hasShownTapToBetTip: Bool = false
    private var hasShownComeOutRollTip: Bool = false
    private var hasShownBetBoxNumbersTip: Bool = false
    private var hasShownHitPointToWinTip: Bool = false
    private var hasShownDragChipTip: Bool = false

    // Optional session to resume from
    private var resumingSession: GameSession?

    // MARK: - Computed Properties (Backward Compatibility)

    /// Backward compatibility: Access rebet properties through pass line manager
    private var rebetEnabled: Bool {
        get { passLineManager.rebetEnabled }
        set { passLineManager.setRebetEnabled(newValue) }
    }
    private var rebetAmount: Int {
        get { passLineManager.rebetAmount }
        set { passLineManager.setRebetAmount(newValue) }
    }

    /// Backward compatibility: Access game through game state manager
    private var game: CrapsGameStateManager {
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
    private var gameplayMetrics: GameplayMetrics { sessionManager?.gameplayMetrics ?? GameplayMetrics() }
    private var pendingBetSizeSnapshot: Int {
        get { 0 } // Read-only, managed internally by session manager
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
            chipSelector?.updateAvailableChips(balance: newValue)
            sessionManager?.currentBalance = newValue
        }
    }

    var selectedChipValue: Int {
        return chipSelector?.selectedValue ?? 5
    }

    // Custom initializer for resuming a session
    init(resumingSession: GameSession? = nil) {
        self.resumingSession = resumingSession
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

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

        // 4. Setup pass line control and odds control
        setupPassLineControls()

        // 5. Setup DontPassControl (between Field and PassLine) - must be before field
        setupDontPassControl()

        // 6. Setup Quad bets scrollView (below top stack)
        setupHardwayStack()

        // 7. Setup PointStack (below Quad bets)
        setupPointStack()

        // 8. Setup FieldControl (below PointStack)
        setupFieldControl()


        setupDebugMenu()

        view.bringSubviewToFront(bottomStackView)
        view.bringSubviewToFront(flipDiceContainer)
        view.bringSubviewToFront(topStackView)

        // Set balance from session manager if resuming (after UI is set up)
        if resumingSession != nil {
            balance = sessionManager.currentBalance
        }

        // Initialize chip availability based on starting balance
        chipSelector.updateAvailableChips(balance: balance)

        // Set UI references for game state manager (after UI is set up)
        gameStateManager.setUIReferences(flipDiceContainer: flipDiceContainer, passLineControl: passLineControl, dontPassControl: dontPassControl, hasAnyBet: { [weak self] in
            self?.hasAnyBetPlaced() ?? false
        })
    }

    // MARK: - Manager Setup

    private func startSession() {
        // Session is already initialized in setupManagers
        // Just start it if it's a new session
        if resumingSession == nil {
            sessionManager.startSession()
        }
    }

    private func setupManagers() {
        // Initialize settings manager
        settingsManager = CrapsSettingsManager()
        settingsManager.delegate = self
        settingsManager.loadSettings()

        // Initialize session manager (with resuming session if available)
        sessionManager = CrapsSessionManager(
            startingBalance: startingBalance,
            resumingSession: resumingSession
        )
        sessionManager.delegate = self

        // Initialize game state manager
        gameStateManager = CrapsGameStateManager()
        gameStateManager.delegate = self

        // Initialize pass line manager with settings
        passLineManager = CrapsPassLineManager(
            rebetEnabled: settingsManager.currentSettings.rebetEnabled,
            rebetAmount: settingsManager.currentSettings.rebetAmount
        )
        passLineManager.delegate = self

        // Initialize special bets manager
        specialBetsManager = CrapsSpecialBetsManager()
        specialBetsManager.delegate = self
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
            pauseSessionTimer() // Ensure we capture final active time
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
        // Stop all tip observations
        NNTipManager.shared.stopAllTipObservations()
        // Save session if view controller is being dismissed (e.g., popped from navigation)
        if isMovingFromParent && hasActiveSession() {
            saveCurrentSessionForced()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update pass line control widths when view size changes
        let availableWidth = view.bounds.width - 32
        let spacing: CGFloat = 12
        let passLineWidth = availableWidth * 0.55
        let oddsWidth = availableWidth * 0.45 - spacing
        
        passLineControlWidthConstraint?.constant = passLineWidth
        passLineOddsControlWidthConstraint?.constant = oddsWidth
        
        // Initialize chip selector indicator position after layout
        // Force chipSelector to layout its subviews first, then initialize indicator
        if let chipSelector = chipSelector {
            chipSelector.layoutIfNeeded()
            DispatchQueue.main.async { [weak self] in
                self?.chipSelector?.initializeIndicatorPosition()
            }
        }
    }
    

    private func recordBalanceSnapshot() {
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
        if passLineOddsControl.betAmount > 0 { concurrentCount += 1 }
        if fieldControl.betAmount > 0 { concurrentCount += 1 }
        if dontPassControl.betAmount > 0 { concurrentCount += 1 }
        
        // Check point bets
        if let pointStack = pointStack {
            for pointNumber in pointStack.pointNumbers {
                if let pointControl = pointStack.getPointControl(for: pointNumber),
                   pointControl.betAmount > 0 {
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
                           hardwayControl.betAmount > 0 {
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
                           hornControl.betAmount > 0 {
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
        let settingsVC = CrapsSettingsViewController()

        // Configure callbacks
        settingsVC.onSettingsChanged = { [weak self] in
            guard let self = self else { return }
            // Reload settings from manager
            let oldSettings = self.settingsManager.currentSettings
            self.settingsManager.loadSettings()
            let newSettings = self.settingsManager.currentSettings

            // Rebuild bet views if bonus bet settings changed
            if newSettings.hardwaysEnabled != oldSettings.hardwaysEnabled ||
               newSettings.makeEmEnabled != oldSettings.makeEmEnabled ||
               newSettings.hornEnabled != oldSettings.hornEnabled {
                self.rebuildBetViews()
            }
        }

        settingsVC.onShowGameDetails = { [weak self] in
            self?.showCurrentGameDetails()
        }

        settingsVC.onFixedRoll = { [weak self] total in
            self?.flipDiceContainer.rollFixedTotal(total)
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
        pointStack = PointStack()
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

        view.addSubview(pointStack)
        
        // Set content hugging priority low to allow pointStack to expand and fill available space
        pointStack.setContentHuggingPriority(.defaultLow, for: .vertical)
        // Set compression resistance to default so it can expand but won't compress unnecessarily
        pointStack.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        NSLayoutConstraint.activate([
            pointStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pointStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            pointStack.topAnchor.constraint(equalTo: betsContainerView.bottomAnchor, constant: 12)
            // Note: bottom constraint to fieldControl will be set in setupFieldControl()
        ])
    }

    func setupPassLineControls() {
        // Create pass line control
        passLineControl = PlainControl(title: "Pass Line")
        passLineControl.translatesAutoresizingMaskIntoConstraints = false
        passLineControl.getSelectedChipValue = { [weak self] in
            return self?.selectedChipValue ?? 1
        }
        passLineControl.getBalance = { [weak self] in
            return self?.balance ?? 200
        }
        passLineControl.onBetPlaced = { [weak self] amount in
            guard let self = self else { return }
            self.trackBet(amount: amount, type: .passLine)

            // Clear manual removal flag when new bet is placed
            self.passLineManuallyRemoved = false

            // Track bet for rebet functionality
            self.trackBetForRebet(amount: self.passLineControl.betAmount)

            // Track that pass line was the last line control used
            self.lastLineControlUsed = self.passLineControl

            self.balance -= amount
            self.updateCurrentBet()
            self.updateRollingState()
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

            // Mark that bet was manually removed to prevent rebet
            self.passLineManuallyRemoved = true

            // Always clear last line control used when bet is manually removed (even partially)
            // This prevents rebet from applying when bet is moved to another controller
            if self.lastLineControlUsed === self.passLineControl {
                self.lastLineControlUsed = nil
            }
        }
        
        passLineControl.addedBetCompletionHandler = { [weak self] in
            // Stop shimmer on both controls when bet is added to pass line
            self?.passLineControl.stopTitleShimmer()
            self?.dontPassControl.stopTitleShimmer()
        }
        
        passLineControl.canRemoveBet = { [weak self] in
            // Pass line bet cannot be removed once the point is set
            guard let self = self else { return true }
            return !self.game.isPointPhase
        }
        
        // Create pass line odds control
        passLineOddsControl = PlainControl(title: "Odds")
        passLineOddsControl.winningsAnimationDirection = .leading
        passLineOddsControl.translatesAutoresizingMaskIntoConstraints = false
        passLineOddsControl.isPerpetualBet = true
        passLineOddsControl.getSelectedChipValue = { [weak self] in
            return self?.selectedChipValue ?? 1
        }
        passLineOddsControl.getBalance = { [weak self] in
            return self?.balance ?? 200
        }
        passLineOddsControl.onBetPlaced = { [weak self] amount in
            guard let self = self else { return }
            // Check if this bet exceeds 10X the pass line bet
            let maxOddsBet = self.passLineControl.betAmount * 10
            let newOddsBet = self.passLineOddsControl.betAmount
            
            if newOddsBet > maxOddsBet {
                // Reverse the bet - remove the excess amount
                let excess = newOddsBet - maxOddsBet
                self.passLineOddsControl.betAmount = maxOddsBet
                self.balance += excess
                HapticsHelper.lightHaptic()
                // Track the actual bet amount (not the excess)
                self.trackBet(amount: maxOddsBet, type: .odds)
            } else {
                self.trackBet(amount: amount, type: .odds)
                self.balance -= amount
            }
            self.updateCurrentBet()
        }
        
        passLineOddsControl.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
            self.updateCurrentBet()
            // Dismiss drag chip tip once user removes a bet (with delay to let them see it)
            NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)
        }
        
        // Add controls directly to view
        view.addSubview(passLineControl)
        view.addSubview(passLineOddsControl)
        
        let spacing: CGFloat = 12
        
        // Calculate available width (will be updated in viewDidLayoutSubviews if needed)
        let availableWidth = view.bounds.width > 0 ? view.bounds.width - 32 : UIScreen.main.bounds.width - 32
        
        // Fixed widths: pass line 55%, odds 45% (with spacing between)
        let passLineWidth = availableWidth * 0.55
        let oddsWidth = availableWidth * 0.45 - spacing
        
        // Create width constraints for both controls (fixed, no animation)
        passLineControlWidthConstraint = passLineControl.widthAnchor.constraint(equalToConstant: passLineWidth)
        passLineOddsControlWidthConstraint = passLineOddsControl.widthAnchor.constraint(equalToConstant: oddsWidth)
        
        // Create leading constraint for odds control
        passLineOddsControlLeadingConstraint = passLineOddsControl.leadingAnchor.constraint(equalTo: passLineControl.trailingAnchor, constant: spacing)
        
        NSLayoutConstraint.activate([
            // Pass line control constraints
            passLineControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            passLineControl.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -24),
            passLineControl.heightAnchor.constraint(equalToConstant: 50),
            passLineControlWidthConstraint,
            
            // Odds control constraints
            passLineOddsControl.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -24),
            passLineOddsControl.heightAnchor.constraint(equalToConstant: 50),
            passLineOddsControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            passLineOddsControlWidthConstraint,
            passLineOddsControlLeadingConstraint
        ])
        
        // Initially update visibility/disabled state
        updatePassLineOddsVisibility()
    }
    
    private func updatePassLineOddsVisibility() {
        passLineManager.updateControlStates(
            isPointPhase: game.isPointPhase,
            hasPassLineBet: passLineControl.betAmount > 0,
            passLineControl: passLineControl,
            oddsControl: passLineOddsControl
        )

        // Update don't pass control state
        // Don't Pass bet can be added at any time, EXCEPT when it already has a bet AND point is set
        // Cannot be removed during point phase (perpetual bet)
        // Check if dontPassControl is initialized (it may not be during initial setup)
        if let dontPass = dontPassControl {
            let hasDontPassBet = dontPass.betAmount > 0
            // Disable placing additional bets only when bet exists AND point is set
            dontPass.isEnabled = !(hasDontPassBet && game.isPointPhase)
            dontPass.setBetRemovalDisabled(game.isPointPhase)  // Cannot remove during point phase
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

        view.addSubview(fieldControl)
        NSLayoutConstraint.activate([
            fieldControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fieldControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            fieldControl.bottomAnchor.constraint(equalTo: dontPassControl.topAnchor, constant: -12),
            // Connect pointStack bottom to fieldControl top to make pointStack flexible
            pointStack.bottomAnchor.constraint(equalTo: fieldControl.topAnchor, constant: -24)
        ])
    }

    func setupDontPassControl() {
        dontPassControl = DontPassControl(title: "Don't Pass")
        dontPassControl.translatesAutoresizingMaskIntoConstraints = false
        dontPassControl.isPerpetualBet = true  // Don't Pass stays until resolved (perpetual bet)
        dontPassControl.getSelectedChipValue = { [weak self] in
            return self?.selectedChipValue ?? 1
        }
        dontPassControl.getBalance = { [weak self] in
            return self?.balance ?? 200
        }
        dontPassControl.onBetPlaced = { [weak self] amount in
            guard let self = self else { return }
            self.trackBet(amount: amount, type: .dontPass)

            // Clear manual removal flag when new bet is placed
            self.dontPassManuallyRemoved = false

            // Track bet for rebet functionality (same as pass line)
            self.trackBetForRebet(amount: self.dontPassControl.betAmount)

            // Track that don't pass was the last line control used
            self.lastLineControlUsed = self.dontPassControl

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

        dontPassControl.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
            self.updateCurrentBet()
            self.updateRollingState()
            // Dismiss drag chip tip once user removes a bet (with delay to let them see it)
            NNTipManager.shared.dismissTip(CrapsTips.dragChipTip, afterDelay: 1.0)

            // Mark that bet was manually removed to prevent rebet
            self.dontPassManuallyRemoved = true

            // Always clear last line control used when bet is manually removed (even partially)
            // This prevents rebet from applying when bet is moved to another controller
            if self.lastLineControlUsed === self.dontPassControl {
                self.lastLineControlUsed = nil
            }
        }

        dontPassControl.addedBetCompletionHandler = { [weak self] in
            // Stop shimmer on both controls when bet is added to don't pass
            self?.passLineControl.stopTitleShimmer()
            self?.dontPassControl.stopTitleShimmer()
        }

        // Prevent bet removal when point is set (same as pass line)
        dontPassControl.canRemoveBet = { [weak self] in
            guard let self = self else { return true }
            return !self.gameStateManager.isPointPhase
        }

        view.addSubview(dontPassControl)
        NSLayoutConstraint.activate([
            dontPassControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            dontPassControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            dontPassControl.bottomAnchor.constraint(equalTo: passLineControl.topAnchor, constant: -12)
        ])
    }

    func setupBalanceView() {
        balanceView = BalanceView()
        
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
        
        // Height: chips are 70pt, plus 13pt for selection indicator below
        let chipSelectorHeight: CGFloat = 60
        
        NSLayoutConstraint.activate([
            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomStackView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6, constant: -16),
            chipSelector.heightAnchor.constraint(equalToConstant: chipSelectorHeight),
            chipSelector.widthAnchor.constraint(equalTo: bottomStackView.widthAnchor)
        ])
    }

    func setupFlipDice() {
        flipDiceContainer = FlipDiceContainer()
        flipDiceContainer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(flipDiceContainer)

        NSLayoutConstraint.activate([
            flipDiceContainer.leadingAnchor.constraint(equalTo: bottomStackView.trailingAnchor, constant: 16),
            flipDiceContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            flipDiceContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 0),
            flipDiceContainer.heightAnchor.constraint(equalToConstant: 80),
            flipDiceContainer.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.4, constant: -16)
        ])

        flipDiceContainer.onRollStarted = { [weak self] in
            // Do something when roll starts
        }

        flipDiceContainer.onRollComplete = { [weak self] die1, die2, total in

            // Handle winnings based on roll
            self?.handleRollResult(die1: die1, die2: die2, total: total)
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
            instructionLabel.showMessage("Please wait for the current roll to complete.", shouldFade: true)
        } else if !hasAnyBetPlaced() {
            // No bets placed - need to place any bet to roll
            instructionLabel.showMessage("Place a bet to roll the dice.", shouldFade: true)
        } else {
            // Rolling is disabled for some other reason (animations, etc.)
            instructionLabel.showMessage("Please wait...", shouldFade: true)
        }
    }
    
    private func updateRollingState() {
        gameStateManager.updateRollingState()
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
        pageControl.isUserInteractionEnabled = false // We'll handle scrolling via the scroll view

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
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Container view constraints - positioned below top stack view
            betsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            betsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            betsContainerView.topAnchor.constraint(equalTo: topStackView.bottomAnchor, constant: 12),
            // Note: bottom constraint to pointStack will be set in setupPointStack()
            
            // Scroll view constraints (within container)
            betsScrollView.leadingAnchor.constraint(equalTo: betsContainerView.leadingAnchor),
            betsScrollView.trailingAnchor.constraint(equalTo: betsContainerView.trailingAnchor),
            betsScrollView.topAnchor.constraint(equalTo: betsContainerView.topAnchor),
            betsScrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -8),
            betsScrollView.heightAnchor.constraint(equalToConstant: 148), // Title (20) + spacing (12) + 2 rows * 50 + 16 spacing
            
            // Page control constraints (within container)
            pageControl.centerXAnchor.constraint(equalTo: betsContainerView.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: betsContainerView.bottomAnchor),
            pageControl.heightAnchor.constraint(equalToConstant: 20),
            
            // Scroll content view constraints
            scrollContentView.leadingAnchor.constraint(equalTo: betsScrollView.contentLayoutGuide.leadingAnchor),
            scrollContentView.trailingAnchor.constraint(equalTo: betsScrollView.contentLayoutGuide.trailingAnchor),
            scrollContentView.topAnchor.constraint(equalTo: betsScrollView.contentLayoutGuide.topAnchor),
            scrollContentView.bottomAnchor.constraint(equalTo: betsScrollView.contentLayoutGuide.bottomAnchor),
            scrollContentView.heightAnchor.constraint(equalTo: betsScrollView.heightAnchor)
        ])

        // Store width constraint for later updates
        scrollContentWidthConstraint = scrollContentView.widthAnchor.constraint(equalTo: betsScrollView.widthAnchor, multiplier: 1)
        scrollContentWidthConstraint?.isActive = true

        // Build initial bet views based on settings
        rebuildBetViews()
    }

    private func rebuildBetViews() {
        // Get settings
        let settings = settingsManager.currentSettings

        // Check if bonus bet settings actually changed
        let currentSettings = (hardways: settings.hardwaysEnabled, makeEm: settings.makeEmEnabled, horn: settings.hornEnabled)
        if let previous = previousBonusBetSettings,
           previous == currentSettings {
            // Settings haven't changed, no need to rebuild
            return
        }

        // Update previous settings
        previousBonusBetSettings = currentSettings

        // Remove all existing bet views from scroll content view
        scrollContentView.subviews.forEach { $0.removeFromSuperview() }

        // Clear references
        hardwayView = nil
        makeEmView = nil
        hornView = nil

        var betViews: [UIView] = []

        // Add enabled bonus bet views
        if settings.hardwaysEnabled {
            let hardway = createBetView(title: "Hardways", controls: [
                (dieValue1: 3, dieValue2: 3, odds: "9:1"),
                (dieValue1: 4, dieValue2: 4, odds: "9:1"),
                (dieValue1: 2, dieValue2: 2, odds: "7:1"),
                (dieValue1: 5, dieValue2: 5, odds: "7:1")
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
            let horn = createBetView(title: "Horn", controls: [
                (dieValue1: 1, dieValue2: 1, odds: "30:1"),  // Snake eyes
                (dieValue1: 6, dieValue2: 6, odds: "30:1"),  // Boxcars
                (dieValue1: 1, dieValue2: 2, odds: "15:1"), // Ace-deuce
                (dieValue1: 5, dieValue2: 6, odds: "15:1")   // Five-six
            ], isPerpetual: false, betType: .horn)
            hornView = horn
            betViews.append(horn)
        }

        // Always add actions view last
        betViews.append(actionsView)

        // Update page control
        pageControl.numberOfPages = betViews.count

        // Update scroll content width multiplier
        scrollContentWidthConstraint?.isActive = false
        scrollContentWidthConstraint = scrollContentView.widthAnchor.constraint(
            equalTo: betsScrollView.widthAnchor,
            multiplier: CGFloat(betViews.count)
        )
        scrollContentWidthConstraint?.isActive = true

        // Add views to scroll content and set up constraints
        var previousView: UIView?
        var constraints: [NSLayoutConstraint] = []

        for (index, betView) in betViews.enumerated() {
            scrollContentView.addSubview(betView)
            betView.translatesAutoresizingMaskIntoConstraints = false

            if let previous = previousView {
                // Position after previous view
                constraints.append(betView.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 48))
            } else {
                // First view - position at leading edge
                constraints.append(betView.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor, constant: 24))
            }

            constraints.append(contentsOf: [
                betView.widthAnchor.constraint(equalTo: betsScrollView.widthAnchor, constant: -48),
                betView.topAnchor.constraint(equalTo: scrollContentView.topAnchor),
                betView.bottomAnchor.constraint(equalTo: scrollContentView.bottomAnchor)
            ])

            previousView = betView
        }

        NSLayoutConstraint.activate(constraints)

        // Force layout update
        view.layoutIfNeeded()
    }
    
    private func createBetView(title: String, controls: [(dieValue1: Int, dieValue2: Int, odds: String)], isPerpetual: Bool, betType: BetType) -> QuadBetView {
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
            let control = SmallControl(dieValue1: controlInfo.dieValue1, dieValue2: controlInfo.dieValue2, odds: controlInfo.odds)
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
        
        // Add controls to columns: left column gets first 2, right column gets last 2
        leftColumn.addArrangedSubview(betControls[0])
        leftColumn.addArrangedSubview(betControls[1])
        rightColumn.addArrangedSubview(betControls[2])
        rightColumn.addArrangedSubview(betControls[3])
        
        // Add columns to bet stack
        quadBetView.betStack.addArrangedSubview(leftColumn)
        quadBetView.betStack.addArrangedSubview(rightColumn)
        
        return quadBetView
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

        // Create Make Em Small control (4, 5, 6, 8, 9, 10)
        let makeEmSmallControl = MultiBetControl(
            title: "Make Em' Small",
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

        // Create Make Em Tall control (2, 3, 4, 10, 11, 12)
        let makeEmTallControl = MultiBetControl(
            title: "Make Em' Tall",
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

        // Create vertical stack for Make Em controls
        let makeEmStack = UIStackView(arrangedSubviews: [makeEmSmallControl, makeEmTallControl])
        makeEmStack.translatesAutoresizingMaskIntoConstraints = false
        makeEmStack.axis = .vertical
        makeEmStack.distribution = .fillEqually
        makeEmStack.spacing = 8
        container.addSubview(makeEmStack)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Title label
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 20),

            // Make Em stack
            makeEmStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            makeEmStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            makeEmStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            makeEmStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
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
        refreshBankrollButton.setTitle("Hit the ATM (Reload Bank Roll)", for: .normal)
        refreshBankrollButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        refreshBankrollButton.backgroundColor = HardwayColors.surfaceGray
        refreshBankrollButton.setTitleColor(.white, for: .normal)
        refreshBankrollButton.layer.cornerRadius = 16
        refreshBankrollButton.layer.borderWidth = 1.5
        refreshBankrollButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
        refreshBankrollButton.addTarget(self, action: #selector(refreshBankrollTapped), for: .touchUpInside)

        // Create vertical stack for all buttons
        let buttonStack = UIStackView(arrangedSubviews: [topButtonStack, refreshBankrollButton])
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

            // Height for each button (50pt for each, 8pt spacing between = 108pt total)
            toggleBetsButton.heightAnchor.constraint(equalToConstant: 50),
            collectBetsButton.heightAnchor.constraint(equalToConstant: 50),
            refreshBankrollButton.heightAnchor.constraint(equalToConstant: 50)
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
        topStackTopConstraint = topStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        
        NSLayoutConstraint.activate([
            topStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            topStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            topStackTopConstraint,
            instructionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 60), // Ensure space for 2 lines
            // Fixed width constraint for currentBetView to prevent compression
            // Width accounts for "Current Bet" title + "$999999" amount (approximately 120pt to be safe)
            currentBetView.widthAnchor.constraint(equalToConstant: 100)
        ])
        
        // Show initial message
        instructionLabel.showMessage("Place a Pass Line bet to begin!", shouldFade: false)
        
        // Update current bet initially
        updateCurrentBet()
    }
    
    private func updateCurrentBet() {
        let totalBet = getAllBettingControls().reduce(0) { $0 + $1.betAmount }
        currentBetView?.currentBet = totalBet
    }

    private func animateChipsAway(to destination: CGPoint, shouldFadeOut: Bool) {
        let allControls = getAllBettingControls()
        animateChipsAway(from: allControls, to: destination, shouldFadeOut: shouldFadeOut)
    }

    private func animateChipsAway(from controls: [PlainControl], to destination: CGPoint, shouldFadeOut: Bool) {
        for control in controls {
            guard control.betAmount > 0 else { continue }

            // Create a temporary chip view to animate
            let chipView = SmallBetChip()
            chipView.amount = control.betAmount
            chipView.translatesAutoresizingMaskIntoConstraints = true  // Enable frame-based layout
            chipView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)  // Set explicit frame size
            chipView.isHidden = false  // Ensure visibility
            view.addSubview(chipView)

            // Position at the control's bet view location
            let betPosition = control.getBetViewPosition(in: view)
            chipView.center = betPosition

            // Random delay for cascading effect
            let randomDelay = Double.random(in: 0...0.15)

            // Animate to destination, then optionally fade out
            UIView.animate(withDuration: 0.5, delay: randomDelay, options: .curveEaseIn, animations: {
                chipView.center = destination
                chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            }, completion: { _ in
                UIView.animate(withDuration: 0.2) {
                    if shouldFadeOut {
                        chipView.alpha = 0
                    }
                } completion: { _ in
                    chipView.removeFromSuperview()
                }
            })

            // Clear the bet from the control
            control.betAmount = 0

            // Reset hit numbers for Make Em bets
            if let makeEmControl = control as? MultiBetControl {
                makeEmControl.resetHitNumbers()
            }
        }

        // Update current bet after clearing bets
        updateCurrentBet()
    }

    // Structure to track winning bets
    private struct WinningBet {
        let control: PlainControl
        let winAmount: Int
        let odds: Double
        let isBonus: Bool
        let description: String?
    }
    
    private func handleRollResult(die1: Int, die2: Int, total: Int) {
        // Increment roll count
        sessionManager.incrementRollCount()
        
        // Dismiss come out roll tip once user rolls for the first time (with delay)
        NNTipManager.shared.dismissTip(CrapsTips.comeOutRollTip)

        // Track balance before roll for loss chasing detection
        let balanceBeforeRoll = balance
        sessionManager.updateLastBalanceBeforeRoll(balanceBeforeRoll)

        pendingBetSizeSnapshot = getAllBettingControls().reduce(0) { $0 + $1.betAmount }

        // Check if we're in point phase BEFORE processing the roll
        // (processRoll changes phase back to comeOut on sevenOut)
        let wasInPointPhase = game.isPointPhase

        // Capture the current point BEFORE processing the roll (it will be cleared by processRoll)
        let currentPointNumber = game.currentPoint
        
        // Process game logic
        let event = game.processRoll(total)

        if total == 7 {
            sessionManager.trackSevenRolled()
        }
        
        // Check for loss chasing: if balance decreased, mark for tracking
        let balanceAfterRoll = balance
        if balanceAfterRoll < balanceBeforeRoll {
            sessionManager.updateLastBalanceBeforeRoll(balanceBeforeRoll)
            // Will check if bets are placed after this loss in trackBet method
        }
        
        // Collect all win messages and winning bets
        var allWinMessages: [String] = []
        var winningBets: [WinningBet] = []

        // Handle hardway bets - they lose on 7, but ONLY during point phase (not come out roll)
        // Hardway bets are "off" during come out roll
        if total == 7 && wasInPointPhase {
            handleHardwayLoss()
        } else if total != 7 {
            // Check hardway bets for wins/losses (only when not a 7)
            let (hardwayMessages, hardwayWins) = handleHardwayBets(die1: die1, die2: die2, total: total)
            allWinMessages.append(contentsOf: hardwayMessages)
            winningBets.append(contentsOf: hardwayWins)
        }
        
        // Handle horn bets - one-time bets that win on specific combinations
        let (hornMessages, hornWins) = handleHornBets(die1: die1, die2: die2, total: total)
        allWinMessages.append(contentsOf: hornMessages)
        winningBets.append(contentsOf: hornWins)

        // Handle Make Em bets - progressive bets that require hitting all target numbers
        let (makeEmMessages, makeEmWins) = handleMakeEmBets(total: total)
        allWinMessages.append(contentsOf: makeEmMessages)
        winningBets.append(contentsOf: makeEmWins)

        // Handle pass line outcomes based on game event
        switch event {
        case .passLineWin:
            // Come out roll 7 or 11 - win pass line
            let passLineBetAmount = passLineControl.betAmount // Capture before clearing
            handlePassLineWin()
            // Only mention Pass Line win if there was actually a bet
            if passLineBetAmount > 0 {
                allWinMessages.insert("You rolled \(total)! Pass Line wins!", at: 0)
                let winAmount = passLineControl.betAmount
                winningBets.append(WinningBet(control: passLineControl, winAmount: winAmount, odds: 1.0, isBonus: false, description: nil))
            }

        case .passLineLoss:
            // Come out roll 2, 3, or 12 - lose pass line (but don't pass may win or push)
            let passLineBetAmount = passLineControl.betAmount // Capture before clearing
            handlePassLineLoss()

            // Only mention Pass Line loss if there was actually a bet
            // Don't Pass messages are handled separately in handleDontPassBet
            if passLineBetAmount > 0 {
                instructionLabel.showMessage("Craps! You rolled \(total). Pass Line loses.", shouldFade: false)
            } else {
                // No Pass Line bet, but Don't Pass messages will be handled separately if needed
                instructionLabel.showMessage("Craps! You rolled \(total).", shouldFade: false)
            }

            // Show loss container for Pass Line if there was a bet and bets are ON
            if passLineBetAmount > 0 && betsAreOn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.showBetResult(amount: passLineBetAmount, isWin: false)
                }
            }

        case .pointEstablished(let number):
            // Point established
            pointStack.setPoint(number)
            instructionLabel.showMessage("Point is \(number)! Roll the point again to win.", shouldFade: false)
            updatePassLineOddsVisibility()

        case .pointMade:
            // Point was made - win pass line and odds, lose don't pass
            // Capture bet amounts before clearing
            let passLineBetAmount = passLineControl.betAmount // Capture before clearing
            let hadOddsBet = passLineOddsControl.betAmount > 0
            let oddsBetAmount = passLineOddsControl.betAmount // Capture before any changes
            let dontPassBetAmount = dontPassControl.betAmount // Capture before clearing

            handlePassLineWin()
            handlePassLineOddsWin(pointNumber: currentPointNumber, capturedBetAmount: oddsBetAmount)
            pointStack.clearPoint()
            
            // Only mention Pass Line win if there was actually a bet
            if passLineBetAmount > 0 {
                allWinMessages.insert("You hit the point! Pass Line wins!", at: 0)
            }
            
            // Dismiss hit point to win tip once user hits the point
            NNTipManager.shared.dismissTip(CrapsTips.hitPointToWinTip)
            if passLineControl.betAmount > 0 {
                let winAmount = passLineControl.betAmount
                winningBets.append(WinningBet(control: passLineControl, winAmount: winAmount, odds: 1.0, isBonus: false, description: "Winner!"))
            }
            // Add pass line odds win to winning bets
            if hadOddsBet, let point = currentPointNumber {
                let oddsMultiplier: Double
                switch point {
                case 4, 10: oddsMultiplier = 2.0
                case 5, 9: oddsMultiplier = 1.5
                case 6, 8: oddsMultiplier = 1.2
                default: oddsMultiplier = 1.0
                }
                let winAmount = Int(Double(oddsBetAmount) * oddsMultiplier)
                winningBets.append(WinningBet(control: passLineOddsControl, winAmount: winAmount, odds: oddsMultiplier, isBonus: false, description: nil))
            }
            // Show loss container for Don't Pass if there was a bet and bets are ON
            if dontPassBetAmount > 0 && betsAreOn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.showBetResult(amount: dontPassBetAmount, isWin: false)
                }
            }
            // Update visibility/disabled state immediately (odds control stays visible, just disabled)
            updatePassLineOddsVisibility()
            if let point = currentPointNumber {
                sessionManager.trackPointMade(number: point)
            }

        case .sevenOut:
            // Seven out - lose pass line and all place bets
            let passLineBetAmount = passLineControl.betAmount // Capture before clearing
            let hadOddsBet = passLineOddsControl.betAmount > 0
            handlePassLineLoss()
            handlePassLineOddsLoss()
            handleSevenOut()
            pointStack.clearPoint()
            
            // Adjust message based on whether there was a pass line bet
            if passLineBetAmount > 0 {
                instructionLabel.showMessage("*$@#! Seven out! Place a new Pass Line bet to continue.", shouldFade: false)
            } else {
                instructionLabel.showMessage("*$@#! Seven out!", shouldFade: false)
            }
            // Update visibility/disabled state immediately (odds control stays visible, just disabled)
            updatePassLineOddsVisibility()

        case .none:
            // No pass line action
            break
        }

        // Handle Don't Pass bet (opposite of Pass Line)
        var dontPassDidLose = false
        if dontPassControl.betAmount > 0 {
            let dontPassResult = handleDontPassBet(total: total, event: event, wasInPointPhase: wasInPointPhase, currentPoint: currentPointNumber)
            if let message = dontPassResult.message {
                allWinMessages.append(message)
            }
            if let win = dontPassResult.winningBet {
                winningBets.append(win)
            }
            dontPassDidLose = dontPassResult.didLose
        }

        // Handle other bets (field, point bets)
        // Pass the event so we know if this roll established the point
        let (otherBetMessages, otherWins) = handleOtherBets(total, event: event)
        allWinMessages.append(contentsOf: otherBetMessages)
        winningBets.append(contentsOf: otherWins)
        
        // Show bet result containers grouped by bet type
        if !winningBets.isEmpty {
            showGroupedBetResults(winningBets: winningBets)
            // Balance will be updated incrementally as each chip reaches balance view
            // See animateWinnings completion handler
        }
        
        // Show loss container if seven out
        // Note: Don't Pass WINS on seven out, so exclude it from losses
        if case .sevenOut = event {
            var losingBets = 0
            for control in getAllBettingControls() {
                // Don't Pass wins on seven out, so don't include it in losses
                if control === dontPassControl {
                    continue
                }
                losingBets += control.betAmount
            }

            // Only show loss container if bets are ON
            if losingBets > 0 && betsAreOn {
                showBetResult(amount: losingBets, isWin: false)
            }
        }

        // Show all win messages combined if any
        if !allWinMessages.isEmpty {
            let combinedMessage = allWinMessages.joined(separator: " • ")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                instructionLabel.showMessage(combinedMessage, shouldFade: false)
            }
        }

        // Clear one-time bets after roll completes (excluding winning bets)
        clearOneTimeBets(excludingWinningControls: winningBets.map { $0.control })
        
        // Update rolling state after all animations complete
        // For seven out, wait longer for all chip animations to complete
        // For pointMade, wait for bet collection animation to complete (or don't pass loss)
        // For passLineLoss, wait for chip removal animation to complete (reduced delay for faster rebet)
        // For passLineWin, check if don't pass lost and wait for chip removal
        let delay: TimeInterval
        if case .sevenOut = event {
            // Seven out: chips animate away starting at 0.5-0.6s, animation takes 0.5s + fade 0.2s = ~1.3s total
            delay = 2.0  // Wait for all chip removal animations to complete
        } else if case .pointMade = event {
            // Point made: pass line wins, but don't pass loses if there was a bet
            // Don't pass loss animation starts at 0.5s, takes 0.5-0.7s = ~1.2s total
            if dontPassDidLose {
                // Don't pass bet lost - wait for chip removal animation
                delay = 1.5  // Wait for chip removal animation to complete
            } else {
                // No don't pass bet, just pass line win - normal delay
                delay = 1.5  // Wait for bet collection animation to complete
            }
        } else if case .passLineLoss = event {
            // Pass line loss: chips animate away starting at 0.5s, animation takes 0.5s + fade 0.2s = ~1.2s total
            delay = 1.0  // Reduced delay for faster rebet
        } else if case .passLineWin = event {
            // Pass line win on come-out (7 or 11), but don't pass loses if there was a bet
            if dontPassDidLose {
                // Don't pass bet lost - wait for chip removal animation
                delay = 1.5  // Wait for chip removal animation to complete
            } else {
                delay = 0.1  // Small delay to ensure game state is fully updated
            }
        } else {
            delay = 0.1  // Small delay to ensure game state is fully updated
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.recordBalanceSnapshot()

            // Apply rebet if needed (after all animations complete)
            self?.applyRebetIfNeeded()

            self?.updateRollingState()
            
            // Check if drag chip tip should be shown after roll completes
            self?.showTips()
        }
    }
    
    
    private func animateWinnings(for control: PlainControl, odds: Double) {
        guard control.betAmount > 0 else { return }

        let winAmount = Int(Double(control.betAmount) * odds)

        // Use ChipAnimationHelper for consistent animations with control-specific offsets
        chipAnimator.animateWinnings(
            for: control,
            winAmount: winAmount
        ) { [weak self] amount in
            self?.balance += amount
        }
    }

    private func handlePassLineWin() {
        guard passLineControl.betAmount > 0 else { return }

        // If bets are OFF, don't process the win
        guard betsAreOn else {
            return
        }

        // Process win through manager
        let result = passLineManager.processPassLineWin(betAmount: passLineControl.betAmount)

        // 1. Animate winnings from house
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            animateWinnings(for: passLineControl, odds: result.oddsMultiplier)
        }
        // 2. Animate original bet being collected (after slight delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
            guard let self else { return }
            animateBetCollection(for: passLineControl)
        }
    }
    
    private func handlePassLineOddsWin(pointNumber: Int?, capturedBetAmount: Int) {
        guard capturedBetAmount > 0 else { return }
        guard let pointNumber = pointNumber else { return }

        // If bets are OFF, don't process the win
        guard betsAreOn else {
            return
        }

        // Process win through manager
        let result = passLineManager.processPassLineOddsWin(betAmount: capturedBetAmount, point: pointNumber)

        // Set the bet amount once before animations start
        passLineOddsControl.betAmount = capturedBetAmount
        passLineOddsControl.isHidden = false

        // Animate winnings and original bet together (matching field control pattern)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.animateWinningsAndBetTogether(for: self.passLineOddsControl, odds: result.oddsMultiplier)
        }
    }
    
    private func handlePassLineOddsLoss() {
        guard passLineOddsControl.betAmount > 0 else { return }

        // If bets are OFF, don't process the loss
        guard betsAreOn else {
            return
        }

        // Process loss through manager
        let betAmount = passLineOddsControl.betAmount
        passLineManager.processPassLineOddsLoss(betAmount: betAmount)

        // Disable rolling immediately to prevent re-rolling before bet is cleared
        flipDiceContainer.disableRolling()

        // Store bet position before any changes
        let betPosition = passLineOddsControl.getBetViewPosition(in: view)

        // Hide the betView immediately by setting alpha to 0
        passLineOddsControl.betView.alpha = 0

        // Create the animation chip immediately (before clearing bet amount)
        let chipView = SmallBetChip()
        chipView.amount = betAmount
        chipView.translatesAutoresizingMaskIntoConstraints = true
        chipView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        chipView.isHidden = false
        view.addSubview(chipView)
        chipView.center = betPosition

        // Now clear the bet amount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self else { return }
            self.passLineOddsControl.betAmount = 0
            self.updateCurrentBet()
        }

        // Animate chip away after the normal delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let randomDelay = Double.random(in: 0...0.15)

            UIView.animate(withDuration: 0.5, delay: randomDelay, options: .curveEaseIn, animations: {
                chipView.center = CGPoint(x: self.view.bounds.width / 2, y: 0)
                chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            }, completion: { _ in
                UIView.animate(withDuration: 0.2) {
                    chipView.alpha = 0
                } completion: { _ in
                    chipView.removeFromSuperview()
                }
            })
        }
    }

    private func handlePassLineLoss() {
        guard passLineControl.betAmount > 0 else { return }

        // If bets are OFF, don't process the loss
        guard betsAreOn else {
            return
        }

        // Clear manual removal flag since this is a game outcome loss (not manual removal)
        // This allows rebet to apply after game outcome losses
        passLineManuallyRemoved = false

        // Process loss through manager
        let betAmount = passLineControl.betAmount
        passLineManager.processPassLineLoss(betAmount: betAmount)

        // Disable rolling immediately to prevent re-rolling before bet is cleared
        flipDiceContainer.disableRolling()

        // Store bet position before any changes
        let betPosition = passLineControl.getBetViewPosition(in: view)

        // Hide the betView immediately by setting alpha to 0
        passLineControl.betView.alpha = 0

        // Clear the bet amount immediately (betView is already hidden)
        passLineControl.betAmount = 0
        updateCurrentBet()

        // Create the animation chip immediately (after clearing bet amount)
        // This ensures seamless transition - chip appears exactly where betView was
        let chipView = SmallBetChip()
        chipView.amount = betAmount
        chipView.translatesAutoresizingMaskIntoConstraints = true
        chipView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        chipView.isHidden = false
        view.addSubview(chipView)
        chipView.center = betPosition

        // Animate chip away after the normal delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let randomDelay = Double.random(in: 0...0.15)

            UIView.animate(withDuration: 0.5, delay: randomDelay, options: .curveEaseIn, animations: {
                chipView.center = CGPoint(x: self.view.bounds.width / 2, y: 0)
                chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            }, completion: { _ in
                UIView.animate(withDuration: 0.2) {
                    chipView.alpha = 0
                } completion: { _ in
                    chipView.removeFromSuperview()
                }
            })
        }
    }

    private func handleDontPassBet(total: Int, event: GameEvent, wasInPointPhase: Bool, currentPoint: Int?) -> (message: String?, winningBet: WinningBet?, didLose: Bool) {
        guard dontPassControl.betAmount > 0 else { return (nil, nil, false) }

        let betAmount = dontPassControl.betAmount

        // Come-out roll logic
        if !wasInPointPhase {
            let result = specialBetsManager.evaluateDontPassComeOutRoll(total: total, betAmount: betAmount)

            if result.isWin {
                // If bets are OFF, don't process the win
                guard betsAreOn else {
                    return (nil, nil, false)
                }

                // Don't Pass wins on 2 or 3 (pays 1:1)
                let winAmount = result.winAmount

                // 1. Animate winnings from house
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.animateWinnings(for: self.dontPassControl, odds: result.oddsMultiplier)
                }

                // 2. Animate original bet being collected (after slight delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                    guard let self = self else { return }
                    self.animateBetCollection(for: self.dontPassControl)
                }

                let message = "Don't Pass wins on \(total)!"
                let winningBet = WinningBet(control: dontPassControl, winAmount: winAmount, odds: result.oddsMultiplier, isBonus: false, description: nil)
                return (message, winningBet, false)

            } else if result.isPush {
                // Push on 12 - return bet to player
                let message = "Push! 12 is a tie for Don't Pass."
                return (message, nil, false)

            } else if total == 7 || total == 11 {
                // Don't Pass loses on 7 or 11 during come-out
                handleDontPassLoss(betAmount: betAmount)
                return (nil, nil, true)  // Return true to indicate loss
            }
            // Point established (4, 5, 6, 8, 9, 10) - no action yet
            return (nil, nil, false)
        }

        // Point phase logic
        if let point = currentPoint {
            let result = specialBetsManager.evaluateDontPassPointPhase(total: total, point: point, betAmount: betAmount)

            if result.isWin {
                // If bets are OFF, don't process the win
                guard betsAreOn else {
                    return (nil, nil, false)
                }

                // Don't Pass wins on 7 before point (pays 1:1)
                let winAmount = result.winAmount

                // 1. Animate winnings from house
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.animateWinnings(for: self.dontPassControl, odds: result.oddsMultiplier)
                }

                // 2. Animate original bet being collected (after slight delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                    guard let self = self else { return }
                    self.animateBetCollection(for: self.dontPassControl)
                }

                let message = "Don't Pass wins on 7!"
                let winningBet = WinningBet(control: dontPassControl, winAmount: winAmount, odds: result.oddsMultiplier, isBonus: false, description: nil)
                return (message, winningBet, false)

            } else if total == point {
                // Don't Pass loses when point is made
                handleDontPassLoss(betAmount: betAmount)
                return (nil, nil, true)  // Return true to indicate loss
            }
        }

        // No action
        return (nil, nil, false)
    }

    private func handleDontPassLoss(betAmount: Int) {
        guard betAmount > 0 else { return }

        // If bets are OFF, don't process the loss
        guard betsAreOn else {
            return
        }

        // Clear manual removal flag since this is a game outcome loss (not manual removal)
        // This allows rebet to apply after game outcome losses
        dontPassManuallyRemoved = false

        // Disable rolling immediately to prevent re-rolling before bet is cleared
        flipDiceContainer.disableRolling()

        // Use ChipAnimationHelper to animate chips away
        chipAnimator.animateChipsAway(from: dontPassControl) { [weak self] in
            self?.updateCurrentBet()
        }
    }

    private func handleSevenOut() {
        // If bets are OFF, don't process losses for place bets or Make Em bets
        guard betsAreOn else { return }

        // Collect all point controls with bets
        var controlsWithBets: [PlainControl] = []
        for pointNumber in pointStack.pointNumbers {
            if let pointControl = pointStack.getPointControl(for: pointNumber),
               pointControl.betAmount > 0 {
                controlsWithBets.append(pointControl)
            }
        }

        // Collect all Make Em controls with bets
        if let makeEmStack = makeEmView?.subviews.first(where: { $0 is UIStackView }) as? UIStackView {
            for arrangedSubview in makeEmStack.arrangedSubviews {
                if let makeEmControl = arrangedSubview as? MultiBetControl,
                   makeEmControl.betAmount > 0 {
                    controlsWithBets.append(makeEmControl)
                }
            }
        }

        guard !controlsWithBets.isEmpty else { return }

        // Animate all place bets and Make Em bets flying away (losing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            animateChipsAway(
                from: controlsWithBets,
                to: CGPoint(x: view.bounds.width / 2, y: 0),
                shouldFadeOut: true
            )
        }
    }
    
    private func handleHardwayLoss() {
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
                       hardwayControl.betAmount > 0 {
                        hardwayControlsWithBets.append(hardwayControl)
                    }
                }
            }
        }

        guard !hardwayControlsWithBets.isEmpty else { return }

        // Animate all hardway bets flying away (losing on 7)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            animateChipsAway(
                from: hardwayControlsWithBets,
                to: CGPoint(x: view.bounds.width / 2, y: 0),
                shouldFadeOut: true
            )
        }
    }
    
    private func handleHardwayBets(die1: Int, die2: Int, total: Int) -> ([String], [WinningBet]) {
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
                      hardwayControl.betAmount > 0 else { continue }

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
                    winningBets.append(WinningBet(
                        control: hardwayControl,
                        winAmount: result.winAmount!,
                        odds: result.oddsMultiplier!,
                        isBonus: true,
                        description: "Hard \(result.total)"
                    ))

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self else { return }
                        animateWinnings(for: hardwayControl, odds: result.oddsMultiplier!)
                    }

                    // Collect the original bet after winnings
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self else { return }
                        animateBetCollection(for: hardwayControl)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                animateChipsAway(
                    from: losingControls,
                    to: CGPoint(x: view.bounds.width / 2, y: 0),
                    shouldFadeOut: true
                )
            }
        }
        
        // Return win messages and winning bets
        return (winMessages, winningBets)
    }
    
    private func handleHornBets(die1: Int, die2: Int, total: Int) -> ([String], [WinningBet]) {
        var winMessages: [String] = []
        var winningBets: [WinningBet] = []

        guard let hornView = hornView else { return (winMessages, winningBets) }

        // Check each horn bet
        // Note: hornView.betStack has 2 columns (UIStackViews), each containing horn controls
        for arrangedSubview in hornView.betStack.arrangedSubviews {
            guard let columnStack = arrangedSubview as? UIStackView else { continue }
            for columnSubview in columnStack.arrangedSubviews {
                guard let hornControl = columnSubview as? SmallControl,
                      hornControl.betAmount > 0 else { continue }

                // Evaluate horn bet using manager
                let result = specialBetsManager.evaluateHornBet(
                    die1: die1,
                    die2: die2,
                    hornDieValue1: hornControl.dieValue1,
                    hornDieValue2: hornControl.dieValue2,
                    betAmount: hornControl.betAmount,
                    oddsString: hornControl.odds
                )

                if result.isWin {
                    // If bets are OFF, don't process horn wins
                    guard betsAreOn else { continue }

                    // Horn bet wins!
                    // Collect bet for winnings container
                    winningBets.append(WinningBet(
                        control: hornControl,
                        winAmount: result.winAmount!,
                        odds: result.oddsMultiplier!,
                        isBonus: true,
                        description: result.hornName
                    ))

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self else { return }
                        animateWinnings(for: hornControl, odds: result.oddsMultiplier!)
                    }

                    // Collect the original bet after winnings
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self else { return }
                        animateBetCollection(for: hornControl)
                    }

                    winMessages.append("\(result.hornName) wins! You won $\(result.winAmount!)!")
                }
            }
        }
        
        // Return win messages and winning bets
        return (winMessages, winningBets)
    }

    private func handleMakeEmBets(total: Int) -> ([String], [WinningBet]) {
        var winMessages: [String] = []
        var winningBets: [WinningBet] = []

        guard let makeEmView = makeEmView else { return (winMessages, winningBets) }

        // Find the Make Em stack within makeEmView
        guard let makeEmStack = makeEmView.subviews.first(where: { $0 is UIStackView }) as? UIStackView else {
            return (winMessages, winningBets)
        }

        // Check each Make Em control (Make Em Small and Make Em Tall)
        for arrangedSubview in makeEmStack.arrangedSubviews {
            guard let makeEmControl = arrangedSubview as? MultiBetControl,
                  makeEmControl.betAmount > 0 else { continue }

            // Determine which Make Em bet this is based on the numbers
            let isMakeEmSmall = makeEmControl.numbers == [4, 5, 6, 8, 9, 10]
            let betName = isMakeEmSmall ? "Make Em Small" : "Make Em Tall"

            // Evaluate Make Em bet using manager
            let result = specialBetsManager.evaluateMakeEmBet(
                total: total,
                betName: betName,
                targetNumbers: makeEmControl.numbers,
                hitNumbers: makeEmControl.hitNumbers,
                betAmount: makeEmControl.betAmount,
                oddsString: makeEmControl.odds
            )

            // Update hit numbers on the control if a new number was hit
            if result.isNewNumber {
                makeEmControl.markNumberAsHit(total)
            }

            if result.isWin {
                // If bets are OFF, don't process Make Em wins
                guard betsAreOn else { continue }

                // Make Em bet wins!
                winningBets.append(WinningBet(
                    control: makeEmControl,
                    winAmount: result.winAmount!,
                    odds: result.oddsMultiplier!,
                    isBonus: true,
                    description: betName
                ))

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self else { return }
                    animateWinningsAndBetTogether(for: makeEmControl, odds: result.oddsMultiplier!)
                }

                // Reset hit numbers after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak makeEmControl] in
                    makeEmControl?.resetHitNumbers()
                }

                winMessages.append("\(betName) wins! You won $\(result.winAmount!)!")
            }
        }

        return (winMessages, winningBets)
    }

    private func clearOneTimeBets(excludingWinningControls: [PlainControl] = []) {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
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

    private func handleOtherBets(_ total: Int, event: GameEvent) -> ([String], [WinningBet]) {
        var winMessages: [String] = []
        var winningBets: [WinningBet] = []

        // Check field bet using manager
        if fieldControl.betAmount > 0 {
            let result = specialBetsManager.evaluateFieldBet(total: total, betAmount: fieldControl.betAmount)

            if result.isWin {
                // If bets are OFF, don't process the win
                guard betsAreOn else {
                    return (winMessages, winningBets)
                }

                // Collect bet for winnings container
                winningBets.append(WinningBet(control: fieldControl, winAmount: result.winAmount, odds: result.oddsMultiplier, isBonus: false, description: nil))

                // Animate winnings and original bet together (field is a one-time bet)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
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
           pointControl.betAmount > 0 {
            // If bets are OFF, don't process the win
            guard betsAreOn else {
                return (winMessages, winningBets)
            }

            let betAmount = pointControl.betAmount
            let winAmount = Int(Double(betAmount) * pointControl.oddsMultiplier)

            // Collect bet for winnings container
            winningBets.append(WinningBet(control: pointControl, winAmount: winAmount, odds: pointControl.oddsMultiplier, isBonus: false, description: nil))

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                animateWinnings(for: pointControl, odds: pointControl.oddsMultiplier)
            }

            // Add place bet win message
            winMessages.append("Place bet on \(total) wins! You won $\(winAmount)!")
        }
        
        // Return win messages and winning bets
        return (winMessages, winningBets)
    }


    // MARK: - Bet Result Display
    
    /// Group winning bets by type and show separate containers
    /// - Pass Line + Odds: Combined into one container
    /// - Each Horn bet: Separate container
    /// - Each Hardway bet: Separate container
    /// - Each Make Em bet: Separate container
    /// - Field + Point bets: Combined into one container
    private func showGroupedBetResults(winningBets: [WinningBet]) {
        // Group bets by type
        var passLineOddsBets: [WinningBet] = []
        var dontPassBets: [WinningBet] = []
        var hornBets: [WinningBet] = []
        var hardwayBets: [WinningBet] = []
        var makeEmBets: [WinningBet] = []
        var fieldPointBets: [WinningBet] = []

        for bet in winningBets {
            // Check if it's pass line or odds
            if bet.control === passLineControl || bet.control === passLineOddsControl {
                passLineOddsBets.append(bet)
            }
            // Check if it's don't pass
            else if bet.control === dontPassControl {
                dontPassBets.append(bet)
            }
            // Check if it's a Make Em bet (MultiBetControl)
            else if bet.control is MultiBetControl {
                makeEmBets.append(bet)
            }
            // Check if it's a horn bet (SmallControl that's a bonus)
            // Horn bets are: (1,1), (6,6), (1,2), (5,6) - not doubles except for 1,1 and 6,6
            // Hardway bets are always doubles: (2,2), (3,3), (4,4), (5,5)
            else if bet.isBonus && bet.control is SmallControl {
                if let smallControl = bet.control as? SmallControl {
                    let die1 = smallControl.dieValue1
                    let die2 = smallControl.dieValue2
                    // Horn bets: (1,1), (6,6), (1,2), (5,6) - check for these specific combinations
                    let isHornBet = (die1 == 1 && die2 == 1) || (die1 == 6 && die2 == 6) ||
                                    (die1 == 1 && die2 == 2) || (die1 == 2 && die2 == 1) ||
                                    (die1 == 5 && die2 == 6) || (die1 == 6 && die2 == 5)
                    if isHornBet {
                        hornBets.append(bet)
                    } else {
                        // Must be hardway (doubles: 2,2 or 3,3 or 4,4 or 5,5)
                        hardwayBets.append(bet)
                    }
                }
            }
            // Check if it's field or point bet
            else if bet.control === fieldControl || bet.control is PointControl {
                fieldPointBets.append(bet)
            }
        }
        
        var delay: TimeInterval = 0.3

        // Show Pass Line + Odds combined
        if !passLineOddsBets.isEmpty {
            let totalWinnings = passLineOddsBets.reduce(0) { $0 + $1.winAmount }
            let hasBonus = passLineOddsBets.contains { $0.isBonus }
            let description = passLineOddsBets.first(where: { $0.isBonus })?.description ??
                             passLineOddsBets.first(where: { $0.description != nil })?.description
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showBetResult(amount: totalWinnings, isWin: true, showBonus: hasBonus, description: description)
            }
            delay += 0.2
        }

        // Show Don't Pass wins
        if !dontPassBets.isEmpty {
            let totalWinnings = dontPassBets.reduce(0) { $0 + $1.winAmount }
            let hasBonus = dontPassBets.contains { $0.isBonus }
            let description = dontPassBets.first(where: { $0.isBonus })?.description ??
                             dontPassBets.first(where: { $0.description != nil })?.description
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showBetResult(amount: totalWinnings, isWin: true, showBonus: hasBonus, description: description)
            }
            delay += 0.2
        }
        
        // Show each Horn bet separately
        for hornBet in hornBets {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showBetResult(amount: hornBet.winAmount, isWin: true, showBonus: true, description: hornBet.description)
            }
            delay += 0.2
        }
        
        // Show each Hardway bet separately
        for hardwayBet in hardwayBets {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showBetResult(amount: hardwayBet.winAmount, isWin: true, showBonus: true, description: hardwayBet.description)
            }
            delay += 0.2
        }

        // Show each Make Em bet separately
        for makeEmBet in makeEmBets {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showBetResult(amount: makeEmBet.winAmount, isWin: true, showBonus: true, description: makeEmBet.description)
            }
            delay += 0.2
        }

        // Show Field + Point bets combined
        if !fieldPointBets.isEmpty {
            let totalWinnings = fieldPointBets.reduce(0) { $0 + $1.winAmount }
            let hasBonus = fieldPointBets.contains { $0.isBonus }
            let description = fieldPointBets.first(where: { $0.isBonus })?.description ?? 
                             fieldPointBets.first(where: { $0.description != nil })?.description
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showBetResult(amount: totalWinnings, isWin: true, showBonus: hasBonus, description: description)
            }
        }
    }

    // MARK: - Rebet Functionality

    private func trackBetForRebet(amount: Int) {
        passLineManager.trackBetForRebet(amount: amount)
    }

    private func applyRebetIfNeeded() {
        // Don't apply rebet if either control had a bet manually removed
        // This prevents rebet when user manually removed a bet, even if lastLineControlUsed is set
        if passLineManuallyRemoved || dontPassManuallyRemoved {
            return
        }
        
        // Determine which control to apply rebet to based on last used
        let targetControl: PlainControl
        let currentBet: Int

        if let lastUsed = lastLineControlUsed {
            // Use whichever control was last used (pass line or don't pass)
            targetControl = lastUsed
            currentBet = lastUsed.betAmount
            
            // Critical check: if the control has no bet now, don't rebet
            // This prevents rebet when bet was manually moved/removed before the roll
            if currentBet == 0 {
                return
            }
            
            // Double-check manual removal flags for the specific control
            if (targetControl === passLineControl && passLineManuallyRemoved) ||
               (targetControl === dontPassControl && dontPassManuallyRemoved) {
                return
            }
        } else {
            // Check which control currently has a bet
            if passLineControl.betAmount > 0 {
                targetControl = passLineControl
                currentBet = passLineControl.betAmount
            } else if dontPassControl.betAmount > 0 {
                targetControl = dontPassControl
                currentBet = dontPassControl.betAmount
            } else {
                // No active line bet and no history - don't apply rebet
                return
            }
        }

        // Calculate rebet amount to apply
        if let rebetAmount = passLineManager.calculateRebetAmount(currentBetAmount: currentBet, balance: balance) {
            // Deduct from balance and set bet on the control that was last used
            balance -= rebetAmount
            targetControl.setDirectBet(rebetAmount)
            updateCurrentBet()

            // Update lastLineControlUsed to reflect where rebet was applied
            lastLineControlUsed = targetControl
        }
    }

    // MARK: - Animation Methods

    /// Animate winnings and original bet together (for one-time bets like field)
    /// Uses ChipAnimationHelper for consistent animations
    private func animateWinningsAndBetTogether(for control: PlainControl, odds: Double) {
        guard control.betAmount > 0 else { return }
        
        let betAmount = control.betAmount
        let winAmount = Int(Double(betAmount) * odds)
        let offset = control.winningsAnimationOffset
        
        chipAnimator.animateBonusBetWinningsWithOffset(
            for: control,
            betAmount: betAmount,
            winAmount: winAmount,
            offset: offset
        ) { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
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

        // Use ChipAnimationHelper for consistent animations
        chipAnimator.animateBetCollection(for: control) { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
            self.updateCurrentBet()
            self.updateRollingState()
        }
    }

    private func getAllBettingControls() -> [PlainControl] {
        var controls: [PlainControl] = []

        // Add plain controls (check for nil to handle initialization order)
        if let passLine = passLineControl {
            controls.append(passLine)
        }
        if let passLineOdds = passLineOddsControl {
            controls.append(passLineOdds)
        }
        if let field = fieldControl {
            controls.append(field)
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
                        }
                    }
                }
            }
        }

        // Add Make Em controls from makeEmView
        if let makeEmView = makeEmView,
           let makeEmStack = makeEmView.subviews.first(where: { $0 is UIStackView }) as? UIStackView {
            for arrangedSubview in makeEmStack.arrangedSubviews {
                if let makeEmControl = arrangedSubview as? MultiBetControl {
                    controls.append(makeEmControl)
                }
            }
        }

        return controls
    }
    
    /// Check if any betting control has a bet placed
    private func hasAnyBetPlaced() -> Bool {
        let allControls = getAllBettingControls()
        return allControls.contains { $0.betAmount > 0 }
    }

    // MARK: - Action Methods

    @objc private func toggleBetsTapped() {
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
        }

        // Enable/disable all betting controls (except pass line and don't pass when in come out)
        let allControls = getAllBettingControls()
        for control in allControls {
            // Don't disable pass line and don't pass during come out roll
            if !gameStateManager.isPointPhase {
                if control === passLineControl || control === dontPassControl {
                    continue
                }
            }
            control.isEnabled = betsAreOn
        }

        // Provide haptic feedback
        HapticsHelper.lightHaptic()
    }

    @objc private func collectBetsTapped() {
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

        if totalCollected > 0 {
            instructionLabel.showMessage("Collected $\(totalCollected) in bets.", shouldFade: true)
            HapticsHelper.successHaptic()

            // Animate each bet collection with slight delays between them
            var delay: TimeInterval = 0.0
            for control in controlsToCollect {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }

                    // Reset hit numbers for Make Em bets
                    if let makeEmControl = control as? MultiBetControl {
                        makeEmControl.resetHitNumbers()
                    }

                    // Use the existing animateBetCollection method which handles the animation
                    // But we need to manually handle balance since animateBetCollection already does it
                    self.chipAnimator.animateBetCollection(for: control) { [weak self] amount in
                        guard let self = self else { return }
                        self.balance += amount
                        self.updateCurrentBet()
                    }
                }
                delay += 0.15  // Stagger animations by 150ms
            }
        } else {
            instructionLabel.showMessage("No bets to collect.", shouldFade: true)
            HapticsHelper.lightHaptic()
        }
    }

    @objc private func refreshBankrollTapped() {

        // Add random amount to the bankroll
        let amount = 200

        let messages: [String] = [
            "Cash acquired! $\(amount) added!",
            "Don't tell your spouse! $\(amount) added!",
            "You're a lucky bastard! $\(amount) added!",
            "Shhh... $\(amount) added!",
            "Added $\(amount) to bankroll!"
        ]

        balance += amount

        // Track ATM visit
        sessionManager.trackATMVisit()

        instructionLabel.showMessage(messages.randomElement() ?? "Cash acquired! $\(amount) added!", shouldFade: true)
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
    
    private func showTips() {
        // Priority 1: Tap to bet tip (highest priority - first thing users need to do)
        if NNTipManager.shared.shouldShowTip(CrapsTips.tapToBetTip),
           !hasShownTapToBetTip,
           !game.isPointPhase,
           passLineControl.betAmount == 0 {
            
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
            return // Always return after attempting to show this highest priority tip
        }
        
        // Priority 2: Come out roll tip (show when user has placed a bet and can roll)
        // Don't show if tap to bet tip is still showing - wait for it to be dismissed first
        if NNTipManager.shared.shouldShowTip(CrapsTips.comeOutRollTip),
           !hasShownComeOutRollTip,
           !game.isPointPhase,
           !NNTipManager.shared.isShowingTip(CrapsTips.tapToBetTip),
           (passLineControl.betAmount > 0 || dontPassControl.betAmount > 0) {
            
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
            return // Return after successfully showing the tip
        }
        
        // Priority 3: Bet box numbers tip (show when point is established)
        if NNTipManager.shared.shouldShowTip(CrapsTips.betBoxNumbersTip),
           !hasShownBetBoxNumbersTip,
           game.isPointPhase,
           let pointNumber = game.currentPoint,
           pointStack != nil {
            
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
            return // Return after successfully showing the tip
        }
        
        // Priority 4: Hit point to win tip (show when point is established)
        // Don't show if bet box numbers tip is still showing - wait for it to be dismissed first
        if NNTipManager.shared.shouldShowTip(CrapsTips.hitPointToWinTip),
           !hasShownHitPointToWinTip,
           game.isPointPhase,
           let pointNumber = game.currentPoint,
           !NNTipManager.shared.isShowingTip(CrapsTips.betBoxNumbersTip) {
            
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
            return // Return after successfully showing the tip
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
           !NNTipManager.shared.isShowingTip(CrapsTips.hitPointToWinTip) {
            
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
                return // Return after successfully showing the tip
            }
        }
    }
}

extension CrapsGameplayViewController: ChipSelectorDelegate {
    func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {
        print("Selected chip value: \(value)")
    }
}

extension CrapsGameplayViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Update page control based on scroll position
        let pageWidth = scrollView.bounds.width
        let currentPage = Int((scrollView.contentOffset.x + pageWidth / 2) / pageWidth)

        if scrollView == betsScrollView {
            pageControl.currentPage = currentPage
        }
    }
}

// MARK: - CrapsSettingsManagerDelegate

extension CrapsGameplayViewController: CrapsSettingsManagerDelegate {
    func settingsDidChange(_ settings: CrapsSettings) {
        // Update pass line manager with new rebet settings
        passLineManager.updateRebetSettings(enabled: settings.rebetEnabled, amount: settings.rebetAmount)

        // Rebuild bet views if bonus bet settings changed
        rebuildBetViews()
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
        // Rolling state changed - could update UI feedback
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

    func rebetAmountDidUpdate(amount: Int) {
        // Update settings manager with new rebet amount
        settingsManager.setRebetAmount(amount)
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

    func dontPassWinEvaluated(total: Int, betAmount: Int, multiplier: Double, winAmount: Int, isPointPhase: Bool) {
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

