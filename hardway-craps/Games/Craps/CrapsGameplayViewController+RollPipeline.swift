//
//  CrapsGameplayViewController+RollPipeline.swift
//  hardway-craps
//

import UIKit

extension CrapsGameplayViewController {
    private func buildRollResolution(
        die1: Int,
        die2: Int,
        total: Int,
        event: GameEvent,
        wasInPointPhase: Bool,
        currentPointBeforeRoll: Int?,
        passLineOddsBetAmount: Int,
        dontPassOddsBetAmount: Int,
        passLineBetAmountBeforeOutcome: Int,
        dontPassBetAmountBeforeOutcome: Int,
        passLineOddsAmountBeforeOutcome: Int
    ) -> CrapsRollResolution {
        return CrapsRollResolution(
            die1: die1,
            die2: die2,
            total: total,
            event: event,
            wasInPointPhase: wasInPointPhase,
            currentPointBeforeRoll: currentPointBeforeRoll,
            passLineOddsBetAmount: passLineOddsBetAmount,
            dontPassOddsBetAmount: dontPassOddsBetAmount,
            passLineBetAmountBeforeOutcome: passLineBetAmountBeforeOutcome,
            dontPassBetAmountBeforeOutcome: dontPassBetAmountBeforeOutcome,
            passLineOddsAmountBeforeOutcome: passLineOddsAmountBeforeOutcome
        )
    }

    private func prepareRollContext(die1: Int, die2: Int, total: Int) -> CrapsRollResolution {
        // Disable rolling immediately to prevent rolling during animations.
        flipDiceContainer.disableRolling()

        // Track session and dismiss onboarding tip once rolling starts.
        sessionManager.incrementRollCount()
        sessionManager.recordDiceOutcome(total: total)
        NNTipManager.shared.dismissTip(CrapsTips.comeOutRollTip)

        let balanceBeforeRoll = balance
        sessionManager.updateLastBalanceBeforeRoll(balanceBeforeRoll)

        pendingBetSizeSnapshot =
            getAllBettingControls().reduce(0) { $0 + $1.betAmount }
            + (comeBetControl?.betAmount ?? 0)
            + (cAndETriZoneControl?.totalBetAmount ?? 0)
            + pointStack.getComeBetTotal()

        let wasInPointPhase = game.isPointPhase
        let currentPointNumber = game.currentPoint
        let passLineOddsBetAmount = passLineControl.oddsAmount
        let dontPassOddsBetAmount = dontPassControl?.oddsAmount ?? 0

        if wasInPointPhase && passLineOddsBetAmount > 0 {
            passLineControl.oddsBetStack?.startPayoutAnimation()
        }
        if wasInPointPhase && dontPassOddsBetAmount > 0 {
            dontPassControl?.oddsBetStack?.startPayoutAnimation()
        }

        let event = game.processRoll(total)

        let balanceAfterRoll = balance
        if balanceAfterRoll < balanceBeforeRoll {
            sessionManager.updateLastBalanceBeforeRoll(balanceBeforeRoll)
        }

        let passLineBetAmountBeforeOutcome = passLineControl.betAmount
        let dontPassBetAmountBeforeOutcome = dontPassControl?.betAmount ?? 0
        let passLineOddsAmountBeforeOutcome = passLineControl.oddsAmount

        let resolution = buildRollResolution(
            die1: die1,
            die2: die2,
            total: total,
            event: event,
            wasInPointPhase: wasInPointPhase,
            currentPointBeforeRoll: currentPointNumber,
            passLineOddsBetAmount: passLineOddsBetAmount,
            dontPassOddsBetAmount: dontPassOddsBetAmount,
            passLineBetAmountBeforeOutcome: passLineBetAmountBeforeOutcome,
            dontPassBetAmountBeforeOutcome: dontPassBetAmountBeforeOutcome,
            passLineOddsAmountBeforeOutcome: passLineOddsAmountBeforeOutcome
        )

        if resolution.total == 7 {
            sessionManager.trackSevenRolled()
        }

        return resolution
    }

    func handleRollResult(die1: Int, die2: Int, total: Int) {
        let resolution = prepareRollContext(die1: die1, die2: die2, total: total)
        let event = resolution.event
        let wasInPointPhase = resolution.wasInPointPhase
        let currentPointNumber = resolution.currentPointBeforeRoll
        let passLineOddsBetAmount = resolution.passLineOddsBetAmount
        let dontPassOddsBetAmount = resolution.dontPassOddsBetAmount
        let passLineBetAmountBeforeOutcome = resolution.passLineBetAmountBeforeOutcome
        let dontPassBetAmountBeforeOutcome = resolution.dontPassBetAmountBeforeOutcome
        let passLineOddsAmountBeforeOutcome = resolution.passLineOddsAmountBeforeOutcome

        // Collect all win messages and winning bets
        var allWinMessages: [String] = []
        var winningBets: [WinningBet] = []

        processBonusBets(
            die1: die1,
            die2: die2,
            total: total,
            wasInPointPhase: wasInPointPhase,
            allWinMessages: &allWinMessages,
            winningBets: &winningBets
        )

        handlePassLineEvent(
            event: event,
            total: total,
            currentPointNumber: currentPointNumber,
            passLineOddsBetAmount: passLineOddsBetAmount,
            dontPassOddsBetAmount: dontPassOddsBetAmount,
            allWinMessages: &allWinMessages,
            winningBets: &winningBets
        )

        let secondaryBetsResult = processSecondaryBets(
            total: total,
            event: event,
            wasInPointPhase: wasInPointPhase,
            currentPointNumber: currentPointNumber,
            dontPassOddsBetAmount: dontPassOddsBetAmount,
            allWinMessages: &allWinMessages,
            winningBets: &winningBets
        )
        let dontPassDidLose = secondaryBetsResult.dontPassDidLose
        let comeBetTotalBeforeHandling = secondaryBetsResult.comeBetTotalBeforeHandling

        presentRollResults(
            event: event,
            allWinMessages: allWinMessages,
            winningBets: winningBets,
            comeBetTotalBeforeHandling: comeBetTotalBeforeHandling,
            passLineOddsAmountBeforeOutcome: passLineOddsAmountBeforeOutcome
        )

        let completionPlan = makePostRollCompletionPlan(
            event: event,
            winningBets: winningBets,
            dontPassDidLose: dontPassDidLose,
            passLineBetAmountBeforeOutcome: passLineBetAmountBeforeOutcome,
            dontPassBetAmountBeforeOutcome: dontPassBetAmountBeforeOutcome
        )
        performPostRollCompletion(using: completionPlan)
    }

    private func processBonusBets(
        die1: Int,
        die2: Int,
        total: Int,
        wasInPointPhase: Bool,
        allWinMessages: inout [String],
        winningBets: inout [WinningBet]
    ) {
        // Hardways: lose on 7 only during point phase, otherwise evaluate wins/soft losses.
        if total == 7 && wasInPointPhase {
            handleHardwayLoss()
        } else if total != 7 {
            let (hardwayMessages, hardwayWins) = handleHardwayBets(die1: die1, die2: die2, total: total)
            allWinMessages.append(contentsOf: hardwayMessages)
            winningBets.append(contentsOf: hardwayWins)
        }

        let (hornMessages, hornWins) = handleHornBets(die1: die1, die2: die2, total: total)
        allWinMessages.append(contentsOf: hornMessages)
        winningBets.append(contentsOf: hornWins)

        let (makeEmMessages, makeEmWins) = handleMakeEmBets(total: total)
        allWinMessages.append(contentsOf: makeEmMessages)
        winningBets.append(contentsOf: makeEmWins)
    }
}
