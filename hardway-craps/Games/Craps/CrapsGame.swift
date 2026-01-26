//
//  CrapsGame.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import Foundation

enum GameEvent {
    case passLineWin
    case passLineLoss
    case pointEstablished(Int)
    case pointMade
    case sevenOut
    case none
}

class CrapsGame {
    enum Phase {
        case comeOut
        case point(Int)
    }

    private(set) var phase: Phase = .comeOut

    var currentPoint: Int? {
        if case .point(let number) = phase { return number }
        return nil
    }

    var isPointPhase: Bool {
        if case .point = phase { return true }
        return false
    }

    func processRoll(_ total: Int) -> GameEvent {
        switch phase {
        case .comeOut:
            return processComeOutRoll(total)
        case .point(let pointNumber):
            return processPointRoll(total, pointNumber: pointNumber)
        }
    }

    private func processComeOutRoll(_ total: Int) -> GameEvent {
        switch total {
        case 7, 11:
            return .passLineWin
        case 2, 3, 12:
            return .passLineLoss
        case 4, 5, 6, 8, 9, 10:
            phase = .point(total)
            return .pointEstablished(total)
        default:
            return .none
        }
    }

    private func processPointRoll(_ total: Int, pointNumber: Int) -> GameEvent {
        if total == pointNumber {
            phase = .comeOut
            return .pointMade
        } else if total == 7 {
            phase = .comeOut
            return .sevenOut
        }
        return .none
    }
}
