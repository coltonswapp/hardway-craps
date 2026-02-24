//
//  PlayerSeat.swift
//  hardway-craps
//
//  A seat representing one player: name, balance, and 1–2 blackjack hands.
//  Layout inspired by BlackjackHandPlayground (balance above horizontal hand stack).
//

import UIKit

final class PlayerSeat: UIView {

    // MARK: - Constants

    private static let handSpacing: CGFloat = 16
    private static let singleHandWidth: CGFloat = 180
    private static let seatHeight: CGFloat = 170

    // MARK: - Subviews

    private let balanceView: MPPlayerBalanceView = {
        let v = MPPlayerBalanceView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let handsStackView: UIStackView = {
        let v = UIStackView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.axis = .horizontal
        v.alignment = .bottom
        v.distribution = .fillEqually
        v.spacing = 16
        return v
    }()

    private let primaryHandView: CompactPlayerHandView
    private var splitHandView: CompactPlayerHandView?

    // MARK: - Public

    /// Chip style for this player's bet controls
    var chipStyle: MPSmallBetChipStyle

    /// When true, seat is read-only (remote player): bet control visible but disabled, hand can spread but not tap.
    var isRemote: Bool = false {
        didSet {
            // Show bet control but disable interaction for remote players
            primaryHandView.betControl.isUserInteractionEnabled = !isRemote
            setRemoteOpacity(for: primaryHandView.betControl, isRemote: isRemote)

            // Allow pan gestures (card spreading) but disable taps
            primaryHandView.canTap = isRemote ? { false } : nil

            // Split hand (if exists)
            splitHandView?.betControl.isUserInteractionEnabled = !isRemote
            if let splitControl = splitHandView?.betControl {
                setRemoteOpacity(for: splitControl, isRemote: isRemote)
            }
            splitHandView?.canTap = isRemote ? { false } : nil
        }
    }

    /// Display name for this seat (e.g. "You" or "Colton S.").
    var nameText: String {
        get { balanceView.nameText }
        set { balanceView.nameText = newValue }
    }

    /// Update balance display; use animated: true for changes from network/sync.
    func setBalance(_ balance: Int?, animated: Bool) {
        balanceView.setBalance(balance, animated: animated)
    }

    /// The first (main) hand. Use for deal, hit, stand, etc.
    var primaryHand: CompactPlayerHandView {
        primaryHandView
    }

    /// All hands (1 or 2). Second hand present only after split.
    var hands: [CompactPlayerHandView] {
        if let split = splitHandView {
            return [primaryHandView, split]
        }
        return [primaryHandView]
    }

    /// Add a second hand (e.g. after split). Caller is responsible for moving one card and adding the new hand to the stack.
    func addSecondHand(_ handView: CompactPlayerHandView) {
        guard splitHandView == nil else { return }
        handView.translatesAutoresizingMaskIntoConstraints = false
        handView.betControl.isHidden = isRemote
        handView.isUserInteractionEnabled = !isRemote
        handsStackView.addArrangedSubview(handView)
        splitHandView = handView
        updateHandsStackWidth()
    }

    /// Remove the second hand (e.g. after round ends). Caller should clear/discard as needed.
    func removeSecondHand() {
        guard let split = splitHandView else { return }
        handsStackView.removeArrangedSubview(split)
        split.removeFromSuperview()
        splitHandView = nil
        updateHandsStackWidth()
    }

    // MARK: - Init

    init(chipStyle: MPSmallBetChipStyle = .yellow) {
        self.chipStyle = chipStyle
        self.primaryHandView = CompactPlayerHandView(mpChipStyle: chipStyle)
        super.init(frame: .zero)
        setupView()
    }

    convenience override init(frame: CGRect) {
        self.init(chipStyle: .yellow)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        primaryHandView.translatesAutoresizingMaskIntoConstraints = false
        handsStackView.addArrangedSubview(primaryHandView)

        addSubview(balanceView)
        addSubview(handsStackView)

        handsStackViewWidthConstraint = handsStackView.widthAnchor.constraint(equalToConstant: Self.singleHandWidth)

        NSLayoutConstraint.activate([
            // Hands at the top
            handsStackView.topAnchor.constraint(equalTo: topAnchor),
            handsStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            handsStackView.heightAnchor.constraint(equalToConstant: Self.seatHeight),
            handsStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            handsStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            handsStackViewWidthConstraint!,

            // Balance below the hands
            balanceView.topAnchor.constraint(equalTo: handsStackView.bottomAnchor, constant: 8),
            balanceView.centerXAnchor.constraint(equalTo: centerXAnchor),
            balanceView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            balanceView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            balanceView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private var handsStackViewWidthConstraint: NSLayoutConstraint!

    override func layoutSubviews() {
        super.layoutSubviews()
        updateHandsStackWidth()
    }

    private func updateHandsStackWidth() {
        let count = hands.count
        let width: CGFloat
        if count == 1 {
            width = Self.singleHandWidth
        } else {
            let needed = Self.singleHandWidth * CGFloat(count) + Self.handSpacing * CGFloat(count - 1)
            width = min(needed, bounds.width)
        }
        handsStackViewWidthConstraint.constant = width
    }

    /// Set opacity for remote player bet controls: control at 50%, chip at 100%
    private func setRemoteOpacity(for betControl: PlainControl, isRemote: Bool) {
        if isRemote {
            // Set bet control background and label to 50% opacity
            betControl.alpha = 0.5
            // Override chip to stay at 100% opacity
            betControl.betView.alpha = 1.0
        } else {
            // Restore normal opacity
            betControl.alpha = 1.0
            betControl.betView.alpha = 1.0
        }
    }
}
