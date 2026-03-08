//
//  FirebasePlaygroundEventLogger.swift
//  hardway-craps
//
//  Logs multiplayer bet playground events to Firebase Realtime Database (default instance).
//

import Foundation
import FirebaseDatabase

/// Event types for the multiplayer bet playground. Extensible for moved_bet, etc.
enum PlaygroundEventType: String, Codable {
    case placedBet = "placed_bet"
    case movedBet = "moved_bet"
}

/// Writes playground events to Firebase Realtime Database (default instance from plist).
final class FirebasePlaygroundEventLogger {

    /// Player slot on the shared Pass Line control.
    enum PlayerSlot: String, Codable {
        case A = "A"
        case B = "B"
    }

    /// Path for events; use push keys so clients can observe .childAdded for streaming.
    private static let eventsPath = "playground/pass_line/events"

    private let ref: DatabaseReference

    init(database: Database = .database()) {
        self.ref = database.reference().child(Self.eventsPath)
    }

    /// Log a "placed bet" event.
    func logPlacedBet(playerId: String, playerSlot: PlayerSlot, amount: Int) {
        let payload = PlaygroundEventPayload(
            playerId: playerId,
            playerSlot: playerSlot,
            eventType: .placedBet,
            amount: amount
        )
        write(payload)
    }

    /// Log a "moved bet" event (for future use).
    func logMovedBet(playerId: String, playerSlot: PlayerSlot, amount: Int, previousAmount: Int? = nil) {
        var payloadDict: [String: Any] = [
            "playerId": playerId,
            "playerSlot": playerSlot.rawValue,
            "eventType": PlaygroundEventType.movedBet.rawValue,
            "amount": amount,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let prev = previousAmount {
            payloadDict["previousAmount"] = prev
        }
        let childRef = ref.childByAutoId()
        childRef.setValue(payloadDict)
    }

    private func write(_ payload: PlaygroundEventPayload) {
        let childRef = ref.childByAutoId()
        guard let dict = try? payload.asDictionary() else { return }
        childRef.setValue(dict)
    }
}

/// Payload written to Realtime Database for each event.
struct PlaygroundEventPayload: Encodable {
    let playerId: String
    let playerSlot: String
    let eventType: String
    let amount: Int
    let timestamp: TimeInterval

    init(playerId: String, playerSlot: FirebasePlaygroundEventLogger.PlayerSlot, eventType: PlaygroundEventType, amount: Int) {
        self.playerId = playerId
        self.playerSlot = playerSlot.rawValue
        self.eventType = eventType.rawValue
        self.amount = amount
        self.timestamp = Date().timeIntervalSince1970
    }
}

private extension Encodable {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "FirebasePlaygroundEventLogger", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode as dictionary"])
        }
        return dict
    }
}
