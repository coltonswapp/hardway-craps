//
//  BaccaratSettingsManager.swift
//  hardway-craps
//
//  Created by Claude Code on 3/10/26.
//

import Foundation

/// Settings structure containing Baccarat game configuration
struct BaccaratSettings {
    var showTotals: Bool
    var showBigRoad: Bool

    static var defaultSettings: BaccaratSettings {
        return BaccaratSettings(
            showTotals: true,
            showBigRoad: true
        )
    }
}

/// Delegate protocol for settings changes
protocol BaccaratSettingsManagerDelegate: AnyObject {
    func settingsDidChange(_ settings: BaccaratSettings)
}

/// Manages persistence and coordination of Baccarat game settings
final class BaccaratSettingsManager {

    // MARK: - Properties

    weak var delegate: BaccaratSettingsManagerDelegate?
    private(set) var currentSettings: BaccaratSettings

    // MARK: - Initialization

    init() {
        self.currentSettings = BaccaratSettingsManager.loadSettingsFromUserDefaults()
    }

    // MARK: - Public Methods

    func loadSettings() {
        currentSettings = BaccaratSettingsManager.loadSettingsFromUserDefaults()
    }

    func saveSettings() {
        BaccaratSettingsManager.saveSettingsToUserDefaults(currentSettings)
    }

    func toggleTotals() {
        currentSettings.showTotals.toggle()
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    func toggleBigRoad() {
        currentSettings.showBigRoad.toggle()
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    // MARK: - Private Helper Methods

    private static func loadSettingsFromUserDefaults() -> BaccaratSettings {
        let defaults = UserDefaults.standard

        let showTotals: Bool
        if defaults.object(forKey: BaccaratSettingsKeys.showTotals) != nil {
            showTotals = defaults.bool(forKey: BaccaratSettingsKeys.showTotals)
        } else {
            showTotals = true
        }

        let showBigRoad: Bool
        if defaults.object(forKey: BaccaratSettingsKeys.showBigRoad) != nil {
            showBigRoad = defaults.bool(forKey: BaccaratSettingsKeys.showBigRoad)
        } else {
            showBigRoad = true
        }

        return BaccaratSettings(
            showTotals: showTotals,
            showBigRoad: showBigRoad
        )
    }

    private static func saveSettingsToUserDefaults(_ settings: BaccaratSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.showTotals, forKey: BaccaratSettingsKeys.showTotals)
        defaults.set(settings.showBigRoad, forKey: BaccaratSettingsKeys.showBigRoad)
    }
}
