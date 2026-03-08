//
//  GameAnalytics.swift
//  hardway-craps
//
//  Firebase Analytics events for game tracking
//

import Foundation
import FirebaseAnalytics

enum GameAnalyticsEvent: String {
    case crapsGameStarted = "craps_game_started"
    case blackjackGameStarted = "blackjack_game_started"
    case mpBlackjackGameStarted = "mp_blackjack_game_started"
    
    /// Log this analytics event
    func log() {
        Analytics.logEvent(self.rawValue, parameters: nil)
    }
}
