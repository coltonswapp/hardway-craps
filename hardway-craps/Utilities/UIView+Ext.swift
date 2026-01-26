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
}
