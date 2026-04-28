//
//  AnyHornControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 3/18/26.
//

import UIKit

/// A SpecialtyControl for the "Any Horn" bet.
/// One-time bet that wins on any horn number (2, 3, 11, 12).
/// Payout: (bet amount / 4) × odds of the specific make.
class AnyHornControl: SpecialtyControl {

    init() {
        super.init(title: "Any", subtitle: "Horn", usesFixedControlHeight: false)
        // One-roll proposition; must clear on a miss like other horn controls (`createBetView` uses isPerpetual: false).
        isPerpetualBet = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
