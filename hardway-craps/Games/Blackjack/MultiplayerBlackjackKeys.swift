//
//  MultiplayerBlackjackKeys.swift
//  hardway-craps
//
//  Centralized string keys for multiplayer blackjack (UserDefaults, Firebase, card/hand data, actions, phases).
//

import Foundation

enum MultiplayerBlackjackKeys {

  // UserDefaults keys
  enum UserDefaults {
    static let displayName = "MultiplayerDisplayName"
    static let tableCode = "MultiplayerTableCode"
    static let playerId = "MultiplayerPlayerId"
  }

  // Firebase function parameter keys
  enum FirebaseParams {
    static let tableCode = "tableCode"
    static let seatIndex = "seatIndex"
    static let handIndex = "handIndex"
    static let action = "action"
    static let amount = "amount"
    static let playerId = "playerId"
  }

  // Firebase response keys
  enum FirebaseResponse {
    static let newBalance = "newBalance"
    static let newBet = "newBet"
  }

  // Dictionary keys for card data
  enum CardData {
    static let rank = "rank"
    static let suit = "suit"
    static let isCutCard = "isCutCard"
  }

  // Dictionary keys for hand data
  enum HandData {
    static let cards = "cards"
    static let stood = "stood"
    static let doubled = "doubled"
    static let busted = "busted"
    static let bet = "bet"
  }

  // Dictionary keys for insurance (stored per-seat in Firebase)
  enum Insurance {
    static let insuranceBet = "insuranceBet"
    static let insuranceDecided = "insuranceDecided"
  }

  // Dictionary keys for bonus bets (stored per-seat and in game state)
  enum BonusBets {
    static let bonusBets = "bonusBets"
    static let amount = "amount"
    static let bonusBetResults = "bonusBetResults"
    static let isWin = "isWin"
    static let odds = "odds"
    static let payout = "payout"
    static let description = "description"
    static let betIndex = "betIndex"
  }

  // Settings keys
  enum Settings {
    static let selectedSideBets = "selectedSideBets"
    static let startingBankroll = "startingBankroll"
  }

  // Action strings
  enum Actions {
    static let hit = "hit"
    static let stand = "stand"
    static let double = "double"
    static let split = "split"
  }

  // Phase strings
  enum Phases {
    static let waitingForPlayers = "waiting_for_players"
    static let betting = "betting"
    static let dealing = "dealing"
    static let playerActions = "player_actions"
    static let dealerTurn = "dealer_turn"
    static let resolving = "resolving"
    static let gameOver = "game_over"
    static let betweenHands = "between_hands"
    static let waitingForReady = "waiting_for_ready"
  }
}
