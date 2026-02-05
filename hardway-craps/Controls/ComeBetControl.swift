//
//  ComeBetControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 2/3/26.
//

import UIKit

/// A standalone control for Come bets with odds functionality
/// Based on PlainControl but designed specifically for odds betting
class ComeBetControl: UIControl, BetDropTarget {
    
    // MARK: - Properties
    
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
    private(set) var oddsView: SmallBetChip!
    
    var title: String? {
        didSet {
            titleLabel.text = title
        }
    }
    
    var betAmount: Int {
        get { betView.amount }
        set { betView.amount = newValue }
    }
    
    var oddsAmount: Int {
        get { oddsView.amount }
        set {
            oddsView.amount = newValue
            // If odds are cleared, snap oddsView back to trailing edge and slide betView back
            if newValue == 0 {
                // Deactivate leading constraint (next to betView)
                oddsViewLeadingConstraint.isActive = false
                // Reactivate trailing constraint (back to trailing edge)
                oddsViewTrailingConstraint.isActive = true
                
                // Slide betView back to normal position
                if betViewTrailingConstraint.constant != -12 {
                    animateBetViewSlide(left: false)
                }
                
                // Hide oddsView
                UIView.animate(withDuration: 0.3) {
                    self.oddsView.alpha = 0
                } completion: { _ in
                    self.oddsView.isHidden = true
                }
            }
        }
    }
    
    private var isBetLocked: Bool = false
    private var isDraggingBet: Bool = false
    private var isDraggingOdds: Bool = false
    
    // Constraints for sliding betView and positioning oddsView
    private var betViewTrailingConstraint: NSLayoutConstraint!
    private var oddsViewTrailingConstraint: NSLayoutConstraint!  // Initial position at trailing edge
    private var oddsViewLeadingConstraint: NSLayoutConstraint!   // Position next to betView when odds exist
    private var oddsViewCenterYConstraint: NSLayoutConstraint!
    
    // Callbacks
    var getSelectedChipValue: (() -> Int)?
    var getBalance: (() -> Int)?
    var onBetPlaced: ((Int) -> Void)?
    var onBetRemoved: ((Int) -> Void)?
    var onOddsPlaced: ((Int) -> Void)?
    var onOddsRemoved: ((Int) -> Void)?
    var canRemoveBet: (() -> Bool)?
    
    // MARK: - Initialization
    
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
    
    // MARK: - Setup
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = background
        layer.cornerRadius = 18
        clipsToBounds = false
        
        titleLabel.text = title
        titleLabel.textColor = labelColor
        addSubview(titleLabel)
        
        // Setup betView (main bet)
        betView = SmallBetChip()
        addSubview(betView)
        
        // Setup oddsView (odds bet)
        oddsView = SmallBetChip()
        oddsView.alpha = 0
        oddsView.isHidden = true
        addSubview(oddsView)
        
        // Ensure betView stays on top initially
        bringSubviewToFront(betView)
        
        let heightConstraint = heightAnchor.constraint(equalToConstant: 50)
        heightConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightConstraint
        ])
        
        setupBetViewConstraints()
        setupOddsViewConstraints()
        setupGestures()
        
        BetDragManager.shared.registerDropTarget(self)
    }
    
    private func setupBetViewConstraints() {
        // BetView starts at trailing edge (normal position)
        betViewTrailingConstraint = betView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        
        NSLayoutConstraint.activate([
            betViewTrailingConstraint,
            betView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    private func setupOddsViewConstraints() {
        // OddsView starts at trailing edge (ready to snap into place)
        oddsViewTrailingConstraint = oddsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        oddsViewCenterYConstraint = oddsView.centerYAnchor.constraint(equalTo: betView.centerYAnchor)
        
        // Position next to betView (to the right) when odds are added
        oddsViewLeadingConstraint = oddsView.leadingAnchor.constraint(equalTo: betView.trailingAnchor, constant: -4)
        
        // Start with trailing edge constraint active (initial position)
        NSLayoutConstraint.activate([
            oddsViewTrailingConstraint,
            oddsViewCenterYConstraint
        ])
        
        // Leading constraint will be activated when odds are added
        oddsViewLeadingConstraint.isActive = false
    }
    
    private func setupGestures() {
        // Control tap/press gestures
        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchDragExit, .touchCancel])
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        
        // BetView pan gesture (drag main bet)
        let betPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleBetViewPan(_:)))
        betView.addGestureRecognizer(betPanGesture)
        betView.isUserInteractionEnabled = true
        
        // BetView tap gesture (increment main bet)
        let betTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        betView.addGestureRecognizer(betTapGesture)
        betTapGesture.require(toFail: betPanGesture)
        
        // OddsView pan gesture (drag odds)
        let oddsPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleOddsViewPan(_:)))
        oddsView.addGestureRecognizer(oddsPanGesture)
        oddsView.isUserInteractionEnabled = true
        
        // OddsView tap gesture (increment odds)
        let oddsTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        oddsView.addGestureRecognizer(oddsTapGesture)
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
        
        if isBetLocked {
            // Add to odds
            addOddsWithAnimation(value)
        } else {
            // Add to main bet
            addBetWithAnimation(value)
        }
    }
    
    @objc private func handleBetViewPan(_ gesture: UIPanGestureRecognizer) {
        guard betAmount > 0 else { return }
        
        // When bet is locked, only odds can be dragged, not the main bet
        if isBetLocked {
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
            isDraggingBet = true
            betView.alpha = 0
            // Pass nil as source since we're not a PlainControl - we'll handle removal ourselves
            BetDragManager.shared.startDragging(value: betAmount, from: location, in: containerView, source: nil)
        case .changed:
            BetDragManager.shared.updateDrag(to: location)
        case .ended:
            // Check drop target before calling endDrag (endDrag may clear it)
            let chipSelectorFrame = findChipSelectorFrame(in: containerView)
            let isDroppingOnChipSelector = chipSelectorFrame.contains(location)
            let controlFrame = frameInView(containerView)
            let isDroppingOnSameControl = controlFrame.contains(location)
            let hasValidDropTarget = BetDragManager.shared.hasCurrentDropTarget()
            
            // Clear isDraggingBet flag BEFORE endDrag so addBetWithAnimation can work
            // (unless dropping back on same control, in which case we'll restore visibility)
            if !isDroppingOnSameControl {
                isDraggingBet = false
            }
            
            BetDragManager.shared.endDrag(at: location, in: containerView)
            
            // Handle bet removal ourselves since we're not a PlainControl
            if isDroppingOnChipSelector {
                // Return bet to balance
                let amountToReturn = betAmount
                betAmount = 0
                onBetRemoved?(amountToReturn)
            } else if !isDroppingOnSameControl && hasValidDropTarget {
                // Moved to different control - bet was already added there, remove silently
                removeBetSilently(betAmount)
            } else if !isDroppingOnSameControl && !hasValidDropTarget {
                // Dropped outside any control - restore bet (don't remove it)
                betView.alpha = 1
                // Restore flag since we're keeping the bet
                isDraggingBet = false
            } else {
                // Dropped back on same control - restore visibility
                betView.alpha = 1
                isDraggingBet = false
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.isDraggingBet = false
                if self.betAmount > 0 && self.betView.alpha == 0 {
                    self.betView.alpha = 1
                }
            }
        case .cancelled, .failed:
            BetDragManager.shared.cancelDrag()
            isDraggingBet = false
            betView.alpha = 1
        default:
            break
        }
    }
    
    @objc private func handleOddsViewPan(_ gesture: UIPanGestureRecognizer) {
        guard oddsAmount > 0 else { return }
        
        var rootView: UIView? = self
        while let parent = rootView?.superview {
            rootView = parent
        }
        
        guard let containerView = rootView else { return }
        
        let location = gesture.location(in: containerView)
        
        switch gesture.state {
        case .began:
            isDraggingOdds = true
            oddsView.alpha = 0
            // Store a reference to self so BetDragManager can detect when we drop back on ourselves
            // Pass self wrapped in a way that BetDragManager can check
            BetDragManager.shared.startDragging(value: oddsAmount, from: location, in: containerView, source: nil)
            // Store reference for detecting drop-back
            BetDragManager.shared.setOddsSource(self)
        case .changed:
            BetDragManager.shared.updateDrag(to: location)
        case .ended:
            // Check drop target before calling endDrag
            let chipSelectorFrame = findChipSelectorFrame(in: containerView)
            let isDroppingOnChipSelector = chipSelectorFrame.contains(location)
            let controlFrame = frameInView(containerView)
            let isDroppingOnSameControl = controlFrame.contains(location)
            
            // Store the original odds amount before endDrag might modify it
            let originalOddsAmount = oddsAmount
            
            // Clear isDraggingOdds flag BEFORE endDrag so removal logic can work
            // This ensures removeBetSilently can properly remove odds and trigger slide-back
            isDraggingOdds = false
            
            if isDroppingOnChipSelector {
                // Clear odds immediately and return to balance
                let amountToReturn = originalOddsAmount
                oddsAmount = 0  // This will trigger setter and slide-back animation
                onOddsRemoved?(amountToReturn)
            }
            
            BetDragManager.shared.endDrag(at: location, in: containerView)
            
            // Handle odds removal/restoration ourselves
            if isDroppingOnChipSelector {
                // Already handled above - odds cleared and bet should have slid back
            } else if !isDroppingOnSameControl {
                // Moved to different control - odds were already added there, remove silently
                removeBetSilently(originalOddsAmount)
            } else {
                // Dropped back on same control - restore the odds amount and visibility
                // Check if endDrag already added the odds (via addBetWithAnimation)
                if oddsAmount != originalOddsAmount {
                    // endDrag already added it back via addBetWithAnimation (which triggered onOddsPlaced)
                    // We need to undo that balance deduction since we're just restoring, not adding new
                    // The odds amount is already correct, but balance was deducted
                    // We need to call onOddsRemoved to undo the deduction, then restore without callback
                    let addedAmount = oddsAmount - originalOddsAmount
                    if addedAmount > 0 {
                        onOddsRemoved?(addedAmount)  // Undo the balance deduction
                    }
                    // Now restore to original amount without triggering callbacks
                    oddsView.amount = originalOddsAmount
                } else {
                    // endDrag didn't add it back (was skipped), so odds are 0 - restore them
                    // Set directly without triggering callbacks since we're just restoring
                    oddsView.amount = originalOddsAmount
                }
                
                // Restore visibility and constraints
                oddsView.alpha = 1
                oddsView.isHidden = false
                if oddsViewLeadingConstraint.isActive == false {
                    oddsViewTrailingConstraint.isActive = false
                    oddsViewLeadingConstraint.isActive = true
                }
                if betViewTrailingConstraint.constant == -12 {
                    animateBetViewSlide(left: true)
                }
                bringSubviewToFront(oddsView)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self else { return }
                self.isDraggingOdds = false
                
                // Ensure odds stay cleared if dropped on ChipSelector
                if isDroppingOnChipSelector && self.oddsAmount == 0 {
                    self.oddsView.alpha = 0
                    self.oddsView.isHidden = true
                    if self.betViewTrailingConstraint.constant != -12 {
                        self.animateBetViewSlide(left: false)
                    }
                }
            }
        case .cancelled, .failed:
            BetDragManager.shared.cancelDrag()
            isDraggingOdds = false
            oddsView.alpha = 1
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
    
    // MARK: - Animations
    
    private func animateBetViewSlide(left: Bool) {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.betViewTrailingConstraint.constant = left ? -42 : -12
            self.layoutIfNeeded()
        }
    }
    
    private func addOddsWithAnimation(_ amount: Int) {
        guard !isDraggingOdds else {
            return
        }
        
        let wasEmpty = oddsAmount == 0
        oddsView.addToBet(amount)
        oddsView.alpha = 1
        oddsView.isHidden = false
        
        // If this is the first odds bet, snap from trailing edge to next to betView
        if wasEmpty {
            // Deactivate trailing constraint (at trailing edge)
            oddsViewTrailingConstraint.isActive = false
            // Activate leading constraint (next to betView)
            oddsViewLeadingConstraint.isActive = true
            
            // Slide betView left to make room (only if not already shifted)
            // This handles the case where the bet was already shifted left from hover animation
            if betViewTrailingConstraint.constant == -12 {
                animateBetViewSlide(left: true)
            }
            // If already shifted (from hover), keep it shifted - no need to animate again
        }
        
        onOddsPlaced?(amount)
        bringSubviewToFront(oddsView)
        
        // Bounce animation
        oddsView.transform = .identity
        UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut]) {
            self.oddsView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                self.oddsView.transform = .identity
            }
        }
        
        HapticsHelper.lightHaptic()
    }
    
    // MARK: - Public Methods
    
    func lockBet() {
        guard betAmount > 0 else { return }
        isBetLocked = true
        // Dim the locked bet to indicate it can't be moved
        UIView.animate(withDuration: 0.2) {
            self.betView.alpha = 0.6
        }
    }
    
    func unlockBet() {
        isBetLocked = false
        // Restore full opacity when unlocked
        UIView.animate(withDuration: 0.2) {
            self.betView.alpha = 1.0
        }
        if oddsAmount > 0 {
            let amountToRemove = oddsAmount
            onOddsRemoved?(amountToRemove)
            oddsAmount = 0  // This will trigger slide-back via setter
        }
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
        
        isBetLocked = false
        // Restore full opacity when clearing
        UIView.animate(withDuration: 0.2) {
            self.betView.alpha = 1.0
        }
        oddsAmount = 0  // This will trigger slide-back via setter
    }
    
    // MARK: - BetDropTarget Protocol
    
    func frameInView(_ view: UIView) -> CGRect {
        guard let superview = superview else { return .zero }
        return superview.convert(frame, to: view)
    }
    
    func getBetViewPosition(in view: UIView) -> CGPoint {
        // If oddsView is visible, return its position, otherwise return betView position
        if oddsAmount > 0, let superview = oddsView.superview {
            return superview.convert(oddsView.center, to: view)
        }
        guard let superview = betView.superview else { return .zero }
        return superview.convert(betView.center, to: view)
    }
    
    func addBet(_ amount: Int) {
        // Allow adding bet even if dragging - this handles the case where odds are dragged back
        // The guard was preventing odds from being restored when dropped back on the same control
        
        // Note: When dragging odds back on same control, handleOddsViewPan handles restoration
        // This method is called for other cases (like moving bets between controls)
        
        if isBetLocked {
            // Add to odds
            let wasEmpty = oddsAmount == 0
            oddsView.addToBet(amount)
            oddsView.alpha = 1
            oddsView.isHidden = false
            
            // If this is the first odds bet, snap from trailing edge to next to betView
            if wasEmpty {
                oddsViewTrailingConstraint.isActive = false
                oddsViewLeadingConstraint.isActive = true
                
                if betViewTrailingConstraint.constant == -12 {
                    animateBetViewSlide(left: true)
                }
            }
            
            bringSubviewToFront(oddsView)
        } else {
            // Add to main bet
            betView.addToBet(amount)
            betView.alpha = 1
            betView.isHidden = false
            bringSubviewToFront(betView)
        }
    }
    
    func addBetWithAnimation(_ amount: Int) {
        guard !isDraggingBet && !isDraggingOdds else {
            return
        }
        
        // If we're currently dragging, this is a bet move - use addBet instead (no balance deduction)
        if isDraggingBet || isDraggingOdds {
            addBet(amount)
            return
        }
        
        if isBetLocked {
            addOddsWithAnimation(amount)
        } else {
            betView.addToBet(amount)
            betView.alpha = 1
            betView.isHidden = false
            onBetPlaced?(amount)
            bringSubviewToFront(betView)
            
            // Bounce animation
            betView.transform = .identity
            UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut]) {
                self.betView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            } completion: { _ in
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                    self.betView.transform = .identity
                }
            }
            
            HapticsHelper.lightHaptic()
        }
    }
    
    func removeBet(_ amount: Int) {
        if isDraggingOdds {
            // Removing from odds - use setter to ensure slide-back animation triggers
            let oldOddsAmount = oddsAmount
            let newOddsAmount = max(0, oddsAmount - amount)
            let removedAmount = oldOddsAmount - newOddsAmount
            
            if removedAmount > 0 {
                oddsAmount = newOddsAmount  // Use setter to trigger slide-back if needed
                onOddsRemoved?(removedAmount)
            }
        } else {
            // Removing from main bet
            let oldAmount = betAmount
            betView.addToBet(-amount)
            let removedAmount = oldAmount - betAmount
            if removedAmount > 0 {
                onBetRemoved?(removedAmount)
            }
        }
    }
    
    func removeBetSilently(_ amount: Int) {
        // Don't remove if we're currently dragging odds - this prevents clearing odds
        // when dropping a chip on a locked bet while odds are being dragged
        if isDraggingOdds {
            return
        }
        
        // Check if we're removing from odds (when bet is locked and odds exist)
        if isBetLocked && oddsAmount > 0 {
            // Removing from odds silently - use setter to ensure slide-back animation triggers
            let newOddsAmount = max(0, oddsAmount - amount)
            oddsAmount = newOddsAmount  // Use setter to trigger slide-back if needed
        } else {
            // Removing from main bet silently
            betView.addToBet(-amount)
        }
    }
    
    func highlightAsDropTarget() {
        originalBorderWidth = layer.borderWidth
        originalBorderColor = layer.borderColor
        
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.4).cgColor
            self.layer.borderWidth = 2
        }
        
        HapticsHelper.superLightHaptic()
    }
    
    func unhighlightAsDropTarget() {
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.transform = .identity
            self.layer.borderWidth = self.originalBorderWidth
            self.layer.borderColor = self.originalBorderColor
        }
    }
    
    // MARK: - BetDropTarget Protocol - Locked Bet Support
    
    func hasLockedBet() -> Bool {
        return isBetLocked && betAmount > 0
    }
    
    func animateBetViewSlideLeftForOdds() {
        // Only animate if bet is locked and not already shifted
        guard isBetLocked && betAmount > 0 else { return }
        guard betViewTrailingConstraint.constant == -12 else { return }
        
        animateBetViewSlide(left: true)
    }
    
    func restoreBetViewPosition() {
        // Only restore if bet is locked and currently shifted (and no odds exist)
        guard isBetLocked && betAmount > 0 else {
            return
        }
        guard oddsAmount == 0 else {
            return
        }
        guard betViewTrailingConstraint.constant != -12 else {
            return
        }
        
        animateBetViewSlide(left: false)
    }
    
    /// Restores odds view visibility if odds exist but view is hidden
    /// Called when addBetWithAnimation returns early due to drag flags
    func ensureOddsVisible() {
        guard isBetLocked && oddsAmount > 0 else { return }
        
        if oddsView.alpha == 0 || oddsView.isHidden {
            oddsView.alpha = 1
            oddsView.isHidden = false
            
            // Ensure constraints are active
            if oddsViewLeadingConstraint.isActive == false {
                oddsViewTrailingConstraint.isActive = false
                oddsViewLeadingConstraint.isActive = true
            }
            
            // Ensure betView stays shifted
            if betViewTrailingConstraint.constant == -12 {
                animateBetViewSlide(left: true)
            }
            
            bringSubviewToFront(oddsView)
        }
    }
}
