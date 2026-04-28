//
//  BaseGameplayViewController.swift
//  hardway-craps
//

import UIKit

class BaseGameplayViewController: UIViewController {

    // MARK: - Shared UI

    private(set) var topBar: GameplayTopBar!
    private(set) var bottomBar: GameplayBottomBar!
    var instructionLabel: InstructionLabel!

    var balanceView: BalanceView { bottomBar.balanceView }
    var chipSelector: ChipSelector { bottomBar.chipSelector }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureNavigationBar()
        setupBars()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        chipSelector.initializeIndicatorPosition()
    }

    // MARK: - Bar Setup

    private func setupBars() {
        instructionLabel = InstructionLabel()
        instructionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        instructionLabel.setContentHuggingPriority(.defaultLow, for: .vertical)

        let chipSel = createChipSelector()
        bottomBar = GameplayBottomBar(chipSelector: chipSel)

        topBar = GameplayTopBar()
        topBar.configure(leadingView: instructionLabel, trailingView: configureTopBarTrailingView())

        installBarConstraints()
    }

    /// Adds bars to the view and activates default safe-area constraints.
    /// Override to manage constraints manually (e.g. multi-layout modes).
    func installBarConstraints() {
        bottomBar.installConstraints(in: view)
        topBar.installConstraints(in: view)
    }

    // MARK: - Hook Methods (override in subclasses)

    /// Returns the view displayed on the trailing side of the top bar.
    /// Craps returns `CurrentBetView`; Blackjack/Baccarat return `DeckView`.
    func configureTopBarTrailingView() -> UIView? { nil }

    /// Creates the `ChipSelector` instance. Override to customize chip values.
    func createChipSelector() -> ChipSelector { ChipSelector() }

    /// Called during `viewDidLoad` to set up navigation bar items.
    /// Default implementation adds the settings gear button.
    func configureNavigationBar() {
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(settingsButtonTapped)
        )
        navigationItem.rightBarButtonItem = settingsButton
    }

    @objc func settingsButtonTapped() {
        // Subclasses override to present their own settings VC
    }
}
