//
//  MPPlayerBalanceView.swift
//  hardway-craps
//
//  Shows a player's name (first name + last initial) stacked above their balance, positioned above their hand(s).
//

import UIKit

final class MPPlayerBalanceView: UIView {

    private let nameLabel = UILabel()
    private let balanceLabel = UILabel()

    private static let nameFontSize: CGFloat = 14
    private static let balanceFontSize: CGFloat = 12
    private static let spacing: CGFloat = 4

    private var displayLink: CADisplayLink?
    private var animationStartTime: CFTimeInterval = 0
    private var startBalance: Int = 0
    private var targetBalance: Int = 0

    /// First name plus last initial, e.g. "Colton S."
    var nameText: String = "" {
        didSet { nameLabel.text = nameText }
    }

    var balanceText: String = "" {
        didSet { 
            // This is kept for backward compatibility, but prefer using setBalance
            balanceLabel.text = balanceText 
        }
    }

    deinit {
        displayLink?.invalidate()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: Self.nameFontSize, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.text = nameText
        addSubview(nameLabel)

        balanceLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceLabel.font = .systemFont(ofSize: Self.balanceFontSize, weight: .regular)
        balanceLabel.textColor = .white
        balanceLabel.textAlignment = .center
        balanceLabel.text = balanceText
        addSubview(balanceLabel)

        NSLayoutConstraint.activate([
            // Balance on top
            balanceLabel.topAnchor.constraint(equalTo: topAnchor),
            balanceLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            balanceLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Name below balance
            nameLabel.topAnchor.constraint(equalTo: balanceLabel.bottomAnchor, constant: Self.spacing),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Set the balance with optional animation
    func setBalance(_ balance: Int?, animated: Bool) {
        displayLink?.invalidate()
        
        guard let balance = balance else {
            balanceLabel.text = "—"
            return
        }
        
        if animated, let currentText = balanceLabel.text, currentText != "—" {
            // Extract current balance from text (remove "$" and parse)
            let currentBalance = Int(currentText.replacingOccurrences(of: "$", with: "")) ?? 0
            animateBalanceChange(from: currentBalance, to: balance)
        } else {
            balanceLabel.text = "$\(balance)"
            targetBalance = balance
            startBalance = balance
        }
    }

    private func animateBalanceChange(from oldValue: Int, to newValue: Int) {
        // Stop any existing animation
        displayLink?.invalidate()

        // If no change, just update immediately
        guard oldValue != newValue else {
            balanceLabel.text = "$\(newValue)"
            return
        }

        // Setup animation values
        startBalance = oldValue
        targetBalance = newValue
        animationStartTime = CACurrentMediaTime()

        // Create and start display link
        displayLink = CADisplayLink(target: self, selector: #selector(updateBalanceDisplay))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateBalanceDisplay() {
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - animationStartTime
        let duration: CFTimeInterval = 0.3

        if elapsed >= duration {
            // Animation complete
            balanceLabel.text = "$\(targetBalance)"
            displayLink?.invalidate()
            displayLink = nil
        } else {
            // Calculate interpolated value
            let progress = elapsed / duration
            let easedProgress = easeOutQuad(progress)
            let currentValue = startBalance + Int(Double(targetBalance - startBalance) * easedProgress)
            balanceLabel.text = "$\(currentValue)"
        }
    }

    private func easeOutQuad(_ t: Double) -> Double {
        return t * (2.0 - t)
    }
}
