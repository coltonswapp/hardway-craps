//
//  CrapsGameplayViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class CrapsGameplayViewController: UIViewController {
    
    // Session tracking
    private var sessionId: String?
    private var sessionStartTime: Date?
    private var accumulatedPlayTime: TimeInterval = 0 // Total active play time
    private var currentPeriodStartTime: Date? // When the current active period started
    private var rollCount: Int = 0
    private var sevensRolled: Int = 0
    private var pointsHit: Int = 0
    private var balanceHistory: [Int] = []
    private var betSizeHistory: [Int] = []
    private var pendingBetSizeSnapshot: Int = 0
    private let startingBalance: Int = 200
    private var gameplayMetrics = GameplayMetrics()
    private var hasBeenSaved: Bool = false // Track if session was already saved (e.g., on background)

    private var chipSelector: ChipSelector!
    private var passLineControl: PlainControl!
    private var passLineOddsControl: PlainControl!
    private var passLineControlWidthConstraint: NSLayoutConstraint!
    private var passLineOddsControlWidthConstraint: NSLayoutConstraint!
    private var passLineOddsControlLeadingConstraint: NSLayoutConstraint!
    private var fieldControl: PlainControl!
    private var pointStack: PointStack!
    private var flipDiceContainer: FlipDiceContainer!
    private var balanceView: BalanceView!
    private var instructionLabel: InstructionLabel!
    private var hardwayView: QuadBetView!
    private var hornView: QuadBetView!
    private var betsScrollView: UIScrollView!
    private var pageControl: UIPageControl!
    private var betsContainerView: UIView!
    private var bottomStackView: UIStackView!
    private var topStackView: UIStackView!
    private var currentBetView: CurrentBetView!
    private var playstyleView: UIView!
    private var playstyleLabel: UILabel!
    private var bankrollLabel: UILabel!
    private var showPlaystyle: Bool = false
    private var topStackTopConstraint: NSLayoutConstraint!
    private var game = CrapsGame()

    var balance: Int {
        get { balanceView?.balance ?? startingBalance }
        set {
            balanceView?.balance = newValue
            chipSelector?.updateAvailableChips(balance: newValue)
        }
    }

    var selectedChipValue: Int {
        return chipSelector?.selectedValue ?? 1
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Load persisted settings
        loadSettings()

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

        // 2. Setup playstyle view (above top stack)
        setupPlaystyleView()

        // 3. Setup top stack view (instruction label and current bet)
        setupTopStackView()

        // 4. Setup pass line control and odds control
        setupPassLineControls()

        // 5. Setup Quad bets scrollView (below top stack)
        setupHardwayStack()

        // 6. Setup PointStack (below Quad bets)
        setupPointStack()

        // 7. Setup FieldControl (below PointStack)
        setupFieldControl()

        setupDebugMenu()

        view.bringSubviewToFront(bottomStackView)
        view.bringSubviewToFront(flipDiceContainer)
        view.bringSubviewToFront(topStackView)
        if showPlaystyle {
            view.bringSubviewToFront(playstyleView)
        }

        // Initialize chip availability based on starting balance
        chipSelector.updateAvailableChips(balance: balance)
    }

    private func loadSettings() {
        // Load showPlaystyle (default: false)
        if UserDefaults.standard.object(forKey: "CrapsShowPlaystyle") != nil {
            showPlaystyle = UserDefaults.standard.bool(forKey: "CrapsShowPlaystyle")
        }
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
        guard let periodStart = currentPeriodStartTime else { return }

        // Add the current active period to accumulated time
        let currentPeriodDuration = Date().timeIntervalSince(periodStart)
        accumulatedPlayTime += currentPeriodDuration

        // Clear the current period start
        currentPeriodStartTime = nil
    }

    private func resumeSessionTimer() {
        guard hasActiveSession() else { return }

        // Start a new active period
        currentPeriodStartTime = Date()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
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
    }
    
    private func startSession() {
        sessionId = UUID().uuidString
        sessionStartTime = Date()
        accumulatedPlayTime = 0
        currentPeriodStartTime = Date() // Start tracking active time
        rollCount = 0
        sevensRolled = 0
        pointsHit = 0
        gameplayMetrics = GameplayMetrics()
        gameplayMetrics.lastBalanceBeforeRoll = startingBalance
        balanceHistory = [startingBalance]
        betSizeHistory = []
        pendingBetSizeSnapshot = 0
        hasBeenSaved = false
    }

    private func recordBalanceSnapshot() {
        balanceHistory.append(balance)
        betSizeHistory.append(pendingBetSizeSnapshot)
    }

    private func finalizeBalanceHistory() {
        if rollCount == 0 {
            balanceHistory = [balance]
            betSizeHistory = [0]
            return
        }
        if balanceHistory.isEmpty {
            balanceHistory = [startingBalance, balance]
        }
        if balanceHistory.last != balance {
            balanceHistory.append(balance)
        }

        if betSizeHistory.isEmpty {
            betSizeHistory = Array(repeating: 0, count: balanceHistory.count)
        } else if betSizeHistory.count < balanceHistory.count {
            let lastBetSize = betSizeHistory.last ?? 0
            betSizeHistory.append(contentsOf: Array(repeating: lastBetSize, count: balanceHistory.count - betSizeHistory.count))
        } else if betSizeHistory.count > balanceHistory.count {
            betSizeHistory = Array(betSizeHistory.prefix(balanceHistory.count))
        }
    }
    
    private func trackBet(amount: Int, type: BetType) {
        let betPercent = Double(amount) / Double(max(balance + amount, 1)) * 100.0
        
        // Check for loss chasing: if placing bet after a loss
        if balance < gameplayMetrics.lastBalanceBeforeRoll {
            gameplayMetrics.betsAfterLossCount += 1
        }
        
        switch type {
        case .passLine:
            gameplayMetrics.passLineBetCount += 1
            gameplayMetrics.totalPassLineAmount += amount
        case .odds:
            gameplayMetrics.oddsBetCount += 1
            gameplayMetrics.totalOddsAmount += amount
        case .place:
            gameplayMetrics.placeBetCount += 1
            gameplayMetrics.totalPlaceAmount += amount
        case .hardway:
            gameplayMetrics.hardwayBetCount += 1
            gameplayMetrics.totalHardwayAmount += amount
        case .horn:
            gameplayMetrics.hornBetCount += 1
            gameplayMetrics.totalHornAmount += amount
        case .field:
            gameplayMetrics.fieldBetCount += 1
            gameplayMetrics.totalFieldAmount += amount
        }
        
        // Track largest bet
        if amount > gameplayMetrics.largestBetAmount {
            gameplayMetrics.largestBetAmount = amount
            gameplayMetrics.largestBetPercent = betPercent
        }
        
        // Track concurrent bets
        updateConcurrentBets()
    }
    
    private enum BetType {
        case passLine
        case odds
        case place
        case hardway
        case horn
        case field
    }
    
    private func updateConcurrentBets() {
        var concurrentCount = 0
        if passLineControl.betAmount > 0 { concurrentCount += 1 }
        if passLineOddsControl.betAmount > 0 { concurrentCount += 1 }
        if fieldControl.betAmount > 0 { concurrentCount += 1 }
        
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
        
        if concurrentCount > gameplayMetrics.maxConcurrentBets {
            gameplayMetrics.maxConcurrentBets = concurrentCount
        }
    }
    
    private func saveCurrentSession() -> GameSession? {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return nil }

        // If already saved (e.g., on background), don't save again unless explicitly ending
        // This prevents duplicate sessions if user returns from background
        if hasBeenSaved {
            return nil
        }

        // Only save session if there was actual gameplay (bets placed or rolls made)
        guard rollCount > 0 || gameplayMetrics.totalBetAmount > 0 else {
            return nil
        }

        // Calculate total duration: accumulated time + current active period (if any)
        var duration = accumulatedPlayTime
        if let periodStart = currentPeriodStartTime {
            duration += Date().timeIntervalSince(periodStart)
        }

        let endingBalance = balance
        finalizeBalanceHistory()
        
        let session = GameSession(
            id: sessionId,
            date: startTime,
            duration: duration,
            startingBalance: startingBalance,
            endingBalance: endingBalance,
            rollCount: rollCount,
            gameplayMetrics: gameplayMetrics,
            sevensRolled: sevensRolled,
            pointsHit: pointsHit,
            balanceHistory: balanceHistory,
            betSizeHistory: betSizeHistory,
            handCount: nil,
            blackjackMetrics: nil
        )
        
        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        return session
    }
    
    private func saveCurrentSessionForced() -> GameSession? {
        // Force save even if already saved (for explicit end session)
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return nil }

        // Only save session if there was actual gameplay (bets placed or rolls made)
        guard rollCount > 0 || gameplayMetrics.totalBetAmount > 0 else {
            return nil
        }

        // Calculate total duration: accumulated time + current active period (if any)
        var duration = accumulatedPlayTime
        if let periodStart = currentPeriodStartTime {
            duration += Date().timeIntervalSince(periodStart)
        }

        let endingBalance = balance
        finalizeBalanceHistory()
        
        let session = GameSession(
            id: sessionId,
            date: startTime,
            duration: duration,
            startingBalance: startingBalance,
            endingBalance: endingBalance,
            rollCount: rollCount,
            gameplayMetrics: gameplayMetrics,
            sevensRolled: sevensRolled,
            pointsHit: pointsHit,
            balanceHistory: balanceHistory,
            betSizeHistory: betSizeHistory,
            handCount: nil,
            blackjackMetrics: nil
        )
        
        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        return session
    }
    
    private func endSession() {
        // Force save even if already saved on background
        guard saveCurrentSessionForced() != nil else { return }

        // Clear session tracking
        sessionId = nil
        sessionStartTime = nil
        accumulatedPlayTime = 0
        currentPeriodStartTime = nil
        rollCount = 0
        sevensRolled = 0
        pointsHit = 0
        gameplayMetrics = GameplayMetrics()
        balanceHistory = []
        betSizeHistory = []
        pendingBetSizeSnapshot = 0
        hasBeenSaved = false

        // Navigate back to main view controller
        navigationController?.popViewController(animated: true)
    }
    
    private func hasActiveSession() -> Bool {
        return sessionId != nil && sessionStartTime != nil
    }
    
    @objc private func endSessionTapped() {
        let alert = UIAlertController(
            title: "End Session?",
            message: "Are you sure you want to end this session?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "End Session", style: .destructive) { [weak self] _ in
            self?.endSession()
        })
        
        present(alert, animated: true)
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
        let settingsVC = CrapsSettingsViewController(showPlaystyle: showPlaystyle)

        // Configure callbacks
        settingsVC.onSettingsChanged = { [weak self] in
            guard let self = self else { return }
            // Reload settings from UserDefaults
            let newShowPlaystyle = UserDefaults.standard.bool(forKey: "CrapsShowPlaystyle")
            if newShowPlaystyle != self.showPlaystyle {
                self.togglePlaystyle()
            }
        }

        settingsVC.onShowGameDetails = { [weak self] in
            self?.showCurrentGameDetails()
        }

        settingsVC.onEndSession = { [weak self] in
            self?.endSessionTapped()
        }

        settingsVC.onFixedRoll = { [weak self] total in
            self?.flipDiceContainer.rollFixedTotal(total)
        }

        let navController = UINavigationController(rootViewController: settingsVC)
        present(navController, animated: true)
    }

    private func showCurrentGameDetails() {
        guard let snapshot = currentSessionSnapshot() else { return }
        let detailViewController = GameDetailViewController(session: snapshot)
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    private func currentSessionSnapshot() -> GameSession? {
        guard let sessionId, let startTime = sessionStartTime else { return nil }
        let duration = Date().timeIntervalSince(startTime)
        let endingBalance = balance

        var balanceSnapshot = balanceHistory
        var betSnapshot = betSizeHistory

        if rollCount == 0 {
            balanceSnapshot = [endingBalance]
            betSnapshot = [0]
        } else {
            if balanceSnapshot.isEmpty {
                balanceSnapshot = [startingBalance, endingBalance]
            } else if balanceSnapshot.last != endingBalance {
                balanceSnapshot.append(endingBalance)
            }

            if betSnapshot.isEmpty {
                betSnapshot = Array(repeating: 0, count: balanceSnapshot.count)
            } else if betSnapshot.count < balanceSnapshot.count {
                let lastBet = betSnapshot.last ?? 0
                betSnapshot.append(contentsOf: Array(repeating: lastBet, count: balanceSnapshot.count - betSnapshot.count))
            } else if betSnapshot.count > balanceSnapshot.count {
                betSnapshot = Array(betSnapshot.prefix(balanceSnapshot.count))
            }
        }

        return GameSession(
            id: sessionId,
            date: startTime,
            duration: duration,
            startingBalance: startingBalance,
            endingBalance: endingBalance,
            rollCount: rollCount,
            gameplayMetrics: gameplayMetrics,
            sevensRolled: sevensRolled,
            pointsHit: pointsHit,
            balanceHistory: balanceSnapshot,
            betSizeHistory: betSnapshot,
            handCount: nil,
            blackjackMetrics: nil
        )
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
        }
        
        pointStack.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
            self.updateCurrentBet()
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
            self.balance -= amount
            self.updateCurrentBet()
            self.updateRollingState()
            self.updatePassLineOddsVisibility()
        }
        
        passLineControl.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
            self.updateCurrentBet()
            self.updateRollingState()
            self.updatePassLineOddsVisibility()
        }
        
        passLineControl.addedBetCompletionHandler = { [weak self] in
            // Stop shimmer when bet is added to pass line control
            self?.passLineControl.stopTitleShimmer()
        }
        
        passLineControl.canRemoveBet = { [weak self] in
            // Pass line bet cannot be removed once the point is set
            guard let self = self else { return true }
            return !self.game.isPointPhase
        }
        
        // Create pass line odds control
        passLineOddsControl = PlainControl(title: "Odds")
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
        let isEnabled = game.isPointPhase && passLineControl.betAmount > 0
        
        // Update disabled state for pass line control (cannot remove bet when point is set)
        passLineControl.setBetRemovalDisabled(game.isPointPhase)
        
        // Update disabled state for odds control (disabled until point is set)
        passLineOddsControl.setBetRemovalDisabled(!isEnabled)
        passLineOddsControl.isEnabled = isEnabled
        
        // Always show odds control, just disable it when point is not set
        passLineOddsControl.isHidden = false
    }
    
    func setupFieldControl() {
        fieldControl = PlainControl(title: "2 • 3 • 4 • 9 • 10 • 11 • 12")
        fieldControl.translatesAutoresizingMaskIntoConstraints = false
        fieldControl.isPerpetualBet = false  // Field is a one-time bet
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
        }
        
        fieldControl.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
            self.updateCurrentBet()
        }

        view.addSubview(fieldControl)
        NSLayoutConstraint.activate([
            fieldControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fieldControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            fieldControl.bottomAnchor.constraint(equalTo: passLineControl.topAnchor, constant: -24),
            // Connect pointStack bottom to fieldControl top to make pointStack flexible
            pointStack.bottomAnchor.constraint(equalTo: fieldControl.topAnchor, constant: -24)
        ])
    }

    func setupBalanceView() {
        balanceView = BalanceView()
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
        } else if passLineControl.betAmount == 0 {
            // No pass line bet - need to place one for come out roll
            instructionLabel.showMessage("Place a Pass Line bet to roll the dice.", shouldFade: true)
            // Shimmer the pass line control label to draw attention
            passLineControl.shimmerTitleLabel()
        } else {
            // Rolling is disabled for some other reason (animations, etc.)
            instructionLabel.showMessage("Please wait...", shouldFade: true)
        }
    }
    
    private var rollingStateUpdateWorkItem: DispatchWorkItem?
    
    private func updateRollingState() {
        // Cancel any pending rolling state updates
        rollingStateUpdateWorkItem?.cancel()
        
        // Enable rolling if:
        // 1. We're in point phase (can always roll), OR
        // 2. We have a pass line bet (for come out roll)
        let shouldEnable = game.isPointPhase || passLineControl.betAmount > 0
        
        if shouldEnable {
            // If we're in point phase, enable immediately (can always roll)
            // If we have a pass line bet in come out phase, enable immediately (bet was just placed)
            // Otherwise delay to allow roll result animations to complete
            let delay: TimeInterval
            if game.isPointPhase {
                delay = 0.2  // Point phase - enable after brief delay to ensure dice animation completes
            } else if passLineControl.betAmount > 0 {
                delay = 0.0  // Pass line bet placed - enable immediately
            } else {
                delay = 1.5  // After roll result - wait for animations to complete
            }
            
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                // Double-check condition hasn't changed
                let stillShouldEnable = self.game.isPointPhase || self.passLineControl.betAmount > 0
                if stillShouldEnable {
                    self.flipDiceContainer.enableRolling()
                } else {
                    self.flipDiceContainer.disableRolling()
                }
            }
            
            rollingStateUpdateWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            flipDiceContainer.disableRolling()
        }
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
        pageControl.numberOfPages = 2
        pageControl.currentPage = 0
        pageControl.pageIndicatorTintColor = HardwayColors.label.withAlphaComponent(0.3)
        pageControl.currentPageIndicatorTintColor = HardwayColors.label
        pageControl.isUserInteractionEnabled = false // We'll handle scrolling via the scroll view
        
        // Create container view for both stacks (content inside scroll view)
        let scrollContentView = UIView()
        scrollContentView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create hardway view (perpetual bets)
        hardwayView = createBetView(title: "Hardways", controls: [
            (dieValue1: 3, dieValue2: 3, odds: "9:1"),
            (dieValue1: 4, dieValue2: 4, odds: "9:1"),
            (dieValue1: 2, dieValue2: 2, odds: "7:1"),
            (dieValue1: 5, dieValue2: 5, odds: "7:1")
        ], isPerpetual: true, betType: .hardway)
        
        // Create horn view (one-time bets)
        hornView = createBetView(title: "Horn", controls: [
            (dieValue1: 1, dieValue2: 1, odds: "30:1"),  // Snake eyes
            (dieValue1: 6, dieValue2: 6, odds: "30:1"),  // Boxcars
            (dieValue1: 1, dieValue2: 2, odds: "15:1"), // Ace-deuce
            (dieValue1: 5, dieValue2: 6, odds: "15:1")   // Five-six
        ], isPerpetual: false, betType: .horn)
        
        // Add views to scroll content view
        scrollContentView.addSubview(hardwayView)
        scrollContentView.addSubview(hornView)
        
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
            scrollContentView.heightAnchor.constraint(equalTo: betsScrollView.heightAnchor),
            scrollContentView.widthAnchor.constraint(equalTo: betsScrollView.widthAnchor, multiplier: 2), // Two pages
            
            // Hardway view constraints
            hardwayView.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor, constant: 24),
            hardwayView.widthAnchor.constraint(equalTo: betsScrollView.widthAnchor, constant: -48),
            hardwayView.topAnchor.constraint(equalTo: scrollContentView.topAnchor),
            hardwayView.bottomAnchor.constraint(equalTo: scrollContentView.bottomAnchor),
            
            // Horn view constraints
            hornView.leadingAnchor.constraint(equalTo: hardwayView.trailingAnchor, constant: 48),
            hornView.widthAnchor.constraint(equalTo: betsScrollView.widthAnchor, constant: -48),
            hornView.topAnchor.constraint(equalTo: scrollContentView.topAnchor),
            hornView.bottomAnchor.constraint(equalTo: scrollContentView.bottomAnchor)
        ])
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
            }
            control.onBetRemoved = { [weak self] amount in
                guard let self = self else { return }
                self.balance += amount
                self.updateCurrentBet()
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
    
    func setupPlaystyleView() {
        playstyleView = UIView()
        playstyleView.translatesAutoresizingMaskIntoConstraints = false
        playstyleView.backgroundColor = HardwayColors.surfaceGray
        playstyleView.layer.cornerRadius = 12
        playstyleView.isHidden = true
        
        // Create playstyle label
        playstyleLabel = UILabel()
        playstyleLabel.translatesAutoresizingMaskIntoConstraints = false
        playstyleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        playstyleLabel.textColor = .white
        playstyleLabel.textAlignment = .left
        
        // Create bankroll label
        bankrollLabel = UILabel()
        bankrollLabel.translatesAutoresizingMaskIntoConstraints = false
        bankrollLabel.font = .systemFont(ofSize: 14, weight: .regular)
        bankrollLabel.textColor = HardwayColors.label
        bankrollLabel.textAlignment = .right
        
        let labelStack = UIStackView(arrangedSubviews: [playstyleLabel, bankrollLabel])
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        labelStack.axis = .horizontal
        labelStack.spacing = 4
        labelStack.alignment = .center
        
        playstyleView.addSubview(labelStack)
        view.addSubview(playstyleView)
        
        // Add tap gesture to show player types
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(showPlayerTypes))
        playstyleView.addGestureRecognizer(tapGesture)
        playstyleView.isUserInteractionEnabled = true
        
        NSLayoutConstraint.activate([
            playstyleView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            playstyleView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            playstyleView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            playstyleView.heightAnchor.constraint(equalToConstant: 40),
            
            labelStack.leadingAnchor.constraint(equalTo: playstyleView.leadingAnchor, constant: 16),
            labelStack.trailingAnchor.constraint(equalTo: playstyleView.trailingAnchor, constant: -16),
            labelStack.centerYAnchor.constraint(equalTo: playstyleView.centerYAnchor)
        ])
    }
    
    private func togglePlaystyle() {
        showPlaystyle.toggle()
        playstyleView.isHidden = !showPlaystyle

        // Persist setting
        UserDefaults.standard.set(showPlaystyle, forKey: "CrapsShowPlaystyle")

        // Update constraint
        if showPlaystyle {
            topStackTopConstraint.isActive = false
            topStackTopConstraint = topStackView.topAnchor.constraint(equalTo: playstyleView.bottomAnchor, constant: 12)
            topStackTopConstraint.isActive = true
        } else {
            topStackTopConstraint.isActive = false
            topStackTopConstraint = topStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
            topStackTopConstraint.isActive = true
        }

        // Update playstyle display
        updatePlaystyleDisplay()
    }
    
    private func updatePlaystyleDisplay() {
        guard showPlaystyle else { return }
        
        // Calculate current playstyle
        let currentPlaystyle = calculateCurrentPlaystyle()
        playstyleLabel.text = "\(currentPlaystyle.emoji) \(currentPlaystyle.rawValue)"
        
        // Calculate bankroll percentage (current total bet / balance)
        let totalBet = getAllBettingControls().reduce(0) { $0 + $1.betAmount }
        let bankrollPercent = balance > 0 ? Double(totalBet) / Double(balance + totalBet) * 100.0 : 0.0
        bankrollLabel.text = String(format: "Bankroll: %.1f%%", bankrollPercent)
    }
    
    private func calculateCurrentPlaystyle() -> PlayerType {
        // Create a temporary session with current metrics to calculate playstyle
        let tempSession = GameSession(
            id: sessionId ?? UUID().uuidString,
            date: sessionStartTime ?? Date(),
            duration: Date().timeIntervalSince(sessionStartTime ?? Date()),
            startingBalance: startingBalance,
            endingBalance: balance,
            rollCount: rollCount,
            gameplayMetrics: gameplayMetrics,
            sevensRolled: sevensRolled,
            pointsHit: pointsHit,
            balanceHistory: balanceHistory,
            betSizeHistory: betSizeHistory,
            handCount: nil,
            blackjackMetrics: nil
        )
        return tempSession.playerType
    }
    
    @objc private func showPlayerTypes() {
        let playerTypesVC = PlayerTypesViewController()
        navigationController?.pushViewController(playerTypesVC, animated: true)
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
        updatePlaystyleDisplay()
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
        }
        
        // Update current bet after clearing bets
        updateCurrentBet()
    }

    // Structure to track winning bets
    private struct WinningBet {
        let control: PlainControl
        let winAmount: Int
        let odds: Double
    }
    
    private func handleRollResult(die1: Int, die2: Int, total: Int) {
        // Increment roll count
        rollCount += 1
        
        // Track balance before roll for loss chasing detection
        let balanceBeforeRoll = balance

        pendingBetSizeSnapshot = getAllBettingControls().reduce(0) { $0 + $1.betAmount }
        
        // Check if we're in point phase BEFORE processing the roll
        // (processRoll changes phase back to comeOut on sevenOut)
        let wasInPointPhase = game.isPointPhase
        
        // Capture the current point BEFORE processing the roll (it will be cleared by processRoll)
        let currentPointNumber = game.currentPoint
        
        // Process game logic
        let event = game.processRoll(total)

        if total == 7 {
            sevensRolled += 1
        }
        
        // Check for loss chasing: if balance decreased, mark for tracking
        let balanceAfterRoll = balance
        if balanceAfterRoll < balanceBeforeRoll {
            gameplayMetrics.lastBalanceBeforeRoll = balanceBeforeRoll
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

        // Handle pass line outcomes based on game event
        switch event {
        case .passLineWin:
            // Come out roll 7 or 11 - win pass line
            handlePassLineWin()
            allWinMessages.insert("You rolled \(total)! Pass Line wins!", at: 0)
            if passLineControl.betAmount > 0 {
                let winAmount = passLineControl.betAmount
                winningBets.append(WinningBet(control: passLineControl, winAmount: winAmount, odds: 1.0))
            }

        case .passLineLoss:
            // Come out roll 2, 3, or 12 - lose pass line
            handlePassLineLoss()
            instructionLabel.showMessage("Craps! You rolled \(total). Pass Line loses.", shouldFade: false)

        case .pointEstablished(let number):
            // Point established
            pointStack.setPoint(number)
            instructionLabel.showMessage("Point is \(number)! Roll the point again to win.", shouldFade: false)
            updatePassLineOddsVisibility()

        case .pointMade:
            // Point was made - win pass line and odds
            // Capture bet amounts before clearing
            let hadOddsBet = passLineOddsControl.betAmount > 0
            let oddsBetAmount = passLineOddsControl.betAmount // Capture before any changes
            
            handlePassLineWin()
            handlePassLineOddsWin(pointNumber: currentPointNumber, capturedBetAmount: oddsBetAmount)
            pointStack.clearPoint()
            allWinMessages.insert("You hit the point! Pass Line wins!", at: 0)
            if passLineControl.betAmount > 0 {
                let winAmount = passLineControl.betAmount
                winningBets.append(WinningBet(control: passLineControl, winAmount: winAmount, odds: 1.0))
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
                winningBets.append(WinningBet(control: passLineOddsControl, winAmount: winAmount, odds: oddsMultiplier))
            }
            // Update visibility/disabled state immediately (odds control stays visible, just disabled)
            updatePassLineOddsVisibility()
            pointsHit += 1

        case .sevenOut:
            // Seven out - lose pass line and all place bets
            let hadOddsBet = passLineOddsControl.betAmount > 0
            handlePassLineLoss()
            handlePassLineOddsLoss()
            handleSevenOut()
            pointStack.clearPoint()
            instructionLabel.showMessage("*$@#! Seven out! Place a new Pass Line bet to continue.", shouldFade: false)
            // Update visibility/disabled state immediately (odds control stays visible, just disabled)
            updatePassLineOddsVisibility()

        case .none:
            // No pass line action
            break
        }

        // Handle other bets (field, point bets)
        // Pass the event so we know if this roll established the point
        let (otherBetMessages, otherWins) = handleOtherBets(total, event: event)
        allWinMessages.append(contentsOf: otherBetMessages)
        winningBets.append(contentsOf: otherWins)
        
        // Show bet result container independently if any wins
        if !winningBets.isEmpty {
            let totalWinnings = winningBets.reduce(0) { $0 + $1.winAmount }
            showBetResult(amount: totalWinnings, isWin: true)
            // Balance will be updated incrementally as each chip reaches balance view
            // See animateWinnings completion handler
        }
        
        // Show loss container if seven out (all bets lost)
        if case .sevenOut = event {
            let totalBet = getAllBettingControls().reduce(0) { $0 + $1.betAmount }
            if totalBet > 0 {
                showBetResult(amount: totalBet, isWin: false)
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

        // Clear one-time bets after roll completes
        clearOneTimeBets()
        
        // Update rolling state after all animations complete
        // For seven out, wait longer for all chip animations to complete
        // For pointMade, wait for bet collection animation to complete
        // For passLineLoss, wait for chip removal animation to complete
        let delay: TimeInterval
        if case .sevenOut = event {
            // Seven out: chips animate away starting at 0.5-0.6s, animation takes 0.5s + fade 0.2s = ~1.3s total
            delay = 2.0  // Wait for all chip removal animations to complete
        } else if case .pointMade = event {
            // Point made: bet collection starts at 0.85s, animation takes 0.5s = ~1.35s total
            delay = 1.5  // Wait for bet collection animation to complete
        } else if case .passLineLoss = event {
            // Pass line loss: chips animate away starting at 0.5s, animation takes 0.5s + fade 0.2s = ~1.2s total
            delay = 1.5  // Wait for chip removal animation to complete
        } else {
            delay = 0.1  // Small delay to ensure game state is fully updated
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.recordBalanceSnapshot()
            self?.updateRollingState()
        }
    }
    
    
    private func animateWinnings(for control: PlainControl, odds: Double) {
        guard control.betAmount > 0 else { return }

        let winAmount = Int(Double(control.betAmount) * odds)

        // Create a temporary chip view to animate
        let chipView = SmallBetChip()
        chipView.amount = winAmount
        chipView.translatesAutoresizingMaskIntoConstraints = true  // Enable frame-based layout
        chipView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)  // Set explicit frame size
        chipView.isHidden = false  // Ensure visibility
        view.addSubview(chipView)

        // Start from center of screen (representing house)
        chipView.center = CGPoint(x: self.view.bounds.midX, y: 0)

        // Step 1: Animate from center to the control's bet position
        let betPosition = control.getBetViewPosition(in: view)
        let animator1 = UIViewPropertyAnimator(duration: 0.75, controlPoint1: CGPoint(x: 0.85, y: 0), controlPoint2: CGPoint(x: 0.15, y: 1), animations: { [weak self] in
            guard self != nil else { return }
            chipView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            chipView.center = betPosition
        })

        animator1.addCompletion { [weak self] _ in
            guard let self = self else { return }
            // Step 2: Animate from control to balance view
            let balancePosition = self.balanceView.convert(self.balanceView.bounds, to: self.view)
            let balanceCenter = CGPoint(x: balancePosition.maxX - 30, y: balancePosition.midY)

            let animator2 = UIViewPropertyAnimator(duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0), controlPoint2: CGPoint(x: 0.15, y: 1), animations: {
                chipView.center = balanceCenter
                chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            })

            animator2.addCompletion { [weak self] _ in
                guard let self = self else { return }
                // Update balance incrementally as each chip reaches balance
                self.balance += winAmount
                chipView.removeFromSuperview()
            }

            animator2.startAnimation(afterDelay: 0.2)
        }

        animator1.startAnimation()
    }

    private func handlePassLineWin() {
        guard passLineControl.betAmount > 0 else { return }

        // 1. Animate winnings from house (1:1 odds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            animateWinnings(for: passLineControl, odds: 1.0)
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
        
        // Calculate odds multiplier based on point number
        let oddsMultiplier: Double
        switch pointNumber {
        case 4, 10:
            oddsMultiplier = 2.0  // 2:1 odds
        case 5, 9:
            oddsMultiplier = 1.5  // 3:2 odds
        case 6, 8:
            oddsMultiplier = 1.2  // 6:5 odds
        default:
            oddsMultiplier = 1.0
        }
        
        // Ensure control is visible for animations
        passLineOddsControl.isHidden = false
        
        // Restore the bet amount for animation purposes
        passLineOddsControl.betAmount = capturedBetAmount
        
        // 1. Animate winnings from house
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            // Ensure bet amount is still set for animation
            if self.passLineOddsControl.betAmount == 0 {
                self.passLineOddsControl.betAmount = capturedBetAmount
            }
            // Ensure control is still visible
            self.passLineOddsControl.isHidden = false
            self.animateWinnings(for: self.passLineOddsControl, odds: oddsMultiplier)
        }
        // 2. Animate original bet being collected (after slight delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
            guard let self = self else { return }
            // Ensure bet amount is still set for collection
            if self.passLineOddsControl.betAmount == 0 {
                self.passLineOddsControl.betAmount = capturedBetAmount
            }
            // Ensure control is still visible
            self.passLineOddsControl.isHidden = false
            self.animateBetCollection(for: self.passLineOddsControl)
        }
    }
    
    private func handlePassLineOddsLoss() {
        guard passLineOddsControl.betAmount > 0 else { return }
        
        // Disable rolling immediately to prevent re-rolling before bet is cleared
        flipDiceContainer.disableRolling()
        
        // Store bet amount and position before any changes
        let betAmount = passLineOddsControl.betAmount
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
        
        // Disable rolling immediately to prevent re-rolling before bet is cleared
        flipDiceContainer.disableRolling()
        
        // Store bet amount and position before any changes
        let betAmount = passLineControl.betAmount
        let betPosition = passLineControl.getBetViewPosition(in: view)
        
        // Hide the betView immediately by setting alpha to 0
        passLineControl.betView.alpha = 0
        
        // Create the animation chip immediately (before clearing bet amount)
        // This ensures seamless transition - chip appears exactly where betView was
        let chipView = SmallBetChip()
        chipView.amount = betAmount
        chipView.translatesAutoresizingMaskIntoConstraints = true
        chipView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        chipView.isHidden = false
        view.addSubview(chipView)
        chipView.center = betPosition
        
        // Now clear the bet amount (chip is already visible at the same position)
        // Use a tiny delay to ensure chip is rendered before clearing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self else { return }
            self.passLineControl.betAmount = 0
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

    private func handleSevenOut() {
        // Collect all point controls with bets
        var controlsWithBets: [PlainControl] = []
        for pointNumber in pointStack.pointNumbers {
            if let pointControl = pointStack.getPointControl(for: pointNumber),
               pointControl.betAmount > 0 {
                controlsWithBets.append(pointControl)
            }
        }

        guard !controlsWithBets.isEmpty else { return }

        // Animate all place bets flying away (losing)
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
        // Collect all hardway controls with bets
        // Note: hardwayView.betStack has 2 columns (UIStackViews), each containing hardway controls
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
        
        // Check each hardway bet
        // Note: hardwayView.betStack has 2 columns (UIStackViews), each containing hardway controls
        for arrangedSubview in hardwayView.betStack.arrangedSubviews {
            guard let columnStack = arrangedSubview as? UIStackView else { continue }
            for columnSubview in columnStack.arrangedSubviews {
                guard let hardwayControl = columnSubview as? SmallControl,
                      hardwayControl.betAmount > 0 else { continue }
                
                let hardwayTotal = hardwayControl.dieValue1 + hardwayControl.dieValue2
                
                // Check if this roll matches the hardway exactly (win)
                // Need to check both orders: die1==dieValue1 && die2==dieValue2 OR die1==dieValue2 && die2==dieValue1
                let isHardway = (die1 == hardwayControl.dieValue1 && die2 == hardwayControl.dieValue2) ||
                                (die1 == hardwayControl.dieValue2 && die2 == hardwayControl.dieValue1)
                
                if isHardway {
                    // Hardway wins!
                    let betAmount = hardwayControl.betAmount
                    // Calculate odds multiplier: 9:1 = 10x total, 7:1 = 8x total
                    let oddsMultiplier: Double
                    if hardwayControl.odds == "9:1" {
                        oddsMultiplier = 10.0  // 9:1 means you get 9x profit + original bet = 10x total
                    } else {
                        oddsMultiplier = 8.0   // 7:1 means you get 7x profit + original bet = 8x total
                    }
                    
                    let winAmount = Int(Double(betAmount) * oddsMultiplier)
                    
                    // Collect bet for winnings container
                    winningBets.append(WinningBet(control: hardwayControl, winAmount: winAmount, odds: oddsMultiplier))
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self else { return }
                        animateWinnings(for: hardwayControl, odds: oddsMultiplier)
                    }
                    
                    // Collect the original bet after winnings
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self else { return }
                        animateBetCollection(for: hardwayControl)
                    }
                    
                    winMessages.append("Hard \(hardwayTotal) wins! You won $\(winAmount)!")
                    
                } else if total == hardwayTotal && die1 != die2 {
                    // Same total but soft way - hardway loses
                    losingControls.append(hardwayControl)
                }
            }
        }
        
        // Animate losing hardway bets (soft way)
        if !losingControls.isEmpty {
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
        
        // Check each horn bet
        // Note: hornView.betStack has 2 columns (UIStackViews), each containing horn controls
        for arrangedSubview in hornView.betStack.arrangedSubviews {
            guard let columnStack = arrangedSubview as? UIStackView else { continue }
            for columnSubview in columnStack.arrangedSubviews {
                guard let hornControl = columnSubview as? SmallControl,
                      hornControl.betAmount > 0 else { continue }
                
                // Check if this roll matches the horn bet exactly (win)
                // Need to check both orders: die1==dieValue1 && die2==dieValue2 OR die1==dieValue2 && die2==dieValue1
                let isMatch = (die1 == hornControl.dieValue1 && die2 == hornControl.dieValue2) ||
                              (die1 == hornControl.dieValue2 && die2 == hornControl.dieValue1)
                
                if isMatch {
                    // Horn bet wins!
                    let betAmount = hornControl.betAmount
                    // Calculate odds multiplier: 30:1 = 31x total, 15:1 = 16x total
                    let oddsMultiplier: Double
                    if hornControl.odds == "30:1" {
                        oddsMultiplier = 31.0  // 30:1 means you get 30x profit + original bet = 31x total
                    } else {
                        oddsMultiplier = 16.0   // 15:1 means you get 15x profit + original bet = 16x total
                    }
                    
                    let winAmount = Int(Double(betAmount) * oddsMultiplier)
                    
                    // Collect bet for winnings container
                    winningBets.append(WinningBet(control: hornControl, winAmount: winAmount, odds: oddsMultiplier))
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self else { return }
                        animateWinnings(for: hornControl, odds: oddsMultiplier)
                    }
                    
                    // Collect the original bet after winnings
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self else { return }
                        animateBetCollection(for: hornControl)
                    }
                    
                    // Create descriptive name for the horn bet
                    let hornName: String
                    if hornControl.dieValue1 == 1 && hornControl.dieValue2 == 1 {
                        hornName = "Snake Eyes"
                    } else if hornControl.dieValue1 == 6 && hornControl.dieValue2 == 6 {
                        hornName = "Boxcars"
                    } else if (hornControl.dieValue1 == 1 && hornControl.dieValue2 == 2) || (hornControl.dieValue1 == 2 && hornControl.dieValue2 == 1) {
                        hornName = "Ace-Deuce"
                    } else if (hornControl.dieValue1 == 5 && hornControl.dieValue2 == 6) || (hornControl.dieValue1 == 6 && hornControl.dieValue2 == 5) {
                        hornName = "Five-Six"
                    } else {
                        hornName = "Horn Bet"
                    }
                    
                    winMessages.append("\(hornName) wins! You won $\(winAmount)!")
                }
            }
        }
        
        // Return win messages and winning bets
        return (winMessages, winningBets)
    }
    
    private func clearOneTimeBets() {
        // Get all controls and clear any one-time bets that didn't win
        let allControls = getAllBettingControls()

        for control in allControls {
            // Skip if perpetual bet or no bet placed
            guard !control.isPerpetualBet && control.betAmount > 0 else { continue }

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
        
        // Check field bet (2, 3, 4, 9, 10, 11, 12)
        let fieldNumbers = [2, 3, 4, 9, 10, 11, 12]
        if fieldNumbers.contains(total), fieldControl.betAmount > 0 {
            let betAmount = fieldControl.betAmount
            
            // Field pays 2:1 on 2 and 12, 1:1 on other field numbers
            let odds: Double = (total == 2 || total == 12) ? 2.0 : 1.0
            let winAmount = Int(Double(betAmount) * odds)
            
            // Collect bet for winnings container
            winningBets.append(WinningBet(control: fieldControl, winAmount: winAmount, odds: odds))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                animateWinnings(for: fieldControl, odds: odds)
            }
            // Collect the original bet after winnings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                animateBetCollection(for: fieldControl)
            }
            
            // Add field win message if appropriate
            if case .none = event {
                if odds == 2.0 {
                    winMessages.append("Field wins! \(total) pays 2:1! You won $\(winAmount).")
                } else {
                    winMessages.append("Field wins! You won $\(winAmount).")
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
            let betAmount = pointControl.betAmount
            let winAmount = Int(Double(betAmount) * pointControl.oddsMultiplier)
            
            // Collect bet for winnings container
            winningBets.append(WinningBet(control: pointControl, winAmount: winAmount, odds: pointControl.oddsMultiplier))
            
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


    private func animateBetCollection(for control: PlainControl) {
        guard control.betAmount > 0 else { return }

        // Create a temporary chip view to animate
        let chipView = SmallBetChip()
        chipView.amount = control.betAmount
        chipView.translatesAutoresizingMaskIntoConstraints = true  // Enable frame-based layout
        chipView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)  // Set explicit frame size
        chipView.isHidden = false  // Ensure visibility
        view.addSubview(chipView)

        // Start from the control's bet position
        let betPosition = control.getBetViewPosition(in: view)
        chipView.center = betPosition

        // Animate directly to balance view
        let balancePosition = balanceView.convert(balanceView.bounds, to: view)
        let balanceCenter = CGPoint(x: balancePosition.maxX - 30, y: balancePosition.midY)

        let betAmount = control.betAmount

        let animator = UIViewPropertyAnimator(duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0), controlPoint2: CGPoint(x: 0.15, y: 1), animations: {
            chipView.center = balanceCenter
        })

        animator.addCompletion { [weak self] _ in
            guard let self = self else { return }
            // Update balance when chip reaches destination
            self.balance += betAmount
            chipView.removeFromSuperview()
            
            // Update rolling state after bet collection completes
            // This ensures we don't enable rolling when bet amount is 0
            self.updateRollingState()
        }

        animator.startAnimation()

        // Clear the bet from the control
        control.betAmount = 0
        updateCurrentBet()
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

        return controls
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

