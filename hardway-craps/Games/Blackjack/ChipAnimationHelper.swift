//
//  ChipAnimationHelper.swift
//  hardway-craps
//
//  Created by Claude Code on 1/26/26.
//

import UIKit

/// Helper class for animating chip movements in Blackjack
final class ChipAnimationHelper {

    // MARK: - Types

    enum AnimationPath {
        case houseToControl(control: PlainControl, offset: CGPoint = .zero)
        case controlToBalance(control: PlainControl)
        case controlToHouse(control: PlainControl)
        case custom(from: CGPoint, to: CGPoint)
    }

    struct AnimationStep {
        let path: AnimationPath
        let duration: TimeInterval
        let delay: TimeInterval
        let scaleTransform: CGAffineTransform
        let controlPoint1: CGPoint
        let controlPoint2: CGPoint
        let onCompletion: (() -> Void)?

        static func standard(
            path: AnimationPath,
            duration: TimeInterval = 0.5,
            delay: TimeInterval = 0,
            scaleTransform: CGAffineTransform = .identity,
            onCompletion: (() -> Void)? = nil
        ) -> AnimationStep {
            return AnimationStep(
                path: path,
                duration: duration,
                delay: delay,
                scaleTransform: scaleTransform,
                controlPoint1: CGPoint(x: 0.85, y: 0),
                controlPoint2: CGPoint(x: 0.15, y: 1),
                onCompletion: onCompletion
            )
        }
    }

    // MARK: - Properties

    private weak var containerView: UIView?
    private weak var balanceView: UIView?

    // MARK: - Initialization

    init(containerView: UIView, balanceView: UIView) {
        self.containerView = containerView
        self.balanceView = balanceView
    }

    // MARK: - Public Methods

    /// Animate a single chip through multiple steps
    func animateChip(
        amount: Int,
        steps: [AnimationStep]
    ) {
        guard let containerView = containerView else { return }

        let chipView = createChipView(amount: amount)
        containerView.addSubview(chipView)

        executeSteps(chipView: chipView, steps: steps, currentIndex: 0)
    }

    /// Animate winnings: house → control → balance
    func animateWinnings(
        for control: PlainControl,
        winAmount: Int,
        onBalanceUpdate: @escaping (Int) -> Void
    ) {
        // Use control-specific offset if available, otherwise default to 30 points right
        let offset = control.winningsAnimationOffset
        animateWinningsWithOffset(
            for: control,
            winAmount: winAmount,
            offset: offset,
            onBalanceUpdate: onBalanceUpdate
        )
    }
    
    /// Animate winnings with custom offset: house → control → balance
    func animateWinningsWithOffset(
        for control: PlainControl,
        winAmount: Int,
        offset: CGPoint,
        onBalanceUpdate: @escaping (Int) -> Void
    ) {
        let steps = [
            AnimationStep.standard(
                path: .houseToControl(control: control, offset: offset),
                duration: 0.75,
                scaleTransform: CGAffineTransform(scaleX: 1.5, y: 1.5)
            ),
            AnimationStep.standard(
                path: .controlToBalance(control: control),
                duration: 0.5,
                delay: 0.2,
                scaleTransform: CGAffineTransform(scaleX: 0.2, y: 0.2),
                onCompletion: { onBalanceUpdate(winAmount) }
            )
        ]

        animateChip(amount: winAmount, steps: steps)
    }

    /// Animate bet collection: control → balance
    func animateBetCollection(
        for control: PlainControl,
        onBalanceUpdate: @escaping (Int) -> Void
    ) {
        let betAmount = control.betAmount
        guard betAmount > 0 else { return }

        // Hide betView immediately to prevent visual overlap with animation chip
        control.betView.alpha = 0

        let steps = [
            AnimationStep.standard(
                path: .controlToBalance(control: control),
                duration: 0.5,
                onCompletion: {
                    onBalanceUpdate(betAmount)
                    control.betAmount = 0
                    // Restore alpha for future bets
                    control.betView.alpha = 1
                }
            )
        ]

        animateChip(amount: betAmount, steps: steps)
    }

    /// Animate chips away: control → house (disappear)
    func animateChipsAway(
        from control: PlainControl,
        onComplete: (() -> Void)? = nil
    ) {
        guard let containerView = containerView else { return }
        let betAmount = control.betAmount
        guard betAmount > 0 else { return }

        let betPosition = control.getBetViewPosition(in: containerView)

        // Hide betView and create chip
        control.betView.alpha = 0

        let chipView = createChipView(amount: betAmount)
        containerView.addSubview(chipView)
        chipView.center = betPosition

        // Clear bet after tiny delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            control.betAmount = 0
        }

        // Animate away with random delay
        let randomDelay = Double.random(in: 0...0.15)

        UIView.animate(withDuration: 0.5, delay: randomDelay, options: .curveEaseIn) {
            chipView.center = CGPoint(x: containerView.bounds.width / 2, y: 0)
            chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        } completion: { _ in
            UIView.animate(withDuration: 0.2) {
                chipView.alpha = 0
            } completion: { _ in
                chipView.removeFromSuperview()
                onComplete?()
            }
        }
    }

    /// Animate bonus bet winnings: house → offset → balance (with original bet)
    func animateBonusBetWinnings(
        for control: PlainControl,
        betAmount: Int,
        winAmount: Int,
        onBalanceUpdate: @escaping (Int) -> Void
    ) {
        animateBonusBetWinningsWithOffset(
            for: control,
            betAmount: betAmount,
            winAmount: winAmount,
            offset: CGPoint(x: -35, y: 0),
            onBalanceUpdate: onBalanceUpdate
        )
    }
    
    /// Animate bonus bet winnings with custom offset: house → offset → balance (with original bet)
    func animateBonusBetWinningsWithOffset(
        for control: PlainControl,
        betAmount: Int,
        winAmount: Int,
        offset: CGPoint,
        onBalanceUpdate: @escaping (Int) -> Void
    ) {
        guard let containerView = containerView else { return }

        let betPosition = control.getBetViewPosition(in: containerView)
        let winningsPosition = CGPoint(x: betPosition.x + offset.x, y: betPosition.y + offset.y)

        // Create winnings chip
        let winningsChip = createChipView(amount: winAmount)
        containerView.addSubview(winningsChip)
        winningsChip.center = CGPoint(x: containerView.bounds.midX, y: 0)
        winningsChip.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)

        // Step 1: Animate winnings to offset position with scale animation
        let animator1 = createAnimator(duration: 0.6) {
            winningsChip.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)  // Scale up like other winnings
            winningsChip.center = winningsPosition
        }

        animator1.addCompletion { [weak self] _ in
            guard let self = self, let containerView = self.containerView else { return }

            // Brief pause, then animate both chips to balance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self else { return }

                // Create bet chip
                let betChip = self.createChipView(amount: betAmount)
                containerView.addSubview(betChip)
                betChip.center = betPosition

                control.betView.alpha = 0

                // Get balance position
                guard let balanceCenter = self.getBalanceCenter(in: containerView) else { return }

                // Animate winnings chip to balance
                let animator2a = self.createAnimator(duration: 0.5) {
                    winningsChip.center = balanceCenter
                    winningsChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                }

                animator2a.addCompletion { _ in
                    onBalanceUpdate(winAmount)
                    winningsChip.removeFromSuperview()
                }

                // Animate bet chip to balance (slightly offset)
                let animator2b = self.createAnimator(duration: 0.5) {
                    betChip.center = CGPoint(x: balanceCenter.x - 10, y: balanceCenter.y)
                    betChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                }

                animator2b.addCompletion { _ in
                    onBalanceUpdate(betAmount)
                    betChip.removeFromSuperview()
                    control.betAmount = 0
                    control.betView.alpha = 1
                }

                animator2a.startAnimation()
                animator2b.startAnimation(afterDelay: 0.1)
            }
        }

        animator1.startAnimation()
    }

    // MARK: - Private Helpers

    private func createChipView(amount: Int) -> SmallBetChip {
        let chipView = SmallBetChip()
        chipView.amount = amount
        chipView.translatesAutoresizingMaskIntoConstraints = true
        chipView.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        chipView.isHidden = false
        return chipView
    }

    private func createAnimator(
        duration: TimeInterval,
        animations: @escaping () -> Void
    ) -> UIViewPropertyAnimator {
        return UIViewPropertyAnimator(
            duration: duration,
            controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1),
            animations: animations
        )
    }

    private func executeSteps(
        chipView: SmallBetChip,
        steps: [AnimationStep],
        currentIndex: Int
    ) {
        guard currentIndex < steps.count else {
            chipView.removeFromSuperview()
            return
        }

        let step = steps[currentIndex]

        guard let destination = getDestination(for: step.path) else {
            chipView.removeFromSuperview()
            return
        }

        // Set initial position for first step
        if currentIndex == 0 {
            if let origin = getOrigin(for: step.path) {
                chipView.center = origin
            }
        }

        let animator = UIViewPropertyAnimator(
            duration: step.duration,
            controlPoint1: step.controlPoint1,
            controlPoint2: step.controlPoint2
        ) {
            chipView.center = destination
            chipView.transform = step.scaleTransform
        }

        animator.addCompletion { [weak self] _ in
            step.onCompletion?()

            // Execute next step
            self?.executeSteps(chipView: chipView, steps: steps, currentIndex: currentIndex + 1)
        }

        animator.startAnimation(afterDelay: step.delay)
    }

    private func getOrigin(for path: AnimationPath) -> CGPoint? {
        guard let containerView = containerView else { return nil }

        switch path {
        case .houseToControl:
            return CGPoint(x: containerView.bounds.midX, y: 0)
        case .controlToBalance(let control):
            return control.getBetViewPosition(in: containerView)
        case .controlToHouse(let control):
            return control.getBetViewPosition(in: containerView)
        case .custom(let from, _):
            return from
        }
    }

    private func getDestination(for path: AnimationPath) -> CGPoint? {
        guard let containerView = containerView else { return nil }

        switch path {
        case .houseToControl(let control, let offset):
            var position = control.getBetViewPosition(in: containerView)
            position.x += offset.x
            position.y += offset.y
            return position
        case .controlToBalance:
            return getBalanceCenter(in: containerView)
        case .controlToHouse:
            return CGPoint(x: containerView.bounds.midX, y: 0)
        case .custom(_, let to):
            return to
        }
    }

    private func getBalanceCenter(in containerView: UIView) -> CGPoint? {
        guard let balanceView = balanceView else { return nil }
        let balancePosition = balanceView.convert(balanceView.bounds, to: containerView)
        return CGPoint(x: balancePosition.maxX - 30, y: balancePosition.midY)
    }
}
