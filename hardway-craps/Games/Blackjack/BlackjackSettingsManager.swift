//
//  BlackjackSettingsManager.swift
//  hardway-craps
//
//  Created by Claude Code on 1/26/26.
//

import Foundation

/// Settings structure containing all Blackjack game configuration
struct BlackjackSettings {
    var showTotals: Bool
    var showDeckCount: Bool
    var showCardCount: Bool
    var deckCount: Int
    var deckPenetration: Double?
    var rebetEnabled: Bool
    var rebetAmount: Int
    var selectedSideBets: [BlackjackSettingsViewController.SideBetType]
    var fixedHandType: FixedHandType?

    /// Default settings configuration
    static var defaultSettings: BlackjackSettings {
        return BlackjackSettings(
            showTotals: true,
            showDeckCount: false,
            showCardCount: false,
            deckCount: 1,
            deckPenetration: nil,
            rebetEnabled: false,
            rebetAmount: 10,
            selectedSideBets: [.royalMatch, .perfectPairs],
            fixedHandType: nil
        )
    }
}

/// Delegate protocol for settings changes
protocol BlackjackSettingsManagerDelegate: AnyObject {
    func settingsDidChange(_ settings: BlackjackSettings)
}

/// Manages persistence and coordination of Blackjack game settings
final class BlackjackSettingsManager {

    // MARK: - Properties

    weak var delegate: BlackjackSettingsManagerDelegate?

    private(set) var currentSettings: BlackjackSettings

    // MARK: - Initialization

    init() {
        // Load settings from UserDefaults on initialization
        self.currentSettings = BlackjackSettingsManager.loadSettingsFromUserDefaults()
    }

    // MARK: - Public Methods

    /// Load settings from UserDefaults
    func loadSettings() {
        currentSettings = BlackjackSettingsManager.loadSettingsFromUserDefaults()
    }

    /// Save current settings to UserDefaults
    func saveSettings() {
        BlackjackSettingsManager.saveSettingsToUserDefaults(currentSettings)
    }

    /// Update settings and notify delegate
    func updateSettings(_ settings: BlackjackSettings) {
        currentSettings = settings
        saveSettings()
        delegate?.settingsDidChange(settings)
    }

    /// Toggle display totals setting
    func toggleTotals() {
        currentSettings.showTotals.toggle()
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    /// Toggle deck count display setting
    func toggleDeckCount() {
        currentSettings.showDeckCount.toggle()
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    /// Toggle card count display setting
    func toggleCardCount() {
        currentSettings.showCardCount.toggle()
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    /// Set the number of decks (1, 2, 4, or 6)
    func setDeckCount(_ count: Int) {
        guard [1, 2, 4, 6].contains(count) else { return }
        currentSettings.deckCount = count
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    /// Set deck penetration (nil = full deck, -1.0 = random, 0.0-1.0 = percentage)
    func setDeckPenetration(_ penetration: Double?) {
        currentSettings.deckPenetration = penetration
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    /// Set fixed hand type for testing
    func setFixedHandType(_ handType: FixedHandType?) {
        currentSettings.fixedHandType = handType
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
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

    /// Set selected side bets
    func setSelectedSideBets(_ sideBets: [BlackjackSettingsViewController.SideBetType]) {
        currentSettings.selectedSideBets = sideBets
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    // MARK: - Private Helper Methods

    /// Load settings from UserDefaults
    private static func loadSettingsFromUserDefaults() -> BlackjackSettings {
        let defaults = UserDefaults.standard

        // Load showTotals (default: true)
        let showTotals: Bool
        if defaults.object(forKey: BlackjackSettingsKeys.showTotals) != nil {
            showTotals = defaults.bool(forKey: BlackjackSettingsKeys.showTotals)
        } else {
            showTotals = true
        }

        // Load showDeckCount (default: false)
        let showDeckCount: Bool
        if defaults.object(forKey: BlackjackSettingsKeys.showDeckCount) != nil {
            showDeckCount = defaults.bool(forKey: BlackjackSettingsKeys.showDeckCount)
        } else {
            showDeckCount = false
        }

        // Load showCardCount (default: false)
        let showCardCount: Bool
        if defaults.object(forKey: BlackjackSettingsKeys.showCardCount) != nil {
            showCardCount = defaults.bool(forKey: BlackjackSettingsKeys.showCardCount)
        } else {
            showCardCount = false
        }

        // Load deckCount (default: 1)
        let deckCount: Int
        if defaults.object(forKey: BlackjackSettingsKeys.deckCount) != nil {
            let savedDeckCount = defaults.integer(forKey: BlackjackSettingsKeys.deckCount)
            if [1, 2, 4, 6].contains(savedDeckCount) {
                deckCount = savedDeckCount
            } else {
                deckCount = 1
            }
        } else {
            deckCount = 1
        }

        // Load rebetEnabled (default: false)
        let rebetEnabled: Bool
        if defaults.object(forKey: BlackjackSettingsKeys.rebetEnabled) != nil {
            rebetEnabled = defaults.bool(forKey: BlackjackSettingsKeys.rebetEnabled)
        } else {
            rebetEnabled = false
        }

        // Load rebetAmount (default: 10)
        let rebetAmount: Int
        if defaults.object(forKey: BlackjackSettingsKeys.rebetAmount) != nil {
            rebetAmount = defaults.integer(forKey: BlackjackSettingsKeys.rebetAmount)
        } else {
            rebetAmount = 10
        }

        // Load deckPenetration (default: nil = full deck)
        // -1.0 = random, 0.0 = full deck, > 0 && <= 1.0 = specific percentage
        let deckPenetration: Double?
        if defaults.object(forKey: BlackjackSettingsKeys.deckPenetration) != nil {
            let savedPenetration = defaults.double(forKey: BlackjackSettingsKeys.deckPenetration)
            if savedPenetration == -1.0 {
                deckPenetration = -1.0 // Random
            } else if savedPenetration > 0 && savedPenetration <= 1.0 {
                deckPenetration = savedPenetration
            } else if savedPenetration == 0 {
                deckPenetration = nil // 0 means full deck
            } else {
                deckPenetration = nil
            }
        } else {
            deckPenetration = nil
        }

        // Load fixedHandType (default: nil/random)
        let fixedHandType: FixedHandType?
        if let savedHandType = defaults.string(forKey: BlackjackSettingsKeys.fixedHandType) {
            fixedHandType = FixedHandType(rawValue: savedHandType)
        } else {
            fixedHandType = nil
        }

        // Load selected side bets
        let selectedSideBets: [BlackjackSettingsViewController.SideBetType]
        if let savedSideBets = defaults.array(forKey: BlackjackSettingsKeys.selectedSideBets) as? [String] {
            selectedSideBets = savedSideBets.compactMap { BlackjackSettingsViewController.SideBetType(rawValue: $0) }
        } else {
            // Default to Royal Match and Perfect Pairs
            selectedSideBets = [.royalMatch, .perfectPairs]
        }

        return BlackjackSettings(
            showTotals: showTotals,
            showDeckCount: showDeckCount,
            showCardCount: showCardCount,
            deckCount: deckCount,
            deckPenetration: deckPenetration,
            rebetEnabled: rebetEnabled,
            rebetAmount: rebetAmount,
            selectedSideBets: selectedSideBets,
            fixedHandType: fixedHandType
        )
    }

    /// Save settings to UserDefaults
    private static func saveSettingsToUserDefaults(_ settings: BlackjackSettings) {
        let defaults = UserDefaults.standard

        defaults.set(settings.showTotals, forKey: BlackjackSettingsKeys.showTotals)
        defaults.set(settings.showDeckCount, forKey: BlackjackSettingsKeys.showDeckCount)
        defaults.set(settings.showCardCount, forKey: BlackjackSettingsKeys.showCardCount)
        defaults.set(settings.deckCount, forKey: BlackjackSettingsKeys.deckCount)
        defaults.set(settings.rebetEnabled, forKey: BlackjackSettingsKeys.rebetEnabled)
        defaults.set(settings.rebetAmount, forKey: BlackjackSettingsKeys.rebetAmount)

        // Save deck penetration
        if let penetration = settings.deckPenetration {
            defaults.set(penetration, forKey: BlackjackSettingsKeys.deckPenetration)
        } else {
            defaults.set(0.0, forKey: BlackjackSettingsKeys.deckPenetration) // 0 = full deck
        }

        // Save fixed hand type
        if let handType = settings.fixedHandType {
            defaults.set(handType.rawValue, forKey: BlackjackSettingsKeys.fixedHandType)
        } else {
            defaults.removeObject(forKey: BlackjackSettingsKeys.fixedHandType)
        }

        // Save selected side bets
        let sideBetStrings = settings.selectedSideBets.map { $0.rawValue }
        defaults.set(sideBetStrings, forKey: BlackjackSettingsKeys.selectedSideBets)
    }
}
