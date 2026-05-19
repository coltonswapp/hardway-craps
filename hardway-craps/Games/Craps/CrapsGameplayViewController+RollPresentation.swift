//
//  CrapsGameplayViewController+RollPresentation.swift
//  hardway-craps
//

import UIKit

private typealias Timing = CrapsAnimationTiming

extension CrapsGameplayViewController {
    struct PostRollCompletionPlan {
        let delay: TimeInterval
    }

    func presentRollResults(
        event: GameEvent,
        allWinMessages: [String],
        winningBets: [WinningBet],
        comeBetTotalBeforeHandling: Int,
        passLineOddsAmountBeforeOutcome: Int
    ) {
        if !winningBets.isEmpty {
            showGroupedBetResults(winningBets: winningBets)
        }

        finalizePostRollPresentation(
            event: event,
            allWinMessages: allWinMessages,
            winningBets: winningBets,
            comeBetTotalBeforeHandling: comeBetTotalBeforeHandling,
            passLineOddsAmountBeforeOutcome: passLineOddsAmountBeforeOutcome
        )
    }

    func makePostRollCompletionPlan(
        event: GameEvent,
        winningBets: [WinningBet],
        dontPassDidLose: Bool
    ) -> PostRollCompletionPlan {
        let scaledDelay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: event,
            hasWinningBets: !winningBets.isEmpty,
            dontPassDidLose: dontPassDidLose,
            applySpeedMultiplier: true
        )
        let unscaledDelay = CrapsRollOutcomePolicy.rollingStateUpdateDelay(
            event: event,
            hasWinningBets: !winningBets.isEmpty,
            dontPassDidLose: dontPassDidLose,
            applySpeedMultiplier: false
        )
        // Chips animate at scaled speed, but “Tap to Roll” should return on the same wall-clock beat as before game speed existed.
        let delay = max(scaledDelay, unscaledDelay)

        return PostRollCompletionPlan(delay: delay)
    }

    func performPostRollCompletion(using plan: PostRollCompletionPlan) {
        Timing.after(plan.delay) { [weak self] in
            self?.recordBalanceSnapshot()

            // Update session after roll completes (so app can be backgrounded/quit safely)
            self?.sessionManager.updateSession()

            self?.updateRollingState()
            self?.showTips()
        }
    }

    private func finalizePostRollPresentation(
        event: GameEvent,
        allWinMessages: [String],
        winningBets: [WinningBet],
        comeBetTotalBeforeHandling: Int,
        passLineOddsAmountBeforeOutcome: Int
    ) {
        // Show loss container if seven out.
        if case .sevenOut = event {
            var losingBets = 0
            for control in getAllBettingControls() {
                if control === dontPassControl {
                    continue
                }
                losingBets += control.betAmount
                losingBets += control.oddsAmount
            }
            losingBets += comeBetTotalBeforeHandling
            losingBets += passLineOddsAmountBeforeOutcome

            if losingBets > 0 && betsAreOn {
                showBetResult(amount: losingBets, isWin: false)
            }
        }

        if !allWinMessages.isEmpty {
            let combinedMessage = allWinMessages.joined(separator: " • ")
            Timing.after(Timing.UIFeedback.instructionTextDelay) { [weak self] in
                guard let self else { return }
                self.instructionLabel.showMessage(combinedMessage, shouldFade: false)
            }
        }

        let winningControls = winningBets.compactMap { $0.control as? PlainControl }
        clearOneTimeBets(excludingWinningControls: winningControls)
    }
}
