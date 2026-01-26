//
//  PlayerControlStack.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

final class PlayerControlStack: UIView {
    
    enum Action {
        case hit
        case stand
        case double
        case split
    }
    
    enum GamePhase {
        case waitingForBet      // Waiting for player to place a bet
        case readyToDeal        // Bet placed, waiting for "Ready?" tap
        case dealing            // Cards are being dealt
        case playerTurn         // Player can hit, stand, double, split
        case dealerTurn         // Dealer's turn
        case gameOver           // Hand is complete
    }
    
    struct GameState {
        let gamePhase: GamePhase
        let cardCount: Int
        let hasHit: Bool
        let canSplit: Bool // First two cards have same rank
        let hasBet: Bool
        let playerHasStood: Bool // Player has chosen to stand
        let hasDoubled: Bool // Player has doubled down
    }
    
    var onActionTapped: ((Action) -> Void)?
    
    private let stackView = UIStackView()
    private let hitButton = ActionButton(title: "Hit")
    private let standButton = ActionButton(title: "Stand")

    // Double and split buttons are now managed separately
    let doubleButton = ActionButton(title: "Double")
    let splitButton = CircularActionButton(systemIconName: "arrow.triangle.branch")
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 8

        hitButton.addTarget(self, action: #selector(hitTapped), for: .touchUpInside)
        standButton.addTarget(self, action: #selector(standTapped), for: .touchUpInside)
        doubleButton.addTarget(self, action: #selector(doubleTapped), for: .touchUpInside)
        splitButton.addTarget(self, action: #selector(splitTapped), for: .touchUpInside)

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Only add Hit and Stand to main stack view
        // Double and Split are now managed separately by the view controller
        stackView.addArrangedSubview(hitButton)
        stackView.addArrangedSubview(standButton)
    }
    
    func updateControls(for gameState: GameState) {
        var disabledButtons: Set<Action> = []
        
        // All buttons are always visible, we just control which are disabled
        switch gameState.gamePhase {
        case .waitingForBet, .readyToDeal, .dealing, .dealerTurn, .gameOver:
            // Disable all buttons when not in player's turn
            disabledButtons = [.hit, .stand, .double, .split]
            
        case .playerTurn:
            // If player has stood, disable all buttons but keep them visible
            if gameState.playerHasStood {
                disabledButtons = [.hit, .stand]
                
                if gameState.cardCount == 2 && !gameState.hasHit {
                    disabledButtons.insert(.double)
                }
                
                if gameState.canSplit && gameState.cardCount == 2 && !gameState.hasHit {
                    disabledButtons.insert(.split)
                }
            } else {
                // Hit and Stand are always available during player's turn
                // Double is only available on first action (2 cards, hasn't hit, hasn't doubled)
                if gameState.cardCount == 2 && !gameState.hasHit && !gameState.hasDoubled {
                    // Double is enabled
                } else {
                    disabledButtons.insert(.double)
                }
                
                // Split is only available if first two cards have same rank and hasn't hit
                if gameState.canSplit && gameState.cardCount == 2 && !gameState.hasHit {
                    // Split is enabled
                } else {
                    disabledButtons.insert(.split)
                }
            }
        }
        
        // Update button states (no animation needed since buttons are always visible)
        updateButtonStates(disabledButtons: disabledButtons)
    }
    
    private func updateButtonStates(disabledButtons: Set<Action>) {
        // Only update Hit and Stand buttons (Double and Split are managed separately by view controller)
        let buttonOrder: [Action] = [.hit, .stand]
        for action in buttonOrder {
            guard let button = button(for: action) else { continue }
            let isDisabled = disabledButtons.contains(action)
            button.isEnabled = !isDisabled
            button.setDisabled(isDisabled)
        }

        // Update double and split button states (they're managed by view controller for visibility)
        let isDoubleDisabled = disabledButtons.contains(.double)
        doubleButton.setDisabled(isDoubleDisabled)

        let isSplitDisabled = disabledButtons.contains(.split)
        splitButton.setDisabled(isSplitDisabled)
    }

    private func button(for action: Action) -> ActionButton? {
        switch action {
        case .hit:
            return hitButton
        case .stand:
            return standButton
        case .double, .split:
            return nil // These are managed separately now
        }
    }
    
    @objc private func hitTapped() {
        onActionTapped?(.hit)
    }
    
    @objc private func standTapped() {
        onActionTapped?(.stand)
    }
    
    @objc private func doubleTapped() {
        onActionTapped?(.double)
    }
    
    @objc private func splitTapped() {
        onActionTapped?(.split)
    }
}

final class ActionButton: UIButton {

    private var originalTransform: CGAffineTransform = .identity
    private var isDisabledState = false

    init(title: String) {
        super.init(frame: .zero)
        setupView(title: title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView(title: String) {
        translatesAutoresizingMaskIntoConstraints = false
        setTitle(title, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        backgroundColor = HardwayColors.surfaceGray
        setTitleColor(.white, for: .normal)
        layer.cornerRadius = 16
        layer.borderWidth = 1.5
        layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 45)
        ])

        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchDragExit, .touchCancel])
    }

    func setDisabled(_ disabled: Bool) {
        isDisabledState = disabled
        isEnabled = !disabled

        UIView.animate(withDuration: 0.2) {
            if disabled {
                self.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.5)
                self.setTitleColor(HardwayColors.label.withAlphaComponent(0.5), for: .normal)
                self.layer.borderColor = HardwayColors.label.withAlphaComponent(0.2).cgColor
            } else {
                self.backgroundColor = HardwayColors.surfaceGray
                self.setTitleColor(.white, for: .normal)
                self.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
            }
        }
    }

    @objc private func touchDown() {
        guard isEnabled else { return }
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            self.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.6)
        }
    }

    @objc private func touchUp() {
        guard isEnabled else { return }
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.transform = .identity
            self.backgroundColor = HardwayColors.surfaceGray
        }

        HapticsHelper.lightHaptic()
    }
}

final class CircularActionButton: UIButton {

    private var isDisabledState = false
    private let iconImageView = UIImageView()

    init(systemIconName: String) {
        super.init(frame: .zero)
        setupView(systemIconName: systemIconName)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView(systemIconName: String) {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = HardwayColors.surfaceGray
        layer.borderWidth = 1.5
        layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor

        // Configure icon
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        iconImageView.image = UIImage(systemName: systemIconName, withConfiguration: config)
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.isUserInteractionEnabled = false
        addSubview(iconImageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 60),
            heightAnchor.constraint(equalToConstant: 60),

            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24)
        ])

        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchDragExit, .touchCancel])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }

    func setDisabled(_ disabled: Bool) {
        isDisabledState = disabled
        isEnabled = !disabled

        UIView.animate(withDuration: 0.2) {
            if disabled {
                self.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.5)
                self.iconImageView.tintColor = HardwayColors.label.withAlphaComponent(0.5)
                self.layer.borderColor = HardwayColors.label.withAlphaComponent(0.2).cgColor
            } else {
                self.backgroundColor = HardwayColors.surfaceGray
                self.iconImageView.tintColor = .white
                self.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
            }
        }
    }

    @objc private func touchDown() {
        guard isEnabled else { return }
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            self.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.6)
        }
    }

    @objc private func touchUp() {
        guard isEnabled else { return }
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.transform = .identity
            self.backgroundColor = HardwayColors.surfaceGray
        }

        HapticsHelper.lightHaptic()
    }
}
