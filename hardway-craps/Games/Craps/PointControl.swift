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
        label.font = .systemFont(ofSize: 24, weight: .medium)
        label.textColor = HardwayColors.label
        return label
    }()

    private let oddsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = HardwayColors.label.withAlphaComponent(0.6)
        return label
    }()

    let pointNumber: Int
    let odds: String

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
    
    // Come bet with odds support (vertical layout, right-aligned)
    private var comeBetStack: OddsBetStack?
    private var betViewCenterXConstraint: NSLayoutConstraint!
    private var betViewLeadingConstraint: NSLayoutConstraint?
    private var comeBetStackTrailingConstraint: NSLayoutConstraint?
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
        
        // Remove PlainControl's default 50pt height constraint
        var heightConstraintsToRemove: [NSLayoutConstraint] = []
        for constraint in constraints {
            if constraint.firstAttribute == .height && constraint.firstItem === self && constraint.constant == 50 {
                heightConstraintsToRemove.append(constraint)
            }
        }
        NSLayoutConstraint.deactivate(heightConstraintsToRemove)
        
        setupPointView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPointView() {
        numberLabel.text = "\(pointNumber)"
        oddsLabel.text = odds

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
        comeBetStack?.removeFromSuperview()
        comeBetStack = nil
        restorePlaceBetPosition()
    }
    
    private func setupComeBetConstraints() {
        guard let stack = comeBetStack else { return }
        
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        // Position come bet stack trailing edge on pointControl trailing edge (with small padding)
        comeBetStackTrailingConstraint = stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        
        // Center vertically initially (will slide up when odds are added)
        comeBetStackCenterYConstraint = stack.centerYAnchor.constraint(equalTo: betView.centerYAnchor, constant: 0)
        
        NSLayoutConstraint.activate([
            comeBetStackTrailingConstraint!,
            comeBetStackCenterYConstraint!
        ])
        
        // Shift place bet to align leading edge with pointControl leading edge
        animatePlaceBetShift(left: true)
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
    
    private func restorePlaceBetPosition() {
        animatePlaceBetShift(left: false)
    }
    
    private func animatePlaceBetShift(left: Bool) {
        if left {
            // When come bet is added: align place bet leading edge with pointControl leading edge
            // SmallBetChip is 30pt wide, so centerX should be at leading + 15pt
            // Current centerX is at pointControl.centerX (which is leading + 30pt for 60pt wide control)
            // So we need to shift: (leading + 15) - (leading + 30) = -15pt
            let chipHalfWidth: CGFloat = 15  // SmallBetChip is 30pt wide, half is 15pt
            let pointControlHalfWidth: CGFloat = 30  // PointControl is 60pt wide, half is 30pt
            let shiftAmount = chipHalfWidth - pointControlHalfWidth  // -15pt
            
            // Deactivate centerX constraint and activate leading constraint
            betViewCenterXConstraint.isActive = false
            betViewLeadingConstraint = betView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0)
            betViewLeadingConstraint?.isActive = true
            
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                self.layoutIfNeeded()
            }
        } else {
            // When come bet is removed: restore place bet to center
            betViewLeadingConstraint?.isActive = false
            betViewLeadingConstraint = nil
            betViewCenterXConstraint.isActive = true
            
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                self.layoutIfNeeded()
            }
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
        comeBetStack?.removeFromSuperview()
        comeBetStack = nil
        restorePlaceBetPosition()
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
