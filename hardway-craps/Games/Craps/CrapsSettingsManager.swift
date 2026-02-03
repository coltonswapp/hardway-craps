//
//  CrapsSettingsManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/28/26.
//

import Foundation

/// Settings structure containing all Craps game configuration
struct CrapsSettings {
    var rebetEnabled: Bool
    var rebetAmount: Int
    var hardwaysEnabled: Bool
    var makeEmEnabled: Bool
    var hornEnabled: Bool

    /// Default settings configuration
    static var defaultSettings: CrapsSettings {
        return CrapsSettings(
            rebetEnabled: false,
            rebetAmount: 10,
            hardwaysEnabled: true,
            makeEmEnabled: true,
            hornEnabled: true
        )
    }
}

/// Delegate protocol for settings changes
protocol CrapsSettingsManagerDelegate: AnyObject {
    func settingsDidChange(_ settings: CrapsSettings)
}

/// Manages persistence and coordination of Craps game settings
final class CrapsSettingsManager {

    // MARK: - Properties

    weak var delegate: CrapsSettingsManagerDelegate?

    private(set) var currentSettings: CrapsSettings

    // MARK: - Initialization

    init() {
        // Load settings from UserDefaults on initialization
        self.currentSettings = CrapsSettingsManager.loadSettingsFromUserDefaults()
    }

    // MARK: - Public Methods

    /// Load settings from UserDefaults
    func loadSettings() {
        currentSettings = CrapsSettingsManager.loadSettingsFromUserDefaults()
    }

    /// Save current settings to UserDefaults
    func saveSettings() {
        CrapsSettingsManager.saveSettingsToUserDefaults(currentSettings)
    }

    /// Update settings and notify delegate
    func updateSettings(_ settings: CrapsSettings) {
        currentSettings = settings
        saveSettings()
        delegate?.settingsDidChange(settings)
    }

    /// Set rebet enabled state
    func setRebetEnabled(_ enabled: Bool) {
        currentSettings.rebetEnabled = enabled
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    /// Set rebet amount
    func setRebetAmount(_ amount: Int) {
        currentSettings.rebetAmount = amount
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    /// Set hardways enabled state
    func setHardwaysEnabled(_ enabled: Bool) {
        currentSettings.hardwaysEnabled = enabled
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    /// Set Make Em enabled state
    func setMakeEmEnabled(_ enabled: Bool) {
        currentSettings.makeEmEnabled = enabled
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    /// Set horn enabled state
    func setHornEnabled(_ enabled: Bool) {
        currentSettings.hornEnabled = enabled
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    // MARK: - Private Helper Methods

    /// Load settings from UserDefaults
    private static func loadSettingsFromUserDefaults() -> CrapsSettings {
        let defaults = UserDefaults.standard

        // Load rebetEnabled (default: false)
        let rebetEnabled: Bool
        if defaults.object(forKey: CrapsSettingsKeys.rebetEnabled) != nil {
            rebetEnabled = defaults.bool(forKey: CrapsSettingsKeys.rebetEnabled)
        } else {
            rebetEnabled = false
        }

        // Load rebetAmount (default: 10)
        let rebetAmount: Int
        if defaults.object(forKey: CrapsSettingsKeys.rebetAmount) != nil {
            rebetAmount = defaults.integer(forKey: CrapsSettingsKeys.rebetAmount)
        } else {
            rebetAmount = 10
        }

        // Load hardwaysEnabled (default: true)
        let hardwaysEnabled: Bool
        if defaults.object(forKey: CrapsSettingsKeys.hardwaysEnabled) != nil {
            hardwaysEnabled = defaults.bool(forKey: CrapsSettingsKeys.hardwaysEnabled)
        } else {
            hardwaysEnabled = true
        }

        // Load makeEmEnabled (default: true)
        let makeEmEnabled: Bool
        if defaults.object(forKey: CrapsSettingsKeys.makeEmEnabled) != nil {
            makeEmEnabled = defaults.bool(forKey: CrapsSettingsKeys.makeEmEnabled)
        } else {
            makeEmEnabled = true
        }

        // Load hornEnabled (default: true)
        let hornEnabled: Bool
        if defaults.object(forKey: CrapsSettingsKeys.hornEnabled) != nil {
            hornEnabled = defaults.bool(forKey: CrapsSettingsKeys.hornEnabled)
        } else {
            hornEnabled = true
        }

        return CrapsSettings(
            rebetEnabled: rebetEnabled,
            rebetAmount: rebetAmount,
            hardwaysEnabled: hardwaysEnabled,
            makeEmEnabled: makeEmEnabled,
            hornEnabled: hornEnabled
        )
    }

    /// Save settings to UserDefaults
    private static func saveSettingsToUserDefaults(_ settings: CrapsSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.rebetEnabled, forKey: CrapsSettingsKeys.rebetEnabled)
        defaults.set(settings.rebetAmount, forKey: CrapsSettingsKeys.rebetAmount)
        defaults.set(settings.hardwaysEnabled, forKey: CrapsSettingsKeys.hardwaysEnabled)
        defaults.set(settings.makeEmEnabled, forKey: CrapsSettingsKeys.makeEmEnabled)
        defaults.set(settings.hornEnabled, forKey: CrapsSettingsKeys.hornEnabled)
    }
}

// MARK: - Settings Keys

/// UserDefaults keys for Craps settings
private struct CrapsSettingsKeys {
    static let rebetEnabled = "CrapsRebetEnabled"
    static let rebetAmount = "CrapsRebetAmount"
    static let hardwaysEnabled = "CrapsHardwaysEnabled"
    static let makeEmEnabled = "CrapsMakeEmEnabled"
    static let hornEnabled = "CrapsHornEnabled"
}
