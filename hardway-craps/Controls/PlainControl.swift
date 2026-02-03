//
//  PlainControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

/// Direction for winnings chip animation
enum WinningsAnimationDirection {
    case leading  // Animate 30 points from the leading edge of betView
    case trailing // Animate 30 points from the trailing edge of betView
}

class PlainControl: UIControl, BetDropTarget {

    let background: UIColor = HardwayColors.surfaceGray
    let labelColor: UIColor = HardwayColors.label

    /// Store the original border properties to restore after drag interaction
    private var originalBorderWidth: CGFloat = 0
    private var originalBorderColor: CGColor?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 18, weight: .regular)
        return label
    }()

    private(set) var betView: SmallBetChip!
    private var originalTransform: CGAffineTransform = .identity

    var title: String? {
        didSet {
            titleLabel.text = title
        }
    }

    var betAmount: Int {
        get { betView.amount }
        set { betView.amount = newValue }
    }

    var getSelectedChipValue: (() -> Int)?
    var getBalance: (() -> Int)?
    var onBetPlaced: ((Int) -> Void)?
    var onBetRemoved: ((Int) -> Void)?
    var addedBetCompletionHandler: (() -> Void)?
    /// Closure that returns whether the bet can be removed. Defaults to true if not set.
    var canRemoveBet: (() -> Bool)?

    private var previousBetAmount: Int = 0

    /// Determines if this bet stays active after a roll (perpetual) or is cleared (one-time)
    var isPerpetualBet: Bool = true

    /// Direction for winnings chip animation. Default is .trailing (30 points from the trailing edge)
    var winningsAnimationDirection: WinningsAnimationDirection = .trailing

    /// Offset for winnings chip animation relative to bet position
    /// Calculates position based on betView's leading or trailing edge
    var winningsAnimationOffset: CGPoint {
        let betViewWidth = betView.bounds.width
        let offsetDistance: CGFloat = 30

        switch winningsAnimationDirection {
        case .leading:
            // Position 30 points to the left of betView's leading edge
            return CGPoint(x: -(betViewWidth / 2 + offsetDistance), y: 0)
        case .trailing:
            // Position 30 points to the right of betView's trailing edge
            return CGPoint(x: betViewWidth / 2 + offsetDistance, y: 0)
        }
    }
    
    /// Shimmer the title label to draw attention
    func shimmerTitleLabel() {
        titleLabel.addShimmerEffect()
    }
    
    func stopTitleShimmer() {
        titleLabel.removeShimmerEffect()
    }
    
    /// Set the disabled/tinted appearance when bet cannot be removed
    func setBetRemovalDisabled(_ disabled: Bool) {
        if disabled {
            // Tint the control to show it's disabled
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.5)
                self.titleLabel.textColor = HardwayColors.label.withAlphaComponent(0.5)
            }
        } else {
            // Restore normal appearance
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = self.background
                self.titleLabel.textColor = self.labelColor
            }
        }
    }

    init(title: String? = nil) {
        self.title = title
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        BetDragManager.shared.unregisterDropTarget(self)
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = background
        layer.cornerRadius = 18
        clipsToBounds = false

        titleLabel.text = title
        titleLabel.textColor = labelColor

        addSubview(titleLabel)

        betView = SmallBetChip()
        addSubview(betView)

        // Ensure betView stays on top
        bringSubviewToFront(betView)

        let heightConstraint = heightAnchor.constraint(equalToConstant: 50)
        heightConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightConstraint
        ])

        // Apply bet view constraints (can be overridden by subclasses)
        configureBetViewConstraints()

        setupGestures()
        BetDragManager.shared.registerDropTarget(self)

        // Add pan gesture to betView to drag bet away
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleBetViewPan(_:)))
        betView.addGestureRecognizer(panGesture)
        betView.isUserInteractionEnabled = true
        
        // Add tap gesture to betView to pass through to control's tap handler
        // This allows tapping the betView to increment the bet
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        betView.addGestureRecognizer(tapGesture)
        // Allow both tap and pan - tap will fire on quick taps, pan on drags
        tapGesture.require(toFail: panGesture)

        // Add tap to add bet
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    private func setupGestures() {
        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchDragExit, .touchCancel])
    }

    // MARK: - Overridable Layout

    /// Override this method in subclasses to customize betView positioning
    /// Default implementation places betView on the trailing edge, vertically centered
    func configureBetViewConstraints() {
        NSLayoutConstraint.activate([
            betView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            betView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func handleTap() {
        // Get selected chip value from closure
        guard let getValue = getSelectedChipValue else {
            return
        }
        
        let value = getValue()
        
        // Check balance before allowing bet
        if let getBalance = getBalance {
            let balance = getBalance()
            if value > balance {
                // Insufficient balance - provide haptic feedback
                HapticsHelper.lightHaptic()
                return
            }
        }
        
        addBetWithAnimation(value)
    }

    @objc private func handleBetViewPan(_ gesture: UIPanGestureRecognizer) {
        guard betAmount > 0 else { return }
        
        // Check if bet can be removed - if not, prevent drag from starting
        let canRemove = canRemoveBet?() ?? true
        if !canRemove {
            // Provide haptic feedback to indicate bet cannot be removed
            HapticsHelper.failureHaptic()
            return
        }
        
        // Find the root view (view controller's view) by traversing up the hierarchy
        // This ensures the dragged chip isn't clipped by scroll views or other containers
        var rootView: UIView? = self
        while let parent = rootView?.superview {
            rootView = parent
        }
        
        guard let containerView = rootView else { return }

        let location = gesture.location(in: containerView)

        switch gesture.state {
        case .began:
            // Hide the betView so it doesn't appear in two places
            betView.alpha = 0
            BetDragManager.shared.startDragging(value: betAmount, from: location, in: containerView, source: self)
        case .changed:
            BetDragManager.shared.updateDrag(to: location)
        case .ended:
            BetDragManager.shared.endDrag(at: location, in: containerView)
            // Note: betView.alpha restoration is handled in BetDragManager.endDrag completion blocks
            // We use a delayed check as a fallback in case the drag was cancelled or failed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                // Only restore if bet still exists and alpha is still 0 (wasn't restored by endDrag)
                if self.betAmount > 0 && self.betView.alpha == 0 {
                    self.betView.alpha = 1
                }
            }
        case .cancelled, .failed:
            BetDragManager.shared.cancelDrag()
            // Show betView again since drag was cancelled
            betView.alpha = 1
        default:
            break
        }
    }

    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        }
    }

    @objc private func touchUp() {
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.transform = .identity
        }
        
        HapticsHelper.lightHaptic()
    }

    // MARK: - BetDropTarget

    func frameInView(_ view: UIView) -> CGRect {
        guard let superview = superview else { return .zero }
        return superview.convert(frame, to: view)
    }

    func getBetViewPosition(in view: UIView) -> CGPoint {
        guard let superview = betView.superview else { return .zero }
        return superview.convert(betView.center, to: view)
    }
    
//    func center(in view: UIView) -> CGPoint {
//        guard let superview = betView.superview else { return .zero }
//        return superview.convert(betView.center, to: view)
//    }

    func addBet(_ amount: Int) {
        betView.addToBet(amount)
        
        // Ensure betView is visible when adding a bet
        betView.alpha = 1
        betView.isHidden = false

        // Ensure betView stays on top after adding bet
        bringSubviewToFront(betView)
        
        // Notify that bet was added (for completion handlers like stopping shimmer)
        addedBetCompletionHandler?()
    }

    func addBetWithAnimation(_ amount: Int) {
        betView.addToBet(amount)

        // Ensure betView is visible when adding a bet
        betView.alpha = 1
        betView.isHidden = false

        // Notify that bet was placed
        onBetPlaced?(amount)

        // Ensure betView stays on top
        bringSubviewToFront(betView)

        // Subtle bounce animation
        let originalTransform = betView.transform

        UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut]) {
            self.betView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                self.betView.transform = originalTransform
            }
            
            // Notify that bet was added (for completion handlers like stopping shimmer)
            // Call after animation completes for better UX
            self.addedBetCompletionHandler?()
        }

        HapticsHelper.lightHaptic()
    }

    private func animateBetViewBounce() {
        // Ensure betView stays on top
        bringSubviewToFront(betView)

        let originalTransform = betView.transform

        UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut]) {
            self.betView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                self.betView.transform = originalTransform
            }
        }
    }

    func removeBet(_ amount: Int) {
        let oldAmount = betView.amount
        betView.addToBet(-amount)
        // Detect bet removal and call callback
        if oldAmount > betView.amount {
            let removedAmount = oldAmount - betView.amount
            onBetRemoved?(removedAmount)
        }
    }

    /// Remove bet without triggering onBetRemoved callback
    /// Used when moving bets between controls (balance shouldn't change)
    func removeBetSilently(_ amount: Int) {
        betView.addToBet(-amount)
    }

    /// Set the bet amount directly without triggering onBetPlaced callback
    /// Used for rebetting functionality where balance is managed externally
    func setDirectBet(_ amount: Int) {
        betView.amount = amount

        // Ensure betView is visible
        betView.alpha = 1
        betView.isHidden = false

        // Ensure betView stays on top
        bringSubviewToFront(betView)

        // Notify that bet was added (for completion handlers like stopping shimmer)
        addedBetCompletionHandler?()
    }

    func highlightAsDropTarget() {
        // Save original border properties before changing them
        originalBorderWidth = layer.borderWidth
        originalBorderColor = layer.borderColor

        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
//            self.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
//            self.backgroundColor = HardwayColors.surfaceDropZone
            self.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.4).cgColor
//            self.layer.borderColor = HardwayColors.surfaceDropZone.cgColor
            self.layer.borderWidth = 2
        }

        HapticsHelper.superLightHaptic()
    }

    func unhighlightAsDropTarget() {
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.transform = .identity
//            self.backgroundColor = self.background
            // Restore original border properties instead of removing border completely
            self.layer.borderWidth = self.originalBorderWidth
            self.layer.borderColor = self.originalBorderColor
        }
    }
}
