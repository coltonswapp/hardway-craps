//
//  NNLoadingSpinner.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/26/26.
//


import UIKit

class NNLoadingSpinner: UIView {
    private let backgroundLayer = CAShapeLayer()
    private let spinningLayer = CAShapeLayer()
    private var rotationDuration: CFTimeInterval = 0.45  // Default 1 second per rotation
    
    private lazy var stateImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = 0
        return imageView
    }()
    
    private var currentColor: UIColor = .systemBlue
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSpinner()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSpinner()
    }
    
    private func setupSpinner() {
        // Add stateImageView first
        addSubview(stateImageView)
        NSLayoutConstraint.activate([
            stateImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stateImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stateImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.6),
            stateImageView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.6)
        ])
        
        // Create circular path centered in the view
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 2
        let path = UIBezierPath(arcCenter: center,
                               radius: radius,
                               startAngle: 0,
                               endAngle: 2 * .pi,
                               clockwise: true)
        
        // Setup background circle layer
        backgroundLayer.frame = bounds
        backgroundLayer.path = path.cgPath
        backgroundLayer.fillColor = UIColor.clear.cgColor
        backgroundLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.4).cgColor
        backgroundLayer.lineWidth = 3
        backgroundLayer.lineCap = .round
        
        // Setup spinning layer
        spinningLayer.frame = bounds
        spinningLayer.path = path.cgPath
        spinningLayer.fillColor = UIColor.clear.cgColor
        spinningLayer.strokeColor = UIColor.systemBlue.cgColor
        spinningLayer.lineWidth = 3
        spinningLayer.lineCap = .round
        spinningLayer.strokeEnd = 0.3 // Only show part of the circle
        
        // Add layers (no need to set position since path is already centered)
        layer.addSublayer(backgroundLayer)
        layer.addSublayer(spinningLayer)
        
        startSpinningAnimation()
    }
    
    private func startSpinningAnimation() {
        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation")
        rotationAnimation.fromValue = 0
        rotationAnimation.toValue = 2 * Double.pi
        rotationAnimation.duration = rotationDuration  // Use the configurable duration
        rotationAnimation.repeatCount = .infinity
        rotationAnimation.isRemovedOnCompletion = false
        rotationAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        
        spinningLayer.add(rotationAnimation, forKey: "rotation")
    }
    
    func setSpeed(duration: CFTimeInterval) {
        rotationDuration = duration
        // Restart animation with new duration
        spinningLayer.removeAnimation(forKey: "rotation")
        startSpinningAnimation()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update frames and paths for new bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 2
        let path = UIBezierPath(arcCenter: center,
                               radius: radius,
                               startAngle: 0,
                               endAngle: 2 * .pi,
                               clockwise: true)
        
        backgroundLayer.frame = bounds
        backgroundLayer.path = path.cgPath
        
        spinningLayer.frame = bounds
        spinningLayer.path = path.cgPath
    }
    
    func configure(with color: UIColor) {
        currentColor = color
        backgroundLayer.strokeColor = color.withAlphaComponent(0.4).cgColor
        spinningLayer.strokeColor = color.cgColor
        stateImageView.tintColor = color
    }
    
    func reset() {
        // Reset layers opacity
        backgroundLayer.opacity = 1
        spinningLayer.opacity = 1
        
        // Reset state image
        stateImageView.alpha = 0
        stateImageView.transform = .identity
        
        // Restart spinning animation
        startSpinningAnimation()
    }
    
    func animateState(success: Bool, completion: (() -> Void)? = nil) {
        // Create the appropriate image
        let imageName = success ? "checkmark" : "xmark"
        let configuration = UIImage.SymbolConfiguration(pointSize: bounds.width * 0.6, weight: .bold)
        stateImageView.image = UIImage(systemName: imageName, withConfiguration: configuration)?.withTintColor(currentColor, renderingMode: .alwaysTemplate)
        
        // Stop spinning animation
        spinningLayer.removeAnimation(forKey: "rotation")
        
        // Hide spinner layers
        UIView.animate(withDuration: 0.2) {
            self.backgroundLayer.opacity = 0
            self.spinningLayer.opacity = 0
        }
        
        // Show and bounce the state image
        stateImageView.alpha = 1
        
        var animation: (() -> Void)? = nil
        
        // Trigger appropriate haptic
        if success {
            HapticsHelper.lightHaptic()
            animation = { self.stateImageView.scaleAnimation(scaleTo: 1.7, duration: 0.15) }
        } else {
            HapticsHelper.failureHaptic()
            animation = {
                self .stateImageView.errorShake()
                self.stateImageView.scaleAnimation(scaleTo: 1.7, duration: 0.15)
            }
        }
        
        UIView.animate(withDuration: 0.2,
                      delay: 0,
                      usingSpringWithDamping: 0.5,
                      initialSpringVelocity: 0.5,
                      options: [],
                      animations: {
            animation!()
            
        }, completion: { _ in
            // Wait 2 seconds then reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                completion?()
            }
        })
    }
} 
