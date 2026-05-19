//
//  CrapsRollOutcomePolicy.swift
//  hardway-craps
//
//  Created by GPT on 3/27/26.
//

import Foundation

enum CrapsRollOutcomePolicy {
    static func rollingStateUpdateDelay(
        event: GameEvent,
        hasWinningBets: Bool,
        dontPassDidLose: Bool,
        applySpeedMultiplier: Bool = true
    ) -> TimeInterval {
        let pace: (TimeInterval) -> TimeInterval =
            applySpeedMultiplier ? { CrapsAnimationTiming.scaled($0) } : { $0 }

        if hasWinningBets {
            return pace(1.875)
        }

        switch event {
        case .sevenOut:
            return pace(2.0)
        case .pointMade:
            return dontPassDidLose ? pace(2.0) : pace(1.5)
        case .passLineLoss:
            return pace(2.0)
        case .passLineWin:
            return dontPassDidLose ? pace(2.0) : pace(0.1)
        case .pointEstablished, .none:
            return pace(0.1)
        }
    }
}
