//
//  PlaceAcrossAutoplayCommands.swift
//  hardway-craps
//

import Foundation

enum PlaceAcrossAutoplayCommands {

  /// One command per place box, matching `applyPlaceAcross` ordering but omitting `skipBox` (usually current point).
  static func staggeredPlaceBets(allocation: PlaceAcrossAllocation, skipBox: Int?) -> [CrapsTableCommand] {
    let rules = CrapsVariantRulesFactory.makeRules(for: allocation.variant)
    let insideBoxes: Set<Int> = [6, 8]
    let ordered = rules.orderedPointNumbers
    let outsidePoints = ordered.filter { !insideBoxes.contains($0) }
    let insidePoints = ordered.filter { insideBoxes.contains($0) }

    var cmds: [CrapsTableCommand] = []
    for n in outsidePoints {
      if let s = skipBox, n == s { continue }
      cmds.append(.placeBetOnBox(number: n, amount: allocation.outsideEach))
    }
    for n in insidePoints {
      if let s = skipBox, n == s { continue }
      cmds.append(.placeBetOnBox(number: n, amount: allocation.insideEach))
    }
    return cmds
  }
}
