//
//  CrapsDebugSettings.swift
//  hardway-craps
//

import Foundation

enum CrapsDebugSettings {
    /// In-memory only: resets when the app process restarts. Random tap-to-roll never totals 7 when true (fixed rolls and UI tests unaffected).
    static var isNoSevensEnabled = false
}
