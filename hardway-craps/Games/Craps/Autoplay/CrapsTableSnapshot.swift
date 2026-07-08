//
//  CrapsTableSnapshot.swift
//  hardway-craps
//

import Foundation

/// Pass-line phase snapshot for autoplay decisions (mirrors `CrapsGame.Phase` without exposing it here).
enum CrapsAutoplayPhase: Equatable {
  case comeOut
  case point(Int)
}

/// Read-only table state for `CrapsAutoplayer` — no UIKit, no control references.
struct CrapsTableSnapshot: Equatable {
  let phase: CrapsAutoplayPhase
  let balance: Int
  let betsAreOn: Bool
  let selectedChipValue: Int
  let passLineBet: Int
  let passLineOdds: Int
  let fieldBet: Int
  let hardwaysEnabled: Bool
  let makeEmEnabled: Bool
  let hornEnabled: Bool
  let variant: CrapsVariant
  /// Dice idle and rolling interaction enabled (matches post-roll `enableRolling`).
  let rollingGateOpen: Bool
  /// Physical dice animation in progress.
  let isDiceRolling: Bool
  /// Table rules allow requesting a roll now (`rollingGateOpen` and phase/bets gate).
  let canRoll: Bool

  var isComeOut: Bool {
    if case .comeOut = phase { return true }
    return false
  }

  var pointNumber: Int? {
    if case .point(let n) = phase { return n }
    return nil
  }

  /// Legacy gate that required the dice UI “tap to roll” enabled — blocked placing **pass** on come-out with no bets.
  var readyForAutoplayTick: Bool {
    rollingGateOpen && !isDiceRolling
  }

  /// Betting actions may run whenever dice are not physically rolling (even if roll UI is disabled before first bet).
  var allowsAutoplayBetPlacement: Bool {
    !isDiceRolling
  }
}
