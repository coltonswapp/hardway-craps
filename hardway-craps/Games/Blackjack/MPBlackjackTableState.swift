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

    private static let path = "mp_blackjack/table"
    private static let seatsKey = "seats"
    private static let maxSeats = 4

    private let ref: DatabaseReference
    private var seatsRef: DatabaseReference { ref.child(Self.seatsKey) }

    init(database: Database = .database()) {
        self.ref = database.reference().child(Self.path)
    }

    /// Hand data for a player (primary or split hand)
    struct HandData {
        let bet: Int
        // Future: could add cards: [String] for full game state sync

        func toDictionary() -> [String: Any] {
            return ["bet": bet]
        }

        static func from(_ dict: [String: Any]?) -> HandData? {
            guard let dict = dict,
                  let bet = dict["bet"] as? Int else { return nil }
            return HandData(bet: bet)
        }
    }

    /// Seat payload as stored in Firebase (and returned when reading).
    struct SeatData {
        let playerId: String?
        let displayName: String
        let balance: Int
        let chipColorName: String
        let hands: [HandData]

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
    
    /// Pre-assigned colors for the 4 seats
    static let seatColors = [
        "Yellow Green",
        "Cyan",
        "Green",
        "Red"
    ]
    
    /// Initialize or ensure table exists with pre-assigned colors for each seat.
    /// Uses NSDictionary-safe parsing so we never overwrite existing playerId/displayName/balance.
    func initializeTableIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        ref.runTransactionBlock({ currentData in
            var data = Self.dictionaryFromTransactionValue(currentData.value)
            var seats = Self.parseSeats(from: data)
            var needsUpdate = false
            
            // Ensure all 4 seats exist with their pre-assigned colors; never replace existing seat content
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
        }) { [weak self] error, committed, _ in
            if let error = error {
                completion(.failure(error))
                return
            }
            if committed {
                print("✅ [MPBlackjack] Player assigned to seat \(seatIndex) with color '\(colorName)'")
                completion(.success((seatIndex: seatIndex, chipColorName: colorName)))
                return
            }
            // This seat was taken, try next
            self?.tryJoinSeat(seatIndex: seatIndex + 1, playerId: playerId, displayName: displayName, balance: balance, completion: completion)
        }
    }
    
    private func findPlayerInSeats(_ seats: [String: [String: Any]], playerId: String, completion: @escaping (Result<(seatIndex: Int, chipColorName: String), Error>) -> Void) {
        for i in 0..<Self.maxSeats {
            let key = "\(i)"
            guard let seat = seats[key] as? [String: Any],
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
        seatsRef.observeSingleEvent(of: .value) { snapshot in
            let seatsDict = Self.parseSeatsValue(snapshot.value)
            var result: [(seatIndex: Int, seatData: SeatData)] = []
            for i in 0..<Self.maxSeats {
                let key = "\(i)"
                guard let seat = seatsDict[key],
                      let playerId = seat["playerId"] as? String, !playerId.isEmpty else { continue }
                // Parse hands array
                var hands: [HandData] = []
                if let handsArray = seat["hands"] as? [[String: Any]] {
                    hands = handsArray.compactMap { HandData.from($0) }
                }
                // Backward compatibility: if no hands but has bet field, create single hand
                if hands.isEmpty, let oldBet = seat["bet"] as? Int, oldBet > 0 {
                    hands = [HandData(bet: oldBet)]
                }

                result.append((seatIndex: i, seatData: SeatData(
                    playerId: playerId,
                    displayName: seat["displayName"] as? String ?? "",
                    balance: seat["balance"] as? Int ?? 0,
                    chipColorName: seat["chipColorName"] as? String ?? Self.seatColors[i],
                    hands: hands
                )))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Fetch current seats once (only returns seats with players).
    func getSeats(completion: @escaping ([SeatData]) -> Void) {
        seatsRef.observeSingleEvent(of: .value) { snapshot in
            let seatsDict = Self.parseSeatsValue(snapshot.value)
            var result: [SeatData] = []
            for i in 0..<Self.maxSeats {
                let key = "\(i)"
                guard let seat = seatsDict[key],
                      let playerId = seat["playerId"] as? String, !playerId.isEmpty else { continue }
                // Parse hands array
                var hands: [HandData] = []
                if let handsArray = seat["hands"] as? [[String: Any]] {
                    hands = handsArray.compactMap { HandData.from($0) }
                }
                // Backward compatibility: if no hands but has bet field, create single hand
                if hands.isEmpty, let oldBet = seat["bet"] as? Int, oldBet > 0 {
                    hands = [HandData(bet: oldBet)]
                }

                result.append(SeatData(
                    playerId: playerId,
                    displayName: seat["displayName"] as? String ?? "",
                    balance: seat["balance"] as? Int ?? 0,
                    chipColorName: seat["chipColorName"] as? String ?? Self.seatColors[i],
                    hands: hands
                ))
            }
            completion(result)
        }
    }

    /// Observe seats in real time. Handler receives array of (seatIndex, SeatData) tuples (only seats with players).
    /// Handler is called on the main queue.
    @discardableResult
    func observeSeats(handler: @escaping ([(seatIndex: Int, seatData: SeatData)]) -> Void) -> DatabaseHandle {
        return seatsRef.observe(.value) { snapshot in
            let seatsDict = Self.parseSeatsValue(snapshot.value)
            var result: [(seatIndex: Int, seatData: SeatData)] = []
            for i in 0..<Self.maxSeats {
                let key = "\(i)"
                guard let seat = seatsDict[key],
                      let playerId = seat["playerId"] as? String, !playerId.isEmpty else { continue }
                // Parse hands array
                var hands: [HandData] = []
                if let handsArray = seat["hands"] as? [[String: Any]] {
                    hands = handsArray.compactMap { HandData.from($0) }
                }
                // Backward compatibility: if no hands but has bet field, create single hand
                if hands.isEmpty, let oldBet = seat["bet"] as? Int, oldBet > 0 {
                    hands = [HandData(bet: oldBet)]
                }

                result.append((seatIndex: i, seatData: SeatData(
                    playerId: playerId,
                    displayName: seat["displayName"] as? String ?? "",
                    balance: seat["balance"] as? Int ?? 0,
                    chipColorName: seat["chipColorName"] as? String ?? Self.seatColors[i],
                    hands: hands
                )))
            }
            DispatchQueue.main.async { handler(result) }
        }
    }

    func removeSeatsObserver(handle: DatabaseHandle) {
        seatsRef.removeObserver(withHandle: handle)
    }

    /// Leave the table: clear player data from their seat while preserving the seat's chipColorName.
    /// Uses setValue to clear the seat (simpler than transaction since we already verified ownership).
    func leaveTable(playerId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🚪 [MPBlackjack] leaveTable called for playerId: \(playerId)")

        // Find which seat this player occupies
        getSeatsWithIndices { [weak self] seatsWithIndices in
            guard let self = self else {
                print("⚠️ [MPBlackjack] Self is nil in getSeatsWithIndices callback")
                return
            }

            print("🚪 [MPBlackjack] Current seats: \(seatsWithIndices.map { "seat \($0.seatIndex): \($0.seatData.playerId ?? "nil")" })")

            // Find the player's seat
            guard let playerSeat = seatsWithIndices.first(where: { $0.seatData.playerId == playerId }) else {
                print("⚠️ [MPBlackjack] Player \(playerId) not found at table")
                completion(.success(())) // Not an error - player already left
                return
            }

            let seatIndex = playerSeat.seatIndex
            let chipColorName = playerSeat.seatData.chipColorName
            print("🚪 [MPBlackjack] Found player in seat \(seatIndex), will clear and preserve color '\(chipColorName)'")

            let seatRef = self.seatsRef.child("\(seatIndex)")

            // Clear player data but preserve chipColorName
            let clearedSeat: [String: Any] = [
                "chipColorName": chipColorName
            ]

            print("🚪 [MPBlackjack] Setting seat \(seatIndex) to: \(clearedSeat)")
            seatRef.setValue(clearedSeat) { error, _ in
                if let error = error {
                    print("❌ [MPBlackjack] Failed to leave table: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ [MPBlackjack] Successfully cleared seat \(seatIndex)")
                    completion(.success(()))
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

    /// Get seats reference for direct access (used by MultiplayerBlackjackViewController for initial sync)
    var seatsRefForSync: DatabaseReference {
        return seatsRef
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
