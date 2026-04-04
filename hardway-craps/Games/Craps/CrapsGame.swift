//
//  CrapsGame.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import Foundation

enum GameEvent: Equatable {
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

    /// Box concrete rule types instead of storing a `CrapsVariantRules` existential on the instance.
    private enum RulesStorage {
        case standard(StandardCrapsVariantRules)
        case crapless(CraplessCrapsVariantRules)

        static func box(_ rules: CrapsVariantRules) -> RulesStorage {
            if let s = rules as? StandardCrapsVariantRules {
                return .standard(s)
            }
            if let c = rules as? CraplessCrapsVariantRules {
                return .crapless(c)
            }
            preconditionFailure("Add a RulesStorage case for new CrapsVariantRules types")
        }
    }

    private(set) var phase: Phase = .comeOut
    private var rulesStorage: RulesStorage

    var rules: CrapsVariantRules {
        switch rulesStorage {
        case .standard(let r): return r
        case .crapless(let r): return r
        }
    }

    init(rules: CrapsVariantRules = StandardCrapsVariantRules()) {
        rulesStorage = RulesStorage.box(rules)
    }

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

    func updateRules(_ rules: CrapsVariantRules) {
        rulesStorage = RulesStorage.box(rules)

        // If current point is not valid in the new variant, reset safely.
        if case .point(let number) = phase, !self.rules.pointNumbers.contains(number) {
            phase = .comeOut
        }
    }

    private func processComeOutRoll(_ total: Int) -> GameEvent {
        let event = rules.passLineComeOutEvent(for: total)
        if case .pointEstablished(let number) = event {
            phase = .point(number)
        }
        return event
    }

    private func processPointRoll(_ total: Int, pointNumber: Int) -> GameEvent {
        let event = rules.passLinePointEvent(for: total, pointNumber: pointNumber)
        switch event {
        case .pointMade, .sevenOut:
            phase = .comeOut
        default:
            break
        }
        return event
    }
}
