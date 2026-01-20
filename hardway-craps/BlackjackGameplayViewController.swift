//
//  BlackjackGameplayViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

final class BlackjackGameplayViewController: UIViewController {
    
    // UserDefaults keys for settings persistence
    private enum SettingsKeys {
        static let showTotals = "BlackjackShowTotals"
        static let showDeckCount = "BlackjackShowDeckCount"
        static let deckCount = "BlackjackDeckCount"
        static let rebetEnabled = "BlackjackRebetEnabled"
        static let rebetAmount = "BlackjackRebetAmount"
        static let fixedHandType = "BlackjackFixedHandType"
    }
    
    // Session tracking
    private var sessionId: String?
    private var sessionStartTime: Date?
    private var handCount: Int = 0
    private var balanceHistory: [Int] = []
    private var betSizeHistory: [Int] = []
    private var pendingBetSizeSnapshot: Int = 0
    private let startingBalance: Int = 200
    private var blackjackMetrics = BlackjackGameplayMetrics()
    private var hasBeenSaved: Bool = false // Track if session was already saved (e.g., on background)
    private var lastBalanceBeforeHand: Int = 200
    
    private let dealerHandView = DealerHandView()
    private let playerHandView = PlayerHandView()
    private var splitHandView: PlayerHandView? // Second hand for split
    private let playerControlStack = PlayerControlStack()
    private var balanceView: BalanceView!
    private var chipSelector: ChipSelector!
    private var bottomStackView: UIStackView!
    private var instructionLabel: InstructionLabel!
    private var newHandButton: UIButton!
    private var bonusStackView: UIStackView!
    private var bonusBetControls: [BonusBetControl] = []
    private let deckView = DeckView()
    
    // Split state tracking
    private var isSplit: Bool = false
    private var activeHandIndex: Int = 0 // 0 = first hand, 1 = split hand
    private var splitHandStates: [(hasHit: Bool, hasStood: Bool, hasDoubled: Bool, busted: Bool)] = []
    
    // Hands scroll view for split support
    private var handsScrollView: UIScrollView!
    private var handsContentStackView: UIStackView!
    
    private var hasPlayerHit = false
    private var hasPlayerStood = false
    private var hasPlayerDoubled = false
    private var playerDoubleDownCardIndex: Int? = nil // Track which card is face-down from double down
    private var gamePhase: PlayerControlStack.GamePhase = .waitingForBet
    private var showTotals: Bool = true
    private var showDeckCount: Bool = false
    private var deck: [BlackjackHandView.Card] = []
    private var fixedHandType: FixedHandType? = nil
    private var playerBusted: Bool = false
    private var deckCount: Int = 1 // Number of decks (1, 2, 4, or 6)

    // Rebet tracking
    private var rebetEnabled: Bool = false
    private var rebetAmount: Int = 10 // Default rebet amount
    private var consecutiveBetCount: Int = 0
    private var lastBetAmount: Int = 0
    
    enum FixedHandType {
        case perfectPair        // Same rank and suit (e.g., 7♠, 7♠)
        case coloredPair        // Same rank, same color, different suits (e.g., 7♥, 7♦)
        case mixedPair          // Same rank, different colors (e.g., 7♥, 7♣)
        case royalMatch         // Suited pair (e.g., K♥, Q♥)
        case suitedCards        // Any two suited cards (e.g., 7♥, K♥)
        case regular            // Regular hand (no bonus)
    }
    
    var selectedChipValue: Int {
        return chipSelector?.selectedValue ?? 1
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Blackjack"
        
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
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        // Load settings from UserDefaults
        loadSettings()
        
        // Create and shuffle the deck first
        createAndShuffleDeck()
        
        setupNavigationBarMenu()
        setupInstructionLabel()
        setupDeckView()
        setupDealerHandView()
        setupBalanceView()
        setupChipSelector()
        setupBottomStackView()
        setupNewHandButton()
        setupPlayerControlStack()
        setupPlayerHandView()
        setupBonusStackView()
        
        // Apply loaded settings to UI
        dealerHandView.setTotalsHidden(!showTotals)
        playerHandView.setTotalsHidden(!showTotals)
        deckView.setCountLabelVisible(showDeckCount)
        
        resetGame()
        // Ensure controls are updated after initial setup
        updateControls()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAppWillResignActive() {
        // Save session when app is about to become inactive (e.g., phone call, notification)
        // This is a "checkpoint" save - user may return to continue
        if hasActiveSession() && !hasBeenSaved {
            saveCurrentSession()
        }
    }
    
    @objc private func handleAppDidEnterBackground() {
        // Save session when app enters background
        // This is a "checkpoint" save - user may return to continue
        if hasActiveSession() && !hasBeenSaved {
            saveCurrentSession()
        }
    }
    
    @objc private func handleAppWillTerminate() {
        // Save session when app is about to terminate
        // Force save final state even if already saved on background
        if hasActiveSession() {
            saveCurrentSessionForced()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Save session if view controller is being dismissed (e.g., popped from navigation)
        if isMovingFromParent && hasActiveSession() {
            saveCurrentSessionForced()
        }
    }
    
    private func setupNavigationBarMenu() {
        updateNavigationBarMenu()
    }
    
    private func updateNavigationBarMenu() {
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
    
    private func loadSettings() {
        // Load showTotals (default: true)
        if UserDefaults.standard.object(forKey: SettingsKeys.showTotals) != nil {
            showTotals = UserDefaults.standard.bool(forKey: SettingsKeys.showTotals)
        }

        // Load showDeckCount (default: false)
        if UserDefaults.standard.object(forKey: SettingsKeys.showDeckCount) != nil {
            showDeckCount = UserDefaults.standard.bool(forKey: SettingsKeys.showDeckCount)
        }

        // Load deckCount (default: 1)
        if UserDefaults.standard.object(forKey: SettingsKeys.deckCount) != nil {
            let savedDeckCount = UserDefaults.standard.integer(forKey: SettingsKeys.deckCount)
            if [1, 2, 4, 6].contains(savedDeckCount) {
                deckCount = savedDeckCount
            }
        }

        // Load rebetEnabled (default: false)
        if UserDefaults.standard.object(forKey: SettingsKeys.rebetEnabled) != nil {
            rebetEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.rebetEnabled)
        }

        // Load rebetAmount (default: 10)
        if UserDefaults.standard.object(forKey: SettingsKeys.rebetAmount) != nil {
            rebetAmount = UserDefaults.standard.integer(forKey: SettingsKeys.rebetAmount)
        }

        // Load fixedHandType (default: nil/random)
        if let savedHandType = UserDefaults.standard.string(forKey: SettingsKeys.fixedHandType) {
            // Map from settings string to gameplay enum
            switch savedHandType {
            case "Perfect Pair (30:1)":
                fixedHandType = .perfectPair
            case "Colored Pair (10:1)":
                fixedHandType = .coloredPair
            case "Mixed Pair (5:1)":
                fixedHandType = .mixedPair
            case "Royal Match (25:1)":
                fixedHandType = .royalMatch
            case "Suited Cards (3:1)":
                fixedHandType = .suitedCards
            case "Regular Hand":
                fixedHandType = .regular
            default:
                fixedHandType = nil
            }
        } else {
            fixedHandType = nil
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(showTotals, forKey: SettingsKeys.showTotals)
        UserDefaults.standard.set(showDeckCount, forKey: SettingsKeys.showDeckCount)
        UserDefaults.standard.set(deckCount, forKey: SettingsKeys.deckCount)
    }
    
    private func toggleTotals() {
        showTotals.toggle()
        dealerHandView.setTotalsHidden(!showTotals)
        playerHandView.setTotalsHidden(!showTotals)
        splitHandView?.setTotalsHidden(!showTotals)
        saveSettings()
        updateNavigationBarMenu()
    }
    
    private func toggleDeckCount() {
        showDeckCount.toggle()
        deckView.setCountLabelVisible(showDeckCount)
        saveSettings()
        updateNavigationBarMenu()
    }
    
    private func setDeckCount(_ count: Int) {
        guard [1, 2, 4, 6].contains(count) else { return }
        deckCount = count
        // Reshuffle with new deck count
        createAndShuffleDeck()
        deckView.setCardCount(52 * deckCount, animated: true)
        saveSettings()
        updateNavigationBarMenu()
        instructionLabel.showMessage("Deck count set to \(count)", shouldFade: true)
    }
    
    private func setupInstructionLabel() {
        instructionLabel = InstructionLabel()
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        // Give instructionLabel lower horizontal priority so it can compress if needed
        instructionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Set higher vertical hugging priority so it doesn't expand unnecessarily
        instructionLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        
        view.addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            instructionLabel.heightAnchor.constraint(lessThanOrEqualToConstant: 44) // Limit maximum height
        ])
    }
    
    private func setupDeckView() {
        view.addSubview(deckView)
        
        NSLayoutConstraint.activate([
            deckView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            deckView.topAnchor.constraint(equalTo: instructionLabel.topAnchor),
            deckView.widthAnchor.constraint(equalToConstant: 80),
            deckView.heightAnchor.constraint(equalToConstant: 110),
            // Prevent instruction label from overlapping deck
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: deckView.leadingAnchor, constant: -12)
        ])
        
        deckView.setCardCount(52 * deckCount, animated: true)
    }
    
    private func setupDealerHandView() {
        dealerHandView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dealerHandView)
        
        NSLayoutConstraint.activate([
            dealerHandView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dealerHandView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 16)
        ])
    }

    private func setupBonusStackView() {
        bonusStackView = UIStackView()
        bonusStackView.translatesAutoresizingMaskIntoConstraints = false
        bonusStackView.axis = .horizontal
        bonusStackView.alignment = .fill
        bonusStackView.distribution = .fillEqually
        bonusStackView.spacing = 20

        let royalMatch = BonusBetControl(title: "Royal Match", description: "Suited Pair")
        let perfectPairs = BonusBetControl(title: "Perfect Pairs", description: "Simply Pairs")
//        let twentyOnePlusThree = BonusBetControl(title: "21+3", description: "Poker Hands")

        bonusBetControls = [royalMatch, perfectPairs]
        bonusBetControls.forEach { control in
            configureBonusBetControl(control)
            bonusStackView.addArrangedSubview(control)
        }

        view.addSubview(bonusStackView)

        // Position bonus stack at a fixed distance from instructionLabel (which is stable)
        // This keeps it completely stable regardless of how hands grow
        let fixedTopPosition = bonusStackView.topAnchor.constraint(
            equalTo: instructionLabel.bottomAnchor,
            constant: 200  // Fixed offset - adjust this value to position it between hands
        )
        fixedTopPosition.priority = .required
        
        // Optional: Lower priority constraints to try to maintain spacing from hands
        // These will be broken if they conflict with the fixed position
        let minSpacingFromDealer = bonusStackView.topAnchor.constraint(
            greaterThanOrEqualTo: dealerHandView.bottomAnchor,
            constant: 20
        )
        minSpacingFromDealer.priority = .defaultLow
        
        let minSpacingFromPlayer = bonusStackView.bottomAnchor.constraint(
            lessThanOrEqualTo: playerHandView.topAnchor,
            constant: -20
        )
        minSpacingFromPlayer.priority = .defaultLow
        
        NSLayoutConstraint.activate([
            bonusStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bonusStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bonusStackView.heightAnchor.constraint(equalToConstant: 55),
            fixedTopPosition,
            minSpacingFromDealer,
            minSpacingFromPlayer
        ])
    }

    private func setupBalanceView() {
        balanceView = BalanceView()
    }

    private func setupChipSelector() {
        chipSelector = ChipSelector()
        chipSelector.delegate = self
        chipSelector.onBetReturned = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
        }
    }
    
    private func setupBottomStackView() {
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
        // Lower compression resistance to allow compression when needed (but still resist more than other views)
        bottomStackView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        
        // Set even higher compression resistance on balanceView to prevent it from getting smushed
        balanceView.setContentCompressionResistancePriority(.required, for: .vertical)
        
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
    
    private func setupNewHandButton() {
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
        
        // Add touch animations similar to ActionButton
        newHandButton.addTarget(self, action: #selector(newHandTouchDown), for: [.touchDown, .touchDragEnter])
        newHandButton.addTarget(self, action: #selector(newHandTouchUp), for: [.touchUpInside, .touchDragExit, .touchCancel])
        
        view.addSubview(newHandButton)
        
        NSLayoutConstraint.activate([
            newHandButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            newHandButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
            newHandButton.heightAnchor.constraint(equalToConstant: 70),
            newHandButton.widthAnchor.constraint(equalToConstant: 120)
        ])
    }
    
    @objc private func newHandTouchDown() {
        guard newHandButton.isEnabled else { return }
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.newHandButton.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        }
    }
    
    @objc private func newHandTouchUp() {
        guard newHandButton.isEnabled else { return }
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.newHandButton.transform = .identity
        }
        HapticsHelper.lightHaptic()
    }
    
    private func setupPlayerHandView() {
        // Create the scroll view for hands
        handsScrollView = UIScrollView()
        handsScrollView.translatesAutoresizingMaskIntoConstraints = false
        handsScrollView.isPagingEnabled = true
        handsScrollView.showsHorizontalScrollIndicator = false
        handsScrollView.showsVerticalScrollIndicator = false
        handsScrollView.alwaysBounceVertical = false
        handsScrollView.alwaysBounceHorizontal = true
        handsScrollView.bounces = true
        handsScrollView.isDirectionalLockEnabled = true  // Lock to horizontal scrolling only
        handsScrollView.contentInsetAdjustmentBehavior = .never  // Prevent iOS from adjusting insets
        handsScrollView.clipsToBounds = false  // Allow content to show beyond scroll view bounds
        handsScrollView.delegate = self
        view.addSubview(handsScrollView)
        
        // Create the content stack view
        handsContentStackView = UIStackView()
        handsContentStackView.translatesAutoresizingMaskIntoConstraints = false
        handsContentStackView.axis = .horizontal
        handsContentStackView.alignment = .bottom
        handsContentStackView.distribution = .fillEqually
        handsContentStackView.spacing = 16  // Add spacing between hands so second hand is more visible
        handsScrollView.addSubview(handsContentStackView)
        
        // Add player hand view to the stack
        playerHandView.translatesAutoresizingMaskIntoConstraints = false
        handsContentStackView.addArrangedSubview(playerHandView)
        
        // Configure the bet control with closures
        configurePlayerHandBetControl(playerHandView.betControl)
        
        // Set lower compression resistance on playerHandView so it compresses before balanceView
        playerHandView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        // Set a minimum height for normal size (approximately 200pt for cards + bet control)
        let minimumHeight: CGFloat = 200
        // Inset from edges so you can see the next hand peeking
        let horizontalInset: CGFloat = 100
        
        NSLayoutConstraint.activate([
            // Scroll view constraints - inset from edges to show adjacent hands peeking
            handsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalInset),
            handsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalInset),
            handsScrollView.bottomAnchor.constraint(equalTo: playerControlStack.topAnchor, constant: -12),
            handsScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight),
            
            // Content stack view constraints (fills scroll view height, width determined by number of hands)
            handsContentStackView.topAnchor.constraint(equalTo: handsScrollView.topAnchor),
            handsContentStackView.bottomAnchor.constraint(equalTo: handsScrollView.bottomAnchor),
            handsContentStackView.leadingAnchor.constraint(equalTo: handsScrollView.leadingAnchor),
            handsContentStackView.trailingAnchor.constraint(equalTo: handsScrollView.trailingAnchor),
            handsContentStackView.heightAnchor.constraint(equalTo: handsScrollView.heightAnchor),
            
            // Each hand should be the width of the scroll view
            playerHandView.widthAnchor.constraint(equalTo: handsScrollView.widthAnchor)
        ])
    }
    
    private func configurePlayerHandBetControl(_ betControl: PlainControl) {
        betControl.getSelectedChipValue = { [weak self] in
            return self?.selectedChipValue ?? 1
        }
        betControl.getBalance = { [weak self] in
            return self?.balance ?? 200
        }
        betControl.onBetPlaced = { [weak self] amount in
            guard let self = self else { return }
            // Prevent bet addition once hand has begun
            if self.gamePhase != .waitingForBet && self.gamePhase != .readyToDeal {
                // Revert the bet addition by removing it
                betControl.betAmount -= amount
                HapticsHelper.lightHaptic()
                return
            }
            self.balance -= amount
            self.trackBet(amount: amount, isMainBet: true)
            self.checkBetStatus()
        }
        betControl.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
            self.checkBetStatus()
        }
        betControl.addedBetCompletionHandler = { [weak self] in
            guard let self = self else { return }
            // Stop shimmer when bet is added
            self.updateBetShimmer()
        }
        betControl.canRemoveBet = { [weak self] in
            // Bet cannot be removed once hand has begun
            guard let self = self else { return true }
            return self.gamePhase == .waitingForBet || self.gamePhase == .readyToDeal
        }
    }
    
    
    private func scrollToHand(_ handIndex: Int, animated: Bool) {
        let pageWidth = handsScrollView.bounds.width + handsContentStackView.spacing
        let offset = CGPoint(x: pageWidth * CGFloat(handIndex), y: 0)
        handsScrollView.setContentOffset(offset, animated: animated)
    }
    
    private func setupPlayerControlStack() {
        playerControlStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerControlStack)
        
        playerControlStack.onActionTapped = { [weak self] action in
            guard let self = self else { return }
            switch action {
            case .hit:
                self.playerHitTapped()
            case .stand:
                self.playerStandTapped()
            case .double:
                self.playerDoubleTapped()
            case .split:
                self.playerSplitTapped()
            }
        }
        
        NSLayoutConstraint.activate([
            playerControlStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            playerControlStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            playerControlStack.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -24),
            playerControlStack.heightAnchor.constraint(equalToConstant: 45)
        ])
    }
    
    var balance: Int {
        get { balanceView?.balance ?? startingBalance }
        set {
            balanceView?.balance = newValue
            chipSelector?.updateAvailableChips(balance: newValue)
        }
    }
    
    private func startSession() {
        sessionId = UUID().uuidString
        sessionStartTime = Date()
        handCount = 0
        blackjackMetrics = BlackjackGameplayMetrics()
        blackjackMetrics.lastBalanceBeforeHand = startingBalance
        balanceHistory = [startingBalance]
        betSizeHistory = []
        pendingBetSizeSnapshot = 0
        lastBalanceBeforeHand = startingBalance
        hasBeenSaved = false
    }
    
    private func recordBalanceSnapshot() {
        balanceHistory.append(balance)
        betSizeHistory.append(pendingBetSizeSnapshot)
    }
    
    private func finalizeBalanceHistory() {
        if handCount == 0 {
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
    
    private func trackBet(amount: Int, isMainBet: Bool) {
        let betPercent = Double(amount) / Double(max(balance + amount, 1))
        
        // Check for loss chasing: if placing bet after a loss
        if balance < lastBalanceBeforeHand {
            blackjackMetrics.betsAfterLossCount += 1
        }
        
        if isMainBet {
            blackjackMetrics.mainBetCount += 1
            blackjackMetrics.totalMainBetAmount += amount
        } else {
            blackjackMetrics.bonusBetCount += 1
            blackjackMetrics.totalBonusBetAmount += amount
        }
        
        // Track largest bet
        if amount > blackjackMetrics.largestBetAmount {
            blackjackMetrics.largestBetAmount = amount
            blackjackMetrics.largestBetPercent = betPercent
        }
        
        // Track concurrent bets
        updateConcurrentBets()
    }
    
    private func updateConcurrentBets() {
        var concurrentCount = 0
        if playerHandView.betControl.betAmount > 0 { concurrentCount += 1 }
        for control in bonusBetControls {
            if control.betAmount > 0 { concurrentCount += 1 }
        }
        
        if concurrentCount > blackjackMetrics.maxConcurrentBets {
            blackjackMetrics.maxConcurrentBets = concurrentCount
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
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        let endingBalance = balance
        finalizeBalanceHistory()
        
        let session = GameSession(
            id: sessionId,
            date: startTime,
            duration: duration,
            startingBalance: startingBalance,
            endingBalance: endingBalance,
            rollCount: nil,
            gameplayMetrics: nil,
            sevensRolled: nil,
            pointsHit: nil,
            balanceHistory: balanceHistory,
            betSizeHistory: betSizeHistory,
            handCount: handCount,
            blackjackMetrics: blackjackMetrics
        )
        
        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        return session
    }
    
    private func saveCurrentSessionForced() -> GameSession? {
        // Force save even if already saved (for explicit end session)
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else { return nil }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        let endingBalance = balance
        finalizeBalanceHistory()
        
        let session = GameSession(
            id: sessionId,
            date: startTime,
            duration: duration,
            startingBalance: startingBalance,
            endingBalance: endingBalance,
            rollCount: nil,
            gameplayMetrics: nil,
            sevensRolled: nil,
            pointsHit: nil,
            balanceHistory: balanceHistory,
            betSizeHistory: betSizeHistory,
            handCount: handCount,
            blackjackMetrics: blackjackMetrics
        )
        
        SessionPersistenceManager.shared.saveSession(session)
        hasBeenSaved = true
        return session
    }
    
    private func hasActiveSession() -> Bool {
        return sessionId != nil && sessionStartTime != nil
    }
    
    @objc private func shuffleTapped() {
        resetGame()
    }
    
    private func showCurrentGameDetails() {
        guard let snapshot = currentSessionSnapshot() else { return }
        let detailViewController = GameDetailViewController(session: snapshot)
        navigationController?.pushViewController(detailViewController, animated: true)
    }
    
    private func showSettingsViewController() {
        let settingsViewController = BlackjackSettingsViewController()
        let navigationController = UINavigationController(rootViewController: settingsViewController)

        // Configure sheet presentation with detents
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.largestUndimmedDetentIdentifier = .medium
        }

        // Set callback to refresh UI when settings change
        settingsViewController.onSettingsChanged = { [weak self] in
            self?.refreshSettings()
        }

        // Set callback to show game details
        settingsViewController.onShowGameDetails = { [weak self] in
            navigationController.dismiss(animated: true) {
                self?.showCurrentGameDetails()
            }
        }

        present(navigationController, animated: true)
    }
    
    private func refreshSettings() {
        loadSettings()
        dealerHandView.setTotalsHidden(!showTotals)
        playerHandView.setTotalsHidden(!showTotals)
        splitHandView?.setTotalsHidden(!showTotals)
        deckView.setCountLabelVisible(showDeckCount)
        if deckCount != deck.count / 52 {
            createAndShuffleDeck()
            deckView.setCardCount(52 * deckCount, animated: true)
        }
        updateNavigationBarMenu()
    }
    
    private func currentSessionSnapshot() -> GameSession? {
        guard let sessionId = sessionId, let startTime = sessionStartTime else { return nil }
        let duration = Date().timeIntervalSince(startTime)
        let endingBalance = balance
        
        var balanceSnapshot = balanceHistory
        var betSnapshot = betSizeHistory
        
        if handCount == 0 {
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
            rollCount: nil,
            gameplayMetrics: nil,
            sevensRolled: nil,
            pointsHit: nil,
            balanceHistory: balanceSnapshot,
            betSizeHistory: betSnapshot,
            handCount: handCount,
            blackjackMetrics: blackjackMetrics
        )
    }
    
    private func resetGame() {
        gamePhase = .waitingForBet
        hasPlayerHit = false
        hasPlayerStood = false
        hasPlayerDoubled = false
        playerDoubleDownCardIndex = nil
        playerBusted = false
        
        // Clear split state
        isSplit = false
        activeHandIndex = 0
        splitHandStates = []
        
        // Remove split hand from scroll view if present
        if let splitHand = splitHandView {
            handsContentStackView.removeArrangedSubview(splitHand)
            splitHand.removeFromSuperview()
            splitHandView = nil
        }
        
        // Reset scroll view position
        scrollToHand(0, animated: false)
        
        // Clear hands and reset deck
        dealerHandView.clearCards()
        playerHandView.clearCards()
        
        // Reshuffle the deck
        createAndShuffleDeck()
        deckView.setCardCount(52 * deckCount, animated: false)
        
        // Note: fixedHandType persists across hands until manually changed
        
        updateInstructionMessage()
        checkBetStatus()
    }
    
    @objc private func newHandTapped() {
        // This button serves dual purpose: "Ready?" and "New Hand"
        if gamePhase == .readyToDeal {
            // Function as "Ready" button
            readyTapped()
        } else if gamePhase == .gameOver {
            // Function as "New Hand" button
            // Clean up split hand if it exists before resetting
            if isSplit {
                cleanupSplitHand()
            }

            // Immediately change phase to prevent re-triggering discard animation
            gamePhase = .waitingForBet
            hasPlayerHit = false
            hasPlayerStood = false
            hasPlayerDoubled = false
            playerDoubleDownCardIndex = nil
            playerBusted = false
            updateControls()

            // Update last balance before next hand
            lastBalanceBeforeHand = balance

            // Discard cards to top left, then check bet status
            discardHandsToTopLeft { [weak self] in
                guard let self = self else { return }

                // Don't reshuffle - continue drawing from existing deck
                // It will auto-reshuffle when empty

                // Apply rebet if enabled
                self.applyRebetIfNeeded()

                self.updateInstructionMessage()
                self.checkBetStatus()
            }
        }
    }
    
    private func checkBetStatus() {
        let betAmount = playerHandView.betControl.betAmount
        
        if betAmount > 0 && gamePhase == .waitingForBet {
            gamePhase = .readyToDeal
            updateControls()
            updateInstructionMessage()
        } else if betAmount == 0 && gamePhase == .readyToDeal {
            gamePhase = .waitingForBet
            updateControls()
            updateInstructionMessage()
        }
        
        // Update shimmer based on current state
        updateBetShimmer()
    }
    
    private func readyTapped() {
        guard gamePhase == .readyToDeal else { return }

        // Record balance before hand starts
        lastBalanceBeforeHand = balance

        // Snapshot bet size before dealing
        let mainBet = playerHandView.betControl.betAmount
        var totalBonusBet = 0
        for control in bonusBetControls {
            totalBonusBet += control.betAmount
        }
        pendingBetSizeSnapshot = mainBet + totalBonusBet

        // Track bet for rebet functionality
        trackBetForRebet(amount: mainBet)
        
        // Check if we need to reshuffle before dealing
        if deck.count < 6 {
            gamePhase = .dealing
            updateControls()
            instructionLabel.showMessage("Reshuffling deck...", shouldFade: false)
            
            // Reshuffle the deck
            createAndShuffleDeck()
            deckView.setCardCount(52 * deckCount, animated: true)
            
            // Wait for shuffle animation to complete (1.4s animation + small buffer)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.startDealingSequence()
            }
        } else {
            gamePhase = .dealing
            updateControls()
            updateInstructionMessage()
            startDealingSequence()
        }
    }
    
    private func startDealingSequence() {
        // Clear any existing cards
        dealerHandView.clearCards()
        playerHandView.clearCards()
        // Show placeholders before dealing
        dealerHandView.showPlaceholders()
        playerHandView.showPlaceholders()
        dealCards()
    }
    
    private func setFixedHand(_ handType: FixedHandType?) {
        fixedHandType = handType
        let message = handType == nil ? "Fixed hand disabled" : "Fixed hand: \(handTypeDescription(handType!))"
        instructionLabel.showMessage(message, shouldFade: true)
    }
    
    private func handTypeDescription(_ handType: FixedHandType) -> String {
        switch handType {
        case .perfectPair: return "Perfect Pair"
        case .coloredPair: return "Colored Pair"
        case .mixedPair: return "Mixed Pair"
        case .royalMatch: return "Royal Match"
        case .suitedCards: return "Suited Cards"
        case .regular: return "Regular Hand"
        }
    }
    
    private func dealCards() {
        let deckCenter = view.convert(deckView.deckCenter, from: deckView)
        
        // Generate cards for this hand
        let playerCard1: BlackjackHandView.Card
        let playerCard2: BlackjackHandView.Card
        let dealerCard1: BlackjackHandView.Card
        let dealerCard2: BlackjackHandView.Card
        
        if let fixedType = fixedHandType {
            // Deal fixed cards based on hand type
            (playerCard1, playerCard2, dealerCard1, dealerCard2) = dealFixedHand(type: fixedType)
        } else {
            // Deal random cards
            // Note: randomHandCard() already calls drawCard() internally, so deck count updates automatically
            playerCard1 = randomHandCard()
            dealerCard1 = randomHandCard()
            playerCard2 = randomHandCard()
            dealerCard2 = randomHandCard()
        }
        
        // Show single dealing message that stays throughout the sequence
        instructionLabel.showMessage("Dealing cards...", shouldFade: false)
        
        // Deal player's first card
        playerHandView.dealCard(playerCard1, from: deckCenter, in: view)
        
        // Deal dealer's first card (face down) after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.dealerHandView.dealCard(dealerCard1, from: deckCenter, in: self.view)
            
            // Deal player's second card
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.playerHandView.dealCard(playerCard2, from: deckCenter, in: self.view)
                
                    // Deal dealer's second card (face up)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self = self else { return }
                        self.dealerHandView.dealCard(dealerCard2, from: deckCenter, in: self.view)
                        
                        // Evaluate bonus bets immediately after initial 4 cards are dealt
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            guard let self = self else { return }
                            let playerCards = self.playerHandView.currentCards
                            self.checkAndPayBonusBets(playerCards: playerCards)
                        }
                        
                        // Transition to player's turn
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            guard let self = self else { return }
                            
                            // Check if player has 21 (blackjack or regular 21)
                            let playerTotal = self.calculateHandTotal(cards: self.playerHandView.currentCards)
                            if playerTotal == 21 {
                                // Auto-stand on 21
                                self.hasPlayerStood = true
                                self.gamePhase = .dealerTurn
                                self.updateControls()
                                self.updateInstructionMessage()
                                self.startDealerTurn()
                            } else {
                                self.gamePhase = .playerTurn
                                self.updateControls()
                                self.updateInstructionMessage()
                            }
                        }
                    }
            }
        }
    }
    
    
    @objc private func playerHitTapped() {
        guard gamePhase == .playerTurn else { return }
        
        if isSplit {
            // Handle split hand hit
            let currentHand = activeHandIndex == 0 ? playerHandView : splitHandView!
            var currentState = splitHandStates[activeHandIndex]
            
            guard !currentState.hasStood else { return }
            
            currentState.hasHit = true
            splitHandStates[activeHandIndex] = currentState
            
            let deckCenter = view.convert(deckView.deckCenter, from: deckView)
            currentHand.dealCard(randomHandCard(), from: deckCenter, in: view)
            
            // Check hand total after card animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                let handTotal = self.calculateHandTotal(cards: currentHand.currentCards)
                
                if handTotal > 21 {
                    // Hand busted
                    var state = self.splitHandStates[self.activeHandIndex]
                    state.busted = true
                    self.splitHandStates[self.activeHandIndex] = state
                    
                    // Check if both hands are done
                    self.checkSplitHandsCompletion()
                } else if handTotal == 21 {
                    // Auto-stand on 21
                    var state = self.splitHandStates[self.activeHandIndex]
                    state.hasStood = true
                    self.splitHandStates[self.activeHandIndex] = state
                    self.checkSplitHandsCompletion()
                } else {
                    self.updateControls()
                    self.updateInstructionMessage()
                }
            }
        } else {
            // Normal single hand hit
            guard !hasPlayerStood else { return }
            hasPlayerHit = true
            let deckCenter = view.convert(deckView.deckCenter, from: deckView)
            playerHandView.dealCard(randomHandCard(), from: deckCenter, in: view)
            
            // Check player's total after card animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                let playerTotal = self.calculateHandTotal(cards: self.playerHandView.currentCards)
                
                if playerTotal > 21 {
                    // Player busted, automatically reveal dealer's hole card
                    self.playerBusted = true
                    
                    // Reveal dealer's hole card automatically
                    if self.dealerHandView.isHoleCardHidden() {
                        self.dealerHandView.revealHoleCard(animated: true)
                    }
                    
                    // Wait a moment for card flip animation, then end game
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self else { return }
                        self.gamePhase = .gameOver
                        self.updateControls()
                        self.updateInstructionMessage()
                        self.endGame()
                    }
                } else if playerTotal == 21 {
                    // Auto-stand on 21
                    self.hasPlayerStood = true
                    self.gamePhase = .dealerTurn
                    self.updateControls()
                    self.updateInstructionMessage()
                    self.startDealerTurn()
                } else {
                    self.updateControls()
                    self.updateInstructionMessage()
                }
            }
        }
    }
    
    private func checkSplitHandsCompletion() {
        let firstHandDone = splitHandStates[0].hasStood || splitHandStates[0].busted
        let secondHandDone = splitHandStates[1].hasStood || splitHandStates[1].busted
        
        if firstHandDone && secondHandDone {
            // Both hands complete, start dealer turn
            gamePhase = .dealerTurn
            updateControls()
            updateInstructionMessage()
            
            // Reveal dealer's hole card
            if dealerHandView.isHoleCardHidden() {
                dealerHandView.revealHoleCard(animated: true)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startDealerTurn()
            }
        } else if firstHandDone && activeHandIndex == 0 {
            // First hand done, switch to second hand
            switchFocusToHand(1)
            updateInstructionMessage()
        } else if secondHandDone && activeHandIndex == 1 {
            // Second hand done, but first isn't - shouldn't happen, but handle it
            if !firstHandDone {
                switchFocusToHand(0)
                updateInstructionMessage()
            }
        }
    }
    
    private func playerStandTapped() {
        guard gamePhase == .playerTurn else { return }
        
        if isSplit {
            // Handle split hand stand
            var currentState = splitHandStates[activeHandIndex]
            guard !currentState.hasStood else { return }
            
            currentState.hasStood = true
            splitHandStates[activeHandIndex] = currentState
            
            checkSplitHandsCompletion()
        } else {
            // Normal single hand stand
            guard !hasPlayerStood else { return }
            hasPlayerStood = true
            gamePhase = .dealerTurn
            updateControls()
            updateInstructionMessage()
            startDealerTurn()
        }
    }
    
    private func playerSplitTapped() {
        guard gamePhase == .playerTurn && !hasPlayerStood && !hasPlayerDoubled else { return }
        guard playerHandView.currentCards.count == 2 && !hasPlayerHit else { return }
        
        let cards = playerHandView.currentCards
        guard cards[0].rank == cards[1].rank else { return }
        
        let betAmount = playerHandView.betControl.betAmount
        guard betAmount > 0 else { return }
        
        // Check if player has enough balance to split
        if betAmount > balance {
            HapticsHelper.lightHaptic()
            return
        }
        
        // Deduct the additional bet for split hand
        balance -= betAmount
        trackBet(amount: betAmount, isMainBet: true)
        
        // Initialize split state
        isSplit = true
        activeHandIndex = 0
        splitHandStates = [
            (hasHit: false, hasStood: false, hasDoubled: false, busted: false),
            (hasHit: false, hasStood: false, hasDoubled: false, busted: false)
        ]
        
        // Create split hand view
        let splitHand = PlayerHandView()
        splitHand.translatesAutoresizingMaskIntoConstraints = false
        splitHand.setTotalsHidden(!showTotals)
        splitHandView = splitHand
        
        // Configure split hand bet control
        configurePlayerHandBetControl(splitHand.betControl)
        splitHand.betControl.betAmount = betAmount
        
        // Move second card to split hand
        let secondCard = cards[1]
        let firstCard = cards[0]
        
        // Add split hand to scroll view and animate it in
        animateSplitHandIn(splitHand: splitHand)
        
        // Clear first hand and add first card back (without animation)
        playerHandView.clearCards()
        // Use addCard which will animate, but we'll deal the new card after
        playerHandView.addCard(firstCard)
        
        // Deal new card to first hand
        let deckCenter = view.convert(deckView.deckCenter, from: deckView)
        let newCard1 = randomHandCard()
        
        // Wait for first card to be added, then deal new card
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.playerHandView.dealCard(newCard1, from: deckCenter, in: self.view)
            
            // Set up split hand with second card
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                // Add second card to split hand
                splitHand.addCard(secondCard)
                
                // Deal new card to split hand
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    let newCard2 = self.randomHandCard()
                    splitHand.dealCard(newCard2, from: deckCenter, in: self.view)
                }
            }
        }
    }
    
    private func animateSplitHandIn(splitHand: PlayerHandView) {
        // Add split hand to the content stack view
        handsContentStackView.addArrangedSubview(splitHand)
        
        // Add width constraint to match scroll view width
        splitHand.widthAnchor.constraint(equalTo: handsScrollView.widthAnchor).isActive = true
        
        // Start split hand with zero alpha
        splitHand.alpha = 0
        
        // Force layout to update content size
        view.layoutIfNeeded()
        
        // Animate split hand appearing
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: [.curveEaseOut]) {
            splitHand.alpha = 1
        }
        
        // Update controls for split state
        updateControls()
    }
    
    private func switchFocusToHand(_ handIndex: Int) {
        guard isSplit, handIndex >= 0 && handIndex <= 1 else { return }
        guard activeHandIndex != handIndex else { return }
        
        activeHandIndex = handIndex
        
        // Scroll to the correct hand
        scrollToHand(handIndex, animated: true)
        
        updateControls()
    }
    
    private func playerDoubleTapped() {
        guard gamePhase == .playerTurn && !hasPlayerStood else { return }
        
        if isSplit {
            // Handle split hand double
            let currentHand = activeHandIndex == 0 ? playerHandView : splitHandView!
            var currentState = splitHandStates[activeHandIndex]
            
            guard currentHand.currentCards.count == 2 && !currentState.hasHit && !currentState.hasDoubled else { return }
            
            let betAmount = currentHand.betControl.betAmount
            guard betAmount > 0 else { return }
            
            // Check if player has enough balance to double
            if betAmount > balance {
                HapticsHelper.lightHaptic()
                return
            }
            
            // Double the bet
            currentState.hasDoubled = true
            splitHandStates[activeHandIndex] = currentState
            blackjackMetrics.doublesDown += 1
            balance -= betAmount
            currentHand.betControl.betAmount = betAmount * 2
            
            // Track the additional bet
            trackBet(amount: betAmount, isMainBet: true)
            
            // Deal a face-down card
            let deckCenter = view.convert(deckView.deckCenter, from: deckView)
            let doubleDownCard = randomHandCard()
            currentHand.dealCardFaceDown(doubleDownCard, from: deckCenter, in: view)
            
            // Auto-stand after double down
            currentState.hasStood = true
            splitHandStates[activeHandIndex] = currentState
            
            // Check if both hands are done
            checkSplitHandsCompletion()
        } else {
            // Normal single hand double
            guard !hasPlayerDoubled else { return }
            guard playerHandView.currentCards.count == 2 && !hasPlayerHit else { return }
            
            let betAmount = playerHandView.betControl.betAmount
            guard betAmount > 0 else { return }
            
            // Check if player has enough balance to double
            if betAmount > balance {
                // Insufficient balance - provide haptic feedback
                HapticsHelper.lightHaptic()
                return
            }
            
            // Double the bet
            hasPlayerDoubled = true
            blackjackMetrics.doublesDown += 1
            balance -= betAmount // Deduct the additional bet
            playerHandView.betControl.betAmount = betAmount * 2
            
            // Update pending bet size snapshot
            var totalBonusBet = 0
            for control in bonusBetControls {
                totalBonusBet += control.betAmount
            }
            pendingBetSizeSnapshot = playerHandView.betControl.betAmount + totalBonusBet
            
            // Track the additional bet
            trackBet(amount: betAmount, isMainBet: true)
            
            // Deal a face-down card to the player
            let deckCenter = view.convert(deckView.deckCenter, from: deckView)
            let doubleDownCard = randomHandCard()
            
            // Deal card face-down
            playerHandView.dealCardFaceDown(doubleDownCard, from: deckCenter, in: view)
            
            // Track which card index is the face-down double down card
            playerDoubleDownCardIndex = playerHandView.currentCards.count - 1
            
            // Auto-stand after double down
            hasPlayerStood = true
            gamePhase = .dealerTurn
            updateControls()
            updateInstructionMessage()
            
            // Start dealer turn after card animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.startDealerTurn()
            }
        }
    }
    
    private func startDealerTurn() {
        // First, reveal the dealer's face-down card
        dealerHandView.revealHoleCard(animated: true)

        // Check if player has blackjack (21 with exactly 2 cards)
        let playerCards = playerHandView.currentCards
        let playerTotal = calculateHandTotal(cards: playerCards)
        let isPlayerBlackjack = playerTotal == 21 && playerCards.count == 2 &&
                                (playerCards[0].rank == .ace || playerCards[1].rank == .ace) &&
                                (playerCards[0].rank == .king || playerCards[0].rank == .queen ||
                                 playerCards[0].rank == .jack || playerCards[0].rank == .ten ||
                                 playerCards[1].rank == .king || playerCards[1].rank == .queen ||
                                 playerCards[1].rank == .jack || playerCards[1].rank == .ten)

        if isPlayerBlackjack {
            // Player has blackjack - just check dealer's hand, don't let dealer play
            // Wait for hole card reveal, then immediately end game
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.endGame()
            }
        } else {
            // Normal game - let dealer play their hand
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.dealerPlay()
            }
        }
    }
    
    private func dealerPlay() {
        let dealerCards = dealerHandView.currentCards
        let dealerTotal = calculateHandTotal(cards: dealerCards)
        
        // Dealer must hit until they reach 17 or higher
        if dealerTotal < 17 {
            // Dealer hits
            let deckCenter = view.convert(deckView.deckCenter, from: deckView)
            // Note: randomHandCard() already calls drawCard() internally, so deck count updates automatically
            dealerHandView.dealCard(randomHandCard(), from: deckCenter, in: view)
            
            // Wait for card animation, then check again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.dealerPlay()
            }
        } else {
            // Dealer stands (17 or higher)
            // If split, reveal any double down cards
            if isSplit {
                var cardsToReveal: [(view: PlayerHandView, index: Int)] = []
                
                // Check first hand for double down - find the face-down card
                if splitHandStates[0].hasDoubled {
                    let firstHandCards = playerHandView.currentCards
                    // Double down adds one card, so it should be the last card
                    if firstHandCards.count >= 3 {
                        cardsToReveal.append((view: playerHandView, index: firstHandCards.count - 1))
                    }
                }
                
                // Check second hand for double down
                if splitHandStates[1].hasDoubled, let splitHand = splitHandView {
                    let secondHandCards = splitHand.currentCards
                    if secondHandCards.count >= 3 {
                        cardsToReveal.append((view: splitHand, index: secondHandCards.count - 1))
                    }
                }
                
                if !cardsToReveal.isEmpty {
                    // Reveal cards sequentially
                    var revealIndex = 0
                    func revealNext() {
                        guard revealIndex < cardsToReveal.count else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                                self?.endGame()
                            }
                            return
                        }
                        
                        let cardToReveal = cardsToReveal[revealIndex]
                        cardToReveal.view.revealCard(at: cardToReveal.index, animated: true)
                        revealIndex += 1
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            revealNext()
                        }
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        revealNext()
                    }
                } else {
                    // No double down cards to reveal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.endGame()
                    }
                }
            } else {
                // Single hand - if player doubled down, reveal their face-down card before ending game
                if hasPlayerDoubled, let cardIndex = playerDoubleDownCardIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self = self else { return }
                        self.playerHandView.revealCard(at: cardIndex, animated: true)
                        // Wait for card flip animation, then end game
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                            self?.endGame()
                        }
                    }
                } else {
                    // No double down, end game immediately
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.endGame()
                    }
                }
            }
        }
    }
    
    private func endGame() {
        gamePhase = .gameOver
        updateControls()
        
        if isSplit {
            endSplitGame()
            return
        }
        
        let playerCards = playerHandView.currentCards
        let dealerCards = dealerHandView.currentCards
        let playerTotal = calculateHandTotal(cards: playerCards)
        let dealerTotal = calculateHandTotal(cards: dealerCards)
        let betAmount = playerHandView.betControl.betAmount
        
        // Determine winner
        var message: String
        var isWin = false
        var isPush = false
        
        // Check for blackjack: ace + face card (10, J, Q, K) = 21 in exactly 2 cards
        let isPlayerBlackjack = playerTotal == 21 && playerCards.count == 2 && 
                                 (playerCards[0].rank == .ace || playerCards[1].rank == .ace) &&
                                 (playerCards[0].rank == .king || playerCards[0].rank == .queen || 
                                  playerCards[0].rank == .jack || playerCards[0].rank == .ten ||
                                  playerCards[1].rank == .king || playerCards[1].rank == .queen || 
                                  playerCards[1].rank == .jack || playerCards[1].rank == .ten)
        
        let isDealerBlackjack = dealerTotal == 21 && dealerCards.count == 2 &&
                                (dealerCards[0].rank == .ace || dealerCards[1].rank == .ace) &&
                                (dealerCards[0].rank == .king || dealerCards[0].rank == .queen || 
                                 dealerCards[0].rank == .jack || dealerCards[0].rank == .ten ||
                                 dealerCards[1].rank == .king || dealerCards[1].rank == .queen || 
                                 dealerCards[1].rank == .jack || dealerCards[1].rank == .ten)
        
        // Track hand outcome
        handCount += 1
        
        // Special rule: If both player and dealer bust, player loses (especially important for double down)
        if playerTotal > 21 && dealerTotal > 21 {
            message = "Both bust! Dealer wins."
            isWin = false
            blackjackMetrics.losses += 1
        } else if playerTotal > 21 {
            playerBusted = true
            message = "Bust! You went over 21. Dealer wins."
            isWin = false
            blackjackMetrics.losses += 1
        } else if dealerTotal > 21 {
            message = isPlayerBlackjack ? "Blackjack! Dealer busts! You win!" : "Dealer busts! You win!"
            isWin = true
            if isPlayerBlackjack {
                blackjackMetrics.blackjacksHit += 1
            }
            blackjackMetrics.wins += 1
        } else if isPlayerBlackjack && isDealerBlackjack {
            // Both have blackjack - push
            message = "Both have blackjack! Push!"
            isPush = true
            blackjackMetrics.pushes += 1
        } else if isPlayerBlackjack {
            // Player has blackjack, dealer doesn't - player wins
            message = "Blackjack! You win!"
            isWin = true
            blackjackMetrics.blackjacksHit += 1
            blackjackMetrics.wins += 1
        } else if playerTotal > dealerTotal {
            message = "You win! \(playerTotal) beats \(dealerTotal)."
            isWin = true
            blackjackMetrics.wins += 1
        } else if dealerTotal > playerTotal {
            message = "Dealer wins! \(dealerTotal) beats \(playerTotal)."
            isWin = false
            blackjackMetrics.losses += 1
        } else {
            message = "Push! Both have \(playerTotal)."
            isPush = true
            blackjackMetrics.pushes += 1
        }
        
        instructionLabel.showMessage(message, shouldFade: false)
        
        // Record balance snapshot after hand completes
        recordBalanceSnapshot()
        
        // Handle win/loss animations
        if isWin {
            // Blackjack pays 3:2 (bet + 50%)
            let winAmount = isPlayerBlackjack ? Int(Double(betAmount) * 1.5) : betAmount
            
            // Show bet result container
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.showBetResult(amount: winAmount, isWin: true)
            }
            
            // Animate winnings from house to bet to balance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                let odds = isPlayerBlackjack ? 1.5 : 1.0
                self.animateWinnings(for: self.playerHandView.betControl, odds: odds)
            }
            
            // Collect the original bet after winnings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                guard let self = self else { return }
                self.animateBetCollection(for: self.playerHandView.betControl)
            }
        } else if isPush {
            // Push - leave the bet on the control, don't return it to balance
            // The bet stays visually and is not added back to balance
        } else {
            // Player lost - animate chips away to top of screen
            if betAmount > 0 {
                // Show loss container
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    self.showBetResult(amount: betAmount, isWin: false)
                }
                
                // Animate chips flying away
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.animateChipsAway(from: self.playerHandView.betControl)
                }
            }
        }

        // Note: Bonus bets are evaluated immediately after initial 4 cards are dealt,
        // not at the end of the game
    }
    
    private func endSplitGame() {
        guard let splitHand = splitHandView else { return }
        
        let dealerCards = dealerHandView.currentCards
        let dealerTotal = calculateHandTotal(cards: dealerCards)
        
        // Evaluate each hand against dealer
        let hands = [
            (view: playerHandView, state: splitHandStates[0], index: 0),
            (view: splitHand, state: splitHandStates[1], index: 1)
        ]
        
        var results: [(handView: PlayerHandView, isWin: Bool, isPush: Bool, betAmount: Int, isBlackjack: Bool)] = []
        
        for (handView, state, _) in hands {
            let handCards = handView.currentCards
            let handTotal = calculateHandTotal(cards: handCards)
            let betAmount = handView.betControl.betAmount
            
            // Check for blackjack
            let isBlackjack = handTotal == 21 && handCards.count == 2 &&
                (handCards[0].rank == .ace || handCards[1].rank == .ace) &&
                (handCards[0].rank == .king || handCards[0].rank == .queen ||
                 handCards[0].rank == .jack || handCards[0].rank == .ten ||
                 handCards[1].rank == .king || handCards[1].rank == .queen ||
                 handCards[1].rank == .jack || handCards[1].rank == .ten)
            
            var isWin = false
            var isPush = false
            
            if state.busted {
                // Hand busted - loses
                isWin = false
            } else if dealerTotal > 21 {
                // Dealer busted - hand wins
                isWin = true
            } else if isBlackjack {
                // Check dealer blackjack
                let isDealerBlackjack = dealerTotal == 21 && dealerCards.count == 2 &&
                    (dealerCards[0].rank == .ace || dealerCards[1].rank == .ace) &&
                    (dealerCards[0].rank == .king || dealerCards[0].rank == .queen ||
                     dealerCards[0].rank == .jack || dealerCards[0].rank == .ten ||
                     dealerCards[1].rank == .king || dealerCards[1].rank == .queen ||
                     dealerCards[1].rank == .jack || dealerCards[1].rank == .ten)
                
                if isDealerBlackjack {
                    isPush = true
                } else {
                    isWin = true
                }
            } else if handTotal > dealerTotal {
                isWin = true
            } else if dealerTotal > handTotal {
                isWin = false
            } else {
                isPush = true
            }
            
            results.append((handView: handView, isWin: isWin, isPush: isPush, betAmount: betAmount, isBlackjack: isBlackjack))
        }
        
        // Update instruction message
        let winCount = results.filter { $0.isWin }.count
        let lossCount = results.filter { !$0.isWin && !$0.isPush }.count
        let pushCount = results.filter { $0.isPush }.count
        
        var message: String
        if winCount == 2 {
            message = "Both hands win!"
        } else if lossCount == 2 {
            message = "Both hands lose."
        } else if pushCount == 2 {
            message = "Both hands push!"
        } else {
            message = "One hand wins, one loses."
        }
        
        instructionLabel.showMessage(message, shouldFade: false)
        
        // Record balance snapshot
        recordBalanceSnapshot()
        
        // Calculate total winnings/losses for bet result display
        let totalWinnings = results.filter { $0.isWin }.reduce(0) { total, result in
            let winAmount = result.isBlackjack ? Int(Double(result.betAmount) * 1.5) : result.betAmount
            return total + winAmount
        }
        let totalLosses = results.filter { !$0.isWin && !$0.isPush }.reduce(0) { $0 + $1.betAmount }

        // Show single bet result container with total amount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            if totalWinnings > 0 {
                self.showBetResult(amount: totalWinnings, isWin: true)
            } else if totalLosses > 0 {
                self.showBetResult(amount: totalLosses, isWin: false)
            }
        }

        // Animate payouts simultaneously for both hands
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            for result in results {
                if result.isWin {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self else { return }
                        let odds = result.isBlackjack ? 1.5 : 1.0
                        self.animateWinnings(for: result.handView.betControl, odds: odds)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                        guard let self = self else { return }
                        self.animateBetCollection(for: result.handView.betControl)
                    }
                } else if result.isPush {
                    // Push - bet stays on control
                } else {
                    // Loss
                    if result.betAmount > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self = self else { return }
                            self.animateChipsAway(from: result.handView.betControl)
                        }
                    }
                }
            }
        }
        
        // Track metrics
        for result in results {
            if result.isWin {
                if result.isBlackjack {
                    blackjackMetrics.blackjacksHit += 1
                }
                blackjackMetrics.wins += 1
            } else if result.isPush {
                blackjackMetrics.pushes += 1
            } else {
                blackjackMetrics.losses += 1
            }
        }
        
        // Note: Split hand cleanup happens when "New Hand" is tapped
    }
    
    private func cleanupSplitHand() {
        guard isSplit else { return }
        
        // Animate split hand out
        if let splitHand = splitHandView {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: [.curveEaseInOut]) {
                splitHand.alpha = 0
            } completion: { [weak self] _ in
                guard let self = self else { return }
                // Remove split hand from stack view
                self.handsContentStackView.removeArrangedSubview(splitHand)
                splitHand.removeFromSuperview()
            }
        }
        
        // Scroll back to first hand
        scrollToHand(0, animated: true)
        
        // Clear split state
        isSplit = false
        activeHandIndex = 0
        splitHandStates = []
        splitHandView = nil
        
        // Force layout update
        view.layoutIfNeeded()
    }
    
    private func discardHandsToTopLeft(completion: (() -> Void)? = nil) {
        // Animate cards further off-screen (beyond the top-left corner)
        let topLeftPoint = CGPoint(
            x: -100, // Well off-screen to the left
            y: -100  // Well off-screen above
        )
        
        let dealerCards = dealerHandView.currentCards
        let playerCards = playerHandView.currentCards
        let splitCards = splitHandView?.currentCards ?? []
        
        guard !dealerCards.isEmpty || !playerCards.isEmpty || !splitCards.isEmpty else {
            completion?()
            return
        }
        
        var completedDiscards = 0
        let totalDiscards = (dealerCards.isEmpty ? 0 : 1) + (playerCards.isEmpty ? 0 : 1) + (splitCards.isEmpty ? 0 : 1)
        
        func checkCompletion() {
            completedDiscards += 1
            if completedDiscards >= totalDiscards {
                // All cards discarded, clear the hands
                dealerHandView.clearCards()
                playerHandView.clearCards()
                splitHandView?.clearCards()
                completion?()
            }
        }
        
        if !dealerCards.isEmpty {
            dealerHandView.discardCards(to: topLeftPoint, in: view) {
                checkCompletion()
            }
        } else {
            checkCompletion()
        }
        
        if !playerCards.isEmpty {
            playerHandView.discardCards(to: topLeftPoint, in: view) {
                checkCompletion()
            }
        } else {
            checkCompletion()
        }
        
        if !splitCards.isEmpty, let splitHand = splitHandView {
            splitHand.discardCards(to: topLeftPoint, in: view) {
                checkCompletion()
            }
        } else {
            checkCompletion()
        }
    }
    
    @objc private func dealerHitTapped() {
        if dealerHandView.revealHoleCard() {
            return
        }
        let deckCenter = view.convert(deckView.deckCenter, from: deckView)
        // Note: randomHandCard() already calls drawCard() internally, so deck count updates automatically
        dealerHandView.dealCard(randomHandCard(), from: deckCenter, in: view)
    }
    
    private func updateControls() {
        if isSplit {
            // Update controls for split state
            let currentHand = activeHandIndex == 0 ? playerHandView : splitHandView!
            let currentState = splitHandStates[activeHandIndex]
            let cards = currentHand.currentCards
            let cardCount = cards.count
            
            // Can't split again after initial split
            let canSplit = false
            
            let controlState = PlayerControlStack.GameState(
                gamePhase: gamePhase,
                cardCount: cardCount,
                hasHit: currentState.hasHit,
                canSplit: canSplit,
                hasBet: currentHand.betControl.betAmount > 0,
                playerHasStood: currentState.hasStood,
                hasDoubled: currentState.hasDoubled
            )
            
            playerControlStack.updateControls(for: controlState)
        } else {
            // Normal single hand controls
            let cards = playerHandView.currentCards
            let cardCount = cards.count
            
            // Check if can split (first two cards have same rank)
            let canSplit = cardCount >= 2 && cards.count >= 2 && cards[0].rank == cards[1].rank
            
            let controlState = PlayerControlStack.GameState(
                gamePhase: gamePhase,
                cardCount: cardCount,
                hasHit: hasPlayerHit,
                canSplit: canSplit,
                hasBet: playerHandView.betControl.betAmount > 0,
                playerHasStood: hasPlayerStood,
                hasDoubled: hasPlayerDoubled
            )
            
            playerControlStack.updateControls(for: controlState)
        }
        
        // Lock bet once hand begins (prevent addition/removal)
        let betLocked = gamePhase != .waitingForBet && gamePhase != .readyToDeal
        playerHandView.betControl.setBetRemovalDisabled(betLocked)
        playerHandView.betControl.isEnabled = !betLocked
        
        // Also disable split hand bet control if it exists
        if let splitHand = splitHandView {
            splitHand.betControl.setBetRemovalDisabled(betLocked)
            splitHand.betControl.isEnabled = !betLocked
        }
        
        bonusBetControls.forEach { control in
            control.setBetRemovalDisabled(betLocked)
            control.isEnabled = !betLocked
        }
        
        // Update New Hand/Ready button visibility and text
        let shouldShowButton = gamePhase == .readyToDeal || gamePhase == .gameOver
        let shouldBeEnabled = (gamePhase == .readyToDeal && playerHandView.betControl.betAmount > 0) || gamePhase == .gameOver
        
        // Update button text based on phase
        if gamePhase == .readyToDeal {
            newHandButton.setTitle("Ready?", for: .normal)
        } else if gamePhase == .gameOver {
            newHandButton.setTitle("New Hand", for: .normal)
        }
        
        // Update button enabled state
        newHandButton.isEnabled = shouldBeEnabled
        if !shouldBeEnabled && gamePhase == .readyToDeal {
            // Disabled state styling
            UIView.animate(withDuration: 0.2) {
                self.newHandButton.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.5)
                self.newHandButton.setTitleColor(HardwayColors.label.withAlphaComponent(0.5), for: .normal)
                self.newHandButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.2).cgColor
            }
        } else {
            // Enabled state styling
            UIView.animate(withDuration: 0.2) {
                self.newHandButton.backgroundColor = HardwayColors.surfaceGray
                self.newHandButton.setTitleColor(.white, for: .normal)
                self.newHandButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
            }
        }
        
        // Show/hide button with animation
        if shouldShowButton && newHandButton.isHidden {
            // Show button with animation
            newHandButton.isHidden = false
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.newHandButton.alpha = 1
                self.newHandButton.transform = .identity
            }
        } else if !shouldShowButton && !newHandButton.isHidden {
            // Hide button with animation
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.newHandButton.alpha = 0
                self.newHandButton.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            } completion: { _ in
                self.newHandButton.isHidden = true
                self.newHandButton.transform = .identity
            }
        }
        
        // Update shimmer based on current state
        updateBetShimmer()
    }

    private func configureBonusBetControl(_ control: BonusBetControl) {
        control.getSelectedChipValue = { [weak self] in
            return self?.selectedChipValue ?? 1
        }
        control.getBalance = { [weak self] in
            return self?.balance ?? 200
        }
        control.onBetPlaced = { [weak self, weak control] amount in
            guard let self = self, let control = control else { return }
            if self.gamePhase != .waitingForBet && self.gamePhase != .readyToDeal {
                control.betAmount -= amount
                HapticsHelper.lightHaptic()
                return
            }
            self.balance -= amount
            self.trackBet(amount: amount, isMainBet: false)
        }
        control.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
        }
        control.canRemoveBet = { [weak self] in
            guard let self = self else { return true }
            return self.gamePhase == .waitingForBet || self.gamePhase == .readyToDeal
        }
    }

    private func checkAndPayBonusBets(playerCards: [BlackjackHandView.Card]) {
        // Bonus bets only check the first two cards
        guard playerCards.count >= 2 else { return }
        
        let firstCard = playerCards[0]
        let secondCard = playerCards[1]
        
        // Check each bonus bet
        for control in bonusBetControls {
            guard control.betAmount > 0 else { continue }
            
            var isWin = false
            var odds: Double = 0.0
            var winMessage: String? = nil
            
            // Determine which bonus bet this is based on title
            if control.title == "Perfect Pairs" {
                // Perfect Pairs: Check for all pair types and pay the highest applicable odds
                if firstCard.rank == secondCard.rank {
                    isWin = true
                    
                    // Determine pair type and payout (check highest odds first)
                    if firstCard.suit == secondCard.suit {
                        // Perfect Pair: same rank and suit - pays 30:1 (highest)
                        odds = 30.0
                        winMessage = "Perfect Pair! Identical \(firstCard.rank.rawValue)s pay 30:1!"
                    } else {
                        // Check if same color (colored pair) or different color (mixed pair)
                        // Red suits: hearts, diamonds
                        // Black suits: clubs, spades
                        let firstIsRed = (firstCard.suit == .hearts || firstCard.suit == .diamonds)
                        let secondIsRed = (secondCard.suit == .hearts || secondCard.suit == .diamonds)
                        let isSameColor = (firstIsRed == secondIsRed)
                        
                        if isSameColor {
                            // Colored Pair: same rank, same color, different suits - pays 10:1
                            odds = 10.0
                            winMessage = "Colored Pair! \(firstCard.rank.rawValue)s pay 10:1!"
                        } else {
                            // Mixed Pair: same rank, different colors - pays 5:1 (lowest)
                            odds = 5.0
                            winMessage = "Mixed Pair! \(firstCard.rank.rawValue)s pay 5:1!"
                        }
                    }
                }
            } else if control.title == "Royal Match" {
                // Royal Match: Check for both Royal Match (K+Q suited) and Suited Cards (any suited)
                // Pay the highest applicable odds
                if firstCard.suit == secondCard.suit {
                    isWin = true
                    
                    // Check if it's a Royal Match (King and Queen of same suit)
                    let isKing = (firstCard.rank == .king || secondCard.rank == .king)
                    let isQueen = (firstCard.rank == .queen || secondCard.rank == .queen)
                    let isRoyalMatch = isKing && isQueen
                    
                    if isRoyalMatch {
                        // Royal Match: K+Q suited - pays 25:1 (highest)
                        odds = 25.0
                        winMessage = "Royal Match! King & Queen suited pay 25:1!"
                    } else {
                        // Suited Cards: Any two suited cards - pays 3:1
                        odds = 3.0
                        winMessage = "Suited Match! Suited cards pay 3:1!"
                    }
                }
            }
            
            if isWin {
                let betAmount = control.betAmount
                let winAmount = Int(Double(betAmount) * odds)

                // Show bet result container with bonus label
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.showBetResult(amount: winAmount, isWin: true, showBonus: true)
                }

                // Animate winnings from house to bonus bet control (offset), then both to balance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    guard let self = self else { return }
                    self.animateBonusBetWinnings(for: control, betAmount: betAmount, winAmount: winAmount, odds: odds)
                }
            } else {
                // Bonus bet lost - animate chips away
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    guard let self = self else { return }
                    if control.betAmount > 0 {
                        self.animateChipsAway(from: control)
                    }
                }
            }
        }
    }
    
    private func clearBonusBetsIfNeeded() {
        // Note: Winning and losing bonus bets are handled in checkAndPayBonusBets()
        // This method is kept for any edge cases where bets weren't handled
        // (e.g., if playerCards.count < 2)
        for control in bonusBetControls {
            guard control.betAmount > 0 else { continue }
            // Only clear if not already handled by checkAndPayBonusBets
            // The delay ensures bonus bet animations complete first
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                if control.betAmount > 0 {
                    self.animateChipsAway(from: control)
                }
            }
        }
    }
    
    private func updateBetShimmer() {
        let betAmount = playerHandView.betControl.betAmount
        
        // Shimmer when waiting for bet and no bet is placed
        if gamePhase == .waitingForBet && betAmount == 0 {
            playerHandView.betControl.shimmerTitleLabel()
        } else {
            // Stop shimmer in all other cases
            playerHandView.betControl.stopTitleShimmer()
        }
    }
    
    private func updateInstructionMessage() {
        let betAmount = playerHandView.betControl.betAmount
        
        switch gamePhase {
        case .waitingForBet:
            if betAmount == 0 {
                instructionLabel.showMessage("Place your bet to begin!", shouldFade: false)
            } else {
                instructionLabel.showMessage("Tap 'Ready?' when you're set!", shouldFade: false)
            }
            
        case .readyToDeal:
            instructionLabel.showMessage("Tap 'Ready?' to deal the cards!", shouldFade: false)
            
        case .dealing:
            instructionLabel.showMessage("Dealing cards...", shouldFade: false)
            
        case .playerTurn:
            if isSplit {
                let currentHand = activeHandIndex == 0 ? playerHandView : splitHandView!
                let currentState = splitHandStates[activeHandIndex]
                let cards = currentHand.currentCards
                let playerTotal = calculateHandTotal(cards: cards)
                let handLabel = activeHandIndex == 0 ? "First hand" : "Second hand"
                
                if currentState.hasDoubled {
                    instructionLabel.showMessage("\(handLabel): Double down!", shouldFade: false)
                } else if currentState.busted {
                    instructionLabel.showMessage("\(handLabel): Bust!", shouldFade: false)
                } else if playerTotal > 21 {
                    instructionLabel.showMessage("\(handLabel): Bust! You went over 21.", shouldFade: false)
                } else if playerTotal == 21 && cards.count == 2 {
                    instructionLabel.showMessage("\(handLabel): Blackjack!", shouldFade: false)
                } else if playerTotal == 21 {
                    instructionLabel.showMessage("\(handLabel): Perfect 21!", shouldFade: false)
                } else if playerTotal >= 17 && playerTotal <= 20 {
                    instructionLabel.showMessage("\(handLabel): \(playerTotal). Hit or stand?", shouldFade: false)
                } else if playerTotal >= 12 && playerTotal <= 16 {
                    instructionLabel.showMessage("\(handLabel): \(playerTotal). Dealer shows \(getDealerVisibleTotal()).", shouldFade: false)
                } else {
                    instructionLabel.showMessage("\(handLabel): \(playerTotal). Hit to improve!", shouldFade: false)
                }
            } else {
                let cards = playerHandView.currentCards
                let playerTotal = calculateHandTotal(cards: cards)
                
                if hasPlayerDoubled {
                    instructionLabel.showMessage("Double down! Waiting for dealer...", shouldFade: false)
                } else if playerTotal > 21 {
                    instructionLabel.showMessage("Bust! You went over 21.", shouldFade: false)
                } else if playerTotal == 21 && cards.count == 2 {
                    instructionLabel.showMessage("Blackjack! What a hand!", shouldFade: false)
                } else if playerTotal == 21 {
                    instructionLabel.showMessage("Perfect 21! Consider standing.", shouldFade: false)
                } else if playerTotal >= 17 && playerTotal <= 20 {
                    instructionLabel.showMessage("Strong hand at \(playerTotal). Hit or stand?", shouldFade: false)
                } else if playerTotal >= 12 && playerTotal <= 16 {
                    instructionLabel.showMessage("You have \(playerTotal). Dealer shows \(getDealerVisibleTotal()).", shouldFade: false)
                } else {
                    instructionLabel.showMessage("You have \(playerTotal). Hit to improve your hand!", shouldFade: false)
                }
            }
            
        case .dealerTurn:
            instructionLabel.showMessage("Dealer's turn...", shouldFade: false)
            
        case .gameOver:
            // Will be set when game ends
            break
        }
    }
    
    private func calculateHandTotal(cards: [BlackjackHandView.Card]) -> Int {
        var total = 0
        var aceCount = 0
        
        for card in cards {
            switch card.rank {
            case .ace:
                aceCount += 1
                total += 11
            case .king, .queen, .jack, .ten:
                total += 10
            case .nine:
                total += 9
            case .eight:
                total += 8
            case .seven:
                total += 7
            case .six:
                total += 6
            case .five:
                total += 5
            case .four:
                total += 4
            case .three:
                total += 3
            case .two:
                total += 2
            }
        }
        
        // Adjust for aces
        while total > 21 && aceCount > 0 {
            total -= 10
            aceCount -= 1
        }
        
        return total
    }
    
    private func getDealerVisibleTotal() -> Int {
        let dealerCards = dealerHandView.currentCards
        // Only count the visible card (second card, index 1)
        if dealerCards.count >= 2 {
            return calculateHandTotal(cards: [dealerCards[1]])
        } else if dealerCards.count == 1 {
            // Only one card visible (shouldn't happen, but handle it)
            return calculateHandTotal(cards: dealerCards)
        }
        return 0
    }
    
    // MARK: - Deck Management
    
    private func createAndShuffleDeck() {
        deck.removeAll()
        
        // Create multiple decks based on deckCount
        for _ in 0..<deckCount {
            // Create a standard 52-card deck
            for suit in PlayingCardView.Suit.allCases {
                for rank in PlayingCardView.Rank.allCases {
                    deck.append(BlackjackHandView.Card(rank: rank, suit: suit))
                }
            }
        }
        
        // Shuffle the deck
        deck.shuffle()
    }
    
    private func drawCard() -> BlackjackHandView.Card {
        // Check if we need to reshuffle before drawing
        if deck.isEmpty || deck.count < 6 {
            createAndShuffleDeck()
            deckView.setCardCount(52 * deckCount, animated: true)
            instructionLabel.showMessage("Deck reshuffled!", shouldFade: true)
        }
        
        // Draw and remove the top card (but don't update visual count yet)
        let card = deck.removeFirst()
        return card
    }
    
    private func dealFixedHand(type: FixedHandType) -> (BlackjackHandView.Card, BlackjackHandView.Card, BlackjackHandView.Card, BlackjackHandView.Card) {
        // Create specific card combinations for testing bonus bets
        // Note: Player cards are created directly (not drawn from deck) for testing purposes
        // Dealer cards are still drawn from deck to maintain deck count accuracy
        
        let playerCard1: BlackjackHandView.Card
        let playerCard2: BlackjackHandView.Card
        
        switch type {
        case .perfectPair:
            // Perfect Pair: Same rank and suit (e.g., 7♠, 7♠) - pays 30:1
            playerCard1 = BlackjackHandView.Card(rank: .seven, suit: .spades)
            playerCard2 = BlackjackHandView.Card(rank: .seven, suit: .spades)
            
        case .coloredPair:
            // Colored Pair: Same rank, same color, different suits (e.g., 7♥, 7♦) - pays 10:1
            playerCard1 = BlackjackHandView.Card(rank: .seven, suit: .hearts)
            playerCard2 = BlackjackHandView.Card(rank: .seven, suit: .diamonds)
            
        case .mixedPair:
            // Mixed Pair: Same rank, different colors (e.g., 7♥, 7♣) - pays 5:1
            playerCard1 = BlackjackHandView.Card(rank: .seven, suit: .hearts)
            playerCard2 = BlackjackHandView.Card(rank: .seven, suit: .clubs)
            
        case .royalMatch:
            // Royal Match: Suited pair (e.g., K♥, Q♥) - pays 25:1
            playerCard1 = BlackjackHandView.Card(rank: .king, suit: .hearts)
            playerCard2 = BlackjackHandView.Card(rank: .queen, suit: .hearts)
            
        case .suitedCards:
            // Suited Cards: Any two suited cards (e.g., 7♥, K♥) - pays 3:1
            playerCard1 = BlackjackHandView.Card(rank: .seven, suit: .hearts)
            playerCard2 = BlackjackHandView.Card(rank: .king, suit: .hearts)
            
        case .regular:
            // Regular hand: No bonus (e.g., 7♥, 9♣)
            playerCard1 = BlackjackHandView.Card(rank: .seven, suit: .hearts)
            playerCard2 = BlackjackHandView.Card(rank: .nine, suit: .clubs)
        }
        
        // Dealer cards are always random (drawn from deck to maintain deck count)
        let dealerCard1 = drawCard()
        let dealerCard2 = drawCard()
        
        return (playerCard1, playerCard2, dealerCard1, dealerCard2)
    }
    
    private func randomHandCard() -> BlackjackHandView.Card {
        // Use the actual deck instead of random generation
        return drawCard()
    }
    
    func onCardDealt() {
        // Update deck count when a card animation starts
        deckView.drawCard()
    }
    
    // MARK: - Chip Animations
    
    private func animateBonusBetWinnings(for control: PlainControl, betAmount: Int, winAmount: Int, odds: Double) {
        // Animate winnings to offset position next to betView, then both chips together to balance
        let betPosition = control.getBetViewPosition(in: view)
        
        // Calculate offset position for winnings (to the left of the original bet)
        let offsetX: CGFloat = -35 // Offset to show chips side by side
        let winningsPosition = CGPoint(x: betPosition.x + offsetX, y: betPosition.y)
        
        // Create chip view representing the winnings payout
        let winningsChipView = SmallBetChip()
        winningsChipView.amount = winAmount
        winningsChipView.translatesAutoresizingMaskIntoConstraints = true
        winningsChipView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        winningsChipView.isHidden = false
        view.addSubview(winningsChipView)
        
        // Start winnings chip from center of screen (representing house)
        winningsChipView.center = CGPoint(x: self.view.bounds.midX, y: 0)
        winningsChipView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        
        // Step 1: Animate winnings chip from house to offset position next to betView
        let animator1 = UIViewPropertyAnimator(
            duration: 0.6,
            controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1)
        ) {
            winningsChipView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
            winningsChipView.center = winningsPosition
        }
        
        animator1.addCompletion { [weak self] _ in
            guard let self = self else { return }
            
            // Brief pause to show both chips side by side
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self else { return }
                
                // Create chip view for the original bet (matching the betView)
                let betChipView = SmallBetChip()
                betChipView.amount = betAmount
                betChipView.translatesAutoresizingMaskIntoConstraints = true
                betChipView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
                betChipView.isHidden = false
                self.view.addSubview(betChipView)
                
                // Position bet chip at the betView position
                betChipView.center = betPosition
                betChipView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                
                // Hide the original betView since we're animating a chip representation
                control.betView.alpha = 0
                
                // Step 2: Animate both chips together to balance view
                let balancePosition = self.balanceView.convert(self.balanceView.bounds, to: self.view)
                let balanceCenter = CGPoint(x: balancePosition.maxX - 30, y: balancePosition.midY)
                
                // Animate winnings chip
                let animator2a = UIViewPropertyAnimator(
                    duration: 0.5,
                    controlPoint1: CGPoint(x: 0.85, y: 0),
                    controlPoint2: CGPoint(x: 0.15, y: 1)
                ) {
                    winningsChipView.center = balanceCenter
                    winningsChipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                }
                
                // Animate bet chip (slightly offset horizontally and delayed)
                let animator2b = UIViewPropertyAnimator(
                    duration: 0.5,
                    controlPoint1: CGPoint(x: 0.85, y: 0),
                    controlPoint2: CGPoint(x: 0.15, y: 1)
                ) {
                    betChipView.center = CGPoint(x: balanceCenter.x - 10, y: balanceCenter.y)
                    betChipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                }
                
                animator2a.addCompletion { [weak self] _ in
                    guard let self = self else { return }
                    // Update balance with winnings
                    self.balance += winAmount
                    winningsChipView.removeFromSuperview()
                }
                
                animator2b.addCompletion { [weak self] _ in
                    guard let self = self else { return }
                    // Update balance with original bet
                    self.balance += betAmount
                    betChipView.removeFromSuperview()
                    
                    // Clear the bet from the control
                    control.betAmount = 0
                    control.betView.alpha = 1 // Restore betView visibility
                }
                
                // Start both animations together
                animator2a.startAnimation()
                animator2b.startAnimation(afterDelay: 0.1)
            }
        }
        
        animator1.startAnimation()
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
        var betPosition = control.getBetViewPosition(in: view)
        betPosition.x += 30
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
    
    private func animateBetCollection(for control: PlainControl) {
        guard control.betAmount > 0 else { return }

        // If rebet is enabled, leave the bet on the control and don't animate collection
        if rebetEnabled {
            // Don't add to balance - the bet stays on the control for the next hand
            // The balance was already updated with the winnings, and the bet will be
            // deducted again when the next hand starts in applyRebetIfNeeded
            return
        }

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
        }

        animator.startAnimation()

        // Clear the bet from the control
        control.betAmount = 0
    }
    
    private func animateChipsAway(from control: PlainControl) {
        guard control.betAmount > 0 else { return }
        
        // Store bet amount and position before any changes
        let betAmount = control.betAmount
        let betPosition = control.getBetViewPosition(in: view)
        
        // Hide the betView immediately by setting alpha to 0
        control.betView.alpha = 0
        
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
            guard let self = self else { return }
            control.betAmount = 0
        }
        
        // Animate chip away to top of screen
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

    // MARK: - Rebet Functionality

    private func trackBetForRebet(amount: Int) {
        guard amount > 0 else { return }

        // Check if this bet matches the last bet
        if amount == lastBetAmount {
            consecutiveBetCount += 1
        } else {
            // Different bet amount, reset counter
            consecutiveBetCount = 1
            lastBetAmount = amount
        }

        // If player has bet the same amount 3 times in a row, update rebet amount
        if consecutiveBetCount >= 3 {
            rebetAmount = amount
            UserDefaults.standard.set(rebetAmount, forKey: SettingsKeys.rebetAmount)
        }
    }

    private func applyRebetIfNeeded() {
        guard rebetEnabled else { return }

        // Check if player already has a bet placed
        let currentBet = playerHandView.betControl.betAmount
        if currentBet > 0 {
            // Player already has a bet (from winning the last hand)
            // The bet stayed on the control and was NEVER returned to balance
            // So we don't need to deduct anything - it's already accounted for
            // Just leave it there for the next hand
            return
        }

        // No bet on control (player lost last hand)
        // When player loses, the bet was already deducted and never returned
        // We need to place a new bet and deduct from balance
        guard rebetAmount <= balance else { return }

        // Deduct from balance and set bet on control
        balance -= rebetAmount
        playerHandView.betControl.setDirectBet(rebetAmount)
    }
}

extension BlackjackGameplayViewController: ChipSelectorDelegate {
    func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {
        print("Selected chip value: \(value)")
    }
}

extension BlackjackGameplayViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === handsScrollView, isSplit else { return }
        
        let pageWidth = scrollView.bounds.width + handsContentStackView.spacing
        let currentPage = Int(round(scrollView.contentOffset.x / pageWidth))
        
        // Update active hand index if changed
        if currentPage != activeHandIndex {
            activeHandIndex = currentPage
            updateControls()
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === handsScrollView, isSplit else { return }
        
        let pageWidth = scrollView.bounds.width + handsContentStackView.spacing
        let currentPage = Int(round(scrollView.contentOffset.x / pageWidth))
        
        // Update active hand index if changed
        if currentPage != activeHandIndex {
            activeHandIndex = currentPage
            updateControls()
        }
    }
}
