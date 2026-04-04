//
//  CrapsRollResolution.swift
//  hardway-craps
//
//  Created by GPT on 3/27/26.
//

import Foundation

struct CrapsRollResolution {
    let die1: Int
    let die2: Int
    let total: Int
    let event: GameEvent
    let wasInPointPhase: Bool
    let currentPointBeforeRoll: Int?
    let passLineOddsBetAmount: Int
    let dontPassOddsBetAmount: Int
    let passLineBetAmountBeforeOutcome: Int
    let dontPassBetAmountBeforeOutcome: Int
    let passLineOddsAmountBeforeOutcome: Int
}
