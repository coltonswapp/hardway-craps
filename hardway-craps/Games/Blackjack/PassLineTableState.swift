//
//  PassLineTableState.swift
//  hardway-craps
//
//  Manages playground/pass_line slot assignment and amounts in Firebase.
//  First device to place a bet gets slot A (left chip), second gets slot B (right chip).
//

import Foundation
import FirebaseDatabase

final class PassLineTableState {

    typealias PlayerSlot = FirebasePlaygroundEventLogger.PlayerSlot

    private static let path = "playground/pass_line"
    private let ref: DatabaseReference

    init(database: Database = .database()) {
        self.ref = database.reference().child(Self.path)
    }

    /// Place a bet: claim slot A or B if this player hasn't yet, then add amount to that slot.
    /// Completion returns the slot assigned and the new total for that slot, or an error (e.g. game full).
    func placeBet(playerId: String, amount: Int, completion: @escaping (Result<(slot: PlayerSlot, newTotal: Int), Error>) -> Void) {
        ref.runTransactionBlock({ currentData in
            let data = currentData.value as? [String: Any] ?? [:]
            let playerIdA = data["playerIdA"] as? String ?? ""
            let playerIdB = data["playerIdB"] as? String ?? ""
            var amountA = data["amountA"] as? Int ?? 0
            var amountB = data["amountB"] as? Int ?? 0
            var balances = data["balances"] as? [String: Int] ?? [:]

            var newData: [String: Any] = [:]

            if playerIdA == playerId {
                amountA += amount
                newData = ["playerIdA": playerIdA, "playerIdB": playerIdB, "amountA": amountA, "amountB": amountB]
                // Preserve balances dictionary
                if !balances.isEmpty {
                    newData["balances"] = balances
                }
                currentData.value = newData
                return .success(withValue: currentData)
            }
            if playerIdB == playerId {
                amountB += amount
                newData = ["playerIdA": playerIdA, "playerIdB": playerIdB, "amountA": amountA, "amountB": amountB]
                // Preserve balances dictionary
                if !balances.isEmpty {
                    newData["balances"] = balances
                }
                currentData.value = newData
                return .success(withValue: currentData)
            }
            if playerIdA.isEmpty {
                amountA = amount
                newData = ["playerIdA": playerId, "playerIdB": playerIdB, "amountA": amountA, "amountB": amountB]
                // Preserve balances dictionary
                if !balances.isEmpty {
                    newData["balances"] = balances
                }
                currentData.value = newData
                return .success(withValue: currentData)
            }
            if playerIdB.isEmpty {
                amountB = amount
                newData = ["playerIdA": playerIdA, "playerIdB": playerId, "amountA": amountA, "amountB": amountB]
                // Preserve balances dictionary
                if !balances.isEmpty {
                    newData["balances"] = balances
                }
                currentData.value = newData
                return .success(withValue: currentData)
            }
            return .abort()
        }) { error, committed, snapshot in
            guard error == nil, committed else {
                completion(.failure(NSError(domain: "PassLineTableState", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transaction failed or game full"])))
                return
            }
            let readCompletion: ([String: Any]) -> Void = { data in
                let playerIdA = data["playerIdA"] as? String ?? ""
                let amountA = data["amountA"] as? Int ?? 0
                let amountB = data["amountB"] as? Int ?? 0
                if playerIdA == playerId {
                    completion(.success((.A, amountA)))
                } else {
                    completion(.success((.B, amountB)))
                }
            }
            if let snapshot = snapshot, let data = snapshot.value as? [String: Any] {
                readCompletion(data)
            } else {
                self.ref.observeSingleEvent(of: .value) { snap in
                    let data = snap.value as? [String: Any] ?? [:]
                    readCompletion(data)
                }
            }
        }
    }

    /// Observe amountA and amountB; handler is called on initial value and on every update.
    @discardableResult
    func observeAmounts(handler: @escaping (Int, Int) -> Void) -> DatabaseHandle {
        ref.observe(.value) { snapshot in
            let data = snapshot.value as? [String: Any] ?? [:]
            let amountA = data["amountA"] as? Int ?? 0
            let amountB = data["amountB"] as? Int ?? 0
            handler(amountA, amountB)
        }
    }

    /// Update a player's balance in Firebase.
    /// Uses both the legacy balanceA/balanceB fields (for backward compatibility) and the scalable balances dictionary.
    func updateBalance(playerId: String, balance: Int) {
        ref.runTransactionBlock({ currentData in
            let data = currentData.value as? [String: Any] ?? [:]
            let playerIdA = data["playerIdA"] as? String ?? ""
            let playerIdB = data["playerIdB"] as? String ?? ""
            var balances = data["balances"] as? [String: Int] ?? [:]

            var newData: [String: Any] = data

            // Update scalable balances dictionary
            balances[playerId] = balance
            newData["balances"] = balances

            // Also update legacy balanceA/balanceB for backward compatibility
            if playerIdA == playerId {
                newData["balanceA"] = balance
            } else if playerIdB == playerId {
                newData["balanceB"] = balance
            }

            // Preserve existing fields
            newData["playerIdA"] = playerIdA
            newData["playerIdB"] = playerIdB
            if let amountA = data["amountA"] {
                newData["amountA"] = amountA
            }
            if let amountB = data["amountB"] {
                newData["amountB"] = amountB
            }

            currentData.value = newData
            return .success(withValue: currentData)
        }) { error, committed, _ in
            if let error = error {
                print("Failed to update balance: \(error.localizedDescription)")
            }
        }
    }

    /// Observe player balances; handler is called on initial value and on every update.
    /// Returns (playerIdA, balanceA, playerIdB, balanceB)
    /// Uses scalable balances dictionary, falls back to legacy balanceA/balanceB for backward compatibility.
    @discardableResult
    func observeBalances(handler: @escaping (String?, Int?, String?, Int?) -> Void) -> DatabaseHandle {
        ref.observe(.value) { snapshot in
            let data = snapshot.value as? [String: Any] ?? [:]
            let playerIdA = data["playerIdA"] as? String
            let playerIdB = data["playerIdB"] as? String
            let balances = data["balances"] as? [String: Int] ?? [:]
            
            // Get balances from scalable dictionary, fall back to legacy fields
            var balanceA: Int?
            var balanceB: Int?
            
            if let idA = playerIdA {
                balanceA = balances[idA] ?? data["balanceA"] as? Int
            }
            if let idB = playerIdB {
                balanceB = balances[idB] ?? data["balanceB"] as? Int
            }
            
            handler(playerIdA, balanceA, playerIdB, balanceB)
        }
    }

    func removeObserver(handle: DatabaseHandle) {
        ref.removeObserver(withHandle: handle)
    }

    func removeBalanceObserver(handle: DatabaseHandle) {
        ref.removeObserver(withHandle: handle)
    }
    
    /// Update chip color for a slot (A or B) in Firebase
    func updateChipColor(slot: PlayerSlot, colorSetName: String) {
        ref.runTransactionBlock({ currentData in
            let data = currentData.value as? [String: Any] ?? [:]
            var newData: [String: Any] = data
            
            // Store color for the slot
            switch slot {
            case .A:
                newData["chipColorA"] = colorSetName
            case .B:
                newData["chipColorB"] = colorSetName
            }
            
            // Preserve all existing fields
            if let playerIdA = data["playerIdA"] {
                newData["playerIdA"] = playerIdA
            }
            if let playerIdB = data["playerIdB"] {
                newData["playerIdB"] = playerIdB
            }
            if let amountA = data["amountA"] {
                newData["amountA"] = amountA
            }
            if let amountB = data["amountB"] {
                newData["amountB"] = amountB
            }
            if let balances = data["balances"] {
                newData["balances"] = balances
            }
            
            currentData.value = newData
            return .success(withValue: currentData)
        }) { error, committed, _ in
            if let error = error {
                print("Failed to update chip color: \(error.localizedDescription)")
            }
        }
    }
    
    /// Observe chip colors for both slots; handler is called on initial value and on every update.
    /// Returns (colorSetNameA, colorSetNameB)
    @discardableResult
    func observeChipColors(handler: @escaping (String?, String?) -> Void) -> DatabaseHandle {
        ref.observe(.value) { snapshot in
            let data = snapshot.value as? [String: Any] ?? [:]
            let colorA = data["chipColorA"] as? String
            let colorB = data["chipColorB"] as? String
            handler(colorA, colorB)
        }
    }
    
    func removeChipColorObserver(handle: DatabaseHandle) {
        ref.removeObserver(withHandle: handle)
    }
}
