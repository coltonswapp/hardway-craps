//
//  CrapsSettingsManager.swift
//  hardway-craps
//

import Foundation

/// Unified settings for both standard craps and crapless craps.
struct CrapsGameSettings {
    var hardwaysEnabled: Bool
    var makeEmEnabled: Bool
    var hornEnabled: Bool

    static var defaultSettings: CrapsGameSettings {
        CrapsGameSettings(
            hardwaysEnabled: true,
            makeEmEnabled: true,
            hornEnabled: true
        )
    }
}

/// Backward-compatible aliases so existing code compiles unchanged.
typealias CrapsSettings = CrapsGameSettings
typealias CraplessSettings = CrapsGameSettings

protocol CrapsGameSettingsManagerDelegate: AnyObject {
    func settingsDidChange(_ settings: CrapsGameSettings)
}

typealias CrapsSettingsManagerDelegate = CrapsGameSettingsManagerDelegate
typealias CraplessSettingsManagerDelegate = CrapsGameSettingsManagerDelegate

/// Single settings manager for all craps variants, parameterized by `CrapsVariant`.
/// Each variant gets its own UserDefaults key namespace so preferences stay independent.
final class CrapsSettingsManager {

    weak var delegate: CrapsGameSettingsManagerDelegate?

    private(set) var currentSettings: CrapsGameSettings

    private let keys: KeySet

    init(variant: CrapsVariant = .standard) {
        self.keys = KeySet(variant: variant)
        self.currentSettings = Self.load(keys: keys)
    }

    func loadSettings() {
        currentSettings = Self.load(keys: keys)
    }

    func saveSettings() {
        Self.save(currentSettings, keys: keys)
    }

    func updateSettings(_ settings: CrapsGameSettings) {
        currentSettings = settings
        saveSettings()
        delegate?.settingsDidChange(settings)
    }

    func setHardwaysEnabled(_ enabled: Bool) {
        currentSettings.hardwaysEnabled = enabled
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    func setMakeEmEnabled(_ enabled: Bool) {
        currentSettings.makeEmEnabled = enabled
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    func setHornEnabled(_ enabled: Bool) {
        currentSettings.hornEnabled = enabled
        saveSettings()
        delegate?.settingsDidChange(currentSettings)
    }

    // MARK: - Persistence

    private static func load(keys: KeySet) -> CrapsGameSettings {
        let defaults = UserDefaults.standard

        func bool(for key: String, default defaultValue: Bool) -> Bool {
            defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : defaultValue
        }

        return CrapsGameSettings(
            hardwaysEnabled: bool(for: keys.hardwaysEnabled, default: true),
            makeEmEnabled: bool(for: keys.makeEmEnabled, default: true),
            hornEnabled: bool(for: keys.hornEnabled, default: true)
        )
    }

    private static func save(_ settings: CrapsGameSettings, keys: KeySet) {
        let defaults = UserDefaults.standard
        defaults.set(settings.hardwaysEnabled, forKey: keys.hardwaysEnabled)
        defaults.set(settings.makeEmEnabled, forKey: keys.makeEmEnabled)
        defaults.set(settings.hornEnabled, forKey: keys.hornEnabled)
    }

    // MARK: - Key Namespace

    private struct KeySet {
        let hardwaysEnabled: String
        let makeEmEnabled: String
        let hornEnabled: String

        init(variant: CrapsVariant) {
            let prefix = variant == .standard ? "Craps" : "Crapless"
            hardwaysEnabled = "\(prefix)HardwaysEnabled"
            makeEmEnabled = "\(prefix)MakeEmEnabled"
            hornEnabled = "\(prefix)HornEnabled"
        }
    }
}
