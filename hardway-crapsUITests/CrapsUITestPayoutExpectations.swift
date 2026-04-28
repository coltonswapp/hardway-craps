import Foundation

/// Payout math for Craps UI tests — matches production rounding and multipliers.
///
/// **Source of truth in the app**
/// - Pass odds multipliers: `StandardCrapsVariantRules.passLineOddsMultiplier(for:)`
/// - Place multipliers: `PointControl.oddsMultiplier`
/// - Rounding: `Int(Double(amount) * multiplier)` (see `CrapsGameplayViewController` place wins,
///   `CrapsPassLineManager.calculateOddsPayout`, `handlePassLineWin` / `animateOddsWinnings` for pass).
///
/// Place wins credit **profit only** to balance (the working bet stays on the layout), matching
/// `animateWinnings(for: PlainControl, odds:)` for `PointControl`.
enum CrapsUITestPayoutExpectations {

  static func placeBetProfitCreditedToBalance(placeBet: Int, pointNumber: Int) -> Int {
    let mult = placeOddsMultiplier(for: pointNumber)
    return Int(Double(placeBet) * mult)
  }

  /// Net balance change when the pass line point is made: pass line pays 1:1 profit to balance (bet stays on the felt),
  /// and free odds pay full return `oddsBet + profit` to balance.
  static func balanceDeltaPassLineHitPoint(lineBet: Int, oddsBet: Int, point: Int) -> Int {
    let passLineProfit = Int(Double(lineBet) * 1.0)
    let oddsMult = passLineOddsMultiplier(for: point)
    let oddsProfit = Int(Double(oddsBet) * oddsMult)
    let oddsTotalReturned = oddsBet + oddsProfit
    return passLineProfit + oddsTotalReturned
  }

  // MARK: - Multipliers (keep aligned with app)

  private static func passLineOddsMultiplier(for point: Int) -> Double {
    switch point {
    case 4, 10: return 2.0
    case 5, 9: return 1.5
    case 6, 8: return 1.2
    default: return 1.0
    }
  }

  private static func placeOddsMultiplier(for point: Int) -> Double {
    switch point {
    case 2, 12: return 6.0
    case 3, 11: return 3.0
    case 4, 10: return 2.0
    case 5, 9: return 1.5
    case 6, 8: return 1.2
    default: return 1.0
    }
  }
}
