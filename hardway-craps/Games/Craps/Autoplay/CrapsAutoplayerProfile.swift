//
//  CrapsAutoplayerProfile.swift
//  hardway-craps
//

import Foundation

enum CrapsAutoplayerProfileKind: CaseIterable {
  case railbird
  case placePlayer
  case gambler
  case conservative
}

/// Tunable odds / behavior knobs per personality.
struct CrapsAutoplayerProfile: Equatable {
  let kind: CrapsAutoplayerProfileKind

  /// Chance to take pass-line odds when eligible (0...1).
  let oddsTakeProbability: Double
  /// Relative appetite for field bets vs pass on come-out (0...1).
  let fieldLean: Double
  /// Chance to fire a place-across spread when affordable on come-out / between points.
  let placeAcrossProbability: Double
  /// Chance to toggle bets OFF after some rolls when point is off or after seven-out.
  let toggleBetsOffProbability: Double
  /// Chance to collect props after seven-out (when bets ON).
  let collectAfterSevenOutProbability: Double
  /// Chance to sprinkle a random hardway when enabled.
  let hardwaySprinkleProbability: Double
  /// Chance to sprinkle horn when enabled.
  let hornSprinkleProbability: Double

  static func random() -> CrapsAutoplayerProfile {
    let pick = CrapsAutoplayerProfileKind.allCases.randomElement() ?? .railbird
    return .preset(pick)
  }

  static func preset(_ kind: CrapsAutoplayerProfileKind) -> CrapsAutoplayerProfile {
    switch kind {
    case .railbird:
      return CrapsAutoplayerProfile(
        kind: kind,
        oddsTakeProbability: 0.45,
        fieldLean: 0.65,
        placeAcrossProbability: 0.08,
        toggleBetsOffProbability: 0.08,
        collectAfterSevenOutProbability: 0.08,
        hardwaySprinkleProbability: 0.06,
        hornSprinkleProbability: 0.12
      )
    case .placePlayer:
      return CrapsAutoplayerProfile(
        kind: kind,
        oddsTakeProbability: 0.55,
        fieldLean: 0.35,
        placeAcrossProbability: 0.42,
        toggleBetsOffProbability: 0.18,
        collectAfterSevenOutProbability: 0.12,
        hardwaySprinkleProbability: 0.04,
        hornSprinkleProbability: 0.05
      )
    case .gambler:
      return CrapsAutoplayerProfile(
        kind: kind,
        oddsTakeProbability: 0.72,
        fieldLean: 0.55,
        placeAcrossProbability: 0.2,
        toggleBetsOffProbability: 0.05,
        collectAfterSevenOutProbability: 0.06,
        hardwaySprinkleProbability: 0.22,
        hornSprinkleProbability: 0.28
      )
    case .conservative:
      return CrapsAutoplayerProfile(
        kind: kind,
        oddsTakeProbability: 0.22,
        fieldLean: 0.25,
        placeAcrossProbability: 0.15,
        toggleBetsOffProbability: 0.35,
        collectAfterSevenOutProbability: 0.18,
        hardwaySprinkleProbability: 0.02,
        hornSprinkleProbability: 0.03
      )
    }
  }
}
