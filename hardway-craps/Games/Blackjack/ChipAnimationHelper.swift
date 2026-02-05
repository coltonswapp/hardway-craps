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
        guard let containerView = containerView else {
            return
        }

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
                onCompletion: { 
                    onBalanceUpdate(winAmount) 
                }
            )
        ]

        animateChip(amount: winAmount, steps: steps)
    }

    /// Animate bet collection: control → balance
    func animateBetCollection(
        for control: PlainControl,
        onBalanceUpdate: @escaping (Int) -> Void
    ) {
        // Use default offset (0, 0) for backward compatibility
        animateBetCollectionWithOffset(
            for: control,
            offset: CGPoint(x: 0, y: 0),
            onBalanceUpdate: onBalanceUpdate
        )
    }
    
    /// Animate bet collection with offset: control + offset → balance
    func animateBetCollectionWithOffset(
        for control: PlainControl,
        offset: CGPoint,
        onBalanceUpdate: @escaping (Int) -> Void
    ) {
        let betAmount = control.betAmount
        guard betAmount > 0 else { return }

        // Hide betView immediately to prevent visual overlap with animation chip
        control.betView.alpha = 0

        // Get bet position and apply offset
        guard let containerView = containerView else { return }
        let betPosition = control.getBetViewPosition(in: containerView)
        let startPosition = CGPoint(x: betPosition.x + offset.x, y: betPosition.y + offset.y)
        guard let balanceCenter = getBalanceCenter(in: containerView) else { return }

        let steps = [
            AnimationStep.standard(
                path: .custom(from: startPosition, to: balanceCenter),
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
    
    /// Animate odds bet collection: odds position + offset → balance
    /// Matches the exact pattern of animateBetCollectionWithOffset for consistency
    func animateOddsBetCollection(
        for control: PlainControl,
        oddsBetAmount: Int,
        offset: CGPoint,
        onBalanceUpdate: @escaping (Int) -> Void
    ) {
        guard oddsBetAmount > 0 else { return }
        guard let containerView = containerView else { return }
        guard let oddsStack = control.oddsBetStack else { return }
        guard let balanceCenter = getBalanceCenter(in: containerView) else { return }

        // Mark that bet collection is starting - prevents fade animation in setter
        oddsStack.startBetCollection()

        // Get odds position and apply offset
        let oddsPosition = oddsStack.getOddsPosition(in: containerView)
        let startPosition = CGPoint(x: oddsPosition.x + offset.x, y: oddsPosition.y + offset.y)

        // Hide odds chip immediately to prevent visual overlap (matches bet collection pattern)
        oddsStack.oddsChip.alpha = 0

        let steps = [
            AnimationStep.standard(
                path: .custom(from: startPosition, to: balanceCenter),
                duration: 0.5,
                onCompletion: {
                    onBalanceUpdate(oddsBetAmount)
                    // Clear odds amount - setter won't fade because isCollectingBet is true
                    control.oddsAmount = 0
                    // End bet collection flag
                    oddsStack.endBetCollection()
                    // Restore alpha for future bets
                    oddsStack.oddsChip.alpha = 1
                }
            )
        ]

        animateChip(amount: oddsBetAmount, steps: steps)
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
    
    /// Animate both bet and odds chips away separately: control with OddsBetStack → house (disappear)
    /// Both chips remain visible until animations start, then animate away separately
    func animateChipsAwayFromOddsStack(
        from control: PlainControl,
        onComplete: (() -> Void)? = nil
    ) {
        guard let containerView = containerView else { return }
        guard let oddsStack = control.oddsBetStack else {
            // Fall back to regular animateChipsAway if no odds stack
            animateChipsAway(from: control, onComplete: onComplete)
            return
        }
        
        let betAmount = control.betAmount
        let oddsAmount = control.oddsAmount
        let totalChips = (betAmount > 0 ? 1 : 0) + (oddsAmount > 0 ? 1 : 0)
        
        // Use a class to track completion state (can't use var in closure)
        class CompletionTracker {
            var count = 0
            let total: Int
            let onComplete: (() -> Void)?
            
            init(total: Int, onComplete: (() -> Void)?) {
                self.total = total
                self.onComplete = onComplete
            }
            
            func increment() {
                count += 1
                if count >= total {
                    onComplete?()
                }
            }
        }
        
        let tracker = CompletionTracker(total: totalChips, onComplete: onComplete)
        
        // Animate bet chip if present
        if betAmount > 0 {
            let betPosition = control.getBetViewPosition(in: containerView)
            
            // Create bet chip animation
            let betChipView = createChipView(amount: betAmount)
            containerView.addSubview(betChipView)
            betChipView.center = betPosition
            
            // Random delay for cascading effect
            let randomDelay1 = Double.random(in: 0...0.15)
            
            // Animate bet chip away
            UIView.animate(withDuration: 0.5, delay: randomDelay1, options: .curveEaseIn) {
                betChipView.center = CGPoint(x: containerView.bounds.width / 2, y: 0)
                betChipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            } completion: { _ in
                UIView.animate(withDuration: 0.2) {
                    betChipView.alpha = 0
                } completion: { _ in
                    betChipView.removeFromSuperview()
                    tracker.increment()
                }
            }
            
            // Hide and clear bet AFTER animation starts
            DispatchQueue.main.asyncAfter(deadline: .now() + randomDelay1) {
                control.betView.alpha = 0
                control.betAmount = 0
            }
        }
        
        // Animate odds chip if present
        if oddsAmount > 0 {
            let oddsPosition = oddsStack.getOddsPosition(in: containerView)
            
            // Create odds chip animation
            let oddsChipView = createChipView(amount: oddsAmount)
            containerView.addSubview(oddsChipView)
            oddsChipView.center = oddsPosition
            
            // Random delay for cascading effect (slightly different from bet chip)
            let randomDelay2 = Double.random(in: 0...0.15)
            
            // Animate odds chip away
            UIView.animate(withDuration: 0.5, delay: randomDelay2, options: .curveEaseIn) {
                oddsChipView.center = CGPoint(x: containerView.bounds.width / 2, y: 0)
                oddsChipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            } completion: { _ in
                UIView.animate(withDuration: 0.2) {
                    oddsChipView.alpha = 0
                } completion: { _ in
                    oddsChipView.removeFromSuperview()
                    // Restore alpha for future bets
                    oddsStack.oddsChip.alpha = 1
                    tracker.increment()
                }
            }
            
            // Hide and clear odds AFTER animation starts (use removeOddsSilently to avoid layout changes)
            DispatchQueue.main.asyncAfter(deadline: .now() + randomDelay2) {
                oddsStack.oddsChip.alpha = 0
                oddsStack.removeOddsSilently(oddsAmount)
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
    
    /// Animate odds bet winnings with custom offset: house → offset → balance (with original odds bet)
    /// Matches the pattern of animateBonusBetWinningsWithOffset but for odds bets
    func animateOddsBetWinningsWithOffset(
        for control: PlainControl,
        oddsBetAmount: Int,
        winAmount: Int,
        offset: CGPoint,
        onBalanceUpdate: @escaping (Int) -> Void
    ) {
        guard let containerView = containerView else { return }
        guard let oddsStack = control.oddsBetStack else { return }

        let oddsPosition = oddsStack.getOddsPosition(in: containerView)
        let winningsPosition = CGPoint(x: oddsPosition.x + offset.x, y: oddsPosition.y + offset.y)

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

                // Create odds bet chip
                let oddsChip = self.createChipView(amount: oddsBetAmount)
                containerView.addSubview(oddsChip)
                oddsChip.center = oddsPosition

                // Hide original odds chip
                oddsStack.oddsChip.alpha = 0

                // Get balance position
                guard let balanceCenter = self.getBalanceCenter(in: containerView) else { return }

                // Animate winnings chip to balance
                let animator2a = self.createAnimator(duration: 0.5) {
                    winningsChip.center = balanceCenter
                    winningsChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                }

                animator2a.addCompletion { _ in
                    // Don't add to balance here - winAmount already includes oddsBetAmount
                    // We'll add the total in the final completion
                    winningsChip.removeFromSuperview()
                }

                // Animate odds bet chip to balance (slightly offset)
                let animator2b = self.createAnimator(duration: 0.5) {
                    oddsChip.center = CGPoint(x: balanceCenter.x - 10, y: balanceCenter.y)
                    oddsChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                }

                animator2b.addCompletion { _ in
                    // Don't add oddsBetAmount here - it's already included in winAmount
                    // This will be called AFTER both animations complete
                    oddsChip.removeFromSuperview()
                    
                    // Clear odds amount while flag is still set (setter will skip fade since chip is already hidden)
                    // This will trigger bet chip slide-back animation
                    control.oddsAmount = 0
                    
                    // DO NOT restore oddsChip.alpha here - it stays at 0 until new bet is placed
                    // The oddsAmount setter in OddsBetStack handles showing the chip when new odds are added
                    
                    // Call onBalanceUpdate - the callback will end the payout animation flag
                    onBalanceUpdate(winAmount)
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

    func getBalanceCenter(in containerView: UIView) -> CGPoint? {
        guard let balanceView = balanceView else { return nil }
        let balancePosition = balanceView.convert(balanceView.bounds, to: containerView)
        return CGPoint(x: balancePosition.maxX - 30, y: balancePosition.midY)
    }
}
