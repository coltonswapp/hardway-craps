//
//  MPBlackjackGameState.swift
//  hardway-craps
//
//  Authoritative game state for multiplayer blackjack stored in Firebase.
//  Manages deck shuffling, turn order, game phases, and player actions.
//

import Foundation
import FirebaseDatabase

/// Game phase for multiplayer blackjack
enum MPGamePhase: String, Codable {
    case waitingForPlayers = "waiting_for_players"  // Waiting for players to join/ready
    case betting = "betting"                         // Players placing bets
    case dealing = "dealing"                        // Cards being dealt
    case playerActions = "player_actions"           // Players taking turns (hit, stand, double, etc.)
    case dealerTurn = "dealer_turn"                 // Dealer playing their hand
    case resolving = "resolving"                    // Calculating wins/losses
    case gameOver = "game_over"                     // Hand complete, waiting for next hand
}

/// Turn state for player actions phase
struct MPPlayerTurnState: Codable {
    let seatIndex: Int              // Which seat's turn it is
    let handIndex: Int              // Which hand (0 = primary, 1+ = split hands)
    let canHit: Bool
    let canStand: Bool
    let canDouble: Bool
    let canSplit: Bool
}

/// Card representation for Firebase storage (compact)
struct MPCard: Codable, Equatable {
    let rank: String  // "A", "K", "Q", "J", "10", "9", ..., "2"
    let suit: String  // "clubs", "hearts", "diamonds", "spades"
    let isCutCard: Bool
    
    init(rank: String, suit: String, isCutCard: Bool = false) {
        self.rank = rank
        self.suit = suit
        self.isCutCard = isCutCard
    }
    
    init(from card: BlackjackHandView.Card) {
        self.rank = card.rank.rawValue
        // Suit doesn't have rawValue, so use string representation
        switch card.suit {
        case .clubs: self.suit = "clubs"
        case .hearts: self.suit = "hearts"
        case .diamonds: self.suit = "diamonds"
        case .spades: self.suit = "spades"
        }
        self.isCutCard = card.isCutCard
    }
    
    func toBlackjackCard() -> BlackjackHandView.Card {
        let rank = PlayingCardView.Rank(rawValue: self.rank) ?? .ace
        let suit: PlayingCardView.Suit
        switch self.suit {
        case "clubs": suit = .clubs
        case "hearts": suit = .hearts
        case "diamonds": suit = .diamonds
        case "spades": suit = .spades
        default: suit = .spades
        }
        return BlackjackHandView.Card(rank: rank, suit: suit, isCutCard: isCutCard)
    }
}

/// Player hand state stored in Firebase
struct MPPlayerHand: Codable {
    var cards: [MPCard]
    var betAmount: Int
    var hasStood: Bool
    var hasDoubled: Bool
    var hasBusted: Bool
    var isSplit: Bool
    
    init(cards: [MPCard] = [], betAmount: Int = 0, hasStood: Bool = false, 
         hasDoubled: Bool = false, hasBusted: Bool = false, isSplit: Bool = false) {
        self.cards = cards
        self.betAmount = betAmount
        self.hasStood = hasStood
        self.hasDoubled = hasDoubled
        self.hasBusted = hasBusted
        self.isSplit = isSplit
    }
}

/// Complete game state stored in Firebase. Deck is derived from deckSeed + deckCount, not stored.
struct MPGameState: Codable {
    var phase: MPGamePhase
    var deckSeed: Int64              // Seed for deterministic shuffle
    var deckCount: Int               // Number of 52-card decks (1–6)
    var deckIndex: Int               // Current position in deck
    var dealerCards: [MPCard]        // Dealer's hand
    var dealerHoleCardRevealed: Bool
    var playerHands: [Int: [MPPlayerHand]]  // seatIndex -> [hands] (supports splits)
    var currentTurn: MPPlayerTurnState?      // Whose turn it is
    var handNumber: Int              // Increments each hand
    var lastShuffleTime: TimeInterval // Timestamp of last shuffle

    init(phase: MPGamePhase = .waitingForPlayers, deckSeed: Int64 = 0,
         deckCount: Int = 1, deckIndex: Int = 0, dealerCards: [MPCard] = [],
         dealerHoleCardRevealed: Bool = false, playerHands: [Int: [MPPlayerHand]] = [:],
         currentTurn: MPPlayerTurnState? = nil, handNumber: Int = 0,
         lastShuffleTime: TimeInterval = Date().timeIntervalSince1970) {
        self.phase = phase
        self.deckSeed = deckSeed
        self.deckCount = deckCount
        self.deckIndex = deckIndex
        self.dealerCards = dealerCards
        self.dealerHoleCardRevealed = dealerHoleCardRevealed
        self.playerHands = playerHands
        self.currentTurn = currentTurn
        self.handNumber = handNumber
        self.lastShuffleTime = lastShuffleTime
    }
}

/// Manages authoritative game state in Firebase
final class MPBlackjackGameState {
    
    private static let path = "mp_blackjack/game"
    private let ref: DatabaseReference
    
    init(database: Database = .database()) {
        self.ref = database.reference().child(Self.path)
    }
    
    // MARK: - Game State Management
    
    /// Initialize a new game state (call when starting a new hand)
    func initializeGame(deckCount: Int = 1, completion: @escaping (Result<Void, Error>) -> Void) {
        let seed = Int64.random(in: Int64.min...Int64.max)
        let initialState = MPGameState(
            phase: .betting,
            deckSeed: seed,
            deckCount: deckCount,
            deckIndex: 0,
            handNumber: 1
        )
        
        writeGameState(initialState) { result in
            completion(result.map { _ in () })
        }
    }
    
    /// Get current game state
    func getGameState(completion: @escaping (Result<MPGameState, Error>) -> Void) {
        ref.observeSingleEvent(of: .value) { snapshot in
            guard let data = snapshot.value as? [String: Any] else {
                completion(.failure(NSError(domain: "MPBlackjackGameState", code: -1, 
                                         userInfo: [NSLocalizedDescriptionKey: "No game state found"])))
                return
            }
            
            do {
                let state = try self.decodeGameState(from: data)
                completion(.success(state))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    /// Observe game state changes
    @discardableResult
    func observeGameState(handler: @escaping (MPGameState) -> Void) -> DatabaseHandle {
        return ref.observe(.value) { [weak self] snapshot in
            guard let self = self, let data = snapshot.value as? [String: Any] else { return }
            do {
                let state = try self.decodeGameState(from: data)
                DispatchQueue.main.async { handler(state) }
            } catch {
                print("⚠️ [MPBlackjackGameState] Failed to decode game state: \(error)")
            }
        }
    }
    
    /// Update game phase (with transaction to prevent conflicts)
    func updatePhase(_ phase: MPGamePhase, completion: @escaping (Result<Void, Error>) -> Void) {
        ref.runTransactionBlock({ currentData in
            var data = currentData.value as? [String: Any] ?? [:]
            data["phase"] = phase.rawValue
            currentData.value = data
            return .success(withValue: currentData)
        }) { error, committed, _ in
            if let error = error {
                completion(.failure(error))
            } else if committed {
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: "MPBlackjackGameState", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "Transaction failed"])))
            }
        }
    }
    
    /// Draw a card from the deck (atomic operation). Deck is derived from deckSeed + deckCount.
    func drawCard(completion: @escaping (Result<MPCard, Error>) -> Void) {
        ref.runTransactionBlock({ currentData in
            var data = currentData.value as? [String: Any] ?? [:]
            guard var deckIndex = data["deckIndex"] as? Int else { return .abort() }
            let deckCount = min(6, max(1, (data["deckCount"] as? Int) ?? 1))
            guard let deckSeed = data["deckSeed"] as? Int64 else { return .abort() }
            let provider = DeterministicDeckProvider(seed: Int(truncatingIfNeeded: deckSeed), deckCount: deckCount)
            guard deckIndex < provider.count else { return .abort() }
            deckIndex += 1
            data["deckIndex"] = deckIndex
            currentData.value = data
            return .success(withValue: currentData)
        }) { error, committed, snapshot in
            guard error == nil, committed else {
                completion(.failure(error ?? NSError(domain: "MPBlackjackGameState", code: -1,
                                                   userInfo: [NSLocalizedDescriptionKey: "Failed to draw card"])))
                return
            }
            guard let data = snapshot?.value as? [String: Any],
                  let deckSeed = data["deckSeed"] as? Int64,
                  let deckIndex = data["deckIndex"] as? Int,
                  deckIndex > 0 else {
                completion(.failure(NSError(domain: "MPBlackjackGameState", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "Invalid deck state"])))
                return
            }
            let deckCount = min(6, max(1, (data["deckCount"] as? Int) ?? 1))
            let provider = DeterministicDeckProvider(seed: Int(truncatingIfNeeded: deckSeed), deckCount: deckCount)
            guard let card = provider.card(at: deckIndex - 1) else {
                completion(.failure(NSError(domain: "MPBlackjackGameState", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "Invalid deck index"])))
                return
            }
            completion(.success(MPCard(rank: card.rank, suit: card.suit, isCutCard: false)))
        }
    }
    
    /// Place a bet for a player (atomic operation)
    func placeBet(seatIndex: Int, amount: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        ref.runTransactionBlock({ currentData in
            var data = currentData.value as? [String: Any] ?? [:]
            
            // Initialize playerHands if needed
            var playerHands: [String: [[String: Any]]] = data["playerHands"] as? [String: [[String: Any]]] ?? [:]
            let seatKey = "\(seatIndex)"
            
            if playerHands[seatKey] == nil {
                playerHands[seatKey] = []
            }
            
            // Create or update primary hand
            var hands = playerHands[seatKey] ?? []
            if hands.isEmpty {
                hands.append([
                    "cards": [],
                    "betAmount": amount,
                    "hasStood": false,
                    "hasDoubled": false,
                    "hasBusted": false,
                    "isSplit": false
                ])
            } else {
                var primaryHand = hands[0]
                var currentBet = primaryHand["betAmount"] as? Int ?? 0
                currentBet += amount
                primaryHand["betAmount"] = currentBet
                hands[0] = primaryHand
            }
            
            playerHands[seatKey] = hands
            data["playerHands"] = playerHands
            
            currentData.value = data
            return .success(withValue: currentData)
        }) { error, committed, _ in
            if let error = error {
                completion(.failure(error))
            } else if committed {
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: "MPBlackjackGameState", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "Failed to place bet"])))
            }
        }
    }
    
    /// Player action (hit, stand, double, split) - atomic operation
    func playerAction(seatIndex: Int, handIndex: Int, action: String, 
                     completion: @escaping (Result<MPCard?, Error>) -> Void) {
        // action can be: "hit", "stand", "double", "split"
        // Returns card if hit/double, nil if stand/split
        let actionToUse = action // Capture action for use in completion handler
        ref.runTransactionBlock({ currentData in
            var data = currentData.value as? [String: Any] ?? [:]
            
            // Verify it's this player's turn
            if let turnData = data["currentTurn"] as? [String: Any],
               let turnSeat = turnData["seatIndex"] as? Int,
               let turnHand = turnData["handIndex"] as? Int {
                guard turnSeat == seatIndex && turnHand == handIndex else {
                    return .abort() // Not this player's turn
                }
            }
            
            var card: MPCard? = nil
            
            // Handle action
            switch actionToUse {
            case "hit", "double":
                // Draw card from deterministic deck (deckSeed + deckCount)
                guard let deckSeed = data["deckSeed"] as? Int64,
                      var deckIndex = data["deckIndex"] as? Int else {
                    return .abort()
                }
                let deckCount = min(6, max(1, (data["deckCount"] as? Int) ?? 1))
                let provider = DeterministicDeckProvider(seed: Int(truncatingIfNeeded: deckSeed), deckCount: deckCount)
                guard let drawn = provider.card(at: deckIndex) else { return .abort() }
                deckIndex += 1
                data["deckIndex"] = deckIndex
                card = MPCard(rank: drawn.rank, suit: drawn.suit, isCutCard: false)
                
                // Add card to hand
                var playerHands: [String: [[String: Any]]] = data["playerHands"] as? [String: [[String: Any]]] ?? [:]
                let seatKey = "\(seatIndex)"
                var hands = playerHands[seatKey] ?? []
                guard handIndex < hands.count else { return .abort() }
                
                var hand = hands[handIndex]
                var cards = hand["cards"] as? [[String: Any]] ?? []
                cards.append([
                    "rank": card!.rank,
                    "suit": card!.suit,
                    "isCutCard": card!.isCutCard
                ])
                hand["cards"] = cards
                
                if action == "double" {
                    hand["hasDoubled"] = true
                }
                
                hands[handIndex] = hand
                playerHands[seatKey] = hands
                data["playerHands"] = playerHands
                
            case "stand":
                // Mark hand as stood
                var playerHands: [String: [[String: Any]]] = data["playerHands"] as? [String: [[String: Any]]] ?? [:]
                let seatKey = "\(seatIndex)"
                var hands = playerHands[seatKey] ?? []
                guard handIndex < hands.count else { return .abort() }
                
                var hand = hands[handIndex]
                hand["hasStood"] = true
                hands[handIndex] = hand
                playerHands[seatKey] = hands
                data["playerHands"] = playerHands
                
            case "split":
                // TODO: Implement split logic
                break
                
            default:
                return .abort()
            }
            
            currentData.value = data
            return .success(withValue: currentData)
        }) { [weak self] error, committed, snapshot in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
            } else if committed {
                // Extract card from snapshot if we drew one (for hit/double actions)
                if actionToUse == "hit" || actionToUse == "double" {
                    guard let data = snapshot?.value as? [String: Any],
                          let deckSeed = data["deckSeed"] as? Int64,
                          let deckIndex = data["deckIndex"] as? Int,
                          deckIndex > 0 else {
                        completion(.success(nil))
                        return
                    }
                    let deckCount = min(6, max(1, (data["deckCount"] as? Int) ?? 1))
                    let provider = DeterministicDeckProvider(seed: Int(truncatingIfNeeded: deckSeed), deckCount: deckCount)
                    guard let c = provider.card(at: deckIndex - 1) else {
                        completion(.success(nil))
                        return
                    }
                    completion(.success(MPCard(rank: c.rank, suit: c.suit, isCutCard: false)))
                } else {
                    // Stand or split - no card drawn
                    completion(.success(nil))
                }
            } else {
                completion(.failure(NSError(domain: "MPBlackjackGameState", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "Action failed"])))
            }
        }
    }
    
    // MARK: - Helper Methods

    private func writeGameState(_ state: MPGameState, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(NSError(domain: "MPBlackjackGameState", code: -1,
                                           userInfo: [NSLocalizedDescriptionKey: "Failed to encode state"])))
                return
            }
            
            // Convert nested structures to Firebase-compatible format (deck not stored; derived from deckSeed + deckCount)
            var firebaseDict: [String: Any] = [
                "phase": state.phase.rawValue,
                "deckSeed": state.deckSeed,
                "deckCount": state.deckCount,
                "deckIndex": state.deckIndex,
                "dealerHoleCardRevealed": state.dealerHoleCardRevealed,
                "handNumber": state.handNumber,
                "lastShuffleTime": state.lastShuffleTime
            ]

            // Encode dealer cards
            firebaseDict["dealerCards"] = state.dealerCards.map { ["rank": $0.rank, "suit": $0.suit, "isCutCard": $0.isCutCard] }
            
            // Encode player hands
            var playerHandsDict: [String: [[String: Any]]] = [:]
            for (seatIndex, hands) in state.playerHands {
                playerHandsDict["\(seatIndex)"] = hands.map { hand in
                    [
                        "cards": hand.cards.map { ["rank": $0.rank, "suit": $0.suit, "isCutCard": $0.isCutCard] },
                        "betAmount": hand.betAmount,
                        "hasStood": hand.hasStood,
                        "hasDoubled": hand.hasDoubled,
                        "hasBusted": hand.hasBusted,
                        "isSplit": hand.isSplit
                    ]
                }
            }
            firebaseDict["playerHands"] = playerHandsDict
            
            // Encode current turn
            if let turn = state.currentTurn {
                firebaseDict["currentTurn"] = [
                    "seatIndex": turn.seatIndex,
                    "handIndex": turn.handIndex,
                    "canHit": turn.canHit,
                    "canStand": turn.canStand,
                    "canDouble": turn.canDouble,
                    "canSplit": turn.canSplit
                ]
            }
            
            ref.setValue(firebaseDict) { error, _ in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    private func decodeGameState(from data: [String: Any]) throws -> MPGameState {
        let phaseRaw = data["phase"] as? String ?? MPGamePhase.waitingForPlayers.rawValue
        let phase = MPGamePhase(rawValue: phaseRaw) ?? .waitingForPlayers
        let deckSeed = data["deckSeed"] as? Int64 ?? 0
        let deckCount = min(6, max(1, (data["deckCount"] as? Int) ?? 1))
        let deckIndex = data["deckIndex"] as? Int ?? 0
        let dealerHoleCardRevealed = data["dealerHoleCardRevealed"] as? Bool ?? false
        let handNumber = data["handNumber"] as? Int ?? 0
        let lastShuffleTime = data["lastShuffleTime"] as? TimeInterval ?? Date().timeIntervalSince1970

        // Decode dealer cards
        let dealerCardsArray = data["dealerCards"] as? [[String: Any]] ?? []
        let dealerCards = try dealerCardsArray.map { try decodeCard(from: $0) }
        
        // Decode player hands
        var playerHands: [Int: [MPPlayerHand]] = [:]
        if let handsDict = data["playerHands"] as? [String: [[String: Any]]] {
            for (seatKey, handsArray) in handsDict {
                guard let seatIndex = Int(seatKey) else { continue }
                let hands = try handsArray.map { try decodePlayerHand(from: $0) }
                playerHands[seatIndex] = hands
            }
        }
        
        // Decode current turn
        var currentTurn: MPPlayerTurnState? = nil
        if let turnData = data["currentTurn"] as? [String: Any] {
            currentTurn = MPPlayerTurnState(
                seatIndex: turnData["seatIndex"] as? Int ?? 0,
                handIndex: turnData["handIndex"] as? Int ?? 0,
                canHit: turnData["canHit"] as? Bool ?? false,
                canStand: turnData["canStand"] as? Bool ?? false,
                canDouble: turnData["canDouble"] as? Bool ?? false,
                canSplit: turnData["canSplit"] as? Bool ?? false
            )
        }
        
        return MPGameState(
            phase: phase,
            deckSeed: deckSeed,
            deckCount: deckCount,
            deckIndex: deckIndex,
            dealerCards: dealerCards,
            dealerHoleCardRevealed: dealerHoleCardRevealed,
            playerHands: playerHands,
            currentTurn: currentTurn,
            handNumber: handNumber,
            lastShuffleTime: lastShuffleTime
        )
    }
    
    private func decodeCard(from data: [String: Any]) throws -> MPCard {
        guard let rank = data["rank"] as? String,
              let suit = data["suit"] as? String else {
            throw NSError(domain: "MPBlackjackGameState", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid card data"])
        }
        let isCutCard = data["isCutCard"] as? Bool ?? false
        return MPCard(rank: rank, suit: suit, isCutCard: isCutCard)
    }
    
    private func decodePlayerHand(from data: [String: Any]) throws -> MPPlayerHand {
        let cardsArray = data["cards"] as? [[String: Any]] ?? []
        let cards = try cardsArray.map { try decodeCard(from: $0) }
        return MPPlayerHand(
            cards: cards,
            betAmount: data["betAmount"] as? Int ?? 0,
            hasStood: data["hasStood"] as? Bool ?? false,
            hasDoubled: data["hasDoubled"] as? Bool ?? false,
            hasBusted: data["hasBusted"] as? Bool ?? false,
            isSplit: data["isSplit"] as? Bool ?? false
        )
    }
    
    func removeObserver(handle: DatabaseHandle) {
        ref.removeObserver(withHandle: handle)
    }
}
