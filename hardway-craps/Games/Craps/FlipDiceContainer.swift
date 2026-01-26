//
//  FlipDiceContainer.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit
import SceneKit

class FlipDiceContainer: UIControl {

    private let sceneView: SCNView = {
        let view = SCNView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false // Allow touches to pass through to parent control
        return view
    }()

    private let resultLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = .white
        label.text = ""
        label.isUserInteractionEnabled = false // Allow touches to pass through to parent control
        return label
    }()
    
    private let tapToRollLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .white
        label.text = "Tap to Roll"
        label.isUserInteractionEnabled = false // Allow touches to pass through to parent control
        return label
    }()

    private var diceScene: FlipDiceScene!
    private var isRollingEnabled: Bool = false
    private var isRolling: Bool = false

    var onRollStarted: (() -> Void)?
    var onRollComplete: ((Int, Int, Int) -> Void)?
    var onDisabledTap: (() -> Void)?

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
//        backgroundColor = .white.withAlphaComponent(0.2)

        // No rounded corners or background - completely transparent
        sceneView.layer.cornerRadius = 0
        sceneView.clipsToBounds = false

        addSubview(sceneView)
        addSubview(resultLabel)
        addSubview(tapToRollLabel)

        NSLayoutConstraint.activate([

            sceneView.topAnchor.constraint(equalTo: topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Result label at the top
            resultLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            resultLabel.centerYAnchor.constraint(equalTo: topAnchor, constant: 0),
            
            // Tap to roll label at the bottom
            tapToRollLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            tapToRollLabel.centerYAnchor.constraint(equalTo: bottomAnchor, constant: 0)
        ])

        setupScene()
    }

    private func setupScene() {
        // Create flip dice scene
        diceScene = FlipDiceScene()
        sceneView.scene = diceScene.scene
        sceneView.delegate = diceScene
    }

    // MARK: - UIControl Touch Tracking
    
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        super.beginTracking(touch, with: event)
        
        // Animate scale down on touch down
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
        
        return true
    }
    
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        
        // Animate scale back up
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.transform = .identity
        }
        
        // Check if touch ended inside bounds
        guard let touch = touch else { return }
        let location = touch.location(in: self)
        
        guard bounds.contains(location) else {
            // Touch ended outside bounds - don't roll
            return
        }
        
        // Check if rolling is enabled
        guard isRollingEnabled && !isRolling else {
            // Rolling is disabled - notify delegate to show message
            onDisabledTap?()
            HapticsHelper.failureHaptic()
            shakeDice()
            return
        }
        
        // Valid tap - roll the dice
        HapticsHelper.thwompHaptic()
        roll()
        
        UIView.animate(withDuration: 0.15) {
            self.resultLabel.alpha = 0
        }
    }
    
    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        
        // Animate scale back up without rolling
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.transform = .identity
        }
    }

    func roll() {
        guard !isRolling else { return }
        isRolling = true
        disableRolling()
        onRollStarted?()
        diceScene.roll { [weak self] value1, value2 in
            guard let self = self else { return }
            let total = value1 + value2
            self.setResultText("\(total)")
            
            self.onRollComplete?(value1, value2, total)
            
            HapticsHelper.superLightHaptic()
            
            // Set isRolling to false immediately after roll completes
            // The ViewController will handle re-enabling rolling via updateRollingState()
            self.isRolling = false
        }
    }
    
    func rollFixedTotal(_ total: Int) {
        guard !isRolling else { return }
        isRolling = true
        disableRolling()
        
        // Calculate die values that sum to the desired total
        // Ensure both dice are valid (1-6) and sum to total
        let die1: Int
        let die2: Int
        
        if total <= 7 {
            // For totals <= 7, die1 can be 1 to (total-1), die2 is the remainder
            die1 = max(1, min(6, total - 1))
            die2 = total - die1
        } else {
            // For totals > 7, die1 must be at least (total-6), die2 is the remainder
            die1 = max(1, min(6, total - 6))
            die2 = total - die1
        }
        
        // Ensure both dice are valid (1-6)
        guard die1 >= 1 && die1 <= 6 && die2 >= 1 && die2 <= 6 else {
            print("Invalid total for fixed roll: \(total)")
            isRolling = false
            return
        }
        
        // Hide result label during animation
        UIView.animate(withDuration: 0.15) {
            self.resultLabel.alpha = 0
        }
        
        // Animate the dice to show the calculated values
        diceScene.rollFixed(die1: die1, die2: die2) { [weak self] value1, value2 in
            guard let self = self else { return }
            let calculatedTotal = value1 + value2
            self.setResultText("\(calculatedTotal)")
            
            self.onRollComplete?(value1, value2, calculatedTotal)
            
            HapticsHelper.superLightHaptic()
            
            // Set isRolling to false immediately after roll completes
            // The ViewController will handle re-enabling rolling via updateRollingState()
            self.isRolling = false
        }
    }
    
    func enableRolling() {
        guard !isRolling else { return }
        isRollingEnabled = true
        
        let animator1 = UIViewPropertyAnimator(duration: 0.3, controlPoint1: CGPoint(x: 0.85, y: 0), controlPoint2: CGPoint(x: 0.24, y: 1.23), animations: { [weak self] in
            guard self != nil else { return }
            
            self?.tapToRollLabel.textColor = HardwayColors.betGray
            self?.tapToRollLabel.alpha = 1.0
            self?.tapToRollLabel.transform = .identity
        })
        
        animator1.startAnimation()
        
        tapToRollLabel.addShimmerEffect()
    }
    
    func disableRolling() {
        isRollingEnabled = false
        
        tapToRollLabel.removeShimmerEffect()
        
        let animator1 = UIViewPropertyAnimator(duration: 0.3, controlPoint1: CGPoint(x: 0.85, y: 0), controlPoint2: CGPoint(x: 0.24, y: 1.23), animations: { [weak self] in
            guard self != nil else { return }
            
            self?.tapToRollLabel.textColor = .quaternaryLabel
            self?.tapToRollLabel.alpha = 0.0
            
        })
        
        animator1.addCompletion { [weak self] _ in
            self?.tapToRollLabel.transform = CGAffineTransform(translationX: 0, y: 40)
        }
        
        animator1.startAnimation()
    }
    
    // MARK: - Animations
    
    private func shakeDice() {
        // Quick shake animation matching failureHaptic timing
        let shakeAnimation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shakeAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        shakeAnimation.duration = 0.3
        shakeAnimation.values = [-10, 10, -10, 10, -6, 6, -2, 2, 0]
        
        sceneView.layer.add(shakeAnimation, forKey: "shake")
    }
    
    private func setResultText(_ text: String) {
        resultLabel.text = text
        
        // Small jump animation when setting result
        resultLabel.transform = CGAffineTransform(translationX: 0, y: 20)
        resultLabel.alpha = 0
        
        let animator = UIViewPropertyAnimator(duration: 0.2, controlPoint1: CGPoint(x: 0.01, y: 1.13), controlPoint2: CGPoint(x: 0.32, y: 1.38), animations: {
            self.resultLabel.transform = .identity
            self.resultLabel.alpha = 1
        })
        
        animator.startAnimation()
    }
}
