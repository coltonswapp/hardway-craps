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
    private var comeBetStackTrailingConstraint: NSLayoutConstraint?
    
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
    var onComeBetOddsPlaced: ((Int) -> Void)?
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
            comeBetStack?.onOddsPlaced = { [weak self] amount in
                self?.onComeBetOddsPlaced?(amount)
            }
            comeBetStack?.onOddsRemoved = { [weak self] amount in
                self?.onComeBetOddsRemoved?(amount)
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
        
        // Position come bet stack on the right side
        comeBetStackTrailingConstraint = stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        
        NSLayoutConstraint.activate([
            comeBetStackTrailingConstraint!,
            stack.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        
        // Shift place bet to the left
        animatePlaceBetShift(left: true)
    }
    
    private func restorePlaceBetPosition() {
        animatePlaceBetShift(left: false)
    }
    
    private func animatePlaceBetShift(left: Bool) {
        let targetConstant: CGFloat = left ? -40 : 0  // Shift left by 40pt when come bet exists
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.betViewCenterXConstraint.constant = targetConstant
            self.layoutIfNeeded()
        }
    }
}
