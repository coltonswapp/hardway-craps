//
//  CrapsRollOutcomePolicy.swift
//  hardway-craps
//
//  Created by GPT on 3/27/26.
//

import Foundation

enum CrapsRollOutcomePolicy {
    static func shouldApplyRebet(
        event: GameEvent,
        passLineBetAmountBeforeOutcome: Int,
        dontPassBetAmountBeforeOutcome: Int,
        dontPassDidLose: Bool,
        didDontPassWin: Bool,
        currentDontPassBetAmount: Int
    ) -> Bool {
        switch event {
        case .passLineWin, .passLineLoss:
            return true
        case .pointMade, .sevenOut:
            let hadPassLineBet = passLineBetAmountBeforeOutcome > 0
            let dontPassHadOutcome = (dontPassBetAmountBeforeOutcome > 0 && dontPassDidLose) || didDontPassWin
            return hadPassLineBet || dontPassHadOutcome
        case .pointEstablished, .none:
            let dontPassHadOutcome = (currentDontPassBetAmount > 0 && dontPassDidLose) || didDontPassWin
            return dontPassHadOutcome
        }
    }

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
