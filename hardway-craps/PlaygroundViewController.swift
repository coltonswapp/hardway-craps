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
    private var bottomStackView: UIStackView!
    
    private var lockBetButton: UIButton!
    private var unlockBetButton: UIButton!
    private var clearAllButton: UIButton!
    private var controlButtonsStackView: UIStackView!
    
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
        setupBalanceView()
        setupChipSelector()
        setupBottomStackView()
        setupPassLineControl()
        setupControlButtons()
    }
    
    // MARK: - Setup
    
    private func setupViewController() {
        title = "Pass Line + Odds Playground"
        
        // Configure navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissPlayground)
        )
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
        passLineControl.onOddsPlaced = { [weak self] amount in
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
}

// MARK: - ChipSelectorDelegate

extension PlaygroundViewController: ChipSelectorDelegate {
    func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {
        // Chip selection handled automatically
    }
}
