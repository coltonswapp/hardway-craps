//
//  PlaygroundViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 2/3/26.
//

import UIKit

class PlaygroundViewController: UIViewController {
    
    // MARK: - Properties
    
    private let startingBalance: Int = 200
    
    private var chipSelector: ChipSelector!
    private var balanceView: BalanceView!
    private var passLineControl: PlainControl!
    private var pointControl: PointControl!
    private var bottomStackView: UIStackView!
    
    private var lockBetButton: UIButton!
    private var unlockBetButton: UIButton!
    private var clearAllButton: UIButton!
    private var controlButtonsStackView: UIStackView!
    
    private var placeBetButton: UIButton!
    private var addComeBetButton: UIButton!
    private var addComeOddsButton: UIButton!
    private var hitComeBetButton: UIButton!
    private var clearPointControlButton: UIButton!
    private var pointControlButtonsStackView: UIStackView!
    
    private var programmaticChipsStackView: UIStackView!
    
    var balance: Int {
        get {
            return balanceView?.balance ?? startingBalance
        }
        set {
            balanceView?.balance = newValue
            chipSelector?.updateAvailableChips(balance: newValue)
        }
    }
    
    var selectedChipValue: Int {
        return chipSelector?.selectedValue ?? 5
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        setupViewController()
        setupProgrammaticChips()
        setupBalanceView()
        setupChipSelector()
        setupBottomStackView()
        setupPointControl()
        setupPointControlButtons()
        setupPassLineControl()
        setupControlButtons()
    }
    
    // MARK: - Setup
    
    private func setupViewController() {
        title = "Playground"
        
        // Configure navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissPlayground)
        )
    }
    
    private func setupProgrammaticChips() {
        // Create stack view for programmatic chips
        programmaticChipsStackView = UIStackView()
        programmaticChipsStackView.translatesAutoresizingMaskIntoConstraints = false
        programmaticChipsStackView.axis = .horizontal
        programmaticChipsStackView.distribution = .fill
        programmaticChipsStackView.alignment = .center
        programmaticChipsStackView.spacing = 12
        
        // Create chips with test values using different color sets
        let chipValues = [1, 5, 25, 50, 100]
        let colorSets: [ChipColorSet] = [.yellowGreen, .cyan, .green, .red, .purple]
        
        for (index, value) in chipValues.enumerated() {
            let colorSet = colorSets[index % colorSets.count] // Cycle through color sets
            let chip = ProgrammaticChipView(value: value, size: 45, colorSet: colorSet)
            chip.translatesAutoresizingMaskIntoConstraints = false
            programmaticChipsStackView.addArrangedSubview(chip)
        }
        
        view.addSubview(programmaticChipsStackView)
        
        NSLayoutConstraint.activate([
            programmaticChipsStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            programmaticChipsStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    private func setupBalanceView() {
        balanceView = BalanceView()
        balanceView.balance = startingBalance
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
        bottomStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Height: chips are 60pt
        let chipSelectorHeight: CGFloat = 60
        
        NSLayoutConstraint.activate([
            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomStackView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6, constant: -16),
            chipSelector.heightAnchor.constraint(equalToConstant: chipSelectorHeight),
            chipSelector.widthAnchor.constraint(equalTo: bottomStackView.widthAnchor)
        ])
    }
    
    private func setupPointControl() {
        pointControl = PointControl(pointNumber: 8)
        pointControl.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure callbacks for place bets
        pointControl.getSelectedChipValue = { [weak self] in
            return self?.selectedChipValue ?? 5
        }
        pointControl.getBalance = { [weak self] in
            return self?.balance ?? 200
        }
        pointControl.onBetPlaced = { [weak self] amount in
            guard let self = self else { return }
            self.balance -= amount
        }
        pointControl.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
        }
        
        // Configure callbacks for come bet odds
        pointControl.onComeBetOddsPlaced = { [weak self] amount, previousOddsAmount, pointNumber in
            guard let self = self else { return }
            // Playground doesn't enforce limits, just deduct the full amount
            self.balance -= amount
        }
        pointControl.onComeBetOddsRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
        }
        
        // Register with BetDragManager for drag-and-drop support
        BetDragManager.shared.registerDropTarget(pointControl)
        
        view.addSubview(pointControl)
        
        NSLayoutConstraint.activate([
            pointControl.widthAnchor.constraint(equalToConstant: 60),
            pointControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // Position above pass line buttons: bottomStackView (20pt gap) + passLineControl (50pt) + gap (20pt) + controlButtonsStackView (44pt) + desired spacing (40pt) = 174pt
            pointControl.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -174),
            pointControl.heightAnchor.constraint(equalToConstant: 150)
        ])
    }
    
    private func setupPointControlButtons() {
        // Create buttons for point control testing
        placeBetButton = createControlButton(title: "Place Bet", backgroundColor: HardwayColors.green)
        placeBetButton.addTarget(self, action: #selector(placeBetTapped), for: .touchUpInside)
        
        addComeBetButton = createControlButton(title: "Add Come Bet", backgroundColor: HardwayColors.green)
        addComeBetButton.addTarget(self, action: #selector(addComeBetTapped), for: .touchUpInside)
        
        addComeOddsButton = createControlButton(title: "Add Come Odds", backgroundColor: HardwayColors.surfaceGray)
        addComeOddsButton.addTarget(self, action: #selector(addComeOddsTapped), for: .touchUpInside)
        
        hitComeBetButton = createControlButton(title: "Hit Come Bet", backgroundColor: HardwayColors.surfaceGray)
        hitComeBetButton.addTarget(self, action: #selector(hitComeBetTapped), for: .touchUpInside)
        
        clearPointControlButton = createControlButton(title: "Clear All", backgroundColor: HardwayColors.surfaceGray)
        clearPointControlButton.addTarget(self, action: #selector(clearPointControlTapped), for: .touchUpInside)
        
        // Create first row (3 buttons)
        let firstRow = UIStackView()
        firstRow.axis = .horizontal
        firstRow.distribution = .fillEqually
        firstRow.alignment = .fill
        firstRow.spacing = 8
        firstRow.addArrangedSubview(placeBetButton)
        firstRow.addArrangedSubview(addComeBetButton)
        firstRow.addArrangedSubview(addComeOddsButton)
        
        // Create second row (2 buttons)
        let secondRow = UIStackView()
        secondRow.axis = .horizontal
        secondRow.distribution = .fillEqually
        secondRow.alignment = .fill
        secondRow.spacing = 8
        secondRow.addArrangedSubview(hitComeBetButton)
        secondRow.addArrangedSubview(clearPointControlButton)
        
        // Create vertical stack view for rows
        pointControlButtonsStackView = UIStackView()
        pointControlButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        pointControlButtonsStackView.axis = .vertical
        pointControlButtonsStackView.distribution = .fillEqually
        pointControlButtonsStackView.alignment = .fill
        pointControlButtonsStackView.spacing = 8
        
        pointControlButtonsStackView.addArrangedSubview(firstRow)
        pointControlButtonsStackView.addArrangedSubview(secondRow)
        
        view.addSubview(pointControlButtonsStackView)
        
        NSLayoutConstraint.activate([
            pointControlButtonsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pointControlButtonsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            pointControlButtonsStackView.bottomAnchor.constraint(equalTo: pointControl.topAnchor, constant: -12),
            // Height: 2 rows * 44pt each + 1 spacing * 8pt = 88 + 8 = 96pt
            pointControlButtonsStackView.heightAnchor.constraint(equalToConstant: 96)
        ])
    }
    
    private func setupPassLineControl() {
        passLineControl = PlainControl(title: "Pass Line")
        passLineControl.translatesAutoresizingMaskIntoConstraints = false
        
        // Enable odds support
        passLineControl.supportsOdds = true
        
        // Configure callbacks
        passLineControl.getSelectedChipValue = { [weak self] in
            return self?.selectedChipValue ?? 5
        }
        passLineControl.getBalance = { [weak self] in
            return self?.balance ?? 200
        }
        passLineControl.onBetPlaced = { [weak self] amount in
            guard let self = self else { return }
            self.balance -= amount
        }
        passLineControl.onBetRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
        }
        passLineControl.onOddsPlaced = { [weak self] amount, previousOddsAmount in
            guard let self = self else { return }
            self.balance -= amount
        }
        passLineControl.onOddsRemoved = { [weak self] amount in
            guard let self = self else { return }
            self.balance += amount
        }
        
        view.addSubview(passLineControl)
        
        NSLayoutConstraint.activate([
            passLineControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            passLineControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            passLineControl.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -20),
            passLineControl.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func setupControlButtons() {
        // Create buttons
        lockBetButton = createControlButton(title: "Lock Bet", backgroundColor: HardwayColors.green)
        lockBetButton.addTarget(self, action: #selector(lockBetTapped), for: .touchUpInside)
        
        unlockBetButton = createControlButton(title: "Unlock Bet", backgroundColor: HardwayColors.surfaceGray)
        unlockBetButton.addTarget(self, action: #selector(unlockBetTapped), for: .touchUpInside)
        
        clearAllButton = createControlButton(title: "Clear All", backgroundColor: HardwayColors.surfaceGray)
        clearAllButton.addTarget(self, action: #selector(clearAllTapped), for: .touchUpInside)
        
        // Create stack view
        controlButtonsStackView = UIStackView()
        controlButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        controlButtonsStackView.axis = .horizontal
        controlButtonsStackView.distribution = .fillEqually
        controlButtonsStackView.alignment = .fill
        controlButtonsStackView.spacing = 12
        
        controlButtonsStackView.addArrangedSubview(lockBetButton)
        controlButtonsStackView.addArrangedSubview(unlockBetButton)
        controlButtonsStackView.addArrangedSubview(clearAllButton)
        
        view.addSubview(controlButtonsStackView)
        
        NSLayoutConstraint.activate([
            controlButtonsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            controlButtonsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            controlButtonsStackView.bottomAnchor.constraint(equalTo: passLineControl.topAnchor, constant: -20),
            controlButtonsStackView.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func createControlButton(title: String, backgroundColor: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = backgroundColor
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1.5
        button.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
        return button
    }
    
    // MARK: - Actions
    
    @objc private func dismissPlayground() {
        dismiss(animated: true)
    }
    
    @objc private func lockBetTapped() {
        guard passLineControl.betAmount > 0 else {
            HapticsHelper.failureHaptic()
            return
        }
        passLineControl.lockBet()
        HapticsHelper.lightHaptic()
    }
    
    @objc private func unlockBetTapped() {
        passLineControl.unlockBet()
        HapticsHelper.lightHaptic()
    }
    
    @objc private func clearAllTapped() {
        passLineControl.clearAll()
        HapticsHelper.lightHaptic()
    }
    
    // MARK: - Point Control Actions
    
    @objc private func placeBetTapped() {
        let amount = selectedChipValue
        guard balance >= amount else {
            HapticsHelper.failureHaptic()
            return
        }
        pointControl.addBetWithAnimation(amount)
        HapticsHelper.lightHaptic()
    }
    
    @objc private func addComeBetTapped() {
        let amount = selectedChipValue
        guard balance >= amount else {
            HapticsHelper.failureHaptic()
            return
        }
        guard pointControl.betAmount > 0 else {
            HapticsHelper.failureHaptic()
            return
        }
        pointControl.addComeBet(
            amount: amount,
            getSelectedChipValue: { [weak self] in
                return self?.selectedChipValue ?? 5
            },
            getBalance: { [weak self] in
                return self?.balance ?? 200
            }
        )
        balance -= amount
        HapticsHelper.lightHaptic()
    }
    
    @objc private func addComeOddsTapped() {
        guard pointControl.hasComeBet else {
            HapticsHelper.failureHaptic()
            return
        }
        let amount = selectedChipValue
        guard balance >= amount else {
            HapticsHelper.failureHaptic()
            return
        }
        pointControl.addComeBetOdds(amount: amount)
        HapticsHelper.lightHaptic()
    }
    
    @objc private func hitComeBetTapped() {
        guard pointControl.hasComeBet else {
            HapticsHelper.failureHaptic()
            return
        }
        // Return the come bet amount to balance (odds already returned via callback)
        let comeBetAmount = pointControl.comeBetAmount
        balance += comeBetAmount
        pointControl.clearComeBet()
        HapticsHelper.lightHaptic()
    }
    
    @objc private func clearPointControlTapped() {
        // Store come bet amount before clearing (odds and place bet handled by callbacks)
        let comeBetAmount = pointControl.comeBetAmount
        
        // Clear all bets (place bet and come bet)
        // clearAll() triggers onBetRemoved callback for place bet
        // clearComeBet() triggers onComeBetOddsRemoved callback for odds
        pointControl.clearAll()
        pointControl.clearComeBet()
        
        // Restore come bet amount manually (addComeBet doesn't trigger callbacks)
        balance += comeBetAmount
        HapticsHelper.lightHaptic()
    }
}

// MARK: - ChipSelectorDelegate

extension PlaygroundViewController: ChipSelectorDelegate {
    func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {
        // Chip selection handled automatically
    }
}
