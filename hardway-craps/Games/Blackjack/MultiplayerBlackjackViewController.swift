//
//  MultiplayerBlackjackViewController.swift
//  hardway-craps
//
//  Multiplayer Blackjack: join table (name, balance, seat order, chip color) then show
//  gameplay UI. Layout matches BlackjackGameplayViewController.
//

import UIKit
import FirebaseDatabase

private enum MultiplayerDisplayNameKey {
    static let key = "MultiplayerDisplayName"
    static var value: String {
        UserDefaults.standard.string(forKey: key) ?? "Player"
    }
    static func set(_ name: String) {
        UserDefaults.standard.set(name, forKey: key)
    }
}

private enum MultiplayerPlayerIdKey {
    static let key = "MultiplayerPlayerId"
    static var value: String {
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}

final class MultiplayerBlackjackViewController: UIViewController {

    // MARK: - UI (matching BlackjackGameplayViewController layout)

    private let dealerHandView = DealerHandView()
    private let standButton = ActionButton(title: "Stand")
    private let doubleButton = ActionButton(title: "Double")

    private var instructionLabel: InstructionLabel!
    private let deckView = DeckView()
    private var balanceView: BalanceView!
    private var chipSelector: ChipSelector!
    private var bottomStackView: UIStackView!
    private var newHandButton: UIButton!
    private var readyButton: UIButton!
    private var rightButtonStack: UIStackView!

    /// Container for player seats: scroll view + horizontal stack of seat cells.
    private var seatsContainerView: UIView!
    private var seatsScrollView: UIScrollView!
    private var seatsStackView: UIStackView!
    /// Local player's seat (interactive); reused for mySeatIndex.
    private var defaultSeat: PlayerSeat!
    /// All seat views by index (local + remote). Rebuilt when observeSeats fires.
    private var seatViewsByIndex: [Int: PlayerSeat] = [:]
    /// Track previous hands for each seat to detect bet changes
    private var previousHandsByIndex: [Int: [MPBlackjackTableState.HandData]] = [:]
    /// Track previous balance for each seat to avoid unnecessary updates
    private var previousBalanceByIndex: [Int: Int] = [:]
    private let seatWidth: CGFloat = 180
    private let maxSeats = 4
    private var seatsObserverHandle: DatabaseHandle?

    // MARK: - Loading state

    private var loadingOverlayView: UIView!
    private var loadingLabel: UILabel!
    private var loadingSpinner: NNLoadingSpinner!
    private var loadingErrorLabel: UILabel!
    private var loadingRetryButton: UIButton!

    // MARK: - Table state (set after join)

    private var tableState: MPBlackjackTableState!
    private var mySeatIndex: Int = 0
    private var myDisplayName: String = "Player"
    private var myChipColorName: String = "Cyan"
    private var joinedBalance: Int = 200

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

        // Prevent dismissal by swipe-down
        isModalInPresentation = true

        // Add menu button with Leave Table option
        let leaveAction = UIAction(title: "Leave Table", image: UIImage(systemName: "rectangle.portrait.and.arrow.right"), attributes: .destructive) { [weak self] _ in
            self?.showLeaveTableConfirmation()
        }
        let menu = UIMenu(children: [leaveAction])
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: menu)

        tableState = MPBlackjackTableState()
        setupLoadingOverlay()
        attemptJoin()
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
            loadingLabel.centerYAnchor.constraint(equalTo: loadingOverlayView.centerYAnchor, constant: -32),

            loadingSpinner.centerXAnchor.constraint(equalTo: loadingOverlayView.centerXAnchor),
            loadingSpinner.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 20),
            loadingSpinner.widthAnchor.constraint(equalToConstant: 44),
            loadingSpinner.heightAnchor.constraint(equalToConstant: 44),

            loadingErrorLabel.centerXAnchor.constraint(equalTo: loadingOverlayView.centerXAnchor),
            loadingErrorLabel.topAnchor.constraint(equalTo: loadingSpinner.bottomAnchor, constant: 24),
            loadingErrorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: loadingOverlayView.leadingAnchor, constant: 24),
            loadingErrorLabel.trailingAnchor.constraint(lessThanOrEqualTo: loadingOverlayView.trailingAnchor, constant: -24),

            loadingRetryButton.centerXAnchor.constraint(equalTo: loadingOverlayView.centerXAnchor),
            loadingRetryButton.topAnchor.constraint(equalTo: loadingErrorLabel.bottomAnchor, constant: 16)
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
        let balanceToUse = AppSettingsViewController.startingBankroll
        joinedBalance = balanceToUse

        // Initialize table with pre-assigned colors, then join
        tableState.initializeTableIfNeeded { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                // Table initialized, now join (chipColorName parameter is ignored - seats have pre-assigned colors)
                self.tableState.joinTable(playerId: playerId, displayName: displayName, balance: balanceToUse, chipColorName: "") { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        switch result {
                        case .success((let seatIndex, let colorName)):
                            print("✅ [MultiplayerBlackjack] Join successful: seatIndex=\(seatIndex), colorName='\(colorName)'")
                            self.mySeatIndex = seatIndex
                            self.myDisplayName = displayName
                            self.myChipColorName = colorName
                            self.joinedBalance = balanceToUse
                            self.setupGameplayUI()
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

        defaultSeat.primaryHand.setPlaceholderCards()

        seatsObserverHandle = tableState.observeSeats { [weak self] seatsWithIndices in
            self?.reconcileSeats(seatsWithIndices)
        }
        // Sync immediately with same parsing as observeSeats so second player sees first (no raw cast / NSDictionary miss)
        tableState.getSeatsWithIndices { [weak self] seatsWithIndices in
            self?.reconcileSeats(seatsWithIndices)
        }
    }

    deinit {
        if let handle = seatsObserverHandle {
            tableState?.removeSeatsObserver(handle: handle)
        }
    }

    // MARK: - Setup

    private func applyHandsToSeat(_ seat: PlayerSeat, hands: [MPBlackjackTableState.HandData], previousHands: [MPBlackjackTableState.HandData]? = nil, animated: Bool = false) {
        // For now, we only support primary hand (no split yet in UI)
        let newBet = hands.first?.bet ?? 0
        let oldBet = previousHands?.first?.bet ?? seat.primaryHand.betControl.betAmount

        // Only update if bet changed
        if newBet != oldBet {
            if animated && seat.isRemote && newBet > oldBet {
                // Animate chip from balance to bet for remote player
                let delta = newBet - oldBet
                animateChipToBet(for: seat, amount: delta) { [weak self] in
                    seat.primaryHand.betControl.betAmount = newBet
                    // After bet updates, animate the chip (scale + shimmer)
                    self?.animateBetChipUpdate(for: seat)
                }
            } else {
                seat.primaryHand.betControl.betAmount = newBet
            }
        }

        // TODO: When split is implemented, handle second hand here
        // if hands.count > 1, let secondHand = hands[1] {
        //     seat.splitHand.betControl.betAmount = secondHand.bet
        // }
    }

    private func animateBetChipUpdate(for seat: PlayerSeat) {
        guard let chip = seat.primaryHand.betControl.betView as? MPSmallBetChip else { return }
        chip.layoutIfNeeded()

        // Scale animation (same as PassLineTwoPlayerControl)
        let originalTransform = chip.transform
        UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut]) {
            chip.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                chip.transform = originalTransform
            }
        }

        // Shimmer effect
        chip.playChipShimmer()
    }

    private func animateChipToBet(for seat: PlayerSeat, amount: Int, completion: @escaping () -> Void) {
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
        let endPoint = seat.primaryHand.betControl.convert(CGPoint(x: betChipFrame.midX, y: betChipFrame.midY), to: view)

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
            controlPoint1: CGPoint(x: 0.25, y: 0.1),
            controlPoint2: CGPoint(x: 0.25, y: 1.0)
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
                hands.append(MPBlackjackTableState.HandData(bet: betAmount))
            }
        }

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
            // Deduct the bet amount from balance
            self.balance -= amount
            print("💰 [MultiplayerBlackjack] Bet placed: \(amount), new balance: \(self.balance)")

            // Sync hands and balance to Firebase
            self.syncHandsToFirebase(for: seat)
        }

        betControl.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            // Refund the bet amount to balance
            self.balance += amount
            print("💰 [MultiplayerBlackjack] Bet removed: \(amount), new balance: \(self.balance)")

            // Sync hands and balance to Firebase
            self.syncHandsToFirebase(for: seat)
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
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            instructionLabel.heightAnchor.constraint(lessThanOrEqualToConstant: 44)
        ])
    }

    private func setupDeckView() {
        view.addSubview(deckView)
        NSLayoutConstraint.activate([
            deckView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            deckView.topAnchor.constraint(equalTo: instructionLabel.topAnchor),
            deckView.widthAnchor.constraint(equalToConstant: 80),
            deckView.heightAnchor.constraint(equalToConstant: 110),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: deckView.leadingAnchor, constant: -12)
        ])
    }

    private func setupDealerHandView() {
        dealerHandView.translatesAutoresizingMaskIntoConstraints = false
        dealerHandView.isUserInteractionEnabled = true
        view.addSubview(dealerHandView)

        NSLayoutConstraint.activate([
            dealerHandView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dealerHandView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 16)
        ])
    }

    private func setupSeatsContainer() {
        seatsContainerView = UIView()
        seatsContainerView.translatesAutoresizingMaskIntoConstraints = false
        seatsContainerView.backgroundColor = .clear

        seatsScrollView = UIScrollView()
        seatsScrollView.translatesAutoresizingMaskIntoConstraints = false
        seatsScrollView.showsHorizontalScrollIndicator = true
        seatsScrollView.alwaysBounceHorizontal = true

        seatsStackView = UIStackView()
        seatsStackView.translatesAutoresizingMaskIntoConstraints = false
        seatsStackView.axis = .horizontal
        seatsStackView.alignment = .bottom
        seatsStackView.spacing = 16
        seatsStackView.distribution = .fill

        defaultSeat = PlayerSeat(chipStyle: chipStyleForColorName(myChipColorName))
        defaultSeat.translatesAutoresizingMaskIntoConstraints = false
        defaultSeat.nameText = displayLabel(name: myDisplayName, playerId: MultiplayerPlayerIdKey.value)
        defaultSeat.setBalance(joinedBalance, animated: false)
        defaultSeat.isRemote = false
        defaultSeat.widthAnchor.constraint(equalToConstant: seatWidth).isActive = true
        seatViewsByIndex[mySeatIndex] = defaultSeat

        // Wire up bet control callbacks
        setupBetControlCallbacks(for: defaultSeat)

        view.addSubview(seatsContainerView)
        seatsContainerView.addSubview(seatsScrollView)
        seatsScrollView.addSubview(seatsStackView)

        NSLayoutConstraint.activate([
            seatsContainerView.topAnchor.constraint(equalTo: dealerHandView.bottomAnchor, constant: 20),
            seatsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            seatsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            // Increased height to accommodate balance view above hands (170 for hands + ~50 for balance/spacing)
            seatsContainerView.heightAnchor.constraint(equalToConstant: 220),

            seatsScrollView.topAnchor.constraint(equalTo: seatsContainerView.topAnchor),
            seatsScrollView.leadingAnchor.constraint(equalTo: seatsContainerView.leadingAnchor),
            seatsScrollView.trailingAnchor.constraint(equalTo: seatsContainerView.trailingAnchor),
            seatsScrollView.bottomAnchor.constraint(equalTo: seatsContainerView.bottomAnchor),

            seatsStackView.topAnchor.constraint(equalTo: seatsScrollView.contentLayoutGuide.topAnchor),
            seatsStackView.leadingAnchor.constraint(equalTo: seatsScrollView.contentLayoutGuide.leadingAnchor),
            seatsStackView.trailingAnchor.constraint(equalTo: seatsScrollView.contentLayoutGuide.trailingAnchor),
            seatsStackView.bottomAnchor.constraint(equalTo: seatsScrollView.contentLayoutGuide.bottomAnchor),
            seatsStackView.heightAnchor.constraint(equalTo: seatsScrollView.frameLayoutGuide.heightAnchor)
        ])
    }
    
    /// Returns displayName unless it's empty or "Player", then first 5 chars of playerId.
    private func displayLabel(name: String, playerId: String) -> String {
        if !name.isEmpty && name != "Player" { return name }
        return String(playerId.prefix(5))
    }
    
    private func configureSeatAsPlayer(_ seat: PlayerSeat, displayName: String, balance: Int, isRemote: Bool, needsPlaceholderCards: Bool = true) {
        seat.isRemote = isRemote
        seat.nameText = displayName
        seat.setBalance(balance, animated: true)

        // Only set placeholder cards if requested (we'll set them after layout for new seats)
        if needsPlaceholderCards {
            seat.primaryHand.setPlaceholderCards()
        }
        seat.alpha = 1.0
    }

    private func reconcileSeats(_ seatsWithIndices: [(seatIndex: Int, seatData: MPBlackjackTableState.SeatData)]) {
        let myPlayerId = MultiplayerPlayerIdKey.value

        // Track which seats currently have players
        let currentSeatIndices = Set(seatsWithIndices.map { $0.seatIndex })

        // Remove seats that no longer have players (except our own seat)
        var indicesToRemove: [Int] = []
        for (idx, seat) in seatViewsByIndex {
            if !currentSeatIndices.contains(idx) && idx != mySeatIndex {
                indicesToRemove.append(idx)
            }
        }
        for idx in indicesToRemove {
            guard let seat = seatViewsByIndex.removeValue(forKey: idx), seat !== defaultSeat else { continue }
            // Animate seat removal
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
                seat.alpha = 0
                seat.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            }) { _ in
                seat.removeFromSuperview()
            }
        }
        
        // Apply player data to occupied seats and create new seats as needed
        for (seatIndex, data) in seatsWithIndices {
            if data.playerId == myPlayerId, seatIndex == mySeatIndex {
                // This is our seat
                seatViewsByIndex[seatIndex] = defaultSeat
                defaultSeat.isRemote = false
                defaultSeat.nameText = data.displayLabel
                defaultSeat.setBalance(data.balance, animated: false)
                defaultSeat.primaryHand.setPlaceholderCards()
                defaultSeat.alpha = 1.0
                
                if myChipColorName != data.chipColorName {
                    print("🎨 [MultiplayerBlackjack] Chip color changed from '\(myChipColorName)' to '\(data.chipColorName)'")
                    myChipColorName = data.chipColorName
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.updateChipSelectorColor(data.chipColorName)
                }
                continue
            }
            
            // Remote player seat - create if needed
            if let existingSeat = seatViewsByIndex[seatIndex], existingSeat !== defaultSeat {
                // Existing seat - update it incrementally (avoid full reconfiguration)
                // Only update balance if it changed
                let previousBalance = previousBalanceByIndex[seatIndex]
                if previousBalance != data.balance {
                    existingSeat.setBalance(data.balance, animated: true)
                    previousBalanceByIndex[seatIndex] = data.balance
                }
                // Only update name if it changed
                if existingSeat.nameText != data.displayLabel {
                    existingSeat.nameText = data.displayLabel
                }
                // Update bet amounts from hands with animation
                let previousHands = previousHandsByIndex[seatIndex]
                applyHandsToSeat(existingSeat, hands: data.hands, previousHands: previousHands, animated: true)
                previousHandsByIndex[seatIndex] = data.hands
            } else {
                // New remote seat - create but defer placeholder cards until after it's in the view hierarchy
                let remoteSeat = PlayerSeat(chipStyle: chipStyleForColorName(data.chipColorName))
                remoteSeat.translatesAutoresizingMaskIntoConstraints = false
                remoteSeat.widthAnchor.constraint(equalToConstant: seatWidth).isActive = true
                configureSeatAsPlayer(remoteSeat, displayName: data.displayLabel, balance: data.balance, isRemote: true, needsPlaceholderCards: false)
                seatViewsByIndex[seatIndex] = remoteSeat
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
                let isNewSeat = seatView !== defaultSeat && !seatsStackView.arrangedSubviews.contains(seatView)
                if isNewSeat {
                    seatView.alpha = 0
                    seatView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                }

                seatsStackView.addArrangedSubview(seatView)

                // Animate in new seat
                if isNewSeat {
                    UIView.animate(withDuration: 0.4, delay: 0.1, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
                        seatView.alpha = 1.0
                        seatView.transform = .identity
                    })
                }

                // Track if this is a new remote seat that needs placeholder cards
                if seatView !== defaultSeat && seatView.primaryHand.currentCards.isEmpty {
                    newlyAddedSeats.append(seatView)
                }

                // Update bet amounts for all remote seats
                if seatView !== defaultSeat, let seatData = seatsWithIndices.first(where: { $0.seatIndex == i })?.seatData {
                    applyHandsToSeat(seatView, hands: seatData.hands)
                }
            }
        }

            // Animate the stack view layout changes
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                self.seatsStackView.layoutIfNeeded()
            })

            // Force layout of the entire seats hierarchy to ensure all views have valid frames
            seatsStackView.setNeedsLayout()
            seatsStackView.layoutIfNeeded()

            // NOW set placeholder cards on newly added remote seats (after they're laid out)
            for seat in newlyAddedSeats {
                seat.primaryHand.setPlaceholderCards()
            }
        }
    }

    private func setupBalanceView() {
        balanceView = BalanceView()
    }

    private func setupChipSelector() {
        chipSelector = ChipSelector()
        chipSelector.delegate = self
        chipSelector.onBetReturned = { [weak self] amount in
            self?.balance += amount
        }
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
        bottomStackView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        balanceView.setContentCompressionResistancePriority(.required, for: .vertical)

        let chipSelectorHeight: CGFloat = 60
        NSLayoutConstraint.activate([
            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomStackView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6, constant: -16),
            bottomStackView.topAnchor.constraint(equalTo: seatsContainerView.bottomAnchor, constant: 24),
            chipSelector.heightAnchor.constraint(equalToConstant: chipSelectorHeight),
            chipSelector.widthAnchor.constraint(equalTo: bottomStackView.widthAnchor)
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

        readyButton = UIButton(type: .system)
        readyButton.translatesAutoresizingMaskIntoConstraints = false
        readyButton.setTitle("Ready?", for: .normal)
        readyButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        readyButton.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.5)
        readyButton.setTitleColor(HardwayColors.label.withAlphaComponent(0.5), for: .normal)
        readyButton.layer.cornerRadius = 16
        readyButton.layer.borderWidth = 1.5
        readyButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.2).cgColor
        readyButton.isEnabled = false
        readyButton.addTarget(self, action: #selector(readyTapped), for: .touchUpInside)

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
        view.addSubview(readyButton)

        NSLayoutConstraint.activate([
            rightButtonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            rightButtonStack.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
            rightButtonStack.topAnchor.constraint(equalTo: bottomStackView.topAnchor),
            rightButtonStack.widthAnchor.constraint(equalToConstant: 120),

            newHandButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            newHandButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
            newHandButton.topAnchor.constraint(equalTo: bottomStackView.topAnchor),
            newHandButton.widthAnchor.constraint(equalToConstant: 120),

            readyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            readyButton.bottomAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
            readyButton.topAnchor.constraint(equalTo: bottomStackView.topAnchor),
            readyButton.widthAnchor.constraint(equalToConstant: 120)
        ])

        rightButtonStack.isHidden = true
        rightButtonStack.alpha = 0
    }

    // MARK: - Actions (stubs)

    @objc private func standTapped() {
        HapticsHelper.lightHaptic()
        instructionLabel.showMessage("Stand", shouldFade: true)
    }

    @objc private func doubleTapped() {
        HapticsHelper.lightHaptic()
        instructionLabel.showMessage("Double", shouldFade: true)
    }

    @objc private func newHandTapped() {
        HapticsHelper.lightHaptic()
        instructionLabel.showMessage("New hand", shouldFade: true)
    }

    @objc private func readyTapped() {
        HapticsHelper.lightHaptic()
        instructionLabel.showMessage("Ready", shouldFade: true)
    }

    private func showLeaveTableConfirmation() {
        let alert = UIAlertController(
            title: "Leave Table?",
            message: "Are you sure you want to leave the table? Your seat will be freed for other players.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Leave", style: .destructive) { [weak self] _ in
            self?.leaveTable()
        })

        present(alert, animated: true)
    }

    private func leaveTable() {
        // Remove observer
        if let handle = seatsObserverHandle {
            tableState?.removeSeatsObserver(handle: handle)
            seatsObserverHandle = nil
        }

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
                // Dismiss regardless of success/failure
                self.dismiss(animated: true)
            }
        }
    }
}

// MARK: - ChipSelectorDelegate

extension MultiplayerBlackjackViewController: ChipSelectorDelegate {
    func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {}
}
