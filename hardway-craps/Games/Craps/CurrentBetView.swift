//
//  CurrentBetView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class CurrentBetView: UIView {

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Current Bet"
        label.textColor = HardwayColors.label
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textAlignment = .right
        return label
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "$0"
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .regular)
        label.textAlignment = .right
        return label
    }()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.distribution = .fill
        sv.alignment = .trailing
        sv.spacing = 4
        return sv
    }()

    private var displayLink: CADisplayLink?
    private var animationStartTime: CFTimeInterval = 0
    private var startBet: Int = 0
    private var targetBet: Int = 0

    var currentBet: Int = 0 {
        didSet {
            animateBetChange(from: oldValue, to: currentBet)
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

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(amountLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func animateBetChange(from oldValue: Int, to newValue: Int) {
        // Stop any existing animation
        displayLink?.invalidate()

        // If no change or first time setting, just update immediately
        guard oldValue != newValue else {
            amountLabel.text = "$\(newValue)"
            return
        }

        // Setup animation values
        startBet = oldValue
        targetBet = newValue
        animationStartTime = CACurrentMediaTime()

        // Create and start display link
        displayLink = CADisplayLink(target: self, selector: #selector(updateBetDisplay))
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

    @objc private func updateBetDisplay() {
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - animationStartTime
        let duration: CFTimeInterval = 0.3

        if elapsed >= duration {
            // Animation complete
            amountLabel.text = "$\(targetBet)"
            displayLink?.invalidate()
            displayLink = nil
        } else {
            // Calculate interpolated value
            let progress = elapsed / duration
            let easedProgress = easeOutQuad(progress)
            let currentValue = startBet + Int(Double(targetBet - startBet) * easedProgress)
            amountLabel.text = "$\(currentValue)"
        }
    }

    private func easeOutQuad(_ t: Double) -> Double {
        return t * (2.0 - t)
    }
}

