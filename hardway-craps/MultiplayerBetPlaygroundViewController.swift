//
//  MultiplayerBetPlaygroundViewController.swift
//  hardway-craps
//
//  Playground to experiment with two players (A/B) placing bets on the same Pass Line control.
//  Events are logged to Firebase Realtime Database (default instance).
//

import UIKit
import FirebaseDatabase

final class MultiplayerBetPlaygroundViewController: UIViewController {

    // MARK: - Experimental Features
    /// Enable experimental chip animation when other players place bets
    private let enableChipAnimation = true

    private let startingBalance = 200
    private let playerId: String = {
        let key = "MultiplayerPlayerId"
        if let savedId = UserDefaults.standard.string(forKey: key) {
            return savedId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }()

    private var balance: Int {
        get { balanceView?.balance ?? startingBalance }
        set {
            balanceView?.balance = newValue
            chipSelector?.updateAvailableChips(balance: newValue)
            // Update balance in Firebase whenever it changes (only if we have a slot)
            if tableState != nil, mySlot != nil {
                tableState.updateBalance(playerId: playerId, balance: newValue)
            }
        }
    }

    private var selectedChipValue: Int {
        chipSelector?.selectedValue ?? 5
    }

    private var chipSelector: ChipSelector!
    private var balanceView: BalanceView!
    private var passLineControl: PassLineTwoPlayerControl!
    private var bottomStackView: UIStackView!
    private var otherPlayerBalanceView: MPPlayerBalanceView!
    private var eventLogger: FirebasePlaygroundEventLogger!
    private var tableState: PassLineTableState!
    private var amountsObserverHandle: DatabaseHandle?
    private var balancesObserverHandle: DatabaseHandle?
    private var chipColorsObserverHandle: DatabaseHandle?

    private var lastAmountA: Int = -1
    private var lastAmountB: Int = -1
    /// Our assigned slot — set on first successful bet. Once known, any delta on this slot is always us.
    private var mySlot: PassLineTableState.PlayerSlot?
    /// Set to the chip amount *before* starting a transaction, so the observer can recognise our own
    /// bet even if it fires before the transaction completion callback returns.
    private var pendingBetAmount: Int?
    /// Track if we're currently animating for each slot to prevent multiple simultaneous animations
    private var isAnimatingSlotA = false
    private var isAnimatingSlotB = false
    /// Track chip colors for each slot to use in animations
    private var chipColorA: String?
    private var chipColorB: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Multiplayer Bet Playground"
        eventLogger = FirebasePlaygroundEventLogger()
        tableState = PassLineTableState()

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissPlayground)
        )

        setupBalanceView()
        setupChipSelector()
        setupPassLineControl()
        setupBottomStackView()
        setupOtherPlayerBalanceView()
        startObservingAmounts()
        startObservingBalances()
        startObservingChipColors()
    }

    deinit {
        if let handle = amountsObserverHandle {
            tableState?.removeObserver(handle: handle)
        }
        if let handle = balancesObserverHandle {
            tableState?.removeBalanceObserver(handle: handle)
        }
        if let handle = chipColorsObserverHandle {
            tableState?.removeChipColorObserver(handle: handle)
        }
    }

    /// Update chip color for a slot and ChipSelector based on the bet position
    /// Position A = Yellow, Position B = Green
    private func updateChipColorForSlot(_ slot: PassLineTwoPlayerControl.PlayerSlot) {
        // Determine the color set based on slot position
        let colorSet: ChipColorSet
        let chipStyle: MPSmallBetChipStyle
        
        switch slot {
        case .A:
            // Position A always uses yellow
            colorSet = .yellowGreen
            chipStyle = .yellow
        case .B:
            // Position B uses green
            colorSet = .green
            chipStyle = .green
        }
        
        // Update the bet chip style
        passLineControl.setChipStyle(chipStyle, for: slot)
        
        // Update the ChipSelector color to match the bet position
        // Note: This will be overridden by handleChipColorsUpdate when Firebase syncs
        chipSelector?.updateColorSet(colorSet)
    }
    
    private func setupOtherPlayerBalanceView() {
        otherPlayerBalanceView = MPPlayerBalanceView()
        otherPlayerBalanceView.translatesAutoresizingMaskIntoConstraints = false
        otherPlayerBalanceView.isUserInteractionEnabled = false
        otherPlayerBalanceView.nameText = "—"
        otherPlayerBalanceView.balanceText = "—"
        view.addSubview(otherPlayerBalanceView)
        NSLayoutConstraint.activate([
            otherPlayerBalanceView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            otherPlayerBalanceView.centerYAnchor.constraint(equalTo: chipSelector.centerYAnchor),
        ])
    }

    private func startObservingAmounts() {
        amountsObserverHandle = tableState.observeAmounts { [weak self] amountA, amountB in
            DispatchQueue.main.async {
                self?.handleAmountsUpdate(amountA: amountA, amountB: amountB)
            }
        }
    }

    private func startObservingBalances() {
        balancesObserverHandle = tableState.observeBalances { [weak self] playerIdA, balanceA, playerIdB, balanceB in
            DispatchQueue.main.async {
                self?.handleBalancesUpdate(playerIdA: playerIdA, balanceA: balanceA, playerIdB: playerIdB, balanceB: balanceB)
            }
        }
    }
    
    private func startObservingChipColors() {
        chipColorsObserverHandle = tableState.observeChipColors { [weak self] colorA, colorB in
            DispatchQueue.main.async {
                self?.handleChipColorsUpdate(colorA: colorA, colorB: colorB)
            }
        }
    }
    
    private func handleChipColorsUpdate(colorA: String?, colorB: String?) {
        guard let mySlot = mySlot else { return }
        
        // Store colors for use in animations
        chipColorA = colorA
        chipColorB = colorB
        
        // Update our own ChipSelector based on our slot's color
        let ourColor: String?
        switch mySlot {
        case .A:
            ourColor = colorA
        case .B:
            ourColor = colorB
        }
        
        if let colorName = ourColor, let colorSet = ChipColorSet.named(colorName) {
            chipSelector?.updateColorSet(colorSet)
        }
        
        // Update bet chip colors for both slots based on Firebase colors
        if let colorNameA = colorA {
            let chipStyleA = chipStyleFromColorSetName(colorNameA)
            passLineControl.setChipStyle(chipStyleA, for: .A)
        }
        
        if let colorNameB = colorB {
            let chipStyleB = chipStyleFromColorSetName(colorNameB)
            passLineControl.setChipStyle(chipStyleB, for: .B)
        }
    }
    
    /// Convert ChipColorSet name to MPSmallBetChipStyle
    private func chipStyleFromColorSetName(_ colorName: String) -> MPSmallBetChipStyle {
        switch colorName.lowercased() {
        case "yellow green", "yellow":
            return .yellow
        case "green":
            return .green
        case "cyan", "blue":
            return .blue
        case "red":
            return .red
        default:
            return .yellow
        }
    }
    
    /// Get the dot color for animation based on the slot's chip color
    private func getDotColor(for slot: PassLineTwoPlayerControl.PlayerSlot) -> UIColor {
        let colorName: String?
        switch slot {
        case .A:
            colorName = chipColorA ?? "Yellow Green" // Default to yellow if not set yet
        case .B:
            colorName = chipColorB ?? "Green" // Default to green if not set yet
        }
        
        // Map color name to bright text color for visibility
        guard let colorName = colorName else {
            return slot == .A ? HardwayColors.hardwaysYellow : HardwayColors.mpChipGreenText
        }
        
        switch colorName.lowercased() {
        case "yellow green", "yellow":
            return HardwayColors.hardwaysYellow
        case "green":
            return HardwayColors.mpChipGreenText
        case "cyan", "blue":
            return HardwayColors.mpChipBlueText
        case "red":
            return HardwayColors.mpChipRedText
        default:
            return slot == .A ? HardwayColors.hardwaysYellow : HardwayColors.mpChipGreenText
        }
    }

    private func handleBalancesUpdate(playerIdA: String?, balanceA: Int?, playerIdB: String?, balanceB: Int?) {
        // Determine which player is the "other" player
        // If we don't know our slot yet, try to determine it from player IDs
        var mySlot = self.mySlot
        var justDetectedSlot = false
        var wasFirstPlayer = false
        if mySlot == nil {
            if playerIdA == playerId {
                mySlot = .A
                self.mySlot = .A
                justDetectedSlot = true
                wasFirstPlayer = true
            } else if playerIdB == playerId {
                mySlot = .B
                self.mySlot = .B
                justDetectedSlot = true
                wasFirstPlayer = false
            } else {
                // Still don't know our slot, can't show other player yet
                return
            }
        }
        
        // If we just detected our slot, sync our balance and chip color to Firebase
        if justDetectedSlot {
            tableState.updateBalance(playerId: playerId, balance: balance)
            
            // Set chip color based on slot position
            let colorSetName: String
            switch mySlot! {
            case .A:
                // Position A = Yellow/Green
                colorSetName = "Yellow Green"
            case .B:
                // Position B = Green
                colorSetName = "Green"
            }
            
            // Store color in Firebase
            tableState.updateChipColor(slot: mySlot!, colorSetName: colorSetName)
            
            // Update local UI - convert PassLineTableState.PlayerSlot to PassLineTwoPlayerControl.PlayerSlot
            let controlSlot: PassLineTwoPlayerControl.PlayerSlot = mySlot! == .A ? .A : .B
            updateChipColorForSlot(controlSlot)
        }

        guard let slot = mySlot else { return }

        let otherPlayerId: String?
        let otherPlayerBalance: Int?

        if slot == .A {
            // We're player A, so show player B's info
            otherPlayerId = playerIdB
            otherPlayerBalance = balanceB
        } else {
            // We're player B, so show player A's info
            otherPlayerId = playerIdA
            otherPlayerBalance = balanceA
        }

        // Track if this is the first time we're seeing the other player
        let previousOtherPlayerName = otherPlayerBalanceView.nameText
        let isFirstTimeSeeingOtherPlayer = (previousOtherPlayerName == "—" || previousOtherPlayerName.isEmpty)
        
        if let otherId = otherPlayerId, !otherId.isEmpty {
            // Show first 5 characters of the userID
            let displayName = String(otherId.prefix(5))
            otherPlayerBalanceView.nameText = displayName
            
            // If we're player A and this is the first time seeing player B, they just joined
            // Note: Player B will update their own chip color when they detect their slot
            if slot == .A && isFirstTimeSeeingOtherPlayer {
                // Player B just joined - they will handle their own chip color update
            }
        } else {
            otherPlayerBalanceView.nameText = "—"
        }

        // Update balance with animation
        if let balance = otherPlayerBalance {
            otherPlayerBalanceView.setBalance(balance, animated: true)
        } else {
            otherPlayerBalanceView.setBalance(nil, animated: false)
        }
    }

    private func handleAmountsUpdate(amountA: Int, amountB: Int) {
        let prevA = lastAmountA
        let prevB = lastAmountB

        if lastAmountA < 0 {
            // Initial load - set amounts but don't update colors here
            // Colors will be set by handleChipColorsUpdate when Firebase syncs
            lastAmountA = amountA
            lastAmountB = amountB
            passLineControl.betAmountA = amountA
            passLineControl.betAmountB = amountB
            return
        }

        let deltaA = amountA - prevA
        let deltaB = amountB - prevB
        var otherPlayerUpdatedA = false
        var otherPlayerUpdatedB = false
        var otherPlayerDeltaA: Int?
        var otherPlayerDeltaB: Int?

        if deltaA > 0 {
            let wasUs: Bool
            if let mySlot = mySlot {
                wasUs = (mySlot == .A)
            } else {
                wasUs = (pendingBetAmount == deltaA)
                if wasUs { pendingBetAmount = nil }
            }
            if !wasUs {
                otherPlayerUpdatedA = true
                otherPlayerDeltaA = deltaA
            }
        }
        if deltaB > 0 {
            let wasUs: Bool
            if let mySlot = mySlot {
                wasUs = (mySlot == .B)
            } else {
                wasUs = (pendingBetAmount == deltaB)
                if wasUs { pendingBetAmount = nil }
            }
            if !wasUs {
                otherPlayerUpdatedB = true
                otherPlayerDeltaB = deltaB
            }
        }

        // If experimental animation is enabled and another player placed a bet, animate first
        if enableChipAnimation && (otherPlayerUpdatedA || otherPlayerUpdatedB) {
            // Only animate if not already animating for this slot (one animation per bet action)
            if otherPlayerUpdatedA, otherPlayerDeltaA != nil, !isAnimatingSlotA {
                isAnimatingSlotA = true
                // Store the new amount to update after delay
                let amountToUpdate = amountA
                // Keep current amount visible during animation (don't change it yet)
                // The chip will show current amount during the dot animation, then update to amountToUpdate after delay
                // DO NOT update lastAmountA yet - wait until animation completes
                
                // Update chip value after delay to sync with dot arrival
                animateChipFromBalance(to: .A, amount: amountA, onUpdate: { [weak self] in
                    guard let self = self else { return }
                    // Update chip value after delay - this will either update existing chip or show new chip
                    self.passLineControl.betAmountA = amountToUpdate
                    self.lastAmountA = amountToUpdate
                    self.passLineControl.layoutIfNeeded()
                }) { [weak self] in
                    guard let self = self else { return }
                    self.isAnimatingSlotA = false
                    // Trigger bet update animation after chip value is set
                    self.passLineControl.animateBetUpdate(for: .A)
                }
            } else {
                // Update immediately if not animating (but only if we're not waiting for an animation)
                if !isAnimatingSlotA {
                    passLineControl.betAmountA = amountA
                    lastAmountA = amountA
                }
            }
            
            // Only animate if not already animating for this slot (one animation per bet action)
            if otherPlayerUpdatedB, otherPlayerDeltaB != nil, !isAnimatingSlotB {
                isAnimatingSlotB = true
                // Store the new amount to update after delay
                let amountToUpdate = amountB
                // Keep current amount visible during animation (don't change it yet)
                // The chip will show current amount during the dot animation, then update to amountToUpdate after delay
                // DO NOT update lastAmountB yet - wait until animation completes
                
                // Update chip value after delay to sync with dot arrival
                animateChipFromBalance(to: .B, amount: amountB, onUpdate: { [weak self] in
                    guard let self = self else { return }
                    // Update chip value after delay - this will either update existing chip or show new chip
                    self.passLineControl.betAmountB = amountToUpdate
                    self.lastAmountB = amountToUpdate
                    self.passLineControl.layoutIfNeeded()
                }) { [weak self] in
                    guard let self = self else { return }
                    self.isAnimatingSlotB = false
                    // Trigger bet update animation after chip value is set
                    self.passLineControl.animateBetUpdate(for: .B)
                }
            } else {
                // Update immediately if not animating (but only if we're not waiting for an animation)
                if !isAnimatingSlotB {
                    passLineControl.betAmountB = amountB
                    lastAmountB = amountB
                }
            }
        } else {
            // No animation - update immediately
            passLineControl.betAmountA = amountA
            passLineControl.betAmountB = amountB
            lastAmountA = amountA
            lastAmountB = amountB

            if otherPlayerUpdatedA || otherPlayerUpdatedB {
                passLineControl.layoutIfNeeded()
                if otherPlayerUpdatedA {
                    passLineControl.animateBetUpdate(for: .A)
                }
                if otherPlayerUpdatedB {
                    passLineControl.animateBetUpdate(for: .B)
                }
            }
        }
    }
    
    /// Animate a small chip circle from the other player's balance view to the bet slot
    /// - Parameters:
    ///   - slot: The slot to animate to
    ///   - amount: The bet amount (for reference)
    ///   - onUpdate: Called at 99% of animation to update chip value synchronously with dot arrival
    ///   - completion: Called when animation fully completes
    private func animateChipFromBalance(to slot: PassLineTwoPlayerControl.PlayerSlot, amount: Int, onUpdate: @escaping () -> Void, completion: @escaping () -> Void) {
        guard let otherPlayerBalanceView = otherPlayerBalanceView,
              otherPlayerBalanceView.superview != nil,
              otherPlayerBalanceView.nameText != "—" else {
            // If balance view isn't available or no other player exists, still apply delay
            // This ensures consistent timing even when balance view isn't ready
            let updateDelay = 0.25 * 0.99
            DispatchQueue.main.asyncAfter(deadline: .now() + updateDelay) {
                onUpdate()
                completion()
            }
            return
        }
        
        // Ensure layout is up to date
        view.layoutIfNeeded()
        passLineControl.layoutIfNeeded()
        otherPlayerBalanceView.layoutIfNeeded()
        
        // Get the center of the balance view in the main view's coordinate space
        // Since otherPlayerBalanceView is added directly to view, we can use its frame directly
        let balanceFrame = otherPlayerBalanceView.frame
        let startPoint = CGPoint(x: balanceFrame.midX, y: balanceFrame.midY)
        
        // Get destination frame for the bet slot (in passLineControl's coordinate space)
        let destinationFrame = passLineControl.frameForBetSlot(slot)
        // Convert to main view's coordinate space
        let destinationPoint = view.convert(CGPoint(x: destinationFrame.midX, y: destinationFrame.midY), from: passLineControl)
        
        // Create a small 8x8 circle (experimental chip indicator) - slightly larger for visibility
        let chipView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        // Use the chip color for this slot to match the bet chip
        let dotColor = getDotColor(for: slot)
        chipView.backgroundColor = dotColor
        chipView.layer.cornerRadius = 4
        chipView.center = startPoint
        chipView.alpha = 0 // Start invisible for fade-in
        
        // Add shadow for depth
        chipView.layer.shadowColor = UIColor.black.cgColor
        chipView.layer.shadowOpacity = 0.3
        chipView.layer.shadowRadius = 2
        chipView.layer.shadowOffset = CGSize(width: 0, height: 1)
        
        // Add to the main view (not a subview that might clip)
        view.addSubview(chipView)
        view.bringSubviewToFront(chipView)
        
        // Animate with easing curve (similar to chip animations)
        let animator = UIViewPropertyAnimator(
            duration: 0.25,
            controlPoint1: CGPoint(x: 0.25, y: 0.1),
            controlPoint2: CGPoint(x: 0.25, y: 1.0)
        ) {
            chipView.center = destinationPoint
            chipView.alpha = 1.0 // Fully visible
            // Add slight scale and rotation for chip-like effect
            chipView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3).rotated(by: .pi / 4)
        }
        
        // Update chip value at 99% of animation duration to sync with dot arrival
        // This ensures the chip updates right as the dot arrives, not after it's removed
        let updateDelay = 0.25 * 0.99
        DispatchQueue.main.asyncAfter(deadline: .now() + updateDelay) {
            // Update chip value right as dot arrives (at 99% of animation)
            onUpdate()
        }
        
        animator.addCompletion { position in
            // Only proceed if animation completed (not cancelled)
            guard position == .end else {
                chipView.removeFromSuperview()
                return
            }
            
            // Remove dot after animation completes
            chipView.removeFromSuperview()
            // Call completion after dot is removed
            completion()
        }
        
        animator.startAnimation()
    }

    private func setupBalanceView() {
        balanceView = BalanceView()
        balanceView.balance = startingBalance
    }

    private func setupChipSelector() {
        chipSelector = ChipSelector()
        chipSelector.delegate = self
        chipSelector.onBetReturned = { [weak self] amount in
            self?.balance += amount
        }
    }

    private func setupPassLineControl() {
        passLineControl = PassLineTwoPlayerControl()
        passLineControl.translatesAutoresizingMaskIntoConstraints = false
        passLineControl.getSelectedChipValue = { [weak self] in self?.selectedChipValue ?? 5 }
        passLineControl.getBalance = { [weak self] in self?.balance ?? 200 }
        passLineControl.onPlaceBetRequested = { [weak self] in
            self?.handlePlaceBetRequested()
        }
        view.addSubview(passLineControl)
        NSLayoutConstraint.activate([
            passLineControl.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            passLineControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            passLineControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            passLineControl.heightAnchor.constraint(equalToConstant: 50),
        ])
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
        let chipHeight: CGFloat = 60
        NSLayoutConstraint.activate([
            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomStackView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6, constant: -16),
            chipSelector.heightAnchor.constraint(equalToConstant: chipHeight),
            chipSelector.widthAnchor.constraint(equalTo: bottomStackView.widthAnchor),
        ])
    }

    private func handlePlaceBetRequested() {
        let amount = selectedChipValue
        guard amount <= balance else {
            HapticsHelper.lightHaptic()
            return
        }
        pendingBetAmount = amount
        tableState.placeBet(playerId: playerId, amount: amount) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success((let slot, _)):
                    if self.mySlot == nil { 
                        self.mySlot = slot
                        // Sync initial balance to Firebase when we first claim a slot
                        self.tableState.updateBalance(playerId: self.playerId, balance: self.balance)
                    }
                    self.balance -= amount
                    self.pendingBetAmount = nil
                    self.passLineControl.addBet(amount, to: slot == .A ? PassLineTwoPlayerControl.PlayerSlot.A : .B)
                    self.eventLogger.logPlacedBet(playerId: self.playerId, playerSlot: slot, amount: amount)
                case .failure:
                    self.pendingBetAmount = nil
                    HapticsHelper.lightHaptic()
                }
            }
        }
    }

    @objc private func dismissPlayground() {
        dismiss(animated: true)
    }
}

extension MultiplayerBetPlaygroundViewController: ChipSelectorDelegate {
    func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {}
}
