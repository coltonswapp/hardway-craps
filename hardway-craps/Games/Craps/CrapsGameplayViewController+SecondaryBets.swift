//
//  CrapsGameplayViewController+SecondaryBets.swift
//  hardway-craps
//

import UIKit

extension CrapsGameplayViewController {
    struct SecondaryBetsResult {
        let dontPassDidLose: Bool
        let comeBetTotalBeforeHandling: Int
    }

    func processSecondaryBets(
        total: Int,
        event: GameEvent,
        wasInPointPhase: Bool,
        currentPointNumber: Int?,
        dontPassOddsBetAmount: Int,
        allWinMessages: inout [String],
        winningBets: inout [WinningBet]
    ) -> SecondaryBetsResult {
        var dontPassDidLose = false
        if let dontPassControl, dontPassControl.betAmount > 0 {
            let dontPassResult = handleDontPassBet(
                total: total,
                event: event,
                wasInPointPhase: wasInPointPhase,
                currentPoint: currentPointNumber,
                capturedOddsBetAmount: dontPassOddsBetAmount
            )
            if let message = dontPassResult.message {
                allWinMessages.append(message)
            }
            if let win = dontPassResult.winningBet {
                winningBets.append(win)
            }
            dontPassDidLose = dontPassResult.didLose
        }

        let comeBetTotalBeforeHandling = pointStack.getComeBetTotal()
        let (comeBetMessages, comeBetWins) = handleComeBets(total: total, event: event, wasInPointPhase: wasInPointPhase)
        allWinMessages.append(contentsOf: comeBetMessages)
        winningBets.append(contentsOf: comeBetWins)

        let (otherBetMessages, otherWins) = handleOtherBets(
            total,
            event: event,
            wasInPointPhase: wasInPointPhase
        )
        allWinMessages.append(contentsOf: otherBetMessages)
        winningBets.append(contentsOf: otherWins)

        let (ceMessages, ceWins) = handleCAndEBets(total: total)
        allWinMessages.append(contentsOf: ceMessages)
        winningBets.append(contentsOf: ceWins)

        return SecondaryBetsResult(
            dontPassDidLose: dontPassDidLose,
            comeBetTotalBeforeHandling: comeBetTotalBeforeHandling
        )
    }
}
