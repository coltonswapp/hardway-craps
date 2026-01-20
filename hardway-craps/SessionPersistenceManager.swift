//
//  SessionPersistenceManager.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import Foundation

class SessionPersistenceManager {
    static let shared = SessionPersistenceManager()
    
    private let fileName = "game_sessions.json"
    
    private var fileURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent(fileName)
    }
    
    private init() {}
    
    func saveSession(_ session: GameSession) {
        var sessions = loadAllSessions()
        sessions.append(session)
        // Sort by date, most recent first
        sessions.sort { $0.date > $1.date }
        saveSessions(sessions)
    }
    
    func loadAllSessions() -> [GameSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let sessions = try decoder.decode([GameSession].self, from: data)
            return sessions
        } catch {
            print("Error loading sessions: \(error)")
            return []
        }
    }
    
    private func saveSessions(_ sessions: [GameSession]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(sessions)
            try data.write(to: fileURL)
        } catch {
            print("Error saving sessions: \(error)")
        }
    }
}

