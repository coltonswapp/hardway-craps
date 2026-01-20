//
//  PassthroughWindow.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/16/26.
//

import UIKit

final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }
        // Only return the hit view if it's not the root view controller's view
        return rootViewController?.view == hitView ? nil : hitView
    }
}
