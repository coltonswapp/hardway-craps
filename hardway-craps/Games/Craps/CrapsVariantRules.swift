//
//  CrapsVariantRules.swift
//  hardway-craps
//
//  Created by GPT on 3/27/26.
//

import Foundation

enum CrapsVariant: String, CaseIterable {
    case standard
    case crapless

    var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .crapless:
            return "Crapless"
        }
    }
}

enum ComeBetComeOutAction {
    case win
    case lose
    case establishPoint
    case none
}

enum DontPassComeOutAction {
    case win
    case lose
    case push
    case establishPoint
    case none
}

protocol CrapsVariantRules {
    var variant: CrapsVariant { get }
    var pointNumbers: Set<Int> { get }
    var orderedPointNumbers: [Int] { get }

    func passLineComeOutEvent(for total: Int) -> GameEvent
    func passLinePointEvent(for total: Int, pointNumber: Int) -> GameEvent

    func comeBetComeOutAction(for total: Int) -> ComeBetComeOutAction
    func dontPassComeOutAction(for total: Int) -> DontPassComeOutAction

    func fieldPayoutMultiplier(for total: Int) -> Double?
    func passLineOddsMultiplier(for point: Int) -> Double
    func dontPassOddsMultiplier(for point: Int) -> Double
    func maxOddsMultiplier(for point: Int) -> Int
}

struct StandardCrapsVariantRules: CrapsVariantRules {
    let variant: CrapsVariant = .standard
    let pointNumbers: Set<Int> = [4, 5, 6, 8, 9, 10]
    let orderedPointNumbers: [Int] = [4, 5, 6, 8, 9, 10]

    func passLineComeOutEvent(for total: Int) -> GameEvent {
        switch total {
        case 7, 11:
            return .passLineWin
        case 2, 3, 12:
            return .passLineLoss
        case 4, 5, 6, 8, 9, 10:
            return .pointEstablished(total)
        default:
            return .none
        }
    }

    func passLinePointEvent(for total: Int, pointNumber: Int) -> GameEvent {
        if total == pointNumber { return .pointMade }
        if total == 7 { return .sevenOut }
        return .none
    }

    func comeBetComeOutAction(for total: Int) -> ComeBetComeOutAction {
        switch total {
        case 7, 11:
            return .win
        case 2, 3, 12:
            return .lose
        case 4, 5, 6, 8, 9, 10:
            return .establishPoint
        default:
            return .none
        }
    }

    func dontPassComeOutAction(for total: Int) -> DontPassComeOutAction {
        switch total {
        case 2, 3:
            return .win
        case 12:
            return .push
        case 7, 11:
            return .lose
        case 4, 5, 6, 8, 9, 10:
            return .establishPoint
        default:
            return .none
        }
    }

    func fieldPayoutMultiplier(for total: Int) -> Double? {
        switch total {
        case 12:
            return 3.0
        case 2:
            return 2.0
        case 3, 4, 9, 10, 11:
            return 1.0
        default:
            return nil
        }
    }

    func passLineOddsMultiplier(for point: Int) -> Double {
        switch point {
        case 4, 10:
            return 2.0
        case 5, 9:
            return 1.5
        case 6, 8:
            return 1.2
        default:
            return 1.0
        }
    }

    func dontPassOddsMultiplier(for point: Int) -> Double {
        switch point {
        case 4, 10:
            return 0.5
        case 5, 9:
            return 2.0 / 3.0
        case 6, 8:
            return 5.0 / 6.0
        default:
            return 1.0
        }
    }

    func maxOddsMultiplier(for point: Int) -> Int {
        switch point {
        case 4, 10:
            return 3
        case 5, 9:
            return 4
        case 6, 8:
            return 5
        default:
            return 10
        }
    }
}

struct CraplessCrapsVariantRules: CrapsVariantRules {
    let variant: CrapsVariant = .crapless
    let pointNumbers: Set<Int> = [2, 3, 4, 5, 6, 8, 9, 10, 11, 12]
    let orderedPointNumbers: [Int] = [2, 3, 4, 5, 6, 8, 9, 10, 11, 12]

    func passLineComeOutEvent(for total: Int) -> GameEvent {
        if total == 7 {
            return .passLineWin
        }
        if pointNumbers.contains(total) {
            return .pointEstablished(total)
        }
        return .none
    }

    func passLinePointEvent(for total: Int, pointNumber: Int) -> GameEvent {
        if total == pointNumber { return .pointMade }
        if total == 7 { return .sevenOut }
        return .none
    }

    func comeBetComeOutAction(for total: Int) -> ComeBetComeOutAction {
        if total == 7 { return .win }
        if pointNumbers.contains(total) { return .establishPoint }
        return .none
    }

    func dontPassComeOutAction(for total: Int) -> DontPassComeOutAction {
        if total == 7 { return .lose }
        if pointNumbers.contains(total) { return .establishPoint }
        return .none
    }

    func fieldPayoutMultiplier(for total: Int) -> Double? {
        switch total {
        case 12:
            return 3.0
        case 2:
            return 2.0
        case 3, 4, 9, 10, 11:
            return 1.0
        default:
            return nil
        }
    }

    func passLineOddsMultiplier(for point: Int) -> Double {
        switch point {
        case 2, 12:
            return 6.0
        case 3, 11:
            return 3.0
        case 4, 10:
            return 2.0
        case 5, 9:
            return 1.5
        case 6, 8:
            return 1.2
        default:
            return 1.0
        }
    }

    func dontPassOddsMultiplier(for point: Int) -> Double {
        switch point {
        case 2, 12:
            return 1.0 / 6.0
        case 3, 11:
            return 1.0 / 3.0
        case 4, 10:
            return 0.5
        case 5, 9:
            return 2.0 / 3.0
        case 6, 8:
            return 5.0 / 6.0
        default:
            return 1.0
        }
    }

    func maxOddsMultiplier(for point: Int) -> Int {
        switch point {
        case 2, 12:
            return 6
        case 3, 11:
            return 5
        case 4, 10:
            return 3
        case 5, 9:
            return 4
        case 6, 8:
            return 5
        default:
            return 10
        }
    }
}

enum CrapsVariantRulesFactory {
    static func makeRules(for variant: CrapsVariant) -> CrapsVariantRules {
        switch variant {
        case .standard:
            return StandardCrapsVariantRules()
        case .crapless:
            return CraplessCrapsVariantRules()
        }
    }
}
