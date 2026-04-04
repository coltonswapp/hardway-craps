//
//  CrapsGameplayViewController+PassLineOutcomes.swift
//  hardway-craps
//

import UIKit

private typealias Timing = CrapsAnimationTiming

extension CrapsGameplayViewController {
    func handlePassLineEvent(
        event: GameEvent,
        total: Int,
        currentPointNumber: Int?,
        passLineOddsBetAmount: Int,
        dontPassOddsBetAmount: Int,
        allWinMessages: inout [String],
        winningBets: inout [WinningBet]
    ) {
        switch event {
        case .passLineWin:
            handlePassLineWinEvent(total: total, allWinMessages: &allWinMessages, winningBets: &winningBets)

        case .passLineLoss:
            handlePassLineLossEvent(total: total)

        case .pointEstablished(let number):
            handlePointEstablishedEvent(number: number)

        case .pointMade:
            handlePointMadeEvent(
                currentPointNumber: currentPointNumber,
                passLineOddsBetAmount: passLineOddsBetAmount,
                dontPassOddsBetAmount: dontPassOddsBetAmount,
                allWinMessages: &allWinMessages,
                winningBets: &winningBets
            )

        case .sevenOut:
            handleSevenOutEvent()

        case .none:
            handleNoPassLineActionEvent()
        }
    }

    private func handlePassLineWinEvent(
        total: Int,
        allWinMessages: inout [String],
        winningBets: inout [WinningBet]
    ) {
        let passLineBetAmount = passLineControl.betAmount
        handlePassLineWin()
        if passLineBetAmount > 0 {
            allWinMessages.insert("You rolled \(total)! Pass Line wins!", at: 0)
            let winAmount = passLineControl.betAmount
            winningBets.append(WinningBet(control: passLineControl, winAmount: winAmount, odds: 1.0, isBonus: false, description: nil))
        }
    }

    private func handlePassLineLossEvent(total: Int) {
        let passLineBetAmount = passLineControl.betAmount
        handlePassLineLoss()
        instructionLabel.showMessage(
            instructionTextProvider.passLineLoss(total: total, hadPassLineBet: passLineBetAmount > 0),
            shouldFade: false
        )

        if passLineBetAmount > 0 && betsAreOn {
            Timing.after(Timing.UIFeedback.betResultLossDelay) { [weak self] in
                self?.showBetResult(amount: passLineBetAmount, isWin: false)
            }
        }
    }

    private func handlePointEstablishedEvent(number: Int) {
        pointStack.setPoint(number)
        instructionLabel.showMessage(instructionTextProvider.pointEstablished(point: number), shouldFade: false)
        if passLineBetPlacedDuringPointPhase && passLineControl.betAmount > 0 {
            passLineBetPlacedDuringPointPhase = false
        }
        if dontPassBetPlacedDuringPointPhase && (dontPassControl?.betAmount ?? 0) > 0 {
            dontPassBetPlacedDuringPointPhase = false
        }
        updatePassLineOddsVisibility()
    }

    private func handlePointMadeEvent(
        currentPointNumber: Int?,
        passLineOddsBetAmount: Int,
        dontPassOddsBetAmount: Int,
        allWinMessages: inout [String],
        winningBets: inout [WinningBet]
    ) {
        let passLineBetAmount = passLineControl.betAmount
        let oddsBetAmount = passLineOddsBetAmount
        let hadOddsBet = oddsBetAmount > 0
        let dontPassBetAmount = dontPassControl?.betAmount ?? 0

        if oddsBetAmount > 0 && passLineControl.oddsAmount == 0 {
            if !passLineControl.oddsBetStack!.isAnimatingPayout {
                passLineControl.oddsBetStack!.startPayoutAnimation()
            }
            passLineControl.oddsAmount = oddsBetAmount
        }

        handlePassLineWin()
        if oddsBetAmount > 0 {
            handlePassLineOddsWin(pointNumber: currentPointNumber, capturedBetAmount: oddsBetAmount)
        }

        pointStack.clearPoint()

        if passLineBetAmount > 0 {
            allWinMessages.insert("You hit the point! Pass Line wins!", at: 0)
        }

        NNTipManager.shared.dismissTip(CrapsTips.hitPointToWinTip)
        if passLineControl.betAmount > 0 {
            let winAmount = passLineControl.betAmount
            winningBets.append(WinningBet(control: passLineControl, winAmount: winAmount, odds: 1.0, isBonus: false, description: "Winner!"))
        }
        if hadOddsBet, let point = currentPointNumber {
            let oddsMultiplier = passLineManager.calculateOddsMultiplier(for: point)
            let winAmount = Int(Double(oddsBetAmount) * oddsMultiplier)
            winningBets.append(WinningBet(control: passLineControl, winAmount: winAmount, odds: oddsMultiplier, isBonus: false, description: nil))
        }

        let dontPassTotalLoss = dontPassBetAmount + dontPassOddsBetAmount
        if dontPassTotalLoss > 0 && betsAreOn {
            Timing.after(Timing.UIFeedback.betResultLossDelay) { [weak self] in
                self?.showBetResult(amount: dontPassTotalLoss, isWin: false)
            }
        }

        Timing.after(Timing.BottomControls.oddsVisibilityDelay) { [weak self] in
            self?.updatePassLineOddsVisibility()
        }
        if let point = currentPointNumber {
            sessionManager.trackPointMade(number: point)
        }
    }

    private func handleSevenOutEvent() {
        passLineControl.oddsBetStack?.endPayoutAnimation()

        let passLineBetAmount = passLineControl.betAmount
        let oddsAmount = passLineControl.oddsAmount
        let hadOddsBet = oddsAmount > 0

        if passLineBetAmount > 0 || hadOddsBet {
            passLineControl.oddsBetStack?.startBetCollection()

            if passLineBetAmount > 0 {
                passLineManager.processPassLineLoss(betAmount: passLineBetAmount)
            }
            if hadOddsBet {
                passLineManager.processPassLineOddsLoss(betAmount: oddsAmount)
            }

            flipDiceContainer.disableRolling()

            if passLineBetAmount > 0 {
                passLineManuallyRemoved = false
            }

            Timing.after(Timing.BottomControls.oddsLossDelay) { [weak self] in
                guard let self else { return }
                self.chipAnimator.animateChipsAwayFromOddsStack(from: self.passLineControl) {
                    self.passLineControl.oddsBetStack?.endBetCollection()
                    self.passLineControl.titleAlignment = .centered
                    self.updateCurrentBet()
                    self.updateRollingState()
                }
            }
        } else {
            updateCurrentBet()
        }

        handleSevenOut()
        pointStack.clearPoint()

        instructionLabel.showMessage(
            instructionTextProvider.sevenOut(hadPassLineBet: passLineBetAmount > 0),
            shouldFade: false
        )
        if passLineBetPlacedDuringPointPhase && passLineControl.betAmount > 0 {
            passLineBetPlacedDuringPointPhase = false
        }
        if dontPassBetPlacedDuringPointPhase && (dontPassControl?.betAmount ?? 0) > 0 {
            dontPassBetPlacedDuringPointPhase = false
        }
        updatePassLineOddsVisibility()
    }

    private func handleNoPassLineActionEvent() {
        if game.isPointPhase {
            if passLineBetPlacedDuringPointPhase && passLineControl.betAmount > 0 {
                passLineBetPlacedDuringPointPhase = false
            }
            if dontPassBetPlacedDuringPointPhase && (dontPassControl?.betAmount ?? 0) > 0 {
                dontPassBetPlacedDuringPointPhase = false
            }
            updatePassLineOddsVisibility()
        }
    }
}
