//
//  PassLineControl.swift
//  hardway-craps
//

import UIKit

/// Pass line uses the shared `PlainControl` + `OddsBetStack` layout; the line-bet payout chip
/// looked slightly too far left vs. the visible line chip, so we nudge its landing X toward the chip.
final class PassLineControl: PlainControl {

  override var originalBetWinningsOffset: CGPoint {
    let p = super.originalBetWinningsOffset
    return CGPoint(x: p.x - 4, y: p.y)
  }
}
