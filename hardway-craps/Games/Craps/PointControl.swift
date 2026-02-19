//
//  PointControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class PointControl: PlainControl {

    private let numberLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        label.font = .systemFont(ofSize: isIPad ? 34 : 24, weight: .medium)
        label.textColor = HardwayColors.label
        return label
    }()

    private let oddsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        label.font = .systemFont(ofSize: isIPad ? 18 : 12, weight: .regular)
        label.textColor = HardwayColors.label.withAlphaComponent(0.6)
        return label
    }()

    let pointNumber: Int
    let odds: String
    
    /// PointControls need flexible height to grow inside the PointStack
    override var wantsDefaultHeightConstraint: Bool { return false }

    var oddsMultiplier: Double {
        switch pointNumber {
        case 4, 10:
            return 2.0  // 2:1
        case 5, 9:
            return 1.5  // 3:2
        case 6, 8:
            return 1.2  // 6:5
        default:
            return 1.0
        }
    }

    var isOn: Bool = false
    
    // Come bet with odds support
    private var comeBetStack: OddsBetStack?
    private var betViewCenterXConstraint: NSLayoutConstraint!
    private var betViewLeftHalfConstraint: NSLayoutConstraint?
    private var comeBetStackCenterXConstraint: NSLayoutConstraint?
    private var comeBetStackCenterYConstraint: NSLayoutConstraint?
    
    var hasComeBet: Bool {
        return comeBetStack != nil && comeBetStack!.betAmount > 0
    }
    
    var comeBetAmount: Int {
        return comeBetStack?.betAmount ?? 0
    }
    
    var comeBetOddsAmount: Int {
        return comeBetStack?.oddsAmount ?? 0
    }
    
    // Callbacks for come bet
    var onComeBetOddsPlaced: ((Int, Int, Int) -> Void)?  // (amount, previousOddsAmount, pointNumber)
    var onComeBetOddsRemoved: ((Int) -> Void)?
    
    /// Override to animate winnings slightly above the bet (instead of to the right)
    override var winningsAnimationOffset: CGPoint {
        return CGPoint(x: 0, y: -30)  // Offset 20 points above the bet
    }
    
    /// Override originalBetWinningsOffset since animateWinnings uses this instead of winningsAnimationOffset
    override var originalBetWinningsOffset: CGPoint {
        return CGPoint(x: 0, y: -30)  // Offset 20 points above the bet
    }

    init(pointNumber: Int) {
        self.pointNumber = pointNumber

        // Calculate odds based on point number
        switch pointNumber {
        case 4, 10:
            self.odds = "2:1"
        case 5, 9:
            self.odds = "3:2"
        case 6, 8:
            self.odds = "6:5"
        default:
            self.odds = ""
        }

        super.init(title: nil)
        
        // PlainControl now skips the height constraint for PointControl subclass,
        // so no removal needed. Set low priorities to allow vertical growth.
        setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        setupPointView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPointView() {
        numberLabel.text = "\(pointNumber)"
        oddsLabel.text = odds

        // Style the control to match SmallControl
        backgroundColor = HardwayColors.surfaceGray
        layer.cornerRadius = 16

        addSubview(numberLabel)
        addSubview(oddsLabel)

        NSLayoutConstraint.activate([
            // Number label - centered but slightly above center
            numberLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),

            // Odds label - below number
            oddsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            oddsLabel.topAnchor.constraint(equalTo: numberLabel.bottomAnchor, constant: 4)
        ])
    }

    override func configureBetViewConstraints() {
        // Store centerX constraint so we can modify it when come bet is added
        betViewCenterXConstraint = betView.centerXAnchor.constraint(equalTo: centerXAnchor)
        
        NSLayoutConstraint.activate([
            betViewCenterXConstraint,
            betView.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
    
    // MARK: - Come Bet Support
    
    func addComeBet(amount: Int, getSelectedChipValue: @escaping () -> Int, getBalance: @escaping () -> Int) {
        if comeBetStack == nil {
            comeBetStack = OddsBetStack(layout: .vertical)
            comeBetStack?.parentControl = self
            addSubview(comeBetStack!)
            
            // Wire up callbacks
            comeBetStack?.getSelectedChipValue = getSelectedChipValue
            comeBetStack?.getBalance = getBalance
            comeBetStack?.onBetPlaced = { [weak self] _ in
                // Come bet is placed - no action needed (already locked)
            }
            comeBetStack?.onBetRemoved = { [weak self] _ in
                // Come bet removal handled by clearComeBet
            }
            comeBetStack?.onOddsPlaced = { [weak self] amount, previousOddsAmount in
                guard let self = self else { return }
                self.onComeBetOddsPlaced?(amount, previousOddsAmount, self.pointNumber)
                // Slide stack up when odds are added
                self.updateComeBetStackPosition()
            }
            comeBetStack?.onOddsRemoved = { [weak self] amount in
                self?.onComeBetOddsRemoved?(amount)
                // Slide stack back to center when odds are removed
                self?.updateComeBetStackPosition()
            }
            
            setupComeBetConstraints()
        }
        
        comeBetStack?.betAmount = amount
        comeBetStack?.lockBet()  // Come bet is locked immediately
    }
    
    func clearComeBet() {
        let oddsToReturn = comeBetStack?.oddsAmount ?? 0
        if oddsToReturn > 0 {
            onComeBetOddsRemoved?(oddsToReturn)
        }
        comeBetStackCenterXConstraint?.isActive = false
        comeBetStackCenterXConstraint = nil
        comeBetStack?.removeFromSuperview()
        comeBetStack = nil
        restorePlaceBetToCenter()
    }
    
    private func setupComeBetConstraints() {
        guard let stack = comeBetStack else { return }
        
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        // Center vertically with betView (will slide up when odds are added)
        comeBetStackCenterYConstraint = stack.centerYAnchor.constraint(equalTo: betView.centerYAnchor, constant: 0)
        comeBetStackCenterYConstraint?.isActive = true
        
        // Position bets using proportional layout
        updateBetLayout(animated: true)
    }
    
    func updateComeBetStackPosition() {
        guard let constraint = comeBetStackCenterYConstraint else { return }
        let hasOdds = (comeBetStack?.oddsAmount ?? 0) > 0
        let targetConstant: CGFloat = hasOdds ? -8 : 0
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            constraint.constant = targetConstant
            self.layoutIfNeeded()
        }
    }
    
    private func restorePlaceBetToCenter() {
        betViewLeftHalfConstraint?.isActive = false
        betViewCenterXConstraint.isActive = true
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.layoutIfNeeded()
        }
    }
    
    /// Updates the horizontal positions of the place bet and come bet based on which bets are present.
    /// - Place bet only: centered
    /// - Both bets: split the space evenly (place bet in left half, come bet in right half)
    /// - Come bet only: slightly off center favoring the right side
    private func updateBetLayout(animated: Bool = true) {
        guard let stack = comeBetStack else { return }
        
        // Deactivate current horizontal positioning constraints
        betViewCenterXConstraint.isActive = false
        betViewLeftHalfConstraint?.isActive = false
        comeBetStackCenterXConstraint?.isActive = false
        
        let hasPlaceBet = betView.amount > 0
        
        if hasPlaceBet {
            // Both bets present — split the space evenly
            // Place bet centered in left half (centerX × 0.5 → 25% of width)
            if betViewLeftHalfConstraint == nil {
                betViewLeftHalfConstraint = NSLayoutConstraint(
                    item: betView!, attribute: .centerX,
                    relatedBy: .equal,
                    toItem: self, attribute: .centerX,
                    multiplier: 0.5, constant: 0
                )
            }
            betViewLeftHalfConstraint?.isActive = true
            
            // Come bet centered in right half (centerX × 1.5 → 75% of width)
            comeBetStackCenterXConstraint = NSLayoutConstraint(
                item: stack, attribute: .centerX,
                relatedBy: .equal,
                toItem: self, attribute: .centerX,
                multiplier: 1.5, constant: 0
            )
            comeBetStackCenterXConstraint?.isActive = true
        } else {
            // Come bet only — slightly off center favoring the right side
            betViewCenterXConstraint.isActive = true  // betView is hidden anyway
            
            // Come bet at 60% of width (centerX × 1.2)
            comeBetStackCenterXConstraint = NSLayoutConstraint(
                item: stack, attribute: .centerX,
                relatedBy: .equal,
                toItem: self, attribute: .centerX,
                multiplier: 1.2, constant: 0
            )
            comeBetStackCenterXConstraint?.isActive = true
        }
        
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                self.layoutIfNeeded()
            }
        } else {
            layoutIfNeeded()
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Add odds to the come bet (convenience method for testing)
    func addComeBetOdds(amount: Int) {
        comeBetStack?.addOddsWithAnimation(amount)
    }
    
    /// Set the come bet odds amount directly (used for enforcing maximum odds)
    func setComeBetOddsAmount(_ amount: Int) {
        comeBetStack?.oddsAmount = amount
    }
    
    /// Get the come bet chip position in the given coordinate space
    func getComeBetPosition(in view: UIView) -> CGPoint {
        guard let stack = comeBetStack else { return .zero }
        return stack.getBetPosition(in: view)
    }
    
    /// Get the come bet odds chip position in the given coordinate space
    func getComeBetOddsPosition(in view: UIView) -> CGPoint {
        guard let stack = comeBetStack else { return .zero }
        return stack.getOddsPosition(in: view)
    }
    
    /// Hide come bet chip (for animation overlay)
    func hideComeBetChip() {
        comeBetStack?.betChip.alpha = 0
    }
    
    /// Show come bet chip (after animation completes)
    func showComeBetChip() {
        comeBetStack?.betChip.alpha = 1
    }
    
    /// Hide come bet odds chip (for animation overlay)
    func hideComeBetOddsChip() {
        comeBetStack?.oddsChip.alpha = 0
    }
    
    /// Clear come bet without triggering odds return callback (for animated loss)
    func clearComeBetSilently() {
        comeBetStackCenterXConstraint?.isActive = false
        comeBetStackCenterXConstraint = nil
        comeBetStack?.removeFromSuperview()
        comeBetStack = nil
        restorePlaceBetToCenter()
    }
    
    // MARK: - Place Bet Change Detection
    
    /// When the place bet changes while a come bet coexists, re-evaluate the proportional layout
    /// so both bets split the space correctly (or the come bet repositions if the place bet is removed).
    
    override func addBet(_ amount: Int) {
        super.addBet(amount)
        if comeBetStack != nil { updateBetLayout() }
    }
    
    override func addBetWithAnimation(_ amount: Int) {
        super.addBetWithAnimation(amount)
        if comeBetStack != nil { updateBetLayout() }
    }
    
    override func removeBet(_ amount: Int) {
        super.removeBet(amount)
        if comeBetStack != nil { updateBetLayout() }
    }
    
    override func removeBetSilently(_ amount: Int) {
        super.removeBetSilently(amount)
        if comeBetStack != nil { updateBetLayout() }
    }
    
    override func setDirectBet(_ amount: Int) {
        super.setDirectBet(amount)
        if comeBetStack != nil { updateBetLayout() }
    }
    
    override func clearAll() {
        super.clearAll()
        if comeBetStack != nil { updateBetLayout() }
    }
    
    // MARK: - Touch Handling
    
    /// Override hitTest to ensure come bet stack receives touches even when it extends outside bounds
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // First check if come bet stack can handle the touch
        if let stack = comeBetStack {
            let stackPoint = convert(point, to: stack)
            if let hitView = stack.hitTest(stackPoint, with: event) {
                return hitView
            }
        }
        
        // Default behavior for other touches
        return super.hitTest(point, with: event)
    }
}
