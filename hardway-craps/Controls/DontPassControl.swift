//
//  DontPassControl.swift
//  hardway-craps
//
//  Created by Claude Code on 1/29/26.
//

import UIKit

class DontPassControl: PlainControl {

    /// Override to animate winnings to the left (similar to field control)
    override var winningsAnimationOffset: CGPoint {
        return CGPoint(x: -30, y: 0)  // Offset 30 points to the left
    }

    init(title: String) {
        super.init(title: title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
