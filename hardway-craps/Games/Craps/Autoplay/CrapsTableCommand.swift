//
//  CrapsTableCommand.swift
//  hardway-craps
//

import Foundation

/// Imperative actions the autoplayer may request; executed by `CrapsGameplayViewController`.
enum CrapsTableCommand: Equatable {
  case setChip(Int)
  case placePassLine(Int)
  case placeField(Int)
  case placeAcross(PlaceAcrossAllocation)
  /// Single box place bet (autoplay stagger); skips current point in execute when applicable.
  case placeBetOnBox(number: Int, amount: Int)
  case placeOdds(Int)
  case placeRandomHardway(Int)
  case placeRandomHorn(Int)
  case toggleBetsOnOff
  case collectBets
  case rollDice
}
