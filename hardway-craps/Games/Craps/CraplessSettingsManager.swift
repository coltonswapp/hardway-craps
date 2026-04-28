//
//  CraplessSettingsManager.swift
//  hardway-craps
//
//  Backward-compatibility shim. All logic now lives in CrapsSettingsManager
//  parameterized by CrapsVariant.
//

import Foundation

/// Drop-in replacement: a CrapsSettingsManager initialized for the crapless variant.
final class CraplessSettingsManager: CrapsGameSettingsManagerDelegate {

    private let inner: CrapsSettingsManager

    weak var delegate: CrapsGameSettingsManagerDelegate?

    var currentSettings: CrapsGameSettings { inner.currentSettings }

    init() {
        inner = CrapsSettingsManager(variant: .crapless)
        inner.delegate = self
    }

    func loadSettings() { inner.loadSettings() }
    func saveSettings() { inner.saveSettings() }
    func updateSettings(_ settings: CrapsGameSettings) { inner.updateSettings(settings) }
    func setRebetEnabled(_ enabled: Bool) { inner.setRebetEnabled(enabled) }
    func setRebetAmount(_ amount: Int) { inner.setRebetAmount(amount) }
    func setHardwaysEnabled(_ enabled: Bool) { inner.setHardwaysEnabled(enabled) }
    func setMakeEmEnabled(_ enabled: Bool) { inner.setMakeEmEnabled(enabled) }
    func setHornEnabled(_ enabled: Bool) { inner.setHornEnabled(enabled) }

    // Forward delegate callbacks from inner manager
    func settingsDidChange(_ settings: CrapsGameSettings) {
        delegate?.settingsDidChange(settings)
    }
}
