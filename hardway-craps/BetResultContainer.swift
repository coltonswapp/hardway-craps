//
//  BetResultContainer.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class BetResultContainer: UIVisualEffectView {

    private let bonusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .heavy)
        label.textColor = HardwayColors.yellow
        label.text = "BONUS"
        label.alpha = 0
        return label
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 40, weight: .bold)
        label.textColor = HardwayColors.yellow
        label.text = "$0"
        return label
    }()
    
    private var displayLink: CADisplayLink?
    private var startValue: Int = 0
    private var targetValue: Int = 0
    private var currentValue: Int = 0
    private var startTime: CFTimeInterval = 0
    private let animationDuration: CFTimeInterval = 1.0
    private var isWin: Bool = true
    
    convenience init() {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            self.init(effect: glassEffect)
        } else {
            // Fallback: Use blur effect for older iOS versions
            let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            self.init(effect: blurEffect)
        }
    }
    
    override init(effect: UIVisualEffect?) {
        super.init(effect: effect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    deinit {
        stopAnimation()
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        // Create liquid glass effect
        setupLiquidGlassEffect()

        contentView.addSubview(bonusLabel)
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            bonusLabel.centerYAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
            bonusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            heightAnchor.constraint(equalToConstant: 80)
        ])
    }
    
    private func setupLiquidGlassEffect() {
        // Capsule shape
        layer.cornerRadius = 40
//        clipsToBounds = true
        
        // Add background styling for non-glass versions
        if #available(iOS 26.0, *) {
            // Glass effect handles the background
        } else {
            // Fallback: Add background color and shadow for non-glass
            backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 2)
            layer.shadowOpacity = 0.1
            layer.shadowRadius = 8
        }
        
        // Add subtle border/shine
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        
        // Add shadow for depth
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 12
        layer.shadowOpacity = 0.3
        layer.masksToBounds = false
    }
    
    func animateToAmount(_ amount: Int, isWin: Bool = true, showBonus: Bool = false) {
        self.isWin = isWin
        startValue = 0
        targetValue = amount
        currentValue = 0
        startTime = CACurrentMediaTime()

        // Set text color based on win/loss
        label.textColor = isWin ? HardwayColors.yellow : .systemRed
        bonusLabel.textColor = isWin ? HardwayColors.yellow : .systemRed

        // Show/hide bonus label
        bonusLabel.alpha = showBonus ? 1 : 0

        // Reset label
        label.text = "$0"

        // Start animation
        startAnimation()
    }
    
    private func startAnimation() {
        stopAnimation()
        
        displayLink = CADisplayLink(target: self, selector: #selector(updateAnimation))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func updateAnimation() {
        let elapsed = CACurrentMediaTime() - startTime
        // Reach final value 0.2 seconds before animation duration ends
        let targetDuration = animationDuration - 0.2
        let progress = min(elapsed / targetDuration, 1.0)
        
        // Faster, more linear curve - accelerates quickly then maintains speed
        let easedProgress = progress < 1.0 ? pow(progress, 0.7) : 1.0
        
        currentValue = Int(Double(startValue) + Double(targetValue - startValue) * easedProgress)
        
        // Format text with + or - prefix based on win/loss
        let prefix = isWin ? "+" : "-"
        label.text = "\(prefix)$\(currentValue)"
        
        if progress >= 1.0 {
            // Ensure final value is set
            currentValue = targetValue
            label.text = "\(prefix)$\(targetValue)"
            stopAnimation()
            
            label.addQuickShimmerEffect()
        }
    }
    
    func show(isWin: Bool, completion: @escaping () -> Void) {
        // Start with scale 0 and fade in
        transform = CGAffineTransform(scaleX: 0, y: 0)
        transform = CGAffineTransform(translationX: 0, y: 60)
        alpha = 0
        
        let animator = UIViewPropertyAnimator(duration: 0.3, controlPoint1: CGPoint(x: 0.85, y: 0), controlPoint2: CGPoint(x: 0.14, y: 1.46), animations: {
            
            self.transform = .identity
            self.alpha = 1
        })
        
        animator.addCompletion { _ in
            let waitTime = self.animationDuration + 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + waitTime) {
                self.animateDisappear(isWin: isWin, completion: completion)
            }
        }
        
        animator.startAnimation()
    }
    
    private func animateDisappear(isWin: Bool, completion: @escaping () -> Void) {
        // Transform animation: Scale down + translate up (combined)
        let transformAnimator = UIViewPropertyAnimator(
            duration: 0.25,
            controlPoint1: CGPoint(x: 1.12, y: -0.1),
            controlPoint2: CGPoint(x: 0.38, y: 1.17)
        ) { [weak self] in
            guard let self = self else { return }
            // Combine scale and translation into one transform
            let scale = CGAffineTransform(scaleX: 0.05, y: 0.05)
            let translate = CGAffineTransform(translationX: 0, y: isWin ? 60 : -200)
            self.transform = scale.concatenating(translate)
            
        }
        
        // Alpha animation: Animate both contentView and view alpha for UIVisualEffectView
        // This ensures the blur effect fades smoothly
        UIView.animate(withDuration: 0.15) {
            // Animate contentView alpha (works better with blur effects)
            self.alpha = 0.05
        }
        
        // Start transform animation immediately
        transformAnimator.startAnimation()
        
        // Complete when transform animation finishes (the primary animation)
        transformAnimator.addCompletion { _ in
            completion()
        }
    }
}

