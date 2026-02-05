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
    
    // Optional odds support via composition
    private(set) var oddsBetStack: OddsBetStack?
    
    var supportsOdds: Bool = false {
        didSet {
            if supportsOdds && oddsBetStack == nil {
                setupOddsBetStack()
            }
        }
    }

    var title: String? {
        didSet {
            titleLabel.text = title
        }
    }
    
    /// Title alignment configuration
    enum TitleAlignment {
        case centered
        case left
    }
    
    /// Title alignment for the control. Default is .centered
    var titleAlignment: TitleAlignment = .centered {
        didSet {
            updateTitleConstraints()
        }
    }
    
    private var titleCenterXConstraint: NSLayoutConstraint?
    private var titleLeadingConstraint: NSLayoutConstraint?

    var betAmount: Int {
        get {
            if let stack = oddsBetStack {
                return stack.betAmount
            }
            return betView.amount
        }
        set {
            if let stack = oddsBetStack {
                stack.betAmount = newValue
            } else {
                betView.amount = newValue
            }
            updateTitleAlignment()
        }
    }
    
    var oddsAmount: Int {
        get { oddsBetStack?.oddsAmount ?? 0 }
        set { 
            oddsBetStack?.oddsAmount = newValue
            updateTitleAlignment()
        }
    }
    
    var onOddsPlaced: ((Int) -> Void)? {
        get { oddsBetStack?.onOddsPlaced }
        set {
            // Wrap the callback to ensure oddsBetStack is brought to front when odds are added
            oddsBetStack?.onOddsPlaced = { [weak self] amount in
                guard let self = self, let stack = self.oddsBetStack else { return }
                // Ensure stack is on top so odds chip can receive touches
                self.bringSubviewToFront(stack)
                self.updateTitleAlignment()
                newValue?(amount)
            }
        }
    }
    
    var onOddsRemoved: ((Int) -> Void)? {
        get { oddsBetStack?.onOddsRemoved }
        set { 
            oddsBetStack?.onOddsRemoved = { [weak self] amount in
                self?.updateTitleAlignment()
                newValue?(amount)
            }
        }
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
    /// Simple offset from betView (SmallBetChip) center
    var winningsAnimationOffset: CGPoint {
        switch winningsAnimationDirection {
        case .leading:
            // Position 20 points to the left of betView center
            return CGPoint(x: -30, y: 0)
        case .trailing:
            // Position 20 points to the right of betView center
            return CGPoint(x: 30, y: 0)
        }
    }
    
    /// Offset for original bet winnings animation (separate from odds bet)
    /// Adjusts based on whether odds exist and bet chip has been shifted
    var originalBetWinningsOffset: CGPoint {
        // Base offset: 20 points to the left of bet chip center
        let baseOffset: CGFloat = -30
        
        // If odds exist in horizontal layout, bet chip is shifted left by 22 points
        // (from -8 to -30 trailing constraint)
        // Adjust offset to account for the shifted position
        if let stack = oddsBetStack,
           stack.oddsAmount > 0,
           stack.layout == .horizontal {
            // Bet chip is shifted left, so winnings should appear further left
            // to maintain visual separation from both bet and odds chips
            return CGPoint(x: baseOffset - 20, y: 0) // -30 total: further left when odds exist
        }
        
        // No odds or vertical layout: use base offset
        return CGPoint(x: baseOffset, y: 0)
    }
    
    /// Offset for odds bet winnings animation (can be customized separately)
    /// Positioned slightly above the odds chip on Y axis, same X position (no X offset)
    var oddsBetWinningsOffset: CGPoint {
        // No X offset - keep same X as odds chip, but position above with negative Y
        return CGPoint(x: 0, y: -40) // -40 moves up 40 points
    }
    
    /// Offset for original bet collection animation
    var originalBetCollectionOffset: CGPoint {
        // Default: no offset (collects from bet position directly)
        return CGPoint(x: -40, y: 0)
    }
    
    /// Offset for odds bet collection animation
    var oddsBetCollectionOffset: CGPoint {
        // Default: no offset (collects from odds position directly)
        return CGPoint(x: 0, y: 60)
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
        
        // Create constraints for title alignment
        titleCenterXConstraint = titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightConstraint
        ])
        
        // Set initial alignment
        updateTitleConstraints()

        // Apply bet view constraints (can be overridden by subclasses)
        configureBetViewConstraints()

        setupGestures()
        BetDragManager.shared.registerDropTarget(self)

        // Add pan gesture to betView to drag bet away (only if not using oddsBetStack)
        if !supportsOdds {
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleBetViewPan(_:)))
            betView.addGestureRecognizer(panGesture)
            betView.isUserInteractionEnabled = true
            
            // Add tap gesture to betView to pass through to control's tap handler
            // This allows tapping the betView to increment the bet
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            betView.addGestureRecognizer(tapGesture)
            // Allow both tap and pan - tap will fire on quick taps, pan on drags
            tapGesture.require(toFail: panGesture)
        }

        // Add tap to add bet (only if not using oddsBetStack - oddsBetStack handles its own taps)
        if !supportsOdds {
            addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        }
    }
    
    private func updateTitleConstraints() {
        // Only update if constraints have been created (after setupView)
        guard titleCenterXConstraint != nil && titleLeadingConstraint != nil else {
            return
        }
        
        // Animate the constraint changes with snappier timing
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 1.0, options: [.curveEaseInOut, .allowUserInteraction]) {
            // Deactivate existing constraints
            self.titleCenterXConstraint?.isActive = false
            self.titleLeadingConstraint?.isActive = false
            
            // Activate appropriate constraint based on alignment
            switch self.titleAlignment {
            case .centered:
                self.titleCenterXConstraint?.isActive = true
                self.titleLabel.textAlignment = .center
            case .left:
                self.titleLeadingConstraint?.isActive = true
                self.titleLabel.textAlignment = .left
            }
            
            // Force layout update within animation block
            self.layoutIfNeeded()
        }
    }
    
    /// Update title alignment based on whether any bets exist (including odds)
    /// If any bet is present, align left; otherwise, align centered
    private func updateTitleAlignment() {
        // Only shift title alignment when using OddsBetStack (for pass line/don't pass with odds)
        // Other controls like field should keep centered alignment
        guard oddsBetStack != nil else {
            // Not using OddsBetStack - keep title centered
            titleAlignment = .centered
            return
        }
        
        // Using OddsBetStack - shift title left when there's a bet
        let hasAnyBet = betAmount > 0 || oddsAmount > 0
        titleAlignment = hasAnyBet ? .left : .centered
    }
    
    private func setupOddsBetStack() {
        // Remove existing betView gestures
        betView.gestureRecognizers?.forEach { betView.removeGestureRecognizer($0) }
        
        // Create OddsBetStack with horizontal layout
        oddsBetStack = OddsBetStack(layout: .horizontal)
        oddsBetStack?.parentControl = self  // Set parent for BetDragManager integration
        oddsBetStack?.isUserInteractionEnabled = true  // Ensure it can receive touches
        addSubview(oddsBetStack!)
        
        // Wire up callbacks
        oddsBetStack?.getSelectedChipValue = { [weak self] in
            return self?.getSelectedChipValue?() ?? 1
        }
        oddsBetStack?.getBalance = { [weak self] in
            return self?.getBalance?() ?? 200
        }
        oddsBetStack?.canRemoveBet = { [weak self] in
            return self?.canRemoveBet?() ?? true
        }
        oddsBetStack?.onBetPlaced = { [weak self] amount in
            guard let self = self else { return }
            self.bringSubviewToFront(self.oddsBetStack!)
            self.updateTitleAlignment()
            self.onBetPlaced?(amount)
        }
        oddsBetStack?.onBetRemoved = { [weak self] amount in
            self?.updateTitleAlignment()
            self?.onBetRemoved?(amount)
        }
        
        // Position OddsBetStack where betView was
        oddsBetStack?.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            oddsBetStack!.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            oddsBetStack!.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        // Hide original betView (OddsBetStack has its own betChip)
        betView.isHidden = true
        betView.alpha = 0
        betView.isUserInteractionEnabled = false  // Disable interaction on hidden betView
        
        // Bring OddsBetStack to front so it can receive touches
        bringSubviewToFront(oddsBetStack!)
        
        // Register OddsBetStack as drop target for BetDragManager proximity animations
        // Note: The control itself is still the drop target, but we need to forward locked bet methods
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
            betView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            betView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func handleTap() {
        // If using OddsBetStack, simulate a tap on it
        if let stack = oddsBetStack {
            // Manually trigger the tap logic (since handleTap is private, we'll call addBetWithAnimation/addOddsWithAnimation)
            guard let getValue = getSelectedChipValue else { return }
            let value = getValue()
            
            if let getBalance = getBalance {
                let balance = getBalance()
                if value > balance {
                    HapticsHelper.lightHaptic()
                    return
                }
            }
            
            // When bet is locked: any tap (chip or control title) adds odds
            // When bet is not locked: tapping chip adds odds, tapping control title adds to bet
            // This allows users to add pass line/don't pass bets when point is set but bet not locked,
            // but once a bet is placed during point phase and rolled, it locks and all taps add odds
            // NOTE: handleTap() is called when tapping the control title area (not the chip)
            // The chip has its own tap handler in OddsBetStack.handleTap() which always adds odds
            if stack.hasLockedBet() {
                // Locked: any tap adds odds
                stack.addOddsWithAnimation(value)
            } else {
                // Not locked: tapping control title adds to bet (chip taps are handled separately)
                stack.addBetWithAnimation(value)
            }
            updateTitleAlignment()
            return
        }
        
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
        if let stack = oddsBetStack {
            return stack.getOddsPosition(in: view)
        }
        guard let superview = betView.superview else { return .zero }
        return superview.convert(betView.center, to: view)
    }
    
//    func center(in view: UIView) -> CGPoint {
//        guard let superview = betView.superview else { return .zero }
//        return superview.convert(betView.center, to: view)
//    }

    func addBet(_ amount: Int) {
        if let stack = oddsBetStack {
            stack.addBet(amount)
            updateTitleAlignment()
            addedBetCompletionHandler?()
            return
        }
        
        betView.addToBet(amount)
        updateTitleAlignment()
        
        // Ensure betView is visible when adding a bet
        betView.alpha = 1
        betView.isHidden = false

        // Ensure betView stays on top after adding bet
        bringSubviewToFront(betView)
        
        // Notify that bet was added (for completion handlers like stopping shimmer)
        addedBetCompletionHandler?()
    }

    func addBetWithAnimation(_ amount: Int) {
        if let stack = oddsBetStack {
            stack.addBetWithAnimation(amount)
            updateTitleAlignment()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.addedBetCompletionHandler?()
            }
            return
        }
        
        betView.addToBet(amount)
        updateTitleAlignment()

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
        updateTitleAlignment()
        // Detect bet removal and call callback
        if oldAmount > betView.amount {
            let removedAmount = oldAmount - betView.amount
            onBetRemoved?(removedAmount)
        }
    }

    /// Remove bet without triggering onBetRemoved callback
    /// Used when moving bets between controls (balance shouldn't change)
    func removeBetSilently(_ amount: Int) {
        if let stack = oddsBetStack {
            // When using OddsBetStack, removeBetSilently only removes from bet chip
            stack.removeBetSilently(amount)
            updateTitleAlignment()
            return
        }
        betView.addToBet(-amount)
        updateTitleAlignment()
    }
    
    /// Remove odds silently (without triggering callbacks)
    /// Used when moving odds between controls (balance shouldn't change)
    func removeOddsSilently(_ amount: Int) {
        oddsBetStack?.removeOddsSilently(amount)
    }

    /// Set the bet amount directly without triggering onBetPlaced callback
    /// Used for rebetting functionality where balance is managed externally
    func setDirectBet(_ amount: Int) {
        // Use betAmount setter which handles oddsBetStack automatically
        betAmount = amount
        
        // If oddsBetStack exists, ensure bet chip is visible and on top
        if let stack = oddsBetStack {
            stack.betChip.alpha = 1
            stack.betChip.isHidden = false
            stack.bringSubviewToFront(stack.betChip)
            // Also bring the stack itself to front
            bringSubviewToFront(stack)
        } else {
            // No oddsBetStack - ensure betView is visible
            betView.alpha = 1
            betView.isHidden = false
            bringSubviewToFront(betView)
        }

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
    
    // MARK: - BetDropTarget Protocol - Locked Bet Support
    
    func hasLockedBet() -> Bool {
        return oddsBetStack?.hasLockedBet() ?? false
    }
    
    func animateBetViewSlideLeftForOdds() {
        oddsBetStack?.animateBetSlideForOdds()
    }
    
    func restoreBetViewPosition() {
        oddsBetStack?.restoreBetPosition()
    }
    
    // MARK: - Odds Support
    
    func lockBet() {
        oddsBetStack?.lockBet()
    }
    
    func unlockBet(clearOdds: Bool = true) {
        oddsBetStack?.unlockBet(clearOdds: clearOdds)
    }
    
    func clearAll() {
        if let stack = oddsBetStack {
            stack.clearAll()
            updateTitleAlignment()
        } else {
            let betToRemove = betAmount
            betAmount = 0
            if betToRemove > 0 {
                onBetRemoved?(betToRemove)
            }
        }
    }
    
    // MARK: - Touch Handling
    
    /// Override point(inside:with:) to prevent control from handling touches in OddsBetStack area
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // If we have an OddsBetStack, check if point is in its area first
        if let stack = oddsBetStack, stack.isUserInteractionEnabled && !stack.isHidden && stack.alpha > 0 {
            let stackPoint = convert(point, to: stack)
            // Use expanded bounds to ensure we catch touches near the stack
            let expandedStackBounds = stack.bounds.insetBy(dx: -20, dy: -20)
            if expandedStackBounds.contains(stackPoint) {
                // Point is in stack area - let stack handle it (don't let control handle it)
                return false
            }
        }
        
        // For other areas, use default behavior
        return super.point(inside: point, with: event)
    }
    
    /// Override hitTest to ensure OddsBetStack receives touches
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // If we have an OddsBetStack, prioritize it for touch handling
        if let stack = oddsBetStack, stack.isUserInteractionEnabled && !stack.isHidden && stack.alpha > 0 {
            let stackPoint = convert(point, to: stack)
            // Check if point is within stack bounds (with some padding for easier interaction)
            let expandedStackBounds = stack.bounds.insetBy(dx: -20, dy: -20)
            if expandedStackBounds.contains(stackPoint) {
                // Let the stack handle the touch - it will route to chips appropriately
                if let hitView = stack.hitTest(stackPoint, with: event) {
                    return hitView
                }
                // If stack's hitTest returns nil but we're in bounds, return the stack itself
                // This ensures pan gestures on chips can still work
                return stack
            }
        }
        
        // For areas outside the stack, check if point is in our bounds
        if bounds.contains(point) {
            // If point is in title label area and we don't have oddsBetStack, allow control to handle it
            if oddsBetStack == nil {
                return super.hitTest(point, with: event)
            }
            // If we have oddsBetStack but touch is outside it, still allow title label taps
            let titleFrame = titleLabel.frame
            if titleFrame.contains(point) {
                return super.hitTest(point, with: event)
            }
        }
        
        // Default behavior
        return super.hitTest(point, with: event)
    }
}
