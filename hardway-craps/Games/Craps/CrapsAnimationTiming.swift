//
//  CrapsAnimationTiming.swift
//  hardway-craps
//

import Foundation

typealias CrapsAnimationTiming = GameAnimationTiming

struct GameAnimationTiming {

    private static let speedKey = "CrapsGameSpeed"

    /// Speed multiplier applied to all gameplay animations.
    /// 1.0 = normal, < 1.0 = faster, > 1.0 = slower.
    static var speedMultiplier: Double = {
        let stored = UserDefaults.standard.double(forKey: speedKey)
        return stored > 0 ? stored : 1.0
    }()

    static func setSpeed(_ multiplier: Double) {
        speedMultiplier = multiplier
        UserDefaults.standard.set(multiplier, forKey: speedKey)
    }

    static func scaled(_ base: TimeInterval) -> TimeInterval {
        base * speedMultiplier
    }

    static func after(_ delay: TimeInterval, execute work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Shared (universal chip motion primitives)

    struct Shared {
        static var flyDuration: TimeInterval { scaled(0.5) }
        static var fadeDuration: TimeInterval { scaled(0.2) }
        static var staggerRange: ClosedRange<Double> { 0...(0.15 * speedMultiplier) }
    }

    // MARK: - BonusBets (top of screen: hardways, horns, Any Horn, Make Em, C&E)

    struct BonusBets {
        static var winDelay: TimeInterval { scaled(0.3) }
        static var lossDelay: TimeInterval { scaled(0.5) }
        static var cAndELossDelay: TimeInterval { scaled(0.7) }
        static var cAndEFlyDuration: TimeInterval { scaled(0.52) }
        static var cAndEFadeDuration: TimeInterval { scaled(0.18) }
        static var cAndEStaggerRange: ClosedRange<Double> { 0...(0.12 * speedMultiplier) }
        static var makeEmResetDelay: TimeInterval { scaled(2.0) }
        static var sevenOutSweepDelay: TimeInterval { scaled(0.6) }
        static var oneTimeBetLossDelay: TimeInterval { scaled(0.7) }
    }

    // MARK: - PointStack (middle of screen: come bets on points, place bets, lay bets)

    struct PointStack {
        static var placeWinDelay: TimeInterval { scaled(0.2) }
        static var layWinBaseDelay: TimeInterval { scaled(0.2) }
        static var layWinStagger: TimeInterval { scaled(0.12) }
        static var layLossDelay: TimeInterval { scaled(0.55) }
        static var layLossStaggerRange: ClosedRange<Double> { 0...(0.12 * speedMultiplier) }
        static var comeMoveDelay: TimeInterval { scaled(0.15) }
        static var comeMoveDuration: TimeInterval { scaled(0.45) }
        static var comePendingMoveDelay: TimeInterval { scaled(2.0) }
        static var comeWinDescendDelay: TimeInterval { scaled(0.3) }
        static var comeWinApproachDuration: TimeInterval { scaled(0.6) }
        static var comeWinPause: TimeInterval { scaled(0.35) }
        static var comeWinToBalanceDuration: TimeInterval { scaled(0.5) }
        static var comeWinBetStagger: TimeInterval { scaled(0.08) }
        static var comeWinOddsStagger: TimeInterval { scaled(0.16) }
        static var comeLossClearDelay: TimeInterval { scaled(0.6) }
    }

    // MARK: - BottomControls (bottom of screen: pass line, don't pass, field, pending come)

    struct BottomControls {
        static var lineWinDelay: TimeInterval { scaled(0.5) }
        static var lineBetCollectionDelay: TimeInterval { scaled(0.85) }
        static var oddsWinDelay: TimeInterval { scaled(0.8) }
        static var lineLossDelay: TimeInterval { scaled(0.5) }
        static var oddsLossDelay: TimeInterval { scaled(0.5) }
        static var fieldWinDelay: TimeInterval { scaled(0.3) }
        static var pendingComeWinDelay: TimeInterval { scaled(0.3) }
        static var pendingComeLossDelay: TimeInterval { scaled(0.5) }
        static var oddsVisibilityDelay: TimeInterval { scaled(2.5) }
    }

    // MARK: - Dice (3D roll in flip dice control; scales with game speed)

    struct Dice {
        /// >1 slows the roll a bit vs chip / line payouts at the same game speed (see `speedMultiplier`).
        private static let rollPacingFactor: Double = 1.22
        static var tumbleDuration: TimeInterval { scaled(0.4 * rollPacingFactor) }
        static var settleDuration: TimeInterval { scaled(0.2 * rollPacingFactor) }
        /// Kept equal to tumble + settle so `onRollComplete` fires as dice finish settling.
        static var completionDelay: TimeInterval { scaled(0.6 * rollPacingFactor) }
    }

    // MARK: - UIFeedback (bet result display, instruction text)

    struct UIFeedback {
        static var betResultInitialDelay: TimeInterval { scaled(0.3) }
        static var betResultGroupSpacing: TimeInterval { scaled(0.2) }
        static var instructionTextDelay: TimeInterval { scaled(0.3) }
        static var betResultLossDelay: TimeInterval { scaled(0.3) }
    }

    // MARK: - Collect (manual collect button)

    struct Collect {
        static var controlStagger: TimeInterval { scaled(0.15) }
    }
}
