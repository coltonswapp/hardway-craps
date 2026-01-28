//
//  UIView+Ext.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/26/26.
//
import UIKit

extension UIView {
    /// Fades in the view with optional spring animation
    func fadeIn(duration: TimeInterval = 0.3, 
                springDamping: CGFloat = 0.85, 
                velocity: CGFloat = 0.4, 
                completion: ((Bool) -> Void)? = nil) {
        self.isHidden = false
        UIView.animate(
            withDuration: duration, 
            delay: 0, 
            usingSpringWithDamping: springDamping, 
            initialSpringVelocity: velocity, 
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: {
                self.alpha = 1
                self.transform = .identity
            },
            completion: completion
        )
    }
    
    /// Fades out the view and optionally hides it
    func fadeOut(duration: TimeInterval = 0.3, 
                 hideOnComplete: Bool = true,
                 completion: ((Bool) -> Void)? = nil) {
        UIView.animate(
            withDuration: duration, 
            delay: 0, 
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        } completion: { finished in
            if hideOnComplete {
                self.isHidden = true
                self.transform = .identity
            }
            completion?(finished)
        }
    }
    
    func scaleAnimation(scaleTo: CGFloat = 1.3, duration: TimeInterval = 0.3) {
        let scaleAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
        
        scaleAnimation.values = [
            1.0,     // Start normal
            scaleTo, // Scale up
            1.0      // Back to normal
        ]
        
        scaleAnimation.keyTimes = [
            0,    // Start
            0.5,  // Peak scale at middle
            1.0   // End
        ]
        
        scaleAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn)
        ]
        
        scaleAnimation.duration = duration
        
        self.layer.add(scaleAnimation, forKey: "scaleAnimation")
    }
    
    func errorShake(angle: CGFloat = 0.1, duration: TimeInterval = 0.4) {
        let rotationAnimation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        
        // Convert angles to radians
        let angleInRadians = angle * .pi
        
        rotationAnimation.values = [
            0,                  // Start position
            -angleInRadians,    // Rotate counterclockwise
            angleInRadians,     // Rotate clockwise
            -angleInRadians/2,  // Smaller counterclockwise
            angleInRadians/4,   // Smaller clockwise
            0                   // Back to center
        ]
        
        rotationAnimation.keyTimes = [
            0,    // Start
            0.2,  // First rotation
            0.4,  // Second rotation
            0.6,  // Third rotation
            0.8,  // Fourth rotation
            1.0   // End
        ]
        
        rotationAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        
        rotationAnimation.duration = duration
        
        self.layer.add(rotationAnimation, forKey: "errorShakeAnimation")
    }
}
