//
//  OddsBetStack.swift
//  hardway-craps
//
//  Created by Colton Swapp on 2/4/26.
//

import UIKit

enum OddsBetStackLayout {
    case horizontal  // [betChip][oddsChip] - for pass line
    case vertical    // [betChip]
                     // [oddsChip]         - for come bet on point
}

/// A reusable component that manages a bet chip and its associated odds chip
/// Supports both horizontal (pass line) and vertical (come bet on point) layouts
class OddsBetStack: UIView {
    
    // MARK: - Constants
    
    private struct LayoutConstants {
        // Horizontal layout constraints
        static let betChipTrailingNormal: CGFloat = -8      // Normal position (right edge)
        static let betChipTrailingShifted: CGFloat = -30      // Shifted left to make room for odds
        static let oddsChipLeadingSpacing: CGFloat = -6      // Spacing between bet and odds chips
        
        // Vertical layout constraints
        static let oddsChipTopSpacing: CGFloat = 4            // Spacing between bet and odds chips
        
        // Hit area expansion for easier dragging
        static let hitAreaExpansion: CGFloat = -5             // Negative inset expands hit area
        
        // Visual states
        static let lockedBetAlpha: CGFloat = 0.6               // Dimmed alpha when bet is locked
        static let unlockedBetAlpha: CGFloat = 1.0             // Full alpha when unlocked
    }
    
    private struct AnimationConstants {
        // Fade animations
        static let fadeDuration: TimeInterval = 0.3           // Duration for fade in/out
        
        // Lock/unlock animations
        static let lockUnlockDuration: TimeInterval = 0.2      // Duration for lock/unlock alpha changes
        
        // Bounce animation (bet/odds added)
        static let bounceInitialDuration: TimeInterval = 0.05  // Initial scale up duration
        static let bounceSpringDuration: TimeInterval = 0.25   // Spring back duration
        static let bounceSpringDamping: CGFloat = 0.5         // Spring damping
        static let bounceInitialVelocity: CGFloat = 0.5         // Initial spring velocity
        static let bounceScale: CGFloat = 1.15                // Scale factor for bounce
        
        // Slide animation (bet chip shifting)
        static let slideDuration: TimeInterval = 0.3          // Duration for bet chip slide
        static let slideSpringDamping: CGFloat = 0.7          // Spring damping for slide
        static let slideInitialVelocity: CGFloat = 0.5         // Initial spring velocity for slide
    }
    
    // MARK: - Properties
    
    let layout: OddsBetStackLayout
    
    private(set) var betChip: SmallBetChip!
    private(set) var oddsChip: SmallBetChip!
    
    private(set) var isLocked: Bool = false
    private var isDraggingOdds: Bool = false
    private var draggedOddsAmount: Int = 0
    /// Flag to prevent clearing odds during payout animations
    private(set) var isAnimatingPayout: Bool = false
    /// Flag to prevent fade animation during bet collection (chip is already hidden)
    private var isCollectingBet: Bool = false
    
    var betAmount: Int {
        get { betChip.amount }
        set {
            // Prevent setting betAmount when dragging odds
            if isDraggingOdds {
                return
            }
            betChip.amount = newValue
        }
    }
    
    var oddsAmount: Int {
        get { oddsChip.amount }
        set {
            // NOTE: We no longer block clearing when isAnimatingPayout=true
            // Instead, we allow the clear but skip the fade-out animation (handled below)
            // The unlockBet() method has its own guard to skip clearing during payout
            
            // Prevent setting oddsAmount back if we're dragging odds
            if isDraggingOdds && newValue > 0 {
                return
            }
            // Also prevent if someone is trying to add back the exact amount we just dragged away
            if draggedOddsAmount > 0 && newValue == draggedOddsAmount && oddsChip.amount == 0 {
                return
            }
            oddsChip.amount = newValue
            // If odds are cleared, ensure betChip slides back to normal position (horizontal layout only)
            // CRITICAL: Don't fade out if we're animating a payout or collecting a bet
            // - During payout: animation chip is visible, original chip is already hidden (alpha=0)
            // - During bet collection: chip is already hidden (alpha=0), no need to fade
            if newValue == 0 && !isAnimatingPayout && !isCollectingBet {
                if layout == .horizontal && betChipTrailingConstraint.constant != LayoutConstants.betChipTrailingNormal {
                    animateBetChipSlide(left: false)
                }
                UIView.animate(withDuration: AnimationConstants.fadeDuration) {
                    self.oddsChip.alpha = 0
                } completion: { _ in
                    self.oddsChip.isHidden = true
                }
            } else if newValue == 0 && (isAnimatingPayout || isCollectingBet) {
                // Chip is already hidden (alpha=0) by animation code, just ensure state is correct
                // DO NOT set alpha=0 again here - the animation code handles visibility
                oddsChip.isHidden = true
                // Trigger bet chip slide-back animation
                if layout == .horizontal && betChipTrailingConstraint.constant != LayoutConstants.betChipTrailingNormal {
                    animateBetChipSlide(left: false)
                }
            }
        }
    }
    
    // Parent control reference for BetDragManager integration
    weak var parentControl: BetDropTarget?
    
    // Callbacks
    var onBetPlaced: ((Int) -> Void)?
    var onBetRemoved: ((Int) -> Void)?
    var onOddsPlaced: ((Int) -> Void)?
    var onOddsRemoved: ((Int) -> Void)?
    var getSelectedChipValue: (() -> Int)?
    var getBalance: (() -> Int)?
    var canRemoveBet: (() -> Bool)?
    
    // Constraints for horizontal layout (betChip sliding)
    private var betChipTrailingConstraint: NSLayoutConstraint!
    private var oddsChipLeadingConstraint: NSLayoutConstraint!
    private var oddsChipCenterYConstraint: NSLayoutConstraint!
    
    // Constraints for vertical layout
    private var oddsChipTopConstraint: NSLayoutConstraint!
    
    // MARK: - Initialization
    
    init(layout: OddsBetStackLayout) {
        self.layout = layout
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        
        betChip = SmallBetChip()
        addSubview(betChip)
        
        oddsChip = SmallBetChip()
        oddsChip.isHidden = true
        oddsChip.alpha = 0
        addSubview(oddsChip)
        
        setupConstraints()
        setupGestures()
    }
    
    private func setupConstraints() {
        switch layout {
        case .horizontal:
            // BetChip starts at trailing edge
            betChipTrailingConstraint = betChip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: LayoutConstants.betChipTrailingNormal)
            
            // OddsChip positioned next to betChip (will be activated when odds are added)
            oddsChipLeadingConstraint = oddsChip.leadingAnchor.constraint(equalTo: betChip.trailingAnchor, constant: LayoutConstants.oddsChipLeadingSpacing)
            oddsChipCenterYConstraint = oddsChip.centerYAnchor.constraint(equalTo: betChip.centerYAnchor)
            
            NSLayoutConstraint.activate([
                betChipTrailingConstraint,
                betChip.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            
        case .vertical:
            // BetChip stays in place (no sliding for vertical layout)
            // OddsChip appears below betChip
            oddsChipTopConstraint = oddsChip.topAnchor.constraint(equalTo: betChip.bottomAnchor, constant: LayoutConstants.oddsChipTopSpacing)
            
            NSLayoutConstraint.activate([
                betChip.centerXAnchor.constraint(equalTo: centerXAnchor),
                betChip.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }
    
    private func setupGestures() {
        // BetChip pan gesture (drag bet away)
        let betPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleBetChipPan(_:)))
        betPanGesture.cancelsTouchesInView = false  // Allow touches to pass through if gesture fails
        betChip.addGestureRecognizer(betPanGesture)
        betChip.isUserInteractionEnabled = true
        
        // BetChip tap gesture (increment bet or odds)
        let betTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        betChip.addGestureRecognizer(betTapGesture)
        betTapGesture.require(toFail: betPanGesture)
        
        // OddsChip pan gesture (drag odds away)
        let oddsPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleOddsChipPan(_:)))
        oddsPanGesture.cancelsTouchesInView = false  // Allow touches to pass through if gesture fails
        oddsChip.addGestureRecognizer(oddsPanGesture)
        oddsChip.isUserInteractionEnabled = true
        
        // OddsChip tap gesture (increment odds)
        let oddsTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        oddsChip.addGestureRecognizer(oddsTapGesture)
        oddsTapGesture.require(toFail: oddsPanGesture)
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handleTap() {
        guard let getValue = getSelectedChipValue else { return }
        
        let value = getValue()
        
        // Check balance
        if let getBalance = getBalance {
            let balance = getBalance()
            if value > balance {
                HapticsHelper.lightHaptic()
                return
            }
        }
        
        // Tapping on the chip directly always adds odds
        // (When locked, any tap adds odds; when not locked, chip tap adds odds, control title tap adds to bet)
        addOddsWithAnimation(value)
    }
    
    @objc private func handleBetChipPan(_ gesture: UIPanGestureRecognizer) {
        guard betAmount > 0 else { return }
        
        // When bet is locked, only odds can be dragged, not the main bet
        if isLocked {
            HapticsHelper.failureHaptic()
            return
        }
        
        let canRemove = canRemoveBet?() ?? true
        if !canRemove {
            HapticsHelper.failureHaptic()
            return
        }
        
        var rootView: UIView? = self
        while let parent = rootView?.superview {
            rootView = parent
        }
        
        guard let containerView = rootView else { return }
        
        let location = gesture.location(in: containerView)
        
        switch gesture.state {
        case .began:
            betChip.alpha = 0
            // Pass parent control as source so BetDragManager knows it's a bet move
            // This allows BetDragManager to call onBetReturned on ChipSelector
            if let parent = parentControl as? PlainControl {
                BetDragManager.shared.startDragging(value: betAmount, from: location, in: containerView, source: parent)
            } else {
                // Fallback: if parent isn't a PlainControl, pass nil
                // We'll handle balance restoration manually in .ended if needed
                BetDragManager.shared.startDragging(value: betAmount, from: location, in: containerView, source: nil)
            }
        case .changed:
            BetDragManager.shared.updateDrag(to: location)
        case .ended:
            let chipSelectorFrame = findChipSelectorFrame(in: containerView)
            let isDroppingOnChipSelector = chipSelectorFrame.contains(location)
            let stackFrame = frameInView(containerView)
            let isDroppingOnSameStack = stackFrame.contains(location)
            
            // Store amount before endDrag in case we need to restore balance
            let amountBeforeDrag = betAmount
            
            BetDragManager.shared.endDrag(at: location, in: containerView)
            
            // Handle visibility restoration for non-ChipSelector drops
            if !isDroppingOnChipSelector {
                if isDroppingOnSameStack {
                    // Dropped back on same stack - restore visibility
                    betChip.alpha = 1
                }
                // For moves to different controls, BetDragManager handles removal in completion block
            }
            
            // Delayed check: if we dropped on ChipSelector and bet wasn't cleared by BetDragManager,
            // restore balance manually. This handles cases where BetDragManager doesn't call onBetReturned
            if isDroppingOnChipSelector {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    // If bet still exists, BetDragManager didn't clear it, so restore balance manually
                    if self.betAmount == amountBeforeDrag && amountBeforeDrag > 0 {
                        // BetDragManager didn't handle it - restore balance manually
                        self.betAmount = 0
                        self.onBetRemoved?(amountBeforeDrag)
                    }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                if self.betAmount > 0 && self.betChip.alpha == 0 {
                    self.betChip.alpha = 1
                }
            }
        case .cancelled, .failed:
            BetDragManager.shared.cancelDrag()
            betChip.alpha = 1
        default:
            break
        }
    }
    
    @objc private func handleOddsChipPan(_ gesture: UIPanGestureRecognizer) {
        guard oddsAmount > 0 else { return }
        
        var rootView: UIView? = self
        while let parent = rootView?.superview {
            rootView = parent
        }
        
        guard let containerView = rootView else { return }
        
        let location = gesture.location(in: containerView)
        
        switch gesture.state {
        case .began:
            oddsChip.alpha = 0
            isDraggingOdds = true
            draggedOddsAmount = oddsAmount
            BetDragManager.shared.startDragging(value: oddsAmount, from: location, in: containerView, source: nil)
            // Set parent control as odds source for BetDragManager
            if let parent = parentControl {
                BetDragManager.shared.setOddsSource(parent)
            }
        case .changed:
            BetDragManager.shared.updateDrag(to: location)
        case .ended:
            let chipSelectorFrame = findChipSelectorFrame(in: containerView)
            let isDroppingOnChipSelector = chipSelectorFrame.contains(location)
            let stackFrame = frameInView(containerView)
            let isDroppingOnSameStack = stackFrame.contains(location)
            
            let originalOddsAmount = oddsAmount
            
            BetDragManager.shared.endDrag(at: location, in: containerView)
            
            // Clear isDraggingOdds flag after endDrag (but we'll use originalOddsAmount to identify odds removal)
            isDraggingOdds = false
            
            if isDroppingOnChipSelector {
                // BetDragManager will call addBetWithAnimation on ChipSelector which calls onBetReturned
                // This handles balance restoration. We just need to clear the odds.
                // Note: We don't call onOddsRemoved here because onBetReturned already restores balance
                oddsAmount = 0
            } else if !isDroppingOnSameStack {
                // Moved to different control - odds were already added there, remove silently
                // Use removeOddsSilently to ensure we remove from odds, not bet
                removeOddsSilently(originalOddsAmount)
            } else {
                // Dropped back on same stack - restore
                if oddsAmount != originalOddsAmount {
                    // endDrag added it back - undo balance deduction
                    let addedAmount = oddsAmount - originalOddsAmount
                    if addedAmount > 0 {
                        onOddsRemoved?(addedAmount)
                    }
                    oddsChip.amount = originalOddsAmount
                } else {
                    // Restore amount
                    oddsChip.amount = originalOddsAmount
                }
                
                oddsChip.alpha = 1
                oddsChip.isHidden = false
                
                // Ensure constraints are active for horizontal layout
                if layout == .horizontal {
                    if oddsChipLeadingConstraint.isActive == false {
                        NSLayoutConstraint.activate([
                            oddsChipLeadingConstraint,
                            oddsChipCenterYConstraint
                        ])
                    }
                    if betChipTrailingConstraint.constant == LayoutConstants.betChipTrailingNormal {
                        animateBetChipSlide(left: true)
                    }
                } else {
                    // Vertical layout
                    if oddsChipTopConstraint.isActive == false {
                        NSLayoutConstraint.activate([
                            oddsChipTopConstraint,
                            oddsChip.centerXAnchor.constraint(equalTo: betChip.centerXAnchor)
                        ])
                    }
                }
                
                bringSubviewToFront(oddsChip)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self else { return }
                self.isDraggingOdds = false
                self.draggedOddsAmount = 0
                
                if isDroppingOnChipSelector && self.oddsAmount == 0 {
                    self.oddsChip.alpha = 0
                    self.oddsChip.isHidden = true
                    if self.layout == .horizontal && self.betChipTrailingConstraint.constant != LayoutConstants.betChipTrailingNormal {
                        self.animateBetChipSlide(left: false)
                    }
                }
            }
        case .cancelled, .failed:
            BetDragManager.shared.cancelDrag()
            isDraggingOdds = false
            draggedOddsAmount = 0
            oddsChip.alpha = 1
        default:
            break
        }
    }
    
    private func findChipSelectorFrame(in view: UIView) -> CGRect {
        for subview in view.subviews {
            if let chipSelector = subview as? ChipSelector {
                return view.convert(chipSelector.bounds, from: chipSelector)
            }
            let frame = findChipSelectorFrame(in: subview)
            if frame != .zero {
                return frame
            }
        }
        return .zero
    }
    
    private func frameInView(_ view: UIView) -> CGRect {
        guard let superview = superview else { return .zero }
        return superview.convert(frame, to: view)
    }
    
    // MARK: - Public Methods
    
    func lockBet() {
        guard betAmount > 0 else { return }
        isLocked = true
        // Dim the locked bet to indicate it can't be moved
        UIView.animate(withDuration: AnimationConstants.lockUnlockDuration) {
            self.betChip.alpha = LayoutConstants.lockedBetAlpha
        }
    }
    
    func unlockBet(clearOdds: Bool = true) {
        isLocked = false
        // Restore full opacity
        UIView.animate(withDuration: AnimationConstants.lockUnlockDuration) {
            self.betChip.alpha = LayoutConstants.unlockedBetAlpha
        }
        // CRITICAL: Don't clear odds if we're animating a payout or collecting a bet
        // The odds will be cleared by the animation completion handler
        // Also don't clear odds if clearOdds is false (when just updating state, not actually unlocking)
        if clearOdds && oddsAmount > 0 && !isAnimatingPayout && !isCollectingBet {
            let amountToRemove = oddsAmount
            onOddsRemoved?(amountToRemove)
            oddsAmount = 0
        }
    }
    
    /// Mark that a payout animation is starting - prevents unlockBet from clearing odds
    func startPayoutAnimation() {
        isAnimatingPayout = true
    }
    
    /// Mark that payout animation is complete - allows odds to be cleared normally
    func endPayoutAnimation() {
        isAnimatingPayout = false
    }
    
    /// Mark that bet collection is starting - prevents fade animation
    func startBetCollection() {
        isCollectingBet = true
    }
    
    /// Mark that bet collection is complete
    func endBetCollection() {
        isCollectingBet = false
    }
    
    func clearAll() {
        let betToRemove = betAmount
        let oddsToRemove = oddsAmount
        
        betAmount = 0
        
        if betToRemove > 0 {
            onBetRemoved?(betToRemove)
        }
        if oddsToRemove > 0 {
            onOddsRemoved?(oddsToRemove)
        }
        
        isLocked = false
        oddsAmount = 0
    }
    
    func addBet(_ amount: Int) {
        guard !isDraggingOdds else { return }
        
        // When bet is locked, add to odds instead of bet
        // When bet is not locked, add to bet
        if isLocked {
            addOdds(amount)
            return
        }
        
        betChip.addToBet(amount)
        betChip.alpha = 1
        betChip.isHidden = false
        bringSubviewToFront(betChip)
    }
    
    func addBetWithAnimation(_ amount: Int) {
        guard !isDraggingOdds else { return }
        
        // When bet is locked, add to odds instead of bet
        // When bet is not locked, add to bet
        if isLocked {
            addOddsWithAnimation(amount)
            return
        }
        
        // Bet is not locked - add to bet
        betChip.addToBet(amount)
        betChip.alpha = 1
        betChip.isHidden = false
        onBetPlaced?(amount)
        bringSubviewToFront(betChip)
        
        // Bounce animation
        betChip.transform = .identity
        UIView.animate(withDuration: AnimationConstants.bounceInitialDuration, delay: 0, options: [.curveEaseOut]) {
            self.betChip.transform = CGAffineTransform(scaleX: AnimationConstants.bounceScale, y: AnimationConstants.bounceScale)
        } completion: { _ in
            UIView.animate(withDuration: AnimationConstants.bounceSpringDuration, delay: 0, usingSpringWithDamping: AnimationConstants.bounceSpringDamping, initialSpringVelocity: AnimationConstants.bounceInitialVelocity, options: .curveEaseInOut) {
                self.betChip.transform = .identity
            }
        }
        
        HapticsHelper.lightHaptic()
    }
    
    func addOdds(_ amount: Int) {
        guard !isDraggingOdds else { return }
        
        if isLocked {
            let wasEmpty = oddsAmount == 0
            oddsChip.addToBet(amount)
            oddsChip.alpha = 1
            oddsChip.isHidden = false
            oddsChip.isUserInteractionEnabled = true  // Ensure interaction is enabled
            
            // Activate constraints if needed
            if layout == .horizontal {
                if oddsChipLeadingConstraint.isActive == false {
                    NSLayoutConstraint.activate([
                        oddsChipLeadingConstraint,
                        oddsChipCenterYConstraint
                    ])
                }
                if wasEmpty && betChipTrailingConstraint.constant == LayoutConstants.betChipTrailingNormal {
                    animateBetChipSlide(left: true)
                }
            } else {
                // Vertical layout
                if oddsChipTopConstraint.isActive == false {
                    NSLayoutConstraint.activate([
                        oddsChipTopConstraint,
                        oddsChip.centerXAnchor.constraint(equalTo: betChip.centerXAnchor)
                    ])
                }
            }
            
            onOddsPlaced?(amount)
            bringSubviewToFront(oddsChip)
            // Also ensure parent brings this stack to front
            if let parentView = parentControl as? UIView {
                parentView.bringSubviewToFront(self)
            }
        }
    }
    
    func addOddsWithAnimation(_ amount: Int) {
        guard !isDraggingOdds else { return }
        
        let wasEmpty = oddsAmount == 0
        oddsChip.addToBet(amount)
        oddsChip.alpha = 1
        oddsChip.isHidden = false
        oddsChip.isUserInteractionEnabled = true  // Ensure interaction is enabled
        
        // Ensure pan gesture is still attached (should be from setupGestures, but verify)
        let hasPanGesture = oddsChip.gestureRecognizers?.contains { $0 is UIPanGestureRecognizer } ?? false
        if !hasPanGesture {
            let oddsPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleOddsChipPan(_:)))
            oddsPanGesture.cancelsTouchesInView = false
            oddsChip.addGestureRecognizer(oddsPanGesture)
        }
        
        // Activate constraints if needed
        if layout == .horizontal {
            if oddsChipLeadingConstraint.isActive == false {
                NSLayoutConstraint.activate([
                    oddsChipLeadingConstraint,
                    oddsChipCenterYConstraint
                ])
            }
            // Slide betChip left if this is the first odds bet (only if not already shifted)
            if wasEmpty && betChipTrailingConstraint.constant == LayoutConstants.betChipTrailingNormal {
                animateBetChipSlide(left: true)
            }
        } else {
            // Vertical layout
            if oddsChipTopConstraint.isActive == false {
                NSLayoutConstraint.activate([
                    oddsChipTopConstraint,
                    oddsChip.centerXAnchor.constraint(equalTo: betChip.centerXAnchor)
                ])
            }
        }
        
        onOddsPlaced?(amount)
        bringSubviewToFront(oddsChip)
        // Also ensure parent brings this stack to front
        if let parentView = parentControl as? UIView {
            parentView.bringSubviewToFront(self)
        }
        
        // Force layout to ensure chip frame is set before gestures can work
        layoutIfNeeded()
        
        // Bounce animation
        oddsChip.transform = .identity
        UIView.animate(withDuration: AnimationConstants.bounceInitialDuration, delay: 0, options: [.curveEaseOut]) {
            self.oddsChip.transform = CGAffineTransform(scaleX: AnimationConstants.bounceScale, y: AnimationConstants.bounceScale)
        } completion: { _ in
            UIView.animate(withDuration: AnimationConstants.bounceSpringDuration, delay: 0, usingSpringWithDamping: AnimationConstants.bounceSpringDamping, initialSpringVelocity: AnimationConstants.bounceInitialVelocity, options: .curveEaseInOut) {
                self.oddsChip.transform = .identity
            }
        }
        
        HapticsHelper.lightHaptic()
    }
    
    func removeBet(_ amount: Int) {
        let oldAmount = betChip.amount
        betChip.addToBet(-amount)
        if oldAmount > betChip.amount {
            let removedAmount = oldAmount - betChip.amount
            onBetRemoved?(removedAmount)
        }
    }
    
    func removeBetSilently(_ amount: Int) {
        // This method removes from bet chip only
        betChip.addToBet(-amount)
    }
    
    /// Remove odds silently (without triggering callbacks)
    /// Used when moving odds between controls (balance shouldn't change)
    func removeOddsSilently(_ amount: Int) {
        let oldOddsAmount = oddsAmount
        if oldOddsAmount > 0 {
            oddsChip.addToBet(-amount)
            if oddsAmount == 0 {
                if layout == .horizontal {
                    animateBetChipSlide(left: false)
                }
                UIView.animate(withDuration: AnimationConstants.fadeDuration) {
                    self.oddsChip.alpha = 0
                } completion: { _ in
                    self.oddsChip.isHidden = true
                }
            } else {
                oddsChip.alpha = 1
            }
        }
    }
    
    // MARK: - Animation
    
    private func animateBetChipSlide(left: Bool) {
        guard layout == .horizontal else { return }
        
        let targetConstant: CGFloat = left ? LayoutConstants.betChipTrailingShifted : LayoutConstants.betChipTrailingNormal
        
        UIView.animate(withDuration: AnimationConstants.slideDuration, delay: 0, usingSpringWithDamping: AnimationConstants.slideSpringDamping, initialSpringVelocity: AnimationConstants.slideInitialVelocity, options: .curveEaseInOut) {
            self.betChipTrailingConstraint.constant = targetConstant
            self.layoutIfNeeded()
        }
    }
    
    // MARK: - BetDropTarget Support
    
    func hasLockedBet() -> Bool {
        return isLocked && betAmount > 0
    }
    
    func animateBetSlideForOdds() {
        guard layout == .horizontal else { return }
        guard isLocked && betAmount > 0 else { return }
        guard betChipTrailingConstraint.constant == LayoutConstants.betChipTrailingNormal else { return }
        
        animateBetChipSlide(left: true)
    }
    
    func restoreBetPosition() {
        guard layout == .horizontal else { return }
        guard isLocked && betAmount > 0 else { return }
        guard oddsAmount == 0 else { return }
        guard betChipTrailingConstraint.constant != LayoutConstants.betChipTrailingNormal else { return }
        
        animateBetChipSlide(left: false)
    }
    
    func getBetPosition(in view: UIView) -> CGPoint {
        guard let superview = betChip.superview else { return .zero }
        return superview.convert(betChip.center, to: view)
    }
    
    func getOddsPosition(in view: UIView) -> CGPoint {
        if oddsAmount > 0, let superview = oddsChip.superview {
            return superview.convert(oddsChip.center, to: view)
        }
        return getBetPosition(in: view)
    }
    
    func ensureOddsVisible() {
        guard isLocked && oddsAmount > 0 else { return }
        
        if oddsChip.alpha == 0 || oddsChip.isHidden {
            oddsChip.alpha = 1
            oddsChip.isHidden = false
            
            if layout == .horizontal {
                if oddsChipLeadingConstraint.isActive == false {
                    NSLayoutConstraint.activate([
                        oddsChipLeadingConstraint,
                        oddsChipCenterYConstraint
                    ])
                }
                if betChipTrailingConstraint.constant == LayoutConstants.betChipTrailingNormal {
                    animateBetChipSlide(left: true)
                }
            } else {
                if oddsChipTopConstraint.isActive == false {
                    NSLayoutConstraint.activate([
                        oddsChipTopConstraint,
                        oddsChip.centerXAnchor.constraint(equalTo: betChip.centerXAnchor)
                    ])
                }
            }
            
            bringSubviewToFront(oddsChip)
            // Also ensure parent brings this stack to front
            if let parentView = parentControl as? UIView {
                parentView.bringSubviewToFront(self)
            }
        }
    }
    
    // MARK: - Touch Handling
    
    /// Override hitTest to ensure chips receive touches
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Check odds chip first (if visible and has amount)
        if oddsAmount > 0, oddsChip.isUserInteractionEnabled, !oddsChip.isHidden, oddsChip.alpha > 0 {
            let oddsPoint = convert(point, to: oddsChip)
            // Use a slightly larger hit area for easier dragging
            let expandedBounds = oddsChip.bounds.insetBy(dx: LayoutConstants.hitAreaExpansion, dy: LayoutConstants.hitAreaExpansion)
            if expandedBounds.contains(oddsPoint) {
                let hitView = oddsChip.hitTest(oddsPoint, with: event)
                if hitView != nil {
                    return hitView
                }
                // If hitTest returns nil but we're in bounds, return the chip itself
                return oddsChip
            }
        }
        
        // Check bet chip
        if betAmount > 0, betChip.isUserInteractionEnabled, !betChip.isHidden, betChip.alpha > 0 {
            let betPoint = convert(point, to: betChip)
            // Use a slightly larger hit area for easier dragging
            let expandedBounds = betChip.bounds.insetBy(dx: LayoutConstants.hitAreaExpansion, dy: LayoutConstants.hitAreaExpansion)
            if expandedBounds.contains(betPoint) {
                let hitView = betChip.hitTest(betPoint, with: event)
                if hitView != nil {
                    return hitView
                }
                // If hitTest returns nil but we're in bounds, return the chip itself
                return betChip
            }
        }
        
        // Default behavior
        return super.hitTest(point, with: event)
    }
}
