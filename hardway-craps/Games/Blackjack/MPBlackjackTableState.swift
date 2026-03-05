//
//  MPBlackjackTableState.swift
//  hardway-craps
//
//  Manages multiplayer blackjack table in Firebase: join (claim first empty seat),
//  record name, balance, seat order, chip color.
//

import Foundation
import FirebaseDatabase
import UIKit

final class MPBlackjackTableState {

    private static let basePath = "mp_blackjack/table"
    private static let seatsKey = "seats"
    private static let maxSeats = 5

    /// 4-digit invite code for this table. Used for all paths and callables.
    let tableCode: String
    private let ref: DatabaseReference
    private var seatsRef: DatabaseReference { ref.child(Self.seatsKey) }
    private var gameRef: DatabaseReference { ref.child("game") }
    private var hostRef: DatabaseReference { ref.child("hostPlayerId") }
    private var settingsRef: DatabaseReference { ref.child("settings") }

    init(tableCode: String = "0000", database: Database = .database()) {
        self.tableCode = tableCode
        self.ref = database.reference().child(Self.basePath).child(tableCode)
    }

    /// Hand data for a player (primary or split hand)
    struct HandData {
        let bet: Int
        let cards: [[String: Any]]  // Array of {rank, suit} dictionaries
        let stood: Bool
        let doubled: Bool
        let busted: Bool
        let playerId: String?  // For bet placement tracking

        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = ["bet": bet, "cards": cards, "stood": stood, "doubled": doubled, "busted": busted]
            if let playerId = playerId {
                dict["playerId"] = playerId
            }
            return dict
        }

        static func from(_ dict: [String: Any]?) -> HandData? {
            guard let dict = dict,
                  let bet = dict["bet"] as? Int else { return nil }
            let cards = Self.parseCards(dict["cards"])
            let stood = dict["stood"] as? Bool ?? false
            let doubled = dict["doubled"] as? Bool ?? false
            let busted = dict["busted"] as? Bool ?? false
            let playerId = dict["playerId"] as? String
            return HandData(bet: bet, cards: cards, stood: stood, doubled: doubled, busted: busted, playerId: playerId)
        }

        /// Parse cards from Firebase. Handles Swift array, NSDictionary (object with "0","1" keys), and NSArray.
        private static func parseCards(_ raw: Any?) -> [[String: Any]] {
            guard let raw = raw else { return [] }
            if let arr = raw as? [[String: Any]] { return arr }
            if let nsArr = raw as? [Any] {
                return nsArr.compactMap { MPBlackjackTableState.dictFromAny($0) as [String: Any]? }.filter { !$0.isEmpty }
            }
            if let nsDict = raw as? NSDictionary {
                var list: [(Int, [String: Any])] = []
                for (k, v) in nsDict {
                    let key: Int
                    if let n = k as? NSNumber { key = n.intValue }
                    else if let s = k as? String, let i = Int(s) { key = i }
                    else { continue }
                    let card = MPBlackjackTableState.dictFromAny(v)
                    if !card.isEmpty { list.append((key, card)) }
                }
                list.sort { $0.0 < $1.0 }
                return list.map { $0.1 }
            }
            if let dict = raw as? [String: Any] {
                var list: [(Int, [String: Any])] = []
                for (k, v) in dict {
                    guard let i = Int(k) else { continue }
                    let card = MPBlackjackTableState.dictFromAny(v)
                    if !card.isEmpty { list.append((i, card)) }
                }
                list.sort { $0.0 < $1.0 }
                return list.map { $0.1 }
            }
            return []
        }
    }

    /// Seat payload as stored in Firebase (and returned when reading).
    struct SeatData {
        let playerId: String?
        let displayName: String
        let balance: Int
        let chipColorName: String
        let hands: [HandData]
        let insuranceBet: Int
        let insuranceDecided: Bool
        let bonusBets: [Int: Int]

        /// Total bet across all hands
        var totalBet: Int {
            hands.reduce(0) { $0 + $1.bet }
        }

        /// Name to show in UI: first 5 chars of playerId when displayName is empty or "Player", else displayName.
        var displayLabel: String {
            if !displayName.isEmpty && displayName != "Player" { return displayName }
            let id = playerId ?? ""
            return String(id.prefix(5))
        }
    }
    
    /// Pre-assigned colors for the 5 seats
    static let seatColors = [
        "Yellow Green",
        "Cyan",
        "Green",
        "Red",
        "Purple"
    ]
    
    /// Initialize or ensure table exists with pre-assigned colors for each seat.
    /// Uses NSDictionary-safe parsing so we never overwrite existing playerId/displayName/balance.
    func initializeTableIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        ref.runTransactionBlock({ currentData in
            var data = Self.dictionaryFromTransactionValue(currentData.value)
            var seats = Self.parseSeats(from: data)
            var needsUpdate = false
            
            // Ensure all 5 seats exist with their pre-assigned colors; never replace existing seat content
            for i in 0..<Self.maxSeats {
                let key = "\(i)"
                var seat = Self.dictFromAny(seats[key])
                
                // Set color only if not already set
                if seat["chipColorName"] == nil {
                    seat["chipColorName"] = Self.seatColors[i]
                    seats[key] = seat
                    needsUpdate = true
                }
                
                // If seat has no player, ensure playerId is missing (not empty string)
                if let playerId = seat["playerId"] as? String {
                    if playerId.isEmpty {
                        seat.removeValue(forKey: "playerId")
                        seat.removeValue(forKey: "displayName")
                        seat.removeValue(forKey: "balance")
                        seats[key] = seat
                        needsUpdate = true
                    }
                }
            }
            
            if needsUpdate {
                data[Self.seatsKey] = seats
                currentData.value = data
                print("✅ [MPBlackjack] Initialized table with \(Self.maxSeats) seats")
                return .success(withValue: currentData)
            }
            print("ℹ️ [MPBlackjack] Table already initialized")
            return .success(withValue: currentData)
        }) { error, committed, _ in
            if let error = error {
                print("❌ [MPBlackjack] Failed to initialize table: \(error.localizedDescription)")
                completion(.failure(error))
            } else if committed {
                print("✅ [MPBlackjack] Table initialization committed")
                completion(.success(()))
            } else {
                print("⚠️ [MPBlackjack] Table initialization not committed (may have been aborted)")
                completion(.success(())) // Not an error if aborted (table already exists)
            }
        }
    }

    /// Join the table: claim first empty seat. Uses a transaction per seat so server state is authoritative and we never overwrite an occupied seat.
    func joinTable(
        playerId: String,
        displayName: String,
        balance: Int,
        chipColorName: String, // Ignored - seats have pre-assigned colors
        completion: @escaping (Result<(seatIndex: Int, chipColorName: String), Error>) -> Void
    ) {
        tryJoinSeat(seatIndex: 0, playerId: playerId, displayName: displayName, balance: balance, completion: completion)
    }

    private func tryJoinSeat(seatIndex: Int, playerId: String, displayName: String, balance: Int, completion: @escaping (Result<(seatIndex: Int, chipColorName: String), Error>) -> Void) {
        guard seatIndex < Self.maxSeats else {
            completion(.failure(NSError(domain: "MPBlackjackTableState", code: -1, userInfo: [NSLocalizedDescriptionKey: "Table full"])))
            return
        }
        let seatRef = seatsRef.child("\(seatIndex)")
        let colorName = Self.seatColors[seatIndex]
        seatRef.runTransactionBlock({ currentData in
            let seat = Self.dictFromAny(currentData.value)
            let existingPlayerId = (seat["playerId"] as? String) ?? ""
            // Rejoin: we already own this seat
            if existingPlayerId == playerId {
                print("🔄 [MPBlackjack] Rejoining: found existing seat \(seatIndex) for player \(playerId)")
                var updated = seat
                updated["playerId"] = playerId
                updated["displayName"] = displayName
                updated["balance"] = balance
                if updated["chipColorName"] == nil { updated["chipColorName"] = colorName }
                currentData.value = updated
                return .success(withValue: currentData)
            }
            // Seat taken by someone else
            if !existingPlayerId.isEmpty {
                return .abort()
            }
            // Claim empty seat
            print("🆕 [MPBlackjack] Joining: claiming seat \(seatIndex) with pre-assigned color '\(colorName)'")
            var updated = seat
            if updated["chipColorName"] == nil { updated["chipColorName"] = colorName }
            updated["playerId"] = playerId
            updated["displayName"] = displayName
            updated["balance"] = balance
            currentData.value = updated
            return .success(withValue: currentData)
        }) { [weak self] error, committed, snapshot in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            if committed {
                print("✅ [MPBlackjack] Player assigned to seat \(seatIndex) with color '\(colorName)'")
                // Set hostPlayerId to this player if no host is recorded yet (first player to join wins host).
                self.hostRef.runTransactionBlock({ currentData in
                    let existing = currentData.value as? String ?? ""
                    if existing.isEmpty {
                        currentData.value = playerId
                        return .success(withValue: currentData)
                    }
                    return .success(withValue: currentData)
                }) { _, _, _ in }
                completion(.success((seatIndex: seatIndex, chipColorName: colorName)))
                return
            }
            // This seat was taken, try next
            self.tryJoinSeat(seatIndex: seatIndex + 1, playerId: playerId, displayName: displayName, balance: balance, completion: completion)
        }
    }
    
    private func findPlayerInSeats(_ seats: [String: [String: Any]], playerId: String, completion: @escaping (Result<(seatIndex: Int, chipColorName: String), Error>) -> Void) {
        for i in 0..<Self.maxSeats {
            let key = "\(i)"
            guard let seat = seats[key],
                  let seatPlayerId = seat["playerId"] as? String,
                  seatPlayerId == playerId else { continue }
            let color = seat["chipColorName"] as? String ?? Self.seatColors[i]
            print("✅ [MPBlackjack] Player assigned to seat \(i) with color '\(color)'")
            completion(.success((seatIndex: i, chipColorName: color)))
            return
        }
        print("❌ [MPBlackjack] Player not found in seats after join")
        completion(.failure(NSError(domain: "MPBlackjackTableState", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player not found after join"])))
    }

    /// Fetch current seats once with seat indices (same shape as observeSeats). Uses NSDictionary-safe parsing.
    func getSeatsWithIndices(completion: @escaping ([(seatIndex: Int, seatData: SeatData)]) -> Void) {
        seatsRef.observeSingleEvent(of: .value, with: { snapshot in
            let seatsDict = Self.parseSeatsValue(snapshot.value)
            var result: [(seatIndex: Int, seatData: SeatData)] = []
            for i in 0..<Self.maxSeats {
                let key = "\(i)"
                guard let seat = seatsDict[key],
                      let playerId = seat["playerId"] as? String, !playerId.isEmpty else { continue }
                let hands = Self.parseHandsFromSeat(seat, playerId: playerId)
                result.append((seatIndex: i, seatData: SeatData(
                    playerId: playerId,
                    displayName: seat["displayName"] as? String ?? "",
                    balance: Self.intFromAny(seat["balance"]) ?? 0,
                    chipColorName: seat["chipColorName"] as? String ?? Self.seatColors[i],
                    hands: hands,
                    insuranceBet: Self.intFromAny(seat[MultiplayerBlackjackKeys.Insurance.insuranceBet]) ?? 0,
                    insuranceDecided: seat[MultiplayerBlackjackKeys.Insurance.insuranceDecided] as? Bool ?? false,
                    bonusBets: Self.parseBonusBets(seat)
                )))
            }
            DispatchQueue.main.async { completion(result) }
        })
    }

    /// Fetch current seats once (only returns seats with players).
    func getSeats(completion: @escaping ([SeatData]) -> Void) {
        seatsRef.observeSingleEvent(of: .value, with: { snapshot in
            let seatsDict = Self.parseSeatsValue(snapshot.value)
            var result: [SeatData] = []
            for i in 0..<Self.maxSeats {
                let key = "\(i)"
                guard let seat = seatsDict[key],
                      let playerId = seat["playerId"] as? String, !playerId.isEmpty else { continue }
                let hands = Self.parseHandsFromSeat(seat, playerId: playerId)
                result.append(SeatData(
                    playerId: playerId,
                    displayName: seat["displayName"] as? String ?? "",
                    balance: Self.intFromAny(seat["balance"]) ?? 0,
                    chipColorName: seat["chipColorName"] as? String ?? Self.seatColors[i],
                    hands: hands,
                    insuranceBet: Self.intFromAny(seat[MultiplayerBlackjackKeys.Insurance.insuranceBet]) ?? 0,
                    insuranceDecided: seat[MultiplayerBlackjackKeys.Insurance.insuranceDecided] as? Bool ?? false,
                    bonusBets: Self.parseBonusBets(seat)
                ))
            }
            completion(result)
        })
    }

    /// Observe seats in real time. Handler receives array of (seatIndex, SeatData) tuples (only seats with players).
    /// Handler is called on the main queue.
    @discardableResult
    func observeSeats(handler: @escaping ([(seatIndex: Int, seatData: SeatData)]) -> Void) -> DatabaseHandle {
        return seatsRef.observe(.value, with: { snapshot in
            let seatsDict = Self.parseSeatsValue(snapshot.value)
            var result: [(seatIndex: Int, seatData: SeatData)] = []
            for i in 0..<Self.maxSeats {
                let key = "\(i)"
                guard let seat = seatsDict[key],
                      let playerId = seat["playerId"] as? String, !playerId.isEmpty else { continue }
                let hands = Self.parseHandsFromSeat(seat, playerId: playerId)
                result.append((seatIndex: i, seatData: SeatData(
                    playerId: playerId,
                    displayName: seat["displayName"] as? String ?? "",
                    balance: Self.intFromAny(seat["balance"]) ?? 0,
                    chipColorName: seat["chipColorName"] as? String ?? Self.seatColors[i],
                    hands: hands,
                    insuranceBet: Self.intFromAny(seat[MultiplayerBlackjackKeys.Insurance.insuranceBet]) ?? 0,
                    insuranceDecided: seat[MultiplayerBlackjackKeys.Insurance.insuranceDecided] as? Bool ?? false,
                    bonusBets: Self.parseBonusBets(seat)
                )))
            }
            DispatchQueue.main.async { handler(result) }
        })
    }

    func removeSeatsObserver(handle: DatabaseHandle) {
        seatsRef.removeObserver(withHandle: handle)
    }

    private static func parseBonusBets(_ seat: [String: Any]) -> [Int: Int] {
        guard let rawBB = seat[MultiplayerBlackjackKeys.BonusBets.bonusBets] else { return [:] }
        var result: [Int: Int] = [:]

        // Firebase converts objects with sequential numeric keys ("0","1",...) into arrays.
        if let arr = rawBB as? [Any] {
            for (idx, value) in arr.enumerated() {
                let inner = dictFromAny(value)
                if !inner.isEmpty, let amount = intFromAny(inner[MultiplayerBlackjackKeys.BonusBets.amount]) {
                    result[idx] = amount
                } else if let amount = intFromAny(value) {
                    result[idx] = amount
                }
            }
        } else if let dict = rawBB as? [String: Any] {
            for (key, value) in dict {
                guard let idx = Int(key) else { continue }
                if let inner = value as? [String: Any], let amount = intFromAny(inner[MultiplayerBlackjackKeys.BonusBets.amount]) {
                    result[idx] = amount
                } else if let amount = intFromAny(value) {
                    result[idx] = amount
                }
            }
        } else if let nsDict = rawBB as? NSDictionary {
            for (key, value) in nsDict {
                let idx: Int
                if let s = key as? String, let i = Int(s) { idx = i }
                else if let n = key as? NSNumber { idx = n.intValue }
                else { continue }
                if let inner = value as? [String: Any], let amount = intFromAny(inner[MultiplayerBlackjackKeys.BonusBets.amount]) {
                    result[idx] = amount
                } else if let amount = intFromAny(value) {
                    result[idx] = amount
                }
            }
        }
        return result
    }


    // MARK: - Game state (for Cloud Functions–driven game)

    /// Snapshot of game state under `game/` (phase, player hands, dealer cards, current turn). Used for deal animations and Hit/Stand/Double.
    struct GameStateSnapshot {
        let phase: String?
        let playerHands: [Int: [[String: Any]]]  // seatIndex -> array of hands; each hand has "cards" (array of {rank, suit}), "bet", "stood", "doubled", "busted"
        let dealerCards: [[String: Any]]
        let dealerHoleRevealed: Bool
        /// Server detected dealer blackjack during deal — bets already resolved server-side.
        let dealerHasBlackjack: Bool
        /// Whose turn: seatIndex and handIndex; nil when not in player_actions or no turn.
        let currentTurn: (seatIndex: Int, handIndex: Int)?
        /// Per-seat hand results from runDealer (only present in game_over / between_hands phases).
        let handResults: [Int: [HandResult]]
        /// Deck is derived from seed + deckCount; deckIndex is current draw position.
        let deckSeed: Int
        let deckCount: Int
        let deckIndex: Int
        /// Per-seat bonus bet results (seatIndex -> betIndex -> result).
        let bonusBetResults: [Int: [Int: BonusBetResultData]]
    }

    struct BonusBetResultData {
        let isWin: Bool
        let odds: Double
        let payout: Int
        let description: String
    }

    /// Outcome for a single hand after dealer resolution.
    struct HandResult {
        let outcome: String   // "win", "lose", "push", "blackjack"
        let payout: Int       // Total returned (0 for lose, bet for push, bet*2 for win, bet+floor(bet*1.5) for blackjack)
        let bet: Int

        var isWin: Bool { outcome == "win" || outcome == "blackjack" }
        var isLoss: Bool { outcome == "lose" }
        var isPush: Bool { outcome == "push" }
        var isBlackjack: Bool { outcome == "blackjack" }
        /// Net winnings (amount gained beyond original bet). Negative for losses.
        var netWinnings: Int { payout - bet }
    }

    /// Observe hostPlayerId in real time. Handler is called on the main queue whenever it changes.
    @discardableResult
    func observeHostPlayerId(handler: @escaping (String?) -> Void) -> DatabaseHandle {
        return hostRef.observe(.value) { snapshot in
            let hostId = snapshot.value as? String
            DispatchQueue.main.async { handler(hostId) }
        }
    }

    func removeHostPlayerIdObserver(handle: DatabaseHandle) {
        hostRef.removeObserver(withHandle: handle)
    }

    /// Fetch hostPlayerId once.
    func fetchHostPlayerId(completion: @escaping (String?) -> Void) {
        hostRef.observeSingleEvent(of: .value) { snapshot in
            let hostId = snapshot.value as? String
            DispatchQueue.main.async { completion(hostId) }
        }
    }
    
    /// Transfer host to a different player. Only callable by current host.
    func transferHost(to newHostPlayerId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        hostRef.setValue(newHostPlayerId) { error, _ in
            if let error = error {
                completion(.failure(error))
            } else {
                print("👑 [MPBlackjack] Host transferred to \(newHostPlayerId)")
                completion(.success(()))
            }
        }
    }
    
    /// Remove a player from the table (host-only action). Clears their seat.
    func removePlayer(playerId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        getSeatsWithIndices { [weak self] seatsWithIndices in
            guard let self = self else {
                completion(.failure(NSError(domain: "MPBlackjackTableState", code: -1, userInfo: [NSLocalizedDescriptionKey: "Self is nil"])))
                return
            }
            
            guard let playerSeat = seatsWithIndices.first(where: { $0.seatData.playerId == playerId }) else {
                print("⚠️ [MPBlackjack] Player \(playerId) not found at table")
                completion(.success(()))
                return
            }
            
            let seatIndex = playerSeat.seatIndex
            let chipColorName = playerSeat.seatData.chipColorName
            let seatRef = self.seatsRef.child("\(seatIndex)")
            let clearedSeat: [String: Any] = ["chipColorName": chipColorName]
            
            seatRef.setValue(clearedSeat) { [weak self] error, _ in
                guard let self = self else { return }
                if let error = error {
                    completion(.failure(error))
                    return
                }
                print("✅ [MPBlackjack] Successfully removed player \(playerId) from seat \(seatIndex)")
                
                // If removed player was host, transfer to next lowest seat
                self.hostRef.observeSingleEvent(of: .value) { [weak self] snapshot in
                    guard let self = self else { return }
                    let currentHost = snapshot.value as? String ?? ""
                    guard currentHost == playerId else {
                        completion(.success(()))
                        return
                    }
                    // Find next host: lowest-indexed remaining seat
                    let remaining = seatsWithIndices
                        .filter { $0.seatData.playerId != playerId && $0.seatData.playerId != nil }
                        .sorted { $0.seatIndex < $1.seatIndex }
                    if let newHost = remaining.first, let newHostId = newHost.seatData.playerId {
                        print("👑 [MPBlackjack] Transferring host from removed player \(playerId) to \(newHostId)")
                        self.hostRef.setValue(newHostId) { _, _ in
                            completion(.success(()))
                        }
                    } else {
                        // No other players — clear host
                        print("👑 [MPBlackjack] No other players, clearing hostPlayerId")
                        self.hostRef.removeValue { _, _ in
                            completion(.success(()))
                        }
                    }
                }
            }
        }
    }

    func fetchGameState(completion: @escaping (GameStateSnapshot) -> Void) {
        gameRef.observeSingleEvent(of: .value) { [weak self] snapshot, _ in
            guard self != nil else { return }
            let parsed = Self.parseGameState(snapshot.value)
            let state = GameStateSnapshot(phase: parsed.phase, playerHands: parsed.playerHands, dealerCards: parsed.dealerCards, dealerHoleRevealed: parsed.dealerHoleRevealed, dealerHasBlackjack: parsed.dealerHasBlackjack, currentTurn: parsed.currentTurn, handResults: parsed.handResults, deckSeed: parsed.deckSeed, deckCount: parsed.deckCount, deckIndex: parsed.deckIndex, bonusBetResults: parsed.bonusBetResults)
            DispatchQueue.main.async { completion(state) }
        }
    }

    @discardableResult
    func observeGameState(handler: @escaping (GameStateSnapshot) -> Void) -> DatabaseHandle {
        return gameRef.observe(.value) { [weak self] snapshot in
            guard self != nil else { return }
            let parsed = Self.parseGameState(snapshot.value)
            let snapshot = GameStateSnapshot(phase: parsed.phase, playerHands: parsed.playerHands, dealerCards: parsed.dealerCards, dealerHoleRevealed: parsed.dealerHoleRevealed, dealerHasBlackjack: parsed.dealerHasBlackjack, currentTurn: parsed.currentTurn, handResults: parsed.handResults, deckSeed: parsed.deckSeed, deckCount: parsed.deckCount, deckIndex: parsed.deckIndex, bonusBetResults: parsed.bonusBetResults)
            DispatchQueue.main.async { handler(snapshot) }
        }
    }

    func removeGameStateObserver(handle: DatabaseHandle) {
        gameRef.removeObserver(withHandle: handle)
    }

    private static func parseGameState(_ value: Any?) -> (phase: String?, playerHands: [Int: [[String: Any]]], dealerCards: [[String: Any]], dealerHoleRevealed: Bool, dealerHasBlackjack: Bool, currentTurn: (seatIndex: Int, handIndex: Int)?, handResults: [Int: [HandResult]], deckSeed: Int, deckCount: Int, deckIndex: Int, bonusBetResults: [Int: [Int: BonusBetResultData]]) {
        let data = dictFromAny(value)
        let phase = data["phase"] as? String
        // playerHands is now stored in seats, not game - return empty dict
        let playerHands: [Int: [[String: Any]]] = [:]
        var dealerCards: [[String: Any]] = []
        if let arr = data["dealerCards"] as? [[String: Any]] {
            dealerCards = arr
        } else if let arr = data["dealerCards"] as? [Any] {
            dealerCards = arr.compactMap { dictFromAny($0) as [String: Any]? }
        }
        let dealerHoleRevealed = (data["dealerHoleRevealed"] as? Bool) ?? false
        let dealerHasBlackjack = (data["dealerHasBlackjack"] as? Bool) ?? false
        var currentTurn: (seatIndex: Int, handIndex: Int)? = nil
        if let turn = data["currentTurn"] as? [String: Any],
           let si = turn["seatIndex"] as? Int,
           let hi = turn["handIndex"] as? Int {
            currentTurn = (seatIndex: si, handIndex: hi)
        } else if let turn = data["currentTurn"] as? NSDictionary,
                  let si = turn["seatIndex"] as? NSNumber,
                  let hi = turn["handIndex"] as? NSNumber {
            currentTurn = (seatIndex: si.intValue, handIndex: hi.intValue)
        }
        let deckSeed: Int = (data["deckSeed"] as? NSNumber)?.intValue ?? (data["deckSeed"] as? Int) ?? 0
        let deckCount: Int = min(6, max(1, (data["deckCount"] as? NSNumber)?.intValue ?? (data["deckCount"] as? Int) ?? 1))
        let deckIndex: Int = (data["deckIndex"] as? NSNumber)?.intValue ?? (data["deckIndex"] as? Int) ?? 0
        let rawHandResults = data["handResults"]
        print("💰 [MPBlackjack] parseGameState: phase=\(phase ?? "nil") rawHandResults type=\(rawHandResults.map { "\(type(of: $0))" } ?? "nil") rawHandResults=\(String(describing: rawHandResults))")
        let handResults = parseHandResults(rawHandResults)
        print("💰 [MPBlackjack] parseGameState: parsed handResults=\(handResults)")
        let bonusBetResults = parseBonusBetResults(data["bonusBetResults"])
        return (phase, playerHands, dealerCards, dealerHoleRevealed, dealerHasBlackjack, currentTurn, handResults, deckSeed, deckCount, deckIndex, bonusBetResults)
    }

    private static func parseBonusBetResults(_ raw: Any?) -> [Int: [Int: BonusBetResultData]] {
        guard let raw = raw else { return [:] }
        var result: [Int: [Int: BonusBetResultData]] = [:]

        let outerDict: [String: Any]
        if let d = raw as? [String: Any] {
            outerDict = d
        } else if let arr = raw as? [Any] {
            var d: [String: Any] = [:]
            for (i, v) in arr.enumerated() { d["\(i)"] = v }
            outerDict = d
        } else {
            outerDict = dictFromAny(raw)
        }

        for (seatKey, seatValue) in outerDict {
            guard let seatIndex = Int(seatKey) else { continue }
            let innerDict: [String: Any]
            if let d = seatValue as? [String: Any] {
                innerDict = d
            } else if let arr = seatValue as? [Any] {
                var d: [String: Any] = [:]
                for (i, v) in arr.enumerated() { d["\(i)"] = v }
                innerDict = d
            } else {
                innerDict = dictFromAny(seatValue)
            }

            var betResults: [Int: BonusBetResultData] = [:]
            for (betKey, betValue) in innerDict {
                guard let betIndex = Int(betKey) else { continue }
                let d = dictFromAny(betValue)
                let isWin = (d["isWin"] as? Bool) ?? false
                let odds = (d["odds"] as? Double) ?? (d["odds"] as? NSNumber)?.doubleValue ?? 0
                let payout = intFromAny(d["payout"]) ?? 0
                let desc = (d["description"] as? String) ?? ""
                betResults[betIndex] = BonusBetResultData(isWin: isWin, odds: odds, payout: payout, description: desc)
            }
            if !betResults.isEmpty {
                result[seatIndex] = betResults
            }
        }
        return result
    }

    private static func parseHandResults(_ raw: Any?) -> [Int: [HandResult]] {
        guard let raw = raw else { return [:] }
        var result: [Int: [HandResult]] = [:]

        // Firebase may return handResults as:
        //  - [String: Any] dict with "0", "1" keys
        //  - NSDictionary with NSString/NSNumber keys
        //  - NSArray (if all keys are sequential from 0)
        //  - [Any] array

        if let arr = raw as? [Any] {
            // Top-level is array (Firebase converted sequential integer keys to array)
            for (i, value) in arr.enumerated() {
                let parsed = parseHandResultsForSeat(value)
                if !parsed.isEmpty { result[i] = parsed }
            }
        } else if let nsArr = raw as? NSArray {
            for (i, value) in nsArr.enumerated() {
                let parsed = parseHandResultsForSeat(value)
                if !parsed.isEmpty { result[i] = parsed }
            }
        } else {
            // Try dict/NSDictionary
            let dict = dictFromAny(raw)
            for (key, value) in dict {
                guard let seatIndex = Int(key) else { continue }
                let parsed = parseHandResultsForSeat(value)
                if !parsed.isEmpty { result[seatIndex] = parsed }
            }
        }
        return result
    }

    /// Parse the array of HandResult for one seat. Firebase may represent it as [Any], NSArray, [[String:Any]], NSDictionary, or even a single dict.
    private static func parseHandResultsForSeat(_ raw: Any?) -> [HandResult] {
        guard let raw = raw else { return [] }
        var results: [HandResult] = []

        if let arr = raw as? [[String: Any]] {
            for hr in arr {
                if let parsed = parseOneHandResult(hr) { results.append(parsed) }
            }
        } else if let arr = raw as? [Any] {
            for item in arr {
                let hr = dictFromAny(item)
                if let parsed = parseOneHandResult(hr) { results.append(parsed) }
            }
        } else if let nsArr = raw as? NSArray {
            for item in nsArr {
                let hr = dictFromAny(item)
                if let parsed = parseOneHandResult(hr) { results.append(parsed) }
            }
        } else if let ns = raw as? NSDictionary {
            // Could be indexed dict {"0": {...}} or a single hand result
            // Check if it looks like a single hand result (has "outcome" key)
            if ns["outcome"] != nil {
                let hr = dictFromAny(ns)
                if let parsed = parseOneHandResult(hr) { results.append(parsed) }
            } else {
                var indexed: [(Int, [String: Any])] = []
                for (k, v) in ns {
                    let idx: Int
                    if let n = k as? NSNumber { idx = n.intValue }
                    else if let s = k as? String, let i = Int(s) { idx = i }
                    else { continue }
                    indexed.append((idx, dictFromAny(v)))
                }
                indexed.sort { $0.0 < $1.0 }
                for (_, hr) in indexed {
                    if let parsed = parseOneHandResult(hr) { results.append(parsed) }
                }
            }
        } else {
            // Single dict?
            let hr = dictFromAny(raw)
            if let parsed = parseOneHandResult(hr) { results.append(parsed) }
        }
        return results
    }

    private static func parseOneHandResult(_ dict: [String: Any]) -> HandResult? {
        guard let outcome = dict["outcome"] as? String else { return nil }
        let payout = intFromAny(dict["payout"]) ?? 0
        let bet = intFromAny(dict["bet"]) ?? 0
        return HandResult(outcome: outcome, payout: payout, bet: bet)
    }

    /// Leave the table: clear player data from their seat while preserving the seat's chipColorName.
    /// If the leaving player is the current host, transfers host to the next lowest-seat player.
    func leaveTable(playerId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🚪 [MPBlackjack] leaveTable called for playerId: \(playerId)")

        getSeatsWithIndices { [weak self] seatsWithIndices in
            guard let self = self else {
                print("⚠️ [MPBlackjack] Self is nil in getSeatsWithIndices callback")
                return
            }

            print("🚪 [MPBlackjack] Current seats: \(seatsWithIndices.map { "seat \($0.seatIndex): \($0.seatData.playerId ?? "nil")" })")

            guard let playerSeat = seatsWithIndices.first(where: { $0.seatData.playerId == playerId }) else {
                print("⚠️ [MPBlackjack] Player \(playerId) not found at table")
                completion(.success(()))
                return
            }

            let seatIndex = playerSeat.seatIndex
            let chipColorName = playerSeat.seatData.chipColorName
            print("🚪 [MPBlackjack] Found player in seat \(seatIndex), will clear and preserve color '\(chipColorName)'")

            let seatRef = self.seatsRef.child("\(seatIndex)")
            let clearedSeat: [String: Any] = ["chipColorName": chipColorName]

            print("🚪 [MPBlackjack] Setting seat \(seatIndex) to: \(clearedSeat)")
            seatRef.setValue(clearedSeat) { [weak self] error, _ in
                guard let self = self else { return }
                if let error = error {
                    print("❌ [MPBlackjack] Failed to leave table: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                print("✅ [MPBlackjack] Successfully cleared seat \(seatIndex)")

                // Transfer host if this player was the host
                self.hostRef.observeSingleEvent(of: .value) { [weak self] snapshot in
                    guard let self = self else { return }
                    let currentHost = snapshot.value as? String ?? ""
                    guard currentHost == playerId else {
                        // Not the host — no transfer needed
                        completion(.success(()))
                        return
                    }
                    // Find the next host: lowest-indexed remaining seat (excluding the seat we just cleared)
                    let remaining = seatsWithIndices
                        .filter { $0.seatData.playerId != playerId }
                        .sorted { $0.seatIndex < $1.seatIndex }
                    if let newHost = remaining.first, let newHostId = newHost.seatData.playerId {
                        print("👑 [MPBlackjack] Transferring host from \(playerId) to \(newHostId) (seat \(newHost.seatIndex))")
                        self.hostRef.setValue(newHostId) { _, _ in
                            completion(.success(()))
                        }
                    } else {
                        // Last player left — clear the host field
                        print("👑 [MPBlackjack] Last player left, clearing hostPlayerId")
                        self.hostRef.removeValue { _, _ in
                            completion(.success(()))
                        }
                    }
                }
            }
        }
    }
    
    /// Update a player's hands (bets) in Firebase
    func updateHands(playerId: String, hands: [HandData], completion: ((Result<Void, Error>) -> Void)? = nil) {
        getSeatsWithIndices { [weak self] seatsWithIndices in
            guard let self = self else { return }

            guard let playerSeat = seatsWithIndices.first(where: { $0.seatData.playerId == playerId }) else {
                print("⚠️ [MPBlackjack] Player \(playerId) not found, cannot update hands")
                completion?(.failure(NSError(domain: "MPBlackjackTableState", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player not found"])))
                return
            }

            let handsData = hands.map { $0.toDictionary() }
            let seatRef = self.seatsRef.child("\(playerSeat.seatIndex)").child("hands")
            seatRef.setValue(handsData) { error, _ in
                if let error = error {
                    print("❌ [MPBlackjack] Failed to update hands: \(error.localizedDescription)")
                    completion?(.failure(error))
                } else {
                    let totalBet = hands.reduce(0) { $0 + $1.bet }
                    print("💰 [MPBlackjack] Updated \(hands.count) hand(s) with total bet \(totalBet) for seat \(playerSeat.seatIndex)")
                    completion?(.success(()))
                }
            }
        }
    }

    /// Update a player's balance in Firebase
    func updateBalance(playerId: String, balance: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
        getSeatsWithIndices { [weak self] seatsWithIndices in
            guard let self = self else { return }

            guard let playerSeat = seatsWithIndices.first(where: { $0.seatData.playerId == playerId }) else {
                print("⚠️ [MPBlackjack] Player \(playerId) not found, cannot update balance")
                completion?(.failure(NSError(domain: "MPBlackjackTableState", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player not found"])))
                return
            }

            let seatRef = self.seatsRef.child("\(playerSeat.seatIndex)").child("balance")
            seatRef.setValue(balance) { error, _ in
                if let error = error {
                    print("❌ [MPBlackjack] Failed to update balance: \(error.localizedDescription)")
                    completion?(.failure(error))
                } else {
                    print("💰 [MPBlackjack] Updated balance to \(balance) for seat \(playerSeat.seatIndex)")
                    completion?(.success(()))
                }
            }
        }
    }

    // MARK: - Insurance

    /// Write insurance bet amount for a seat. Direct write (no Cloud Function needed).
    func placeInsuranceBet(seatIndex: Int, amount: Int, completion: ((Error?) -> Void)? = nil) {
        let updates: [String: Any] = [
            MultiplayerBlackjackKeys.Insurance.insuranceBet: amount,
            MultiplayerBlackjackKeys.Insurance.insuranceDecided: true
        ]
        seatsRef.child("\(seatIndex)").updateChildValues(updates) { error, _ in
            if let error = error {
                print("❌ [MPBlackjack] Failed to place insurance bet: \(error.localizedDescription)")
            }
            completion?(error)
        }
    }

    /// Mark a seat as having decided on insurance (declined — bet stays 0).
    func declineInsurance(seatIndex: Int, completion: ((Error?) -> Void)? = nil) {
        let updates: [String: Any] = [
            MultiplayerBlackjackKeys.Insurance.insuranceBet: 0,
            MultiplayerBlackjackKeys.Insurance.insuranceDecided: true
        ]
        seatsRef.child("\(seatIndex)").updateChildValues(updates) { error, _ in
            if let error = error {
                print("❌ [MPBlackjack] Failed to decline insurance: \(error.localizedDescription)")
            }
            completion?(error)
        }
    }

    /// Clear insurance fields for all seats (called on new hand).
    func clearInsuranceForAllSeats(completion: ((Error?) -> Void)? = nil) {
        var updates: [String: Any] = [:]
        for i in 0..<Self.maxSeats {
            updates["\(i)/\(MultiplayerBlackjackKeys.Insurance.insuranceBet)"] = 0
            updates["\(i)/\(MultiplayerBlackjackKeys.Insurance.insuranceDecided)"] = false
        }
        seatsRef.updateChildValues(updates) { error, _ in
            if let error = error {
                print("❌ [MPBlackjack] Failed to clear insurance: \(error.localizedDescription)")
            }
            completion?(error)
        }
    }

    /// Clear bonus bet fields for all seats (called on new hand).
    func clearBonusBetsForAllSeats(completion: ((Error?) -> Void)? = nil) {
        var updates: [String: Any] = [:]
        for i in 0..<Self.maxSeats {
            updates["\(i)/\(MultiplayerBlackjackKeys.BonusBets.bonusBets)"] = NSNull()
        }
        seatsRef.updateChildValues(updates) { error, _ in
            if let error = error {
                print("❌ [MPBlackjack] Failed to clear bonus bets: \(error.localizedDescription)")
            }
            completion?(error)
        }
    }

    // MARK: - Settings Observer

    func observeSettings(handler: @escaping ([String: Any]) -> Void) -> DatabaseHandle {
        return settingsRef.observe(.value) { snapshot in
            let dict = Self.dictFromAny(snapshot.value)
            DispatchQueue.main.async { handler(dict) }
        }
    }

    func removeSettingsObserver(handle: DatabaseHandle) {
        settingsRef.removeObserver(withHandle: handle)
    }
    
    /// Fetch settings once (not observe). Handler is called on the main queue.
    func fetchSettings(completion: @escaping ([String: Any]) -> Void) {
        settingsRef.observeSingleEvent(of: .value) { snapshot in
            let dict = Self.dictFromAny(snapshot.value)
            DispatchQueue.main.async { completion(dict) }
        }
    }

    /// Get seats reference for direct access (used by MultiplayerBlackjackViewController for initial sync)
    var seatsRefForSync: DatabaseReference {
        return seatsRef
    }

    /// Ensure the game node exists with initial phase (e.g. waiting_for_ready). Call once after join. Uses a transaction so we never overwrite an existing node (e.g. after startGame has already set phase to "betting").
    func ensureGameNodeExistsIfNeeded(completion: (() -> Void)? = nil) {
        gameRef.runTransactionBlock({ currentData in
            let value = currentData.value
            let isEmpty = (value == nil || value is NSNull)
            let dict = Self.dictionaryFromTransactionValue(value)
            let hasPhase = (dict["phase"] != nil)
            if isEmpty || !hasPhase {
                currentData.value = [
                    "phase": "betting",
                    "handNumber": 0,
                    "playerHands": [String: Any](),
                    "dealerCards": [Any](),
                    "deckIndex": 0,
                    "deckSeed": 0,
                    "deckCount": 1,
                    "dealerHoleRevealed": false,
                    "currentTurn": NSNull(),
                    "phaseResumeAt": 0
                ]
                return TransactionResult.success(withValue: currentData)
            }
            return TransactionResult.abort()
        }) { _, _, _ in
            DispatchQueue.main.async { completion?() }
        }
    }
    
    /// Convert transaction currentData.value to [String: Any]. Firebase iOS often returns NSDictionary; direct cast can fail and yield empty dict, causing every join to see no players and claim seat 0.
    private static func dictionaryFromTransactionValue(_ value: Any?) -> [String: Any] {
        guard let value = value else { return [:] }
        if let dict = value as? [String: Any] { return dict }
        guard let ns = value as? NSDictionary else { return [:] }
        var result: [String: Any] = [:]
        for (k, v) in ns {
            if let key = k as? String {
                result[key] = v
            }
        }
        return result
    }
    
    /// Parse seats from table data (data has "seats" key). Firebase may return nested structure as dict, array, or NSDictionary.
    private static func parseSeats(from data: [String: Any]) -> [String: [String: Any]] {
        guard let raw = data[Self.seatsKey] else { return [:] }
        return parseSeatsValue(raw)
    }
    
    /// Convert any nested NSDictionary (e.g. a single seat) to [String: Any] so we don't lose fields like playerId.
    private static func dictFromAny(_ value: Any?) -> [String: Any] {
        guard let value = value else { return [:] }
        if let d = value as? [String: Any] { return d }
        guard let ns = value as? NSDictionary else { return [:] }
        var result: [String: Any] = [:]
        for (k, v) in ns {
            if let key = k as? String { result[key] = v }
        }
        return result
    }

    /// Parse Int from Firebase/callable result (can be Int or NSNumber). Use for balance, bet, etc.
    static func intFromAny(_ value: Any?) -> Int? {
        guard let value = value else { return nil }
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    /// Parse hands from a seat dict. Firebase may store hands as array or as object with keys "0", "1".
    private static func parseHandsFromSeat(_ seat: [String: Any], playerId: String) -> [HandData] {
        let handsRaw = seat["hands"]
        if let handsArray = handsRaw as? [[String: Any]], !handsArray.isEmpty {
            return handsArray.compactMap { HandData.from($0) }
        }
        if let handsDict = handsRaw as? [String: Any] {
            var list: [HandData] = []
            for i in 0..<maxSeats {
                let key = "\(i)"
                let raw = handsDict[key]
                let handDict = dictFromAny(raw)
                if let h = HandData.from(handDict) {
                    list.append(h)
                }
            }
            if !list.isEmpty { return list }
        }
        if let handsNS = handsRaw as? NSDictionary {
            var list: [HandData] = []
            for i in 0..<maxSeats {
                let key = "\(i)"
                let raw = handsNS[key] ?? handsNS[NSNumber(value: i)]
                let handDict = dictFromAny(raw)
                if let h = HandData.from(handDict) {
                    list.append(h)
                }
            }
            if !list.isEmpty { return list }
        }
        if let oldBet = seat["bet"] as? Int, oldBet > 0 {
            return [HandData(bet: oldBet, cards: [], stood: false, doubled: false, busted: false, playerId: playerId)]
        }
        return []
    }

    /// Parse raw seats value (from seatsRef or data["seats"]). Handles [String: Any], array, or NSDictionary. Nested seat objects can also be NSDictionary.
    private static func parseSeatsValue(_ raw: Any?) -> [String: [String: Any]] {
        guard let raw = raw else { return [:] }
        // Dictionary with string keys "0", "1", ...
        if let dict = raw as? [String: [String: Any]] {
            return dict
        }
        // Array when Firebase serializes numeric keys as array
        if let arr = raw as? [[String: Any]] {
            var result: [String: [String: Any]] = [:]
            for (i, seat) in arr.enumerated() where i < Self.maxSeats {
                result["\(i)"] = dictFromAny(seat)
            }
            return result
        }
        // NSDictionary from Firebase (keys can be NSString "0" or NSNumber 0); each seat value can also be NSDictionary
        if let nsDict = raw as? NSDictionary {
            var result: [String: [String: Any]] = [:]
            for i in 0..<Self.maxSeats {
                let seat = nsDict["\(i)"] ?? nsDict[NSNumber(value: i)]
                result["\(i)"] = dictFromAny(seat)
            }
            return result
        }
        return [:]
    }
}
