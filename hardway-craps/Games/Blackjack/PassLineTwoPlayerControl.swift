//
//  PassLineTwoPlayerControl.swift
//  hardway-craps
//
//  Pass Line control with two bet views: Player A (8pt from leading), Player B (8pt from trailing).
//  Subclasses PlainControl to reuse tap/balance/chip logic; adds a second chip and slot-aware callback.
//

import UIKit

/// Pass Line control with two MPSmallBetChip views (yellow = A, blue = B). Tap on each chip adds to that slot.
final class PassLineTwoPlayerControl: PlainControl {

    enum PlayerSlot: String {
        case A = "A"
        case B = "B"
    }

    private var chipA: MPSmallBetChip!
    private var betViewB: MPSmallBetChip!
    /// Always-visible tap target for the B slot so the right chip is tappable when amount is 0 (chip hides when empty).
    private var bSlotTapTarget: UIView!

    /// Called when the user taps to place a bet (either side). VC assigns slot (first bettor = A, second = B) and calls addBet(amount, to: slot).
    var onPlaceBetRequested: (() -> Void)?

    var betAmountA: Int {
        get { chipA.amount }
        set { chipA.amount = newValue }
    }

    var betAmountB: Int {
        get { betViewB.amount }
        set { betViewB.amount = newValue }
    }

    func betAmount(for slot: PlayerSlot) -> Int {
        switch slot {
        case .A: return chipA.amount
        case .B: return betViewB.amount
        }
    }

    /// Frame of the bet chip for the given slot in the receiver's bounds. Use to animate a visual from another view to the bet.
    func frameForBetSlot(_ slot: PlayerSlot) -> CGRect {
        switch slot {
        case .A: return chipA.frame
        case .B: return betViewB.frame
        }
    }
    
    /// Change the chip style for a given slot (e.g., when player joins and needs to match their chipSelector color)
    func setChipStyle(_ style: MPSmallBetChipStyle, for slot: PlayerSlot) {
        switch slot {
        case .A:
            chipA.style = style
        case .B:
            betViewB.style = style
        }
    }

    override init(title: String? = nil, mpChipStyle: MPSmallBetChipStyle? = nil) {
        super.init(title: title ?? "Pass Line", mpChipStyle: mpChipStyle)
        setupTwoPlayerGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configureBetViewConstraints() {
        // Hide PlainControl's default betView; we use MPSmallBetChip (yellow/blue) for both slots.
        betView.isHidden = true
        betView.alpha = 0

        chipA = MPSmallBetChip(style: .yellow)
        addSubview(chipA)
        NSLayoutConstraint.activate([
            chipA.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            chipA.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // B slot: tap target is always visible so the right side is tappable when B has no bet.
        let chipHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 30 * 1.25 : 30
        bSlotTapTarget = UIView()
        bSlotTapTarget.translatesAutoresizingMaskIntoConstraints = false
        bSlotTapTarget.backgroundColor = .clear
        bSlotTapTarget.isUserInteractionEnabled = true
        addSubview(bSlotTapTarget)
        NSLayoutConstraint.activate([
            bSlotTapTarget.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bSlotTapTarget.centerYAnchor.constraint(equalTo: centerYAnchor),
            bSlotTapTarget.widthAnchor.constraint(equalToConstant: chipHeight),
            bSlotTapTarget.heightAnchor.constraint(equalToConstant: chipHeight),
        ])

        betViewB = MPSmallBetChip(style: .blue)
        addSubview(betViewB)
        NSLayoutConstraint.activate([
            betViewB.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            betViewB.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        bringSubviewToFront(betViewB)
        bringSubviewToFront(chipA)
    }

    private func setupTwoPlayerGestures() {
        let tapA = UITapGestureRecognizer(target: self, action: #selector(handlePlaceBetRequested))
        chipA.addGestureRecognizer(tapA)
        chipA.isUserInteractionEnabled = true
        let tapB = UITapGestureRecognizer(target: self, action: #selector(handleTapB(_:)))
        bSlotTapTarget.addGestureRecognizer(tapB)
        let tapBOnChip = UITapGestureRecognizer(target: self, action: #selector(handleTapB(_:)))
        betViewB.addGestureRecognizer(tapBOnChip)
        betViewB.isUserInteractionEnabled = true
    }

    @objc private func handlePlaceBetRequested() {
        onPlaceBetRequested?()
    }

    override func addBetWithAnimation(_ amount: Int) {
        onPlaceBetRequested?()
    }

    @objc private func handleTapB(_ gesture: UITapGestureRecognizer) {
        onPlaceBetRequested?()
    }

    /// Add a bet to the given slot (called by VC after slot is assigned). Includes scale animation for user's own bets.
    func addBet(_ amount: Int, to slot: PlayerSlot) {
        let chip: UIView
        switch slot {
        case .A:
            chip = chipA
            chipA.addToBet(amount)
            chipA.alpha = 1
            chipA.isHidden = false
            bringSubviewToFront(chipA)
        case .B:
            chip = betViewB
            betViewB.addToBet(amount)
            betViewB.alpha = 1
            betViewB.isHidden = false
            bringSubviewToFront(betViewB)
        }
        
        // Scale animation for user's own bet
        chip.layoutIfNeeded()
        let originalTransform = chip.transform
        UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut]) {
            chip.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                chip.transform = originalTransform
            }
        }
        
        HapticsHelper.lightHaptic()
    }

    /// Scale and shimmer the chip for the given slot (e.g. when another player's bet updates).
    func animateBetUpdate(for slot: PlayerSlot) {
        let chip: MPSmallBetChip
        switch slot {
        case .A: chip = chipA
        case .B: chip = betViewB
        }
        chip.layoutIfNeeded()
        
        // Scale animation (same as user's own bets)
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

    // MARK: - Bounce Animation (kept for future use)
    
    /// Bounce animation for chip (position-based). Currently unused but kept for potential future use.
    private func animateChipBounce(_ chip: UIView) {
        let initialPosition = chip.center
        let bounceAnimation = CAKeyframeAnimation(keyPath: "position")
        bounceAnimation.values = [
            NSValue(cgPoint: initialPosition),
            NSValue(cgPoint: CGPoint(x: initialPosition.x, y: initialPosition.y - 12)),
            NSValue(cgPoint: initialPosition),
            NSValue(cgPoint: CGPoint(x: initialPosition.x, y: initialPosition.y - 6)),
            NSValue(cgPoint: initialPosition)
        ]
        bounceAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn)
        ]
        bounceAnimation.duration = 0.4
        bounceAnimation.repeatCount = 1
        chip.layer.add(bounceAnimation, forKey: "bounceAnimation")
    }
}
