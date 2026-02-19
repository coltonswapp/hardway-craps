//
//  ChipStackPlayground.swift
//  hardway-craps
//
//  Created by Colton Swapp on 2/10/26.
//

import UIKit

class ChipStackPlayground: UIViewController {

    // MARK: - Constants

    private let chipThreshold = 2000
    private let incrementAmount = 250
    private let chipSize: CGFloat = 60

    // MARK: - State

    private var currentBalance: Int = 1500 {
        didSet {
            balanceView.balance = currentBalance
            updateChipStack(animated: true)
        }
    }

    // MARK: - Views

    private var balanceView: BalanceView!
    private var chipSelector: ChipSelector!
    private var chipSelectorContainer: UIView!
    private var bankrollButtonsStackView: UIStackView!
    private var thresholdLabel: UILabel!
    private var increaseButton: UIButton!
    private var decreaseButton: UIButton!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Chip Stack Playground"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissPlayground)
        )

        setupThresholdLabel()
        setupChipSelectorContainer()
        setupBalanceView()
        setupChipSelector()
        setupBankrollButtons()
    }

    // MARK: - Setup

    private func setupThresholdLabel() {
        thresholdLabel = UILabel()
        thresholdLabel.translatesAutoresizingMaskIntoConstraints = false
        thresholdLabel.font = .systemFont(ofSize: 13, weight: .regular)
        thresholdLabel.textColor = .secondaryLabel
        thresholdLabel.textAlignment = .center
        thresholdLabel.text = "Chip stack changes above $\(chipThreshold)"
        view.addSubview(thresholdLabel)

        NSLayoutConstraint.activate([
            thresholdLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            thresholdLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
    }

    private func setupChipSelectorContainer() {
        chipSelectorContainer = UIView()
        chipSelectorContainer.translatesAutoresizingMaskIntoConstraints = false
        chipSelectorContainer.clipsToBounds = false
        view.addSubview(chipSelectorContainer)

        NSLayoutConstraint.activate([
            chipSelectorContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            chipSelectorContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            chipSelectorContainer.heightAnchor.constraint(equalToConstant: chipSize + 13)
        ])
    }

    private func setupBalanceView() {
        balanceView = BalanceView()
        balanceView.balance = currentBalance
        balanceView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(balanceView)

        NSLayoutConstraint.activate([
            balanceView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            balanceView.bottomAnchor.constraint(equalTo: chipSelectorContainer.topAnchor, constant: -8)
        ])
    }

    private func setupChipSelector() {
        chipSelector = ChipSelector(chipValues: [1, 5, 25, 50, 100], chipSize: chipSize)
        chipSelector.delegate = self
        chipSelector.translatesAutoresizingMaskIntoConstraints = false
        chipSelectorContainer.addSubview(chipSelector)

        NSLayoutConstraint.activate([
            chipSelector.centerXAnchor.constraint(equalTo: chipSelectorContainer.centerXAnchor),
            chipSelector.centerYAnchor.constraint(equalTo: chipSelectorContainer.centerYAnchor)
        ])
    }

    private func setupBankrollButtons() {
        increaseButton = makeButton(title: "+ $\(incrementAmount)", color: HardwayColors.green)
        increaseButton.addTarget(self, action: #selector(increaseBalance), for: .touchUpInside)

        decreaseButton = makeButton(title: "- $\(incrementAmount)", color: HardwayColors.surfaceGray)
        decreaseButton.addTarget(self, action: #selector(decreaseBalance), for: .touchUpInside)

        bankrollButtonsStackView = UIStackView(arrangedSubviews: [decreaseButton, increaseButton])
        bankrollButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        bankrollButtonsStackView.axis = .horizontal
        bankrollButtonsStackView.distribution = .fillEqually
        bankrollButtonsStackView.spacing = 12
        view.addSubview(bankrollButtonsStackView)

        NSLayoutConstraint.activate([
            bankrollButtonsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bankrollButtonsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bankrollButtonsStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            bankrollButtonsStackView.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func makeButton(title: String, color: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = color
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1.5
        button.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
        return button
    }

    // MARK: - Chip Stack Updates

    private func updateChipStack(animated: Bool) {
        chipSelector.updateBalance(currentBalance)
    }

    // MARK: - Actions

    @objc private func dismissPlayground() {
        dismiss(animated: true)
    }

    @objc private func increaseBalance() {
        currentBalance += incrementAmount
        HapticsHelper.lightHaptic()
    }

    @objc private func decreaseBalance() {
        let newBalance = currentBalance - incrementAmount
        guard newBalance > 0 else {
            HapticsHelper.failureHaptic()
            return
        }
        currentBalance = newBalance
        HapticsHelper.lightHaptic()
    }
}

// MARK: - ChipSelectorDelegate

extension ChipStackPlayground: ChipSelectorDelegate {
    func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int) {}
}
