//
//  BlackjackGameplayViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

final class BlackjackGameplayViewController: UIViewController {

    // Use SideBetType from BlackjackSettingsViewController
    typealias SideBetType = BlackjackSettingsViewController.SideBetType
    
    // Session tracking (managed by SessionManager)
    private let startingBalance: Int = 200
    private var initialBalance: Int = 200 // Store the initial balance to set after UI is ready

    private let dealerHandView = DealerHandView()
    private let playerHandView = PlayerHandView()
    private var splitHandView: PlayerHandView? // Second hand for split

    // Action buttons
    private let standButton = ActionButton(title: "Stand")
    private let doubleButton = ActionButton(title: "Double")
    private let splitButton = CircularActionButton(systemIconName: "arrow.triangle.branch")
    private let insuranceControl = InsuranceControl()
    private var rightButtonStack: UIStackView!
    private var balanceView: BalanceView!
    private var chipSelector: ChipSelector!
    private var bottomStackView: UIStackView!
    private var instructionLabel: InstructionLabel!
    private var newHandButton: UIButton!
    private var readyButton: UIButton!
    private var bonusStackView: UIStackView!
    private var bonusBetControls: [BonusBetControl] = []
    private let deckView = DeckView()
    private var cutCardView: PlayingCardView? // Visible cut card when dealt

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
    private var hasInsuranceBeenChecked = false // Track if insurance has been checked/declined
    private var playerDoubleDownCardIndex: Int? = nil // Track which card is face-down from double down
    private var gamePhase: PlayerControlStack.GamePhase = .waitingForBet

    // MARK: - Managers

    private var settingsManager: BlackjackSettingsManager!
    private var deckManager: BlackjackDeckManager!
    private var sessionManager: BlackjackSessionManager!

    // MARK: - Settings Computed Properties (for backward compatibility)

    private var showTotals: Bool { settingsManager.currentSettings.showTotals }
    private var showDeckCount: Bool { settingsManager.currentSettings.showDeckCount }
    private var showCardCount: Bool { settingsManager.currentSettings.showCardCount }
    private var fixedHandType: FixedHandType? { settingsManager.currentSettings.fixedHandType }

    // MARK: - Deck Computed Properties (for backward compatibility)

    private var deck: [BlackjackHandView.Card] { deckManager.deck }
    private var runningCount: Int { deckManager.runningCount }

    // MARK: - Session Computed Properties (for backward compatibility)

    private var sessionId: String? { sessionManager.sessionId }
    private var handCount: Int { sessionManager.handCount }
    private var blackjackMetrics: BlackjackGameplayMetrics { sessionManager.blackjackMetrics }
    private var playerBusted: Bool = false
    private var deckCount: Int = 1 // Number of decks (1, 2, 4, or 6)
    private var deckPenetration: Double? = nil // nil = full deck, -1.0 = random, otherwise percentage (0.5 = 50%, etc.)
    private var cutCardPosition: Int? = nil // Position in deck where cut card is placed (nil if no cut card)
    private var shouldShuffleAfterHand: Bool = false // Flag to shuffle after current hand completes

    // Rebet tracking
    private var rebetEnabled: Bool = false
    private var rebetAmount: Int = 10 // Default rebet amount
    private var consecutiveBetCount: Int = 0
    private var lastBetAmount: Int = 0

    // Tip tracking
    private var hasShownPlaceBetTip: Bool = false
    private var hasShownTapToHitTip: Bool = false
    private var hasShownBonusBetsTip: Bool = false
    private var hasShownSettingsTip: Bool = false
    private var hasShownDragChipTip: Bool = false
    private var hasShownInsuranceTip: Bool = false

    // Optional session to resume from
    private var resumingSession: GameSession?

    // Custom initializer for resuming a session
    init(resumingSession: GameSession? = nil) {
        self.resumingSession = resumingSession
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    struct HandResult {
        let isWin: Bool
        let isPush: Bool
        let isBlackjack: Bool
        let playerTotal: Int
        let dealerTotal: Int
        
        var message: String {
            if isPush {
                if isBlackjack {
                    return "Both have blackjack! Push!"
                } else {
                    return "Push! Both have \(playerTotal)."
                }
            } else if isWin {
                if isBlackjack {
                    return dealerTotal > 21 ? "Blackjack! Dealer busts! You win!" : "Blackjack! You win!"
                } else {
                    return dealerTotal > 21 ? "Dealer busts! You win!" : "You win! \(playerTotal) beats \(dealerTotal)."
                }
            } else {
                if playerTotal > 21 && dealerTotal > 21 {
                    return "Both bust! Dealer wins."
                } else if playerTotal > 21 {
                    return "Bust! You went over 21. Dealer wins."
                } else {
                    return "Dealer wins! \(dealerTotal) beats \(playerTotal)."
                }
            }
        }
        
        var winOdds: Double {
            return isBlackjack ? 1.5 : 1.0
        }
    }
    
    var selectedChipValue: Int {
        return chipSelector?.selectedValue ?? 1
    }

    // Peek amount for split hands - relative to screen width (20% on each side)
    private func getPeekAmount() -> CGFloat {
        return view.bounds.width * 0.20
    }

    private func getTotalPeekAmount() -> CGFloat {
        return getPeekAmount() * 2 // Both sides
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
        
        // Create and shuffle the deck first
        createAndShuffleDeck()
        
        setupNavigationBarMenu()
        setupInstructionLabel()
        setupDeckView()
        setupDealerHandView()
        setupBonusStackView()
        setupBalanceView()
        setupChipSelector()
        setupBottomStackView()

        // Set the initial balance now that balanceView is created
        balance = initialBalance

        setupPlayerHandView()
        setupActionButtons()
        
        // Apply loaded settings to UI
        dealerHandView.setTotalsHidden(!showTotals)
        playerHandView.setTotalsHidden(!showTotals)
        deckView.setCountLabelVisible(showDeckCount)
        deckView.setCardCountLabelVisible(showCardCount)

        resetGame()
        // Ensure controls are updated after initial setup
        updateControls()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Track screen visit for tip rules
        trackScreenVisit()
        // Show tips if appropriate
        showTips()
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
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Stop all tip observations
        stopAllTipObservations()

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
    
    // MARK: - Manager Setup

    private func setupManagers() {
        // Initialize settings manager
        settingsManager = BlackjackSettingsManager()
        settingsManager.delegate = self

        // Initialize deck manager with settings
        deckManager = BlackjackDeckManager(
            deckCount: settingsManager.currentSettings.deckCount,
            deckPenetration: settingsManager.currentSettings.deckPenetration,
            fixedHandType: settingsManager.currentSettings.fixedHandType
        )
        deckManager.delegate = self

        // Initialize session manager (with resuming session if available)
        sessionManager = BlackjackSessionManager(
            startingBalance: startingBalance,
            resumingSession: resumingSession
        )
        sessionManager.delegate = self

        // Set initial balance from session manager
        initialBalance = sessionManager.currentBalance

        // Apply loaded settings to deck count (moved from loadSettings)
        deckCount = settingsManager.currentSettings.deckCount
        deckPenetration = settingsManager.currentSettings.deckPenetration
        rebetEnabled = settingsManager.currentSettings.rebetEnabled
        rebetAmount = settingsManager.currentSettings.rebetAmount
    }
    
    private func toggleTotals() {
        settingsManager.toggleTotals()
        // UI updates handled in settingsDidChange delegate method
    }

    private func toggleDeckCount() {
        settingsManager.toggleDeckCount()
        // UI updates handled in settingsDidChange delegate method
    }

    private func setDeckCount(_ count: Int) {
        settingsManager.setDeckCount(count)
        // UI updates handled in settingsDidChange delegate method
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
        dealerHandView.isUserInteractionEnabled = false // Disable tapping on dealer hand
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
        bonusStackView.spacing = 8

        // Load selected side bets from settings
        setupBonusBetControls()
        
        // Configure insurance control
        configureInsuranceControl()

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

        NSLayoutConstraint.activate([
            bonusStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bonusStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bonusStackView.heightAnchor.constraint(equalToConstant: 55),
            fixedTopPosition,
            minSpacingFromDealer
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
    
    
    private func setupPlayerHandView() {
        // Create the scroll view for hands
        handsScrollView = UIScrollView()
        handsScrollView.translatesAutoresizingMaskIntoConstraints = false
        handsScrollView.isPagingEnabled = false // We'll implement custom paging in scrollViewWillEndDragging
        handsScrollView.showsHorizontalScrollIndicator = false
        handsScrollView.showsVerticalScrollIndicator = false
        handsScrollView.alwaysBounceVertical = false
        handsScrollView.alwaysBounceHorizontal = true
        handsScrollView.bounces = true
        handsScrollView.isDirectionalLockEnabled = true  // Lock to horizontal scrolling only
        handsScrollView.contentInsetAdjustmentBehavior = .never  // Prevent iOS from adjusting insets
        handsScrollView.clipsToBounds = false  // Allow content to show beyond scroll view bounds
        handsScrollView.isScrollEnabled = false // Will be enabled when split
        handsScrollView.delegate = self
        handsScrollView.decelerationRate = .fast // Faster deceleration for snappier paging
        // Add initial content insets to center single hand (will be updated when split)
        handsScrollView.contentInset = UIEdgeInsets(top: 0, left: getPeekAmount(), bottom: 0, right: getPeekAmount())
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

        // Configure tap action to trigger hit
        playerHandView.onTap = { [weak self] in
            guard let self = self else { return }
            // Only trigger hit during player's turn and when on first hand
            if self.gamePhase == .playerTurn && (!self.isSplit || self.activeHandIndex == 0) {
                self.playerHitTapped()
            }
        }

        // Configure when tapping is allowed
        playerHandView.canTap = { [weak self] in
            guard let self = self else { return false }
            // Allow tapping only during player's turn, when on first hand, and not busted
            if self.isSplit {
                // In split mode, check if first hand is active and not busted
                return self.gamePhase == .playerTurn &&
                       self.activeHandIndex == 0 &&
                       !self.splitHandStates[0].busted
            } else {
                // In regular mode, check if not busted
                return self.gamePhase == .playerTurn && !self.playerBusted
            }
        }

        // Configure the bet control with closures
        configurePlayerHandBetControl(playerHandView.betControl)
        
        // Set lower compression resistance on playerHandView so it compresses before balanceView
        playerHandView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        // Set a minimum height for normal size (approximately 200pt for cards + bet control)
        let minimumHeight: CGFloat = 200

        NSLayoutConstraint.activate([
            // Scroll view constraints - edge to edge for better split hand visibility
            handsScrollView.topAnchor.constraint(equalTo: bonusStackView.bottomAnchor, constant: 16),
            handsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            handsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            handsScrollView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -24),

            // Content stack view constraints (fills scroll view height, width determined by number of hands)
            handsContentStackView.topAnchor.constraint(equalTo: handsScrollView.topAnchor),
            handsContentStackView.bottomAnchor.constraint(equalTo: handsScrollView.bottomAnchor),
            handsContentStackView.leadingAnchor.constraint(equalTo: handsScrollView.leadingAnchor),
            handsContentStackView.trailingAnchor.constraint(equalTo: handsScrollView.trailingAnchor),
            handsContentStackView.heightAnchor.constraint(equalTo: handsScrollView.heightAnchor),

            // Each hand should be slightly less than scroll view width to show peeking
            // Using multiplier 0.6 (each hand is 60% of screen, leaving 20% peek on each side)
            playerHandView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6)
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

            // Dismiss place bet tip once user places their first bet
            NNTipManager.shared.dismissTip(BlackjackTips.placeBetTip)
        }
        betControl.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
            self.checkBetStatus()

            // Dismiss drag chip tip once user removes a bet
            NNTipManager.shared.dismissTip(BlackjackTips.drapChipTip)
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
        // Calculate the width of each hand plus spacing
        let handWidth = handsScrollView.bounds.width - 160 // Each hand is 160pt narrower than scroll view
        let spacing = handsContentStackView.spacing
        let pageWidth = handWidth + spacing

        // Calculate offset (accounting for content inset)
        let offset = CGPoint(x: pageWidth * CGFloat(handIndex) - handsScrollView.contentInset.left, y: 0)
        handsScrollView.setContentOffset(offset, animated: animated)
    }
    
    private func setupActionButtons() {
        // Stand button action
        standButton.addTarget(self, action: #selector(playerStandTapped), for: .touchUpInside)

        // Double button action
        doubleButton.addTarget(self, action: #selector(playerDoubleTapped), for: .touchUpInside)

        // Split button action
        splitButton.addTarget(self, action: #selector(playerSplitTapped), for: .touchUpInside)

        // Set up New Hand button
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

        // Set up Ready button with subtitle label for insurance status
        readyButton = UIButton(type: .system)
        readyButton.translatesAutoresizingMaskIntoConstraints = false
        readyButton.setTitle("Ready?", for: .normal)
        readyButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        readyButton.backgroundColor = HardwayColors.surfaceGray
        readyButton.setTitleColor(.white, for: .normal)
        readyButton.layer.cornerRadius = 16
        readyButton.layer.borderWidth = 1.5
        readyButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
        readyButton.isHidden = false
        readyButton.alpha = 1
        readyButton.isEnabled = false
        readyButton.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.5)
        readyButton.setTitleColor(HardwayColors.label.withAlphaComponent(0.5), for: .normal)
        readyButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.2).cgColor
        readyButton.addTarget(self, action: #selector(readyTapped), for: .touchUpInside)
        
        // Add subtitle label for insurance status
        let insuranceStatusLabel = UILabel()
        insuranceStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        insuranceStatusLabel.textAlignment = .center
        insuranceStatusLabel.font = .systemFont(ofSize: 10, weight: .regular)
        insuranceStatusLabel.textColor = HardwayColors.label.withAlphaComponent(0.7)
        insuranceStatusLabel.tag = 999 // Tag to find it later
        readyButton.addSubview(insuranceStatusLabel)
        
        NSLayoutConstraint.activate([
            insuranceStatusLabel.centerXAnchor.constraint(equalTo: readyButton.centerXAnchor),
            insuranceStatusLabel.topAnchor.constraint(equalTo: readyButton.titleLabel!.bottomAnchor, constant: 2),
            insuranceStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: readyButton.leadingAnchor, constant: 4),
            insuranceStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: readyButton.trailingAnchor, constant: -4)
        ])

        // Create vertical stack for Stand and Double buttons in bottom right
        rightButtonStack = UIStackView()
        rightButtonStack.translatesAutoresizingMaskIntoConstraints = false
        rightButtonStack.axis = .vertical
        rightButtonStack.spacing = 8
        rightButtonStack.alignment = .fill
        rightButtonStack.distribution = .fillEqually

        // Add Stand and Double to stack
        rightButtonStack.addArrangedSubview(standButton)
        rightButtonStack.addArrangedSubview(doubleButton)

        view.addSubview(rightButtonStack)
        view.addSubview(newHandButton)
        view.addSubview(readyButton)

        // Set up split button on the right side
        splitButton.isHidden = true
        splitButton.alpha = 0
        view.addSubview(splitButton)
        
        // Set up insurance control on the left side (same pattern as split button)
        insuranceControl.isHidden = true
        insuranceControl.alpha = 0
        view.addSubview(insuranceControl)

        NSLayoutConstraint.activate([
            // Right button stack (Stand/Double) in bottom right corner
            rightButtonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            rightButtonStack.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
            rightButtonStack.topAnchor.constraint(equalTo: bottomStackView.topAnchor),
            rightButtonStack.widthAnchor.constraint(equalToConstant: 120),

            // New Hand button in bottom RIGHT (same position as Stand/Double stack)
            newHandButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            newHandButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
            newHandButton.topAnchor.constraint(equalTo: bottomStackView.topAnchor),
            newHandButton.widthAnchor.constraint(equalToConstant: 120),

            // Ready button in bottom RIGHT (same position as New Hand button)
            readyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            readyButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
            readyButton.topAnchor.constraint(equalTo: bottomStackView.topAnchor),
            readyButton.widthAnchor.constraint(equalToConstant: 120),

            // Split button positioned on right side
            splitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            splitButton.centerYAnchor.constraint(equalTo: playerHandView.centerYAnchor, constant: 0),
            
            // Insurance control positioned on left side (leading edge), opposite split button
            insuranceControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            insuranceControl.centerYAnchor.constraint(equalTo: playerHandView.centerYAnchor, constant: 0)
        ])

        // Initially hide the Stand/Double stack
        rightButtonStack.isHidden = true
        rightButtonStack.alpha = 0
    }
    
    var balance: Int {
        get { sessionManager?.currentBalance ?? (balanceView?.balance ?? startingBalance) }
        set {
            sessionManager?.currentBalance = newValue
            balanceView?.balance = newValue
            chipSelector?.updateAvailableChips(balance: newValue)
        }
    }
    
    private func startSession() {
        // Session is already initialized in setupManagers
        // Just start it if it's a new session
        if resumingSession == nil {
            sessionManager.startSession()
        }
    }

    private func recordBalanceSnapshot() {
        sessionManager.recordBalanceSnapshot()
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
        sessionManager.trackBet(amount: amount, isMainBet: isMainBet)
        updateConcurrentBets()
    }
    
    private func updateConcurrentBets() {
        var concurrentCount = 0
        if playerHandView.betControl.betAmount > 0 { concurrentCount += 1 }
        for control in bonusBetControls {
            if control.betAmount > 0 { concurrentCount += 1 }
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
        return sessionManager.hasActiveSession()
    }
    
    @objc private func shuffleTapped() {
        resetGame()
    }
    
    private func showCurrentGameDetails() {
        guard let snapshot = currentSessionSnapshot() else { return }
        let detailViewController = GameDetailViewController(session: snapshot)

        // Don't allow continuing from current session view (user is already playing)
        // The onContinueSession callback is intentionally left nil here

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
        // Store previous deck count setting before loading new settings
        let previousDeckCount = deckCount

        // Reload settings from manager
        settingsManager.loadSettings()

        // Apply settings to local properties
        deckCount = settingsManager.currentSettings.deckCount
        deckPenetration = settingsManager.currentSettings.deckPenetration
        rebetEnabled = settingsManager.currentSettings.rebetEnabled
        rebetAmount = settingsManager.currentSettings.rebetAmount

        // Update UI based on settings
        dealerHandView.setTotalsHidden(!showTotals)
        playerHandView.setTotalsHidden(!showTotals)
        splitHandView?.setTotalsHidden(!showTotals)
        deckView.setCountLabelVisible(showDeckCount)
        deckView.setCardCountLabelVisible(showCardCount)

        // Only reshuffle if the deck count setting actually changed
        if deckCount != previousDeckCount {
            createAndShuffleDeck()
            deckView.setCardCount(52 * deckCount, animated: true)
        }

        // Reload bonus bet controls if we're in a safe state (waiting for bet or ready to deal)
        // This allows side bet selection changes to take effect
        if gamePhase == .waitingForBet || gamePhase == .readyToDeal {
            setupBonusBetControls()
        }

        updateNavigationBarMenu()
    }

    private func showTips() {
        // Priority 1: Place bet tip (highest priority - first thing users need to do)
        if NNTipManager.shared.shouldShowTip(BlackjackTips.placeBetTip),
           !hasShownPlaceBetTip,
           gamePhase == .waitingForBet {

            hasShownPlaceBetTip = true

            // Show tip anchored to the bottom of the chip selector
            NNTipManager.shared.showTip(
                BlackjackTips.placeBetTip,
                sourceView: playerHandView.betControl,
                in: self,
                pinToEdge: .top,
                offset: CGPoint(x: 0, y: -8),
                centerHorizontally: true
            )
            return // Always return after attempting to show this highest priority tip
        }

        // Priority 2: Tap to hit tip (second priority - show during player's turn)
        if NNTipManager.shared.shouldShowTip(BlackjackTips.tapToHitTip),
           !hasShownTapToHitTip,
           gamePhase == .playerTurn,
           !isSplit {

            hasShownTapToHitTip = true

            // Show tip anchored to the top of the player hand view
            NNTipManager.shared.showTip(
                BlackjackTips.tapToHitTip,
                sourceView: playerHandView.handView.cardContainer,
                in: self,
                pinToEdge: .top,
                offset: CGPoint(x: 0, y: -8),
                centerHorizontally: true
            )
            return // Return after successfully showing the tip
        }

        // Priority 3: Bonus bets tip (third priority - show after 3 hands played)
        if NNTipManager.shared.shouldShowTip(BlackjackTips.bonusBetsTip),
           !hasShownBonusBetsTip,
           handCount >= 3,
           gamePhase == .waitingForBet,
           !bonusBetControls.isEmpty {

            hasShownBonusBetsTip = true

            // Show tip anchored to the bottom of the first bonus bet control
            if let firstBonusBet = bonusBetControls.first {
                NNTipManager.shared.showTip(
                    BlackjackTips.bonusBetsTip,
                    sourceView: firstBonusBet,
                    in: self,
                    pinToEdge: .top,
                    offset: CGPoint(x: 0, y: -8)
                )
            }
            return // Return after successfully showing the tip
        }

        // Priority 4: Drag chip tip (fourth priority - show after 5-6 hands)
        if NNTipManager.shared.shouldShowTip(BlackjackTips.drapChipTip),
           !hasShownDragChipTip,
           handCount >= 5,
           gamePhase == .waitingForBet,
           playerHandView.betControl.betAmount > 0 {

            hasShownDragChipTip = true

            // Show tip centered horizontally, anchored to the bet control
            NNTipManager.shared.showTip(
                BlackjackTips.drapChipTip,
                sourceView: playerHandView.betControl,
                in: self,
                pinToEdge: .top,
                offset: CGPoint(x: 0, y: -8),
                centerHorizontally: true
            )
            return // Return after successfully showing the tip
        }
        
        // Priority 5: Insurance tip (show when insurance becomes available for the first time)
        if NNTipManager.shared.shouldShowTip(BlackjackTips.insuranceTip),
           !hasShownInsuranceTip,
           isInsuranceAvailable,
           !insuranceControl.isHidden {

            hasShownInsuranceTip = true

            // Show tip anchored to the insurance control
            NNTipManager.shared.showTip(
                BlackjackTips.insuranceTip,
                sourceView: insuranceControl,
                in: self,
                pinToEdge: .top,
                offset: CGPoint(x: 0, y: -8)
            )
            return // Return after successfully showing the tip
        }
    }
    
    private func currentSessionSnapshot() -> GameSession? {
        return sessionManager.currentSessionSnapshot()
    }
    
    private func resetGame() {
        gamePhase = .waitingForBet
        hasPlayerHit = false
        hasPlayerStood = false
        hasPlayerDoubled = false
        hasInsuranceBeenChecked = false
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
        guard gamePhase == .gameOver else { return }

        // Clean up split hand if it exists before resetting
        if isSplit {
            cleanupSplitHand()
        }

        // Immediately change phase to prevent re-triggering discard animation
        gamePhase = .waitingForBet
        hasPlayerHit = false
        hasPlayerStood = false
        hasPlayerDoubled = false
        hasInsuranceBeenChecked = false
        playerDoubleDownCardIndex = nil
        playerBusted = false
        updateControls()

        // Update last balance before next hand
        sessionManager.updateLastBalanceBeforeHand(balance)

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
    
    @objc private func readyTapped() {
        // Check if insurance is available and needs to be checked
        if isInsuranceAvailable {
            // Check dealer blackjack for insurance
            checkDealerBlackjackAfterInsurance()
            return
        }
        
        // Normal ready flow - only proceed if in readyToDeal phase
        guard gamePhase == .readyToDeal else { return }
        guard playerHandView.betControl.betAmount > 0 else { return }

        // Record balance before hand starts
        sessionManager.updateLastBalanceBeforeHand(balance)

        // Snapshot bet size before dealing
        let mainBet = playerHandView.betControl.betAmount
        var totalBonusBet = 0
        for control in bonusBetControls {
            totalBonusBet += control.betAmount
        }
        let totalBetSize = mainBet + totalBonusBet
        sessionManager.snapshotBetSize(totalBetSize)

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
        // Clear insurance bet
        insuranceControl.betAmount = 0
        // Show placeholders before dealing
        dealerHandView.showPlaceholders()
        playerHandView.showPlaceholders()
        dealCards()
    }
    
    private func setFixedHand(_ handType: FixedHandType?) {
        deckManager.setFixedHandType(handType)
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
        case .aceUp: return "Ace Up"
        case .dealerBlackjack: return "Dealer BlackJack"
        case .random: return "Random"
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
        
        // Dismiss tap to hit tip when user taps to hit (either via button or card tap)
        NNTipManager.shared.dismissTip(BlackjackTips.tapToHitTip)
        
        // If insurance is available, trigger insurance check instead of hitting
        if isInsuranceAvailable {
            checkDealerBlackjackAfterInsurance()
            return
        }
        
        executePlayerHit()
    }
    
    private func executePlayerHit() {
        // Dismiss tap to hit tip once user hits for the first time
        NNTipManager.shared.dismissTip(BlackjackTips.tapToHitTip)

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
    
    @objc private func playerStandTapped() {
        guard gamePhase == .playerTurn else { return }
        
        // If insurance is available, trigger insurance check instead of standing
        if isInsuranceAvailable {
            checkDealerBlackjackAfterInsurance()
            return
        }
        
        executePlayerStand()
    }
    
    private func executePlayerStand() {
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
    
    @objc private func playerSplitTapped() {
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

        // Configure tap action to trigger hit on split hand
        splitHand.onTap = { [weak self] in
            guard let self = self else { return }
            // Only trigger hit during player's turn and when split hand is active
            if self.gamePhase == .playerTurn && self.isSplit && self.activeHandIndex == 1 {
                self.playerHitTapped()
            }
        }

        // Configure when tapping is allowed on split hand
        splitHand.canTap = { [weak self] in
            guard let self = self else { return false }
            // Allow tapping only during player's turn, when split hand is active, and not busted
            return self.gamePhase == .playerTurn &&
                   self.isSplit &&
                   self.activeHandIndex == 1 &&
                   !self.splitHandStates[1].busted
        }

        // Configure split hand bet control
        configurePlayerHandBetControl(splitHand.betControl)
        splitHand.betControl.betAmount = betAmount
        
        // Move second card to split hand
        let secondCard = cards[1]
        let firstCard = cards[0]

        // Add split hand to scroll view and animate it in
        animateSplitHandIn(splitHand: splitHand)

        // Prepare the split hand with the second card (without animation, hidden initially)
        splitHand.setCardsWithoutAnimation([secondCard])

        // Animate the second card from original hand to split hand
        animateCardToSplitHand(card: secondCard, from: playerHandView, to: splitHand, completion: { [weak self] in
            guard let self = self else { return }

            // After animation completes, update both hands without animation
            // Update original hand to just have the first card
            self.playerHandView.setCardsWithoutAnimation([firstCard])

            // Set up split hand with the second card (without animation)
            splitHand.setCardsWithoutAnimation([secondCard])

            // Reveal the card in the split hand (it was hidden during animation)
            if let firstCardView = splitHand.cardViewsForAnimation.first {
                firstCardView.alpha = 1
            }

            // Update controls - player can now choose to hit either hand
            self.updateControls()
        })
    }
    
    private func animateSplitHandIn(splitHand: PlayerHandView) {
        // Add split hand to the content stack view
        handsContentStackView.addArrangedSubview(splitHand)

        // Add width constraint to match first hand (60% of screen, leaving 20% peek on each side)
        splitHand.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6).isActive = true

        // Update content insets to center hands (20% on each side for peeking)
        handsScrollView.contentInset = UIEdgeInsets(top: 0, left: getPeekAmount(), bottom: 0, right: getPeekAmount())

        // Enable scrolling now that we have two hands
        handsScrollView.isScrollEnabled = true

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

    private func animateCardToSplitHand(card: BlackjackHandView.Card, from sourceHandView: PlayerHandView, to targetHandView: PlayerHandView, completion: @escaping () -> Void) {
        // Force layout to ensure accurate positions
        view.layoutIfNeeded()

        // Get the second card view from the source hand (index 1)
        let sourceCardViews = sourceHandView.cardViewsForAnimation
        guard sourceCardViews.count >= 2 else {
            // Fallback: just complete immediately if we can't find the card
            completion()
            return
        }

        let secondCardView = sourceCardViews[1]

        // Get source position (second card in the original hand)
        guard let sourceFrame = sourceHandView.getCardViewFrame(at: 1, in: view) else {
            completion()
            return
        }
        let sourceCenter = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)

        // Get target position from the actual card position in the split hand
        // The split hand should already have the card added (but hidden)
        let targetCardViews = targetHandView.cardViewsForAnimation
        guard targetCardViews.count >= 1 else {
            completion()
            return
        }

        // Hide the target card initially so we can animate to its position
        targetCardViews[0].alpha = 0

        // Force layout on target hand to get accurate position
        targetHandView.layoutIfNeeded()

        // Get the actual target frame of the first card in the split hand
        guard let targetFrame = targetHandView.getCardViewFrame(at: 0, in: view) else {
            completion()
            return
        }
        let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)

        // Get the transform of the target card
        let targetTransform = targetCardViews[0].transform

        // Create temporary card for animation
        let tempCard = PlayingCardView()
        if card.isCutCard {
            tempCard.configureCutCard()
        } else {
            tempCard.configure(rank: card.rank, suit: card.suit)
        }
        tempCard.setFaceDown(false, animated: false)

        // Apply shadow
        tempCard.layer.masksToBounds = false
        tempCard.layer.shadowColor = UIColor.black.cgColor
        tempCard.layer.shadowOpacity = 0.18
        tempCard.layer.shadowRadius = 6
        tempCard.layer.shadowOffset = CGSize(width: 0, height: 3)

        // Match the size and transform of the source card
        tempCard.bounds = CGRect(origin: .zero, size: sourceFrame.size)
        tempCard.center = sourceCenter
        tempCard.transform = secondCardView.transform

        view.addSubview(tempCard)

        // Hide the original second card immediately
        secondCardView.alpha = 0

        // Animate to target position
        UIView.animate(withDuration: 0.4, delay: 0.1, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.3, options: [.curveEaseInOut]) {
            tempCard.center = targetCenter
            tempCard.transform = targetTransform // Match the target card's transform
        } completion: { _ in
            // Remove temporary card
            tempCard.removeFromSuperview()

            // Call completion to update the actual hands
            completion()
        }

        // Trigger haptic
        HapticsHelper.superLightHaptic()
    }

    private func switchFocusToHand(_ handIndex: Int) {
        guard isSplit, handIndex >= 0 && handIndex <= 1 else { return }
        guard activeHandIndex != handIndex else { return }
        
        activeHandIndex = handIndex
        
        // Scroll to the correct hand
        scrollToHand(handIndex, animated: true)
        
        updateControls()
    }
    
    @objc private func playerDoubleTapped() {
        guard gamePhase == .playerTurn && !hasPlayerStood else { return }
        
        // If insurance is available, trigger insurance check instead of doubling
        if isInsuranceAvailable {
            checkDealerBlackjackAfterInsurance()
            return
        }
        
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
            sessionManager.recordDoubleDown()
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
            
            executePlayerDouble()
        }
    }
    
    private func executePlayerDouble() {
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
        sessionManager.recordDoubleDown()
        balance -= betAmount // Deduct the additional bet
        playerHandView.betControl.betAmount = betAmount * 2
        
        // Update pending bet size snapshot
        var totalBonusBet = 0
        for control in bonusBetControls {
            totalBonusBet += control.betAmount
        }
        let totalBetSize = playerHandView.betControl.betAmount + totalBonusBet
        sessionManager.snapshotBetSize(totalBetSize)
        
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
        
        // Evaluate hand result
        let result = evaluateHandResult(playerCards: playerCards, dealerCards: dealerCards, playerBusted: playerBusted)
        let isPlayerBlackjack = result.isBlackjack
        let isDealerBlackjack = isBlackjack(cards: dealerCards)
        
        // Track hand outcome
        sessionManager.incrementHandCount()

        // Update metrics based on result
        if result.isWin {
            sessionManager.recordWin(isBlackjack: isPlayerBlackjack)
        } else if result.isPush {
            sessionManager.recordPush()
        } else {
            sessionManager.recordLoss()
            if playerTotal > 21 {
                playerBusted = true
            }
        }
        
        instructionLabel.showMessage(result.message, shouldFade: false)
        
        // Record balance snapshot after hand completes
        recordBalanceSnapshot()
        
        // Handle win/loss animations
        if result.isWin {
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
                self.animateWinnings(for: self.playerHandView.betControl, odds: result.winOdds)
            }
            
            // Collect the original bet after winnings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                guard let self = self else { return }
                self.animateBetCollection(for: self.playerHandView.betControl)
            }
        } else if result.isPush {
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

        // Handle insurance bet (if not already handled in checkDealerBlackjackAfterInsurance)
        // This is a fallback in case insurance wasn't checked earlier
        let insuranceBetAmount = insuranceControl.betAmount
        if insuranceBetAmount > 0 {
            if isDealerBlackjack {
                // Insurance pays 2:1 if dealer has blackjack
                let insuranceWin = insuranceBetAmount * 2
                balance += insuranceWin
                instructionLabel.showMessage("Insurance pays \(insuranceWin)!", shouldFade: true)
            } else {
                // Insurance loses if dealer doesn't have blackjack
                // Bet was already deducted, just animate it away
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.animateChipsAway(from: self.insuranceControl)
                }
            }
        }
        
        // Check Buster bets (dealer bust bets) after dealer's turn
        checkBusterBets(dealerCards: dealerCards)

        // Check Lucky 7 bets (evaluated after hand completes to count all 7s)
        checkLucky7Bets(playerCards: playerCards)

        // Note: Most bonus bets are evaluated immediately after initial 4 cards are dealt,
        // but Lucky 7 and Buster are evaluated at the end of the game
        
        // Check if we need to shuffle after hand completes (cut card was reached)
        if shouldShuffleAfterHand {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.createAndShuffleDeck()
                self.deckView.setCardCount(52 * self.deckCount, animated: true)
                self.instructionLabel.showMessage("Deck reshuffled!", shouldFade: true)
            }
        }
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
        
        var results: [(handView: PlayerHandView, result: HandResult, betAmount: Int)] = []
        
        for (handView, state, _) in hands {
            let handCards = handView.currentCards
            let betAmount = handView.betControl.betAmount
            
            // Evaluate hand result
            let result = evaluateHandResult(playerCards: handCards, dealerCards: dealerCards, playerBusted: state.busted)
            results.append((handView: handView, result: result, betAmount: betAmount))
        }
        
        // Update instruction message
        let winCount = results.filter { $0.result.isWin }.count
        let lossCount = results.filter { !$0.result.isWin && !$0.result.isPush }.count
        let pushCount = results.filter { $0.result.isPush }.count
        
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
        let totalWinnings = results.filter { $0.result.isWin }.reduce(0) { total, item in
            let winAmount = item.result.isBlackjack ? Int(Double(item.betAmount) * 1.5) : item.betAmount
            return total + winAmount
        }
        let totalLosses = results.filter { !$0.result.isWin && !$0.result.isPush }.reduce(0) { $0 + $1.betAmount }

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

            for item in results {
                if item.result.isWin {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self else { return }
                        self.animateWinnings(for: item.handView.betControl, odds: item.result.winOdds)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                        guard let self = self else { return }
                        self.animateBetCollection(for: item.handView.betControl)
                    }
                } else if item.result.isPush {
                    // Push - bet stays on control
                } else {
                    // Loss
                    if item.betAmount > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self = self else { return }
                            self.animateChipsAway(from: item.handView.betControl)
                        }
                    }
                }
            }
        }
        
        // Check Buster bets (dealer bust bets) after dealer's turn
        checkBusterBets(dealerCards: dealerCards)

        // Check Lucky 7 bets for each hand (evaluated after hand completes to count all 7s)
        // For split hands, we check each hand separately
        for (handView, _, _) in hands {
            checkLucky7Bets(playerCards: handView.currentCards)
        }

        // Track metrics
        for item in results {
            if item.result.isWin {
                sessionManager.recordWin(isBlackjack: item.result.isBlackjack)
            } else if item.result.isPush {
                sessionManager.recordPush()
            } else {
                sessionManager.recordLoss()
            }
        }

        // Track hand outcome (split hands count as one hand)
        sessionManager.incrementHandCount()
        
        // Note: Split hand cleanup happens when "New Hand" is tapped
        
        // Check if we need to shuffle after hand completes (cut card was reached)
        if shouldShuffleAfterHand {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.createAndShuffleDeck()
                self.deckView.setCardCount(52 * self.deckCount, animated: true)
                self.instructionLabel.showMessage("Deck reshuffled!", shouldFade: true)
            }
        }
    }
    
    private func cleanupSplitHand() {
        guard isSplit else { return }

        // Collect any remaining bet from split hand (for wins/pushes)
        if let splitHand = splitHandView {
            let splitBetAmount = splitHand.betControl.betAmount
            if splitBetAmount > 0 {
                // Return the bet to balance
                balance += splitBetAmount
                // Clear the bet display
                splitHand.betControl.betAmount = 0
            }

            // Animate split hand out
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

        // Disable scrolling when back to single hand
        handsScrollView.isScrollEnabled = false

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
        // Update button states based on game phase
        updateActionButtonsVisibility()
        updateStandButtonState()
        updateDoubleButtonState()
        updateSplitButtonVisibility()
        updateInsuranceButtonVisibility()

        // Lock bet once hand begins (prevent addition/removal)
        let betLocked = gamePhase != .waitingForBet && gamePhase != .readyToDeal
        playerHandView.betControl.setBetRemovalDisabled(betLocked)
        playerHandView.betControl.isEnabled = !betLocked

        // Show tips based on game phase
        showTips()
        
        // Also disable split hand bet control if it exists
        if let splitHand = splitHandView {
            splitHand.betControl.setBetRemovalDisabled(betLocked)
            splitHand.betControl.isEnabled = !betLocked
        }
        
        bonusBetControls.forEach { control in
            control.setBetRemovalDisabled(betLocked)
            control.isEnabled = !betLocked
        }
        
        // Update Ready/Continue button
        // Show "Continue" when insurance is available, "Ready?" when readyToDeal
        // Insurance is only available if it hasn't been checked yet
        let shouldShowReadyButton = gamePhase == .readyToDeal || isInsuranceAvailable
        let shouldReadyBeEnabled = (gamePhase == .readyToDeal && playerHandView.betControl.betAmount > 0) || isInsuranceAvailable
        
        // Update button title based on context
        if isInsuranceAvailable {
            readyButton.setTitle("Continue", for: .normal)
        } else {
            readyButton.setTitle("Ready?", for: .normal)
        }
        
        // Update insurance status label
        updateInsuranceStatusLabel()
        
        if shouldShowReadyButton && readyButton.isHidden {
            // Show button with animation
            readyButton.isHidden = false
            readyButton.isEnabled = shouldReadyBeEnabled
            
            // Update insurance status label
            updateInsuranceStatusLabel()
            
            readyButton.setGameButtonStyle(enabled: shouldReadyBeEnabled)
            readyButton.fadeIn()
        } else if !shouldShowReadyButton && !readyButton.isHidden {
            // Hide button with animation
            readyButton.fadeOut()
        } else if shouldShowReadyButton && !readyButton.isHidden {
            // Button is already visible, just update styling and title if needed
            readyButton.isEnabled = shouldReadyBeEnabled
            // Update title based on context
            if isInsuranceAvailable {
                readyButton.setTitle("Continue", for: .normal)
            } else {
                readyButton.setTitle("Ready?", for: .normal)
            }
            
            // Update insurance status label
            updateInsuranceStatusLabel()
            
            readyButton.setGameButtonStyle(enabled: shouldReadyBeEnabled)
        }

        // Update New Hand button visibility
        let shouldShowNewHandButton = gamePhase == .gameOver

        if shouldShowNewHandButton && newHandButton.isHidden {
            // Show button with animation
            newHandButton.isHidden = false
            newHandButton.fadeIn()
        } else if !shouldShowNewHandButton && !newHandButton.isHidden {
            // Hide button with animation
            newHandButton.fadeOut()
        }
        
        // Update shimmer based on current state
        updateBetShimmer()
    }

    private func updateActionButtonsVisibility() {
        // Show Stand/Double stack during player turn, but hide when insurance is available
        // Show New Hand button when game is over or ready to deal
        
        let shouldShowActionButtons = gamePhase == .playerTurn && !isInsuranceAvailable
        let shouldShowNewHandButton = gamePhase == .readyToDeal || gamePhase == .gameOver

        // Toggle between action buttons and new hand button
        if shouldShowActionButtons && rightButtonStack.isHidden {
            // Show action buttons
            rightButtonStack.isHidden = false
            rightButtonStack.fadeIn()
        } else if !shouldShowActionButtons && !rightButtonStack.isHidden {
            // Hide action buttons quickly
            rightButtonStack.fadeOut(duration: 0.15, hideOnComplete: true)
        }
    }

    private func updateStandButtonState() {
        // Stand button should be enabled during player's turn, but disabled when insurance is available
        let isEnabled = gamePhase == .playerTurn && !hasPlayerStood && !isInsuranceAvailable
        standButton.isEnabled = isEnabled
        standButton.setDisabled(!isEnabled)
    }

    private func updateDoubleButtonState() {
        // Double button should be greyed out (disabled) when not available
        // Always visible during player turn, just disabled when can't double
        // Also disabled when insurance is available
        
        let isEnabled: Bool
        if isSplit {
            let currentState = splitHandStates[activeHandIndex]
            let currentHand = activeHandIndex == 0 ? playerHandView : splitHandView!
            let cardCount = currentHand.currentCards.count
            isEnabled = gamePhase == .playerTurn && cardCount == 2 && !currentState.hasHit && !currentState.hasDoubled && !isInsuranceAvailable
        } else {
            let cardCount = playerHandView.currentCards.count
            isEnabled = gamePhase == .playerTurn && cardCount == 2 && !hasPlayerHit && !hasPlayerDoubled && !isInsuranceAvailable
        }

        doubleButton.isEnabled = isEnabled
        doubleButton.setDisabled(!isEnabled)
    }

    private func updateSplitButtonVisibility() {
        // Split button should only be visible when cards are eligible to split
        let shouldShow: Bool
        if isSplit {
            // Can't split again after initial split
            shouldShow = false
        } else {
            let cards = playerHandView.currentCards
            let cardCount = cards.count
            let canSplit = cardCount >= 2 && cards.count >= 2 && cards[0].rank == cards[1].rank
            shouldShow = gamePhase == .playerTurn && canSplit && cardCount == 2 && !hasPlayerHit
        }

        if shouldShow && splitButton.isHidden {
            splitButton.isHidden = false
            splitButton.fadeIn()
        } else if !shouldShow && !splitButton.isHidden {
            splitButton.fadeOut()
        }
    }
    
    private func updateInsuranceButtonVisibility() {
        // Use the centralized isInsuranceAvailable property to determine visibility
        let shouldShow = isInsuranceAvailable

        if shouldShow && insuranceControl.isHidden {
            insuranceControl.isHidden = false
            // Force layout update to apply constraints
            view.setNeedsLayout()
            view.layoutIfNeeded()

            insuranceControl.fadeIn()
        } else if !shouldShow && !insuranceControl.isHidden {
            insuranceControl.fadeOut()
        }
    }

    private func setupBonusBetControls() {
        // Clear existing controls
        bonusBetControls.forEach { $0.removeFromSuperview() }
        bonusBetControls.removeAll()

        // Load selected side bets from settings manager
        var selectedSideBetTypes = settingsManager.currentSettings.selectedSideBets

        // Ensure max 2 side bets
        if selectedSideBetTypes.count > 2 {
            selectedSideBetTypes = Array(selectedSideBetTypes.prefix(2))
        }

        // Create bonus bet controls based on selected side bets
        for sideBetType in selectedSideBetTypes {
            let control = BonusBetControl(
                title: sideBetType.displayName,
                description: sideBetType.description
            )
            
            configureBonusBetControl(control)
            bonusBetControls.append(control)
            bonusStackView.addArrangedSubview(control)
        }
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

            // Dismiss bonus bets tip once user places their first bonus bet
            NNTipManager.shared.dismissTip(BlackjackTips.bonusBetsTip)
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
    
    private func checkDealerBlackjackAfterInsurance() {
        // This is called when player taps Continue while insurance is available
        // We need to check if dealer has blackjack WITHOUT revealing the hole card first
        // Only reveal the hole card if dealer actually has blackjack
        
        // Dismiss insurance tip when user continues (whether they took insurance or not)
        NNTipManager.shared.dismissTip(BlackjackTips.insuranceTip)
        
        let dealerCards = dealerHandView.currentCards
        guard dealerCards.count >= 2 else { return }
        guard dealerHandView.isHoleCardHidden() else { return } // Only check if hole card is still hidden
        
        // Check for blackjack by looking at the cards directly (hole card is at index 0, up card is at index 1)
        // Insurance is available when upcard is an Ace
        // Check if hole card is a 10-value card (10, J, Q, K)
        let holeCard = dealerCards[0]
        let upCard = dealerCards[1]

        let isDealerBlackjack = upCard.rank == .ace && isTenValueRank(holeCard.rank)
        
        if isDealerBlackjack {
            // Dealer has blackjack - reveal hole card and handle insurance
            dealerHandView.revealHoleCard(animated: true)
            
            // Wait for reveal animation, then handle insurance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.handleDealerBlackjackWithInsurance()
            }
        } else {
            // Dealer doesn't have blackjack - don't reveal hole card, just handle insurance loss and continue play
            handleNoDealerBlackjack()
        }
    }
    
    private func handleDealerBlackjackWithInsurance() {
        // Dealer has blackjack
        // Mark insurance as checked
        hasInsuranceBeenChecked = true
        
        // Pay insurance (2:1) if player took insurance
        let insuranceBetAmount = insuranceControl.betAmount
        if insuranceBetAmount > 0 {
            let insuranceWin = insuranceBetAmount * 2
            instructionLabel.showMessage("Dealer Blackjack! Insurance pays \(insuranceWin)!", shouldFade: false)
            
            // Show bet result container immediately
            showBetResult(amount: insuranceWin, isWin: true)
            
            // Animate insurance winnings (2:1 payout) - start sooner
            // Animation timeline: 0.4s delay + 0.6s step1 + 0.4s pause + 0.5s step2 = ~1.9s total
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                self.animateBonusBetWinnings(for: self.insuranceControl, betAmount: insuranceBetAmount, winAmount: insuranceWin, odds: 2.0)
            }
            
            // Hide insurance button after payout animation completes (~2.0s total)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                self.insuranceControl.fadeOut()
            }
            
            // Start main bet resolution while insurance animation is completing
            // Start endGame() after insurance animation step1 completes (~1.0s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.endGame()
            }
        } else {
            instructionLabel.showMessage("Dealer Blackjack!", shouldFade: false)
            // No insurance bet, hide button immediately and resolve main bet
            insuranceControl.fadeOut()
            
            // Resolve main bet immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.endGame()
            }
        }
    }
    
    private func handleNoDealerBlackjack() {
        // Dealer doesn't have blackjack - hole card stays hidden
        // Insurance bet is lost (already deducted from balance)
        let insuranceBetAmount = insuranceControl.betAmount
        
        // Shake animation when dealer doesn't have blackjack
        revealNoDealerBlackjack()
        
        // Mark insurance as checked so Continue button disappears
        hasInsuranceBeenChecked = true
        
        // Immediately update controls to show Hit/Stand/Double buttons
        // (insurance is no longer available, so action buttons should appear)
        updateControls()
        
        if insuranceBetAmount > 0 {
            instructionLabel.showMessage("No dealer blackjack. Insurance lost.", shouldFade: true)
            
            // Animate insurance bet away
            // Animation timeline: 0.3s delay + 0.15s max random delay + 0.5s animation + 0.2s fade = ~1.15s total
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.animateChipsAway(from: self.insuranceControl)
            }
            
            // Hide insurance button after animation completes (~1.5s total to be safe)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                self.insuranceControl.fadeOut()
            }
        } else {
            // No insurance bet, hide button immediately
            insuranceControl.fadeOut()
        }
        
        // Player can now take actions normally (Hit/Stand/Double)
        // Hole card remains hidden until dealer's turn
    }
    
    private func revealNoDealerBlackjack() {
        dealerHandView.playSpreadAnimation()
    }
    
    private func configureInsuranceControl() {
        insuranceControl.getSelectedChipValue = { [weak self] in
            return self?.selectedChipValue ?? 1
        }
        insuranceControl.getBalance = { [weak self] in
            return self?.balance ?? 200
        }
        insuranceControl.onBetPlaced = { [weak self] amount in
            guard let self = self else { return }
            // Insurance can only be placed during player turn when dealer shows Ace
            if self.gamePhase != .playerTurn {
                self.insuranceControl.betAmount -= amount
                HapticsHelper.lightHaptic()
                return
            }
            
            // Insurance bet is limited to half of main bet
            let mainBet = self.playerHandView.betControl.betAmount
            let maxInsurance = mainBet / 2
            if self.insuranceControl.betAmount > maxInsurance {
                // Revert excess amount - don't subtract from balance since bet was rejected
                let excess = self.insuranceControl.betAmount - maxInsurance
                self.insuranceControl.betAmount = maxInsurance
                // Don't add excess back to balance - it was never subtracted
                // The bet amount was already increased by PlainControl, but we're reverting it
                // So we need to ensure balance wasn't affected
                HapticsHelper.lightHaptic()
                return
            }
            
            // Only subtract from balance if bet was successfully placed
            self.balance -= amount
            self.trackBet(amount: amount, isMainBet: false)
            
            // Dismiss insurance tip once user places their first insurance bet
            NNTipManager.shared.dismissTip(BlackjackTips.insuranceTip)
            
            // Update controls to show Continue button
            self.updateControls()
        }
        insuranceControl.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
        }
        insuranceControl.canRemoveBet = { [weak self] in
            guard let self = self else { return true }
            // Insurance can only be removed before dealer reveals hole card
            return self.gamePhase == .playerTurn && self.dealerHandView.isHoleCardHidden()
        }
    }

    private func checkAndPayBonusBets(playerCards: [BlackjackHandView.Card]) {
        // Bonus bets only check the first two cards
        guard playerCards.count >= 2 else { return }
        
        let firstCard = playerCards[0]
        let secondCard = playerCards[1]
        
        // Get dealer's upcard for Lucky 7 evaluation
        let dealerCards = dealerHandView.currentCards
        let dealerUpcard = dealerCards.count >= 2 ? dealerCards[1] : nil
        
        // Check each bonus bet
        for control in bonusBetControls {
            guard control.betAmount > 0 else { continue }

            // Skip Buster and Lucky 7 bets - they're handled separately after hand completes
            guard control.title != "Buster" && control.title != "Lucky 7" else { continue }
            
            // Evaluate the bonus bet
            let result = BlackjackBonusBetEvaluator.evaluate(
                betType: control.title ?? "",
                firstCard: firstCard,
                secondCard: secondCard,
                dealerUpcard: dealerUpcard
            )
            
            // Update metrics if provided
            if let metricsUpdate = result.metricsUpdate {
                sessionManager.updateBonusMetrics(
                    perfectPairs: metricsUpdate.perfectPairsWon,
                    coloredPairs: metricsUpdate.coloredPairsWon,
                    mixedPairs: metricsUpdate.mixedPairsWon,
                    royalMatches: metricsUpdate.royalMatchesWon,
                    suitedMatches: metricsUpdate.suitedMatchesWon
                )
            }
            
            if result.isWin {
                let betAmount = control.betAmount
                let winAmount = Int(Double(betAmount) * result.odds)

                // Track bonus win metrics
                sessionManager.recordBonusWin(amount: winAmount, type: control.title ?? "Unknown")

                // Show bet result container with bonus description
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.showBetResult(amount: winAmount, isWin: true, showBonus: true, description: result.bonusDescription)
                }

                // Animate winnings from house to bonus bet control (offset), then both to balance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    guard let self = self else { return }
                    self.animateBonusBetWinnings(for: control, betAmount: betAmount, winAmount: winAmount, odds: result.odds)
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
    
    private func checkBusterBets(dealerCards: [BlackjackHandView.Card]) {
        // Buster bets: Win if dealer busts, with higher payouts for more cards
        let dealerTotal = calculateHandTotal(cards: dealerCards)
        let cardCount = dealerCards.count

        for control in bonusBetControls {
            guard control.title == "Buster" else { continue }
            guard control.betAmount > 0 else { continue }

            // Evaluate the Buster bet
            let result = BlackjackBonusBetEvaluator.evaluateBuster(
                dealerTotal: dealerTotal,
                dealerCardCount: cardCount
            )

            if result.isWin {
                let betAmount = control.betAmount
                let winAmount = Int(Double(betAmount) * result.odds)

                // Track bonus win metrics
                sessionManager.recordBonusWin(amount: winAmount, type: control.title ?? "Unknown")

                // Show bet result container with bonus description
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.showBetResult(amount: winAmount, isWin: true, showBonus: true, description: result.bonusDescription)
                }

                // Animate winnings from house to bonus bet control (offset), then both to balance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    guard let self = self else { return }
                    self.animateBonusBetWinnings(for: control, betAmount: betAmount, winAmount: winAmount, odds: result.odds)
                }
            } else {
                // Buster bet lost - animate chips away
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    guard let self = self else { return }
                    if control.betAmount > 0 {
                        self.animateChipsAway(from: control)
                    }
                }
            }
        }
    }

    private func checkLucky7Bets(playerCards: [BlackjackHandView.Card]) {
        // Lucky 7 bets: Evaluated after hand completes to count all 7s player receives
        for control in bonusBetControls {
            guard control.title == "Lucky 7" else { continue }
            guard control.betAmount > 0 else { continue }

            // Evaluate the Lucky 7 bet with all player cards
            let result = BlackjackBonusBetEvaluator.evaluateLucky7Complete(playerCards: playerCards)

            if result.isWin {
                let betAmount = control.betAmount
                let winAmount = Int(Double(betAmount) * result.odds)

                // Track bonus win metrics
                sessionManager.recordBonusWin(amount: winAmount, type: control.title ?? "Unknown")

                // Show bet result container with bonus description
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.showBetResult(amount: winAmount, isWin: true, showBonus: true, description: result.bonusDescription)
                }

                // Animate winnings from house to bonus bet control (offset), then both to balance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    guard let self = self else { return }
                    self.animateBonusBetWinnings(for: control, betAmount: betAmount, winAmount: winAmount, odds: result.odds)
                }
            } else {
                // Lucky 7 bet lost - animate chips away
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
    
    // MARK: - Helper Methods
    
    /// Checks if a rank has a value of 10 (10, J, Q, K)
    private func isTenValueRank(_ rank: PlayingCardView.Rank) -> Bool {
        return rank == .ten || rank == .king || rank == .queen || rank == .jack
    }
    
    
    /// Checks if a hand is a blackjack (21 with exactly 2 cards: one Ace and one 10-value card)
    private func isBlackjack(cards: [BlackjackHandView.Card]) -> Bool {
        guard cards.count == 2 else { return false }
        
        let total = calculateHandTotal(cards: cards)
        guard total == 21 else { return false }
        
        let hasAce = cards[0].rank == .ace || cards[1].rank == .ace
        let hasTenValue = isTenValueRank(cards[0].rank) || isTenValueRank(cards[1].rank)
        
        return hasAce && hasTenValue
    }
    
    /// Computed property that checks if insurance is currently available
    private var isInsuranceAvailable: Bool {
        return !hasInsuranceBeenChecked &&
               dealerHandView.currentCards.count >= 2 &&
               dealerHandView.currentCards[1].rank == .ace &&
               dealerHandView.isHoleCardHidden() &&
               gamePhase == .playerTurn &&
               !hasPlayerHit &&
               playerHandView.currentCards.count == 2
    }
    
    /// Updates the insurance status label on the ready button
    private func updateInsuranceStatusLabel() {
        guard let insuranceStatusLabel = readyButton.viewWithTag(999) as? UILabel else { return }
        
        if isInsuranceAvailable {
            let hasInsuranceBet = insuranceControl.betAmount > 0
            insuranceStatusLabel.text = hasInsuranceBet ? "Insured" : "Not Insured"
            insuranceStatusLabel.textColor = hasInsuranceBet ? 
                HardwayColors.label.withAlphaComponent(0.9) : 
                HardwayColors.label.withAlphaComponent(0.5)
        } else {
            insuranceStatusLabel.text = ""
        }
    }
    
    /// Evaluates the result of a hand against the dealer
    private func evaluateHandResult(playerCards: [BlackjackHandView.Card], 
                                   dealerCards: [BlackjackHandView.Card],
                                   playerBusted: Bool = false) -> HandResult {
        let playerTotal = calculateHandTotal(cards: playerCards)
        let dealerTotal = calculateHandTotal(cards: dealerCards)
        let isPlayerBlackjack = isBlackjack(cards: playerCards)
        let isDealerBlackjack = isBlackjack(cards: dealerCards)
        
        var isWin = false
        var isPush = false
        
        // Special rule: If both player and dealer bust, player loses
        if playerTotal > 21 && dealerTotal > 21 {
            isWin = false
        } else if playerTotal > 21 || playerBusted {
            isWin = false
        } else if dealerTotal > 21 {
            isWin = true
        } else if isPlayerBlackjack && isDealerBlackjack {
            // Both have blackjack - push
            isPush = true
        } else if isPlayerBlackjack {
            // Player has blackjack, dealer doesn't - player wins
            isWin = true
        } else if playerTotal > dealerTotal {
            isWin = true
        } else if dealerTotal > playerTotal {
            isWin = false
        } else {
            // Same total - push
            isPush = true
        }
        
        return HandResult(
            isWin: isWin,
            isPush: isPush,
            isBlackjack: isPlayerBlackjack,
            playerTotal: playerTotal,
            dealerTotal: dealerTotal
        )
    }
    
    // MARK: - Deck Management
    
    private func createAndShuffleDeck() {
        // Animate cut card away
        UIView.animate(withDuration: 0.2) {
            self.cutCardView?.transform = CGAffineTransform(translationX: -200, y: 0).scaledBy(x: 0.5, y: 0.5)
        } completion: { _ in
            // Remove the cut card view when shuffling
            self.cutCardView?.removeFromSuperview()
            self.cutCardView = nil
        }

        // Delegate to deck manager
        deckManager.createAndShuffleDeck()
        // UI updates handled in deckWasShuffled delegate method
    }

    private func drawCard() -> BlackjackHandView.Card {
        return deckManager.drawCard()
        // Delegate callbacks will handle UI updates
    }

    private func animateCutCardOffScreen() {
        // Remove any existing cut card
        cutCardView?.removeFromSuperview()

        // Get deck center in view coordinates
        let deckCenter = view.convert(deckView.deckCenter, from: deckView)

        // Create the cut card view
        let newCutCardView = PlayingCardView()
        newCutCardView.configureCutCard()
        newCutCardView.translatesAutoresizingMaskIntoConstraints = false

        // Apply shadow
        newCutCardView.layer.masksToBounds = false
        newCutCardView.layer.shadowColor = UIColor.black.cgColor
        newCutCardView.layer.shadowOpacity = 0.25
        newCutCardView.layer.shadowRadius = 4
        newCutCardView.layer.shadowOffset = CGSize(width: 0, height: 2)

        // Add to view
        view.addSubview(newCutCardView)
        cutCardView = newCutCardView

        // Set up constraints - positioned to the left of dealer hand
        let cardHeight: CGFloat = 60
        let cardAspectRatio: CGFloat = 60.0 / 88.0
        NSLayoutConstraint.activate([
            newCutCardView.leadingAnchor.constraint(equalTo: instructionLabel.leadingAnchor),
            newCutCardView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 16),
            newCutCardView.heightAnchor.constraint(equalToConstant: cardHeight),
            newCutCardView.widthAnchor.constraint(equalTo: newCutCardView.heightAnchor, multiplier: cardAspectRatio)
        ])

        // Force layout to get final position
        view.layoutIfNeeded()
        let finalCenter = newCutCardView.center

        // Calculate offset from deck to final position
        let offsetX = finalCenter.x - deckCenter.x
        let offsetY = finalCenter.y - deckCenter.y

        // Start with transform that moves it to deck position
        newCutCardView.transform = CGAffineTransform(translationX: -offsetX, y: -offsetY).scaledBy(x: 0.5, y: 0.5)
        newCutCardView.alpha = 0

        // Update deck count
        deckView.drawCard()

        // Animate to final position (constraints will handle positioning, we just animate the transform away)
        UIView.animate(withDuration: 0.4, delay: 0.1, options: .curveEaseOut, animations: {
            newCutCardView.transform = .identity
            newCutCardView.alpha = 1.0
        })
    }
    
    private func dealFixedHand(type: FixedHandType) -> (BlackjackHandView.Card, BlackjackHandView.Card, BlackjackHandView.Card, BlackjackHandView.Card) {
        // Delegate to deck manager
        return deckManager.dealFixedHand(type: type)
    }

    private func randomHandCard() -> BlackjackHandView.Card {
        // Use the actual deck instead of random generation
        return drawCard()
    }
    
    func onCardDealt() {
        // Update deck count when a card animation starts
        deckView.drawCard()
    }

    func onCardAnimationComplete(card: BlackjackHandView.Card) {
        // Update card count when card animation completes
        deckManager.updateCardCount(for: card)
        // UI updates handled in cardCountDidUpdate delegate method
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
            UserDefaults.standard.set(rebetAmount, forKey: BlackjackSettingsKeys.rebetAmount)
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

// MARK: - UIButton Styling Extension

extension UIButton {
    /// Sets the game button style based on enabled state
    func setGameButtonStyle(enabled: Bool) {
        if enabled {
            self.backgroundColor = HardwayColors.surfaceGray
            self.setTitleColor(.white, for: .normal)
            self.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
        } else {
            self.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.5)
            self.setTitleColor(HardwayColors.label.withAlphaComponent(0.5), for: .normal)
            self.layer.borderColor = HardwayColors.label.withAlphaComponent(0.2).cgColor
        }
    }
}

// MARK: - Delegates

extension BlackjackGameplayViewController: ChipSelectorDelegate {
    func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {
        print("Selected chip value: \(value)")
    }
}

extension BlackjackGameplayViewController: UIScrollViewDelegate {
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scrollView === handsScrollView, isSplit else { return }

        // Calculate the width of each hand plus spacing
        let handWidth = scrollView.bounds.width - getTotalPeekAmount()
        let spacing = handsContentStackView.spacing
        let pageWidth = handWidth + spacing

        // Account for content inset when calculating target page
        let adjustedOffset = targetContentOffset.pointee.x + scrollView.contentInset.left

        // Determine which page to snap to
        let targetPage: Int
        if velocity.x > 0.5 {
            // Swiping right with momentum - go to next page
            targetPage = min(1, activeHandIndex + 1)
        } else if velocity.x < -0.5 {
            // Swiping left with momentum - go to previous page
            targetPage = max(0, activeHandIndex - 1)
        } else {
            // Low velocity - snap to nearest page
            targetPage = Int(round(adjustedOffset / pageWidth))
        }

        // Calculate the target offset
        let targetOffset = pageWidth * CGFloat(targetPage) - scrollView.contentInset.left
        targetContentOffset.pointee.x = targetOffset

        // Update active hand index
        if targetPage != activeHandIndex {
            activeHandIndex = targetPage
            updateControls()
            print("DEBUG: Snapping to hand \(targetPage)")
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === handsScrollView, isSplit else { return }

        // Calculate the width of each hand plus spacing
        let handWidth = scrollView.bounds.width - getTotalPeekAmount()
        let spacing = handsContentStackView.spacing
        let pageWidth = handWidth + spacing

        // Account for content inset when calculating current page
        let adjustedOffset = scrollView.contentOffset.x + scrollView.contentInset.left
        let currentPage = Int(round(adjustedOffset / pageWidth))

        // Update active hand index if changed
        if currentPage != activeHandIndex {
            activeHandIndex = currentPage
            updateControls()
            print("DEBUG: Scrolled to hand \(currentPage)")
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === handsScrollView, isSplit else { return }

        // Calculate the width of each hand plus spacing
        let handWidth = scrollView.bounds.width - getTotalPeekAmount()
        let spacing = handsContentStackView.spacing
        let pageWidth = handWidth + spacing

        // Account for content inset when calculating current page
        let adjustedOffset = scrollView.contentOffset.x + scrollView.contentInset.left
        let currentPage = Int(round(adjustedOffset / pageWidth))

        // Update active hand index if changed
        if currentPage != activeHandIndex {
            activeHandIndex = currentPage
            updateControls()
            print("DEBUG: Scrolled to hand \(currentPage)")
        }
    }
}

// MARK: - BlackjackSettingsManagerDelegate

extension BlackjackGameplayViewController: BlackjackSettingsManagerDelegate {
    func settingsDidChange(_ settings: BlackjackSettings) {
        // Update local properties from settings
        deckCount = settings.deckCount
        deckPenetration = settings.deckPenetration
        rebetEnabled = settings.rebetEnabled
        rebetAmount = settings.rebetAmount

        // Update deck manager with new settings
        deckManager.deckCount = settings.deckCount
        deckManager.deckPenetration = settings.deckPenetration
        deckManager.setFixedHandType(settings.fixedHandType)

        // Update UI based on changed settings
        dealerHandView.setTotalsHidden(!settings.showTotals)
        playerHandView.setTotalsHidden(!settings.showTotals)
        splitHandView?.setTotalsHidden(!settings.showTotals)
        deckView.setCountLabelVisible(settings.showDeckCount)
        deckView.setCardCountLabelVisible(settings.showCardCount)

        // Reshuffle deck if deck count changed
        if deckCount != settings.deckCount {
            createAndShuffleDeck()
        }

        updateNavigationBarMenu()
    }
}

// MARK: - BlackjackDeckManagerDelegate

extension BlackjackGameplayViewController: BlackjackDeckManagerDelegate {
    func deckWasShuffled(cardCount: Int) {
        // Update deck view with new card count
        deckView.setCardCount(cardCount, animated: true)
        deckView.updateCardCountLabel(runningCount: 0, trueCount: 0)
        instructionLabel.showMessage("Deck reshuffled!", shouldFade: true)
    }

    func cutCardWasReached() {
        // Animate cut card off-screen
        animateCutCardOffScreen()
        instructionLabel.showMessage("Cut card reached.", shouldFade: true)
    }

    func cardCountDidUpdate(running: Int, trueCount: Int) {
        // Update the deck view with new card count
        deckView.updateCardCountLabel(runningCount: running, trueCount: trueCount)
    }

    func deckCountDidChange(remaining: Int) {
        // Update deck view when a card is drawn
        deckView.drawCard()
    }
}

// MARK: - BlackjackSessionManagerDelegate

extension BlackjackGameplayViewController: BlackjackSessionManagerDelegate {
    func sessionDidStart(id: String) {
        // Session started - no UI update needed
    }

    func sessionWasSaved(session: GameSession) {
        // Session saved - could show a notification if desired
    }

    func metricsDidUpdate(metrics: BlackjackGameplayMetrics) {
        // Metrics updated - could refresh any metrics UI if needed
    }

    func balanceDidChange(from oldBalance: Int, to newBalance: Int) {
        // Balance change is already handled through the balance property setter
        // This callback is available for any additional balance change reactions
    }

    func handCountDidChange(count: Int) {
        // Hand count updated - could update UI if displaying hand count
    }
}
