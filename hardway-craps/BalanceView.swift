//
//  BalanceView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class BalanceView: UIView {

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "$200"
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .regular)
        label.textAlignment = .left
        return label
    }()

    private var displayLink: CADisplayLink?
    private var animationStartTime: CFTimeInterval = 0
    private var startBalance: Int = 200
    private var targetBalance: Int = 200

    var balance: Int = 200 {
        didSet {
            animateBalanceChange(from: oldValue, to: balance)
        }
    }

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        addSubview(amountLabel)

        NSLayoutConstraint.activate([
            // Amount label only, right-aligned
            amountLabel.topAnchor.constraint(equalTo: topAnchor),
            amountLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            amountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            amountLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func animateBalanceChange(from oldValue: Int, to newValue: Int) {
        // Stop any existing animation
        displayLink?.invalidate()

        // If no change or first time setting, just update immediately
        guard oldValue != newValue else {
            amountLabel.text = "$\(newValue)"
            return
        }
        
        

        // Setup animation values
        startBalance = oldValue
        targetBalance = newValue
        animationStartTime = CACurrentMediaTime()

        // Create and start display link
        displayLink = CADisplayLink(target: self, selector: #selector(updateBalanceDisplay))
        displayLink?.add(to: .main, forMode: .common)
        
        if oldValue < newValue {
            UIView.animate(withDuration: 0.1) {
                self.amountLabel.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UIView.animate(withDuration: 0.2) {
                    self.amountLabel.transform = .identity
                }
            }
        }
    }

    @objc private func updateBalanceDisplay() {
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - animationStartTime
        let duration: CFTimeInterval = 0.3

        if elapsed >= duration {
            // Animation complete
            amountLabel.text = "$\(targetBalance)"
            displayLink?.invalidate()
            displayLink = nil
        } else {
            // Calculate interpolated value
            let progress = elapsed / duration
            let easedProgress = easeOutQuad(progress)
            let currentValue = startBalance + Int(Double(targetBalance - startBalance) * easedProgress)
            amountLabel.text = "$\(currentValue)"
        }
    }

    private func easeOutQuad(_ t: Double) -> Double {
        return t * (2.0 - t)
    }
}
