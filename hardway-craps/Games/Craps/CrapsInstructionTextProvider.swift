//
//  CrapsInstructionTextProvider.swift
//  hardway-craps
//
//  Created by GPT on 3/27/26.
//

import Foundation

struct CrapsInstructionTextProvider {
    let variant: CrapsVariant

    func initialInstruction() -> String {
        switch variant {
        case .standard:
            return "Place a Pass Line bet to begin!"
        case .crapless:
            return "Place a line bet to begin Crapless!"
        }
    }

    func pointEstablished(point: Int) -> String {
        return "Point is \(point)! Roll the point again to win."
    }

    func passLineLoss(total: Int, hadPassLineBet: Bool) -> String {
        switch variant {
        case .standard:
            if hadPassLineBet {
                return "Craps! You rolled \(total). Pass Line loses."
            }
            return "Craps! You rolled \(total)."
        case .crapless:
            if hadPassLineBet {
                return "You rolled \(total). Pass Line loses."
            }
            return "You rolled \(total)."
        }
    }

    func sevenOut(hadPassLineBet: Bool) -> String {
        if hadPassLineBet {
            return "*$@#! Seven out! Place a new Pass Line bet to continue."
        }
        return "*$@#! Seven out!"
    }

    func dontPassWin(total: Int) -> String {
        return "Don't Pass wins on \(total)!"
    }

    func dontPassPush(total: Int) -> String {
        switch variant {
        case .standard:
            return "Push! \(total) is a tie for Don't Pass."
        case .crapless:
            return "No action for Don't Pass on \(total)."
        }
    }

    func comeBetPointWin(total: Int) -> String {
        return "Come bet on \(total) wins!"
    }

    func comeBetComeOutWin(total: Int) -> String {
        return "Come bet wins on \(total)!"
    }

    func comeBetComeOutLoss(total: Int) -> String? {
        switch variant {
        case .standard:
            return "Come bet loses on \(total)."
        case .crapless:
            return nil
        }
    }
}
