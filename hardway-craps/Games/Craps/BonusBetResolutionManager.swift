//
//  BonusBetResolutionManager.swift
//  hardway-craps
//

import UIKit

/// Structured result from resolving a single bonus bet against a dice outcome.
struct BonusBetResolutionResult {
    let control: PlainControl
    let winAmount: Int
    let oddsMultiplier: Double
    let description: String
    let isWin: Bool
    let isSoftLoss: Bool
    let isNewMakeEmNumber: Bool
    let markTotal: Int?
}

/// Resolves bonus bets (hardways, horns, make-em) against dice outcomes,
/// delegating evaluation to `CrapsSpecialBetsManager` and returning
/// structured results the VC can animate.
final class BonusBetResolutionManager {

    private let specialBetsManager: CrapsSpecialBetsManager

    init(specialBetsManager: CrapsSpecialBetsManager) {
        self.specialBetsManager = specialBetsManager
    }

    // MARK: - Hardways

    func resolveHardwayBets(
        die1: Int, die2: Int, total: Int,
        hardwayView: QuadBetView?
    ) -> [BonusBetResolutionResult] {
        guard let hardwayView else { return [] }
        var results: [BonusBetResolutionResult] = []

        for arrangedSubview in hardwayView.betStack.arrangedSubviews {
            guard let columnStack = arrangedSubview as? UIStackView else { continue }
            for columnSubview in columnStack.arrangedSubviews {
                guard let control = columnSubview as? SmallControl,
                      control.betAmount > 0 else { continue }

                let eval = specialBetsManager.evaluateHardwayBet(
                    die1: die1,
                    die2: die2,
                    hardwayDieValue: control.dieValue1,
                    betAmount: control.betAmount,
                    oddsString: control.odds
                )

                results.append(BonusBetResolutionResult(
                    control: control,
                    winAmount: eval.isWin ? eval.winAmount! : 0,
                    oddsMultiplier: eval.isWin ? eval.oddsMultiplier! : 0,
                    description: "Hard \(eval.total)",
                    isWin: eval.isWin,
                    isSoftLoss: eval.isSoftWayLoss,
                    isNewMakeEmNumber: false,
                    markTotal: nil
                ))
            }
        }
        return results
    }

    // MARK: - Horns

    func resolveHornBets(
        die1: Int, die2: Int, total: Int,
        hornView: QuadBetView?
    ) -> [BonusBetResolutionResult] {
        guard let hornView else { return [] }
        var results: [BonusBetResolutionResult] = []

        for arrangedSubview in hornView.betStack.arrangedSubviews {
            guard let columnStack = arrangedSubview as? UIStackView else { continue }
            for columnSubview in columnStack.arrangedSubviews {
                if let anyHorn = columnSubview as? AnyHornControl, anyHorn.betAmount > 0 {
                    guard let eval = specialBetsManager.evaluateAnyHornBet(
                        die1: die1, die2: die2, betAmount: anyHorn.betAmount
                    ) else { continue }

                    results.append(BonusBetResolutionResult(
                        control: anyHorn,
                        winAmount: eval.winAmount!,
                        oddsMultiplier: eval.oddsMultiplier!,
                        description: eval.hornName,
                        isWin: true,
                        isSoftLoss: false,
                        isNewMakeEmNumber: false,
                        markTotal: nil
                    ))
                    continue
                }

                guard let control = columnSubview as? SmallControl,
                      control.betAmount > 0 else { continue }

                let eval = specialBetsManager.evaluateHornBet(
                    die1: die1,
                    die2: die2,
                    hornDieValue1: control.dieValue1,
                    hornDieValue2: control.dieValue2,
                    betAmount: control.betAmount,
                    oddsString: control.odds
                )

                if eval.isWin {
                    results.append(BonusBetResolutionResult(
                        control: control,
                        winAmount: eval.winAmount!,
                        oddsMultiplier: eval.oddsMultiplier!,
                        description: eval.hornName,
                        isWin: true,
                        isSoftLoss: false,
                        isNewMakeEmNumber: false,
                        markTotal: nil
                    ))
                }
            }
        }
        return results
    }

    // MARK: - Make Em

    func resolveMakeEmBets(
        total: Int,
        makeEmView: UIView?
    ) -> [BonusBetResolutionResult] {
        guard let makeEmView,
              let makeEmStack = makeEmView.subviews.first(where: { $0 is UIStackView }) as? UIStackView
        else { return [] }

        var results: [BonusBetResolutionResult] = []

        for arrangedSubview in makeEmStack.arrangedSubviews {
            if let makeEmAll = arrangedSubview as? MakeEmAllControl, makeEmAll.betAmount > 0 {
                let eval = specialBetsManager.evaluateMakeEmBet(
                    total: total,
                    betName: "Make Em All",
                    targetNumbers: makeEmAll.numbers,
                    hitNumbers: makeEmAll.hitNumbers,
                    betAmount: makeEmAll.betAmount,
                    oddsString: makeEmAll.odds
                )
                results.append(BonusBetResolutionResult(
                    control: makeEmAll,
                    winAmount: eval.isWin ? eval.winAmount! : 0,
                    oddsMultiplier: eval.isWin ? eval.oddsMultiplier! : 0,
                    description: "Make Em All",
                    isWin: eval.isWin,
                    isSoftLoss: false,
                    isNewMakeEmNumber: eval.isNewNumber,
                    markTotal: eval.isNewNumber ? total : nil
                ))
                continue
            }

            guard let control = arrangedSubview as? MultiBetControl,
                  control.betAmount > 0 else { continue }

            let isMakeEmSmall = control.numbers == [2, 3, 4, 5, 6]
            let betName = isMakeEmSmall ? "Small" : "Tall"

            let eval = specialBetsManager.evaluateMakeEmBet(
                total: total,
                betName: betName,
                targetNumbers: control.numbers,
                hitNumbers: control.hitNumbers,
                betAmount: control.betAmount,
                oddsString: control.odds
            )

            results.append(BonusBetResolutionResult(
                control: control,
                winAmount: eval.isWin ? eval.winAmount! : 0,
                oddsMultiplier: eval.isWin ? eval.oddsMultiplier! : 0,
                description: betName,
                isWin: eval.isWin,
                isSoftLoss: false,
                isNewMakeEmNumber: eval.isNewNumber,
                markTotal: eval.isNewNumber ? total : nil
            ))
        }
        return results
    }
}
