//
//  BaccaratSettingsViewController.swift
//  hardway-craps
//
//  Created by Claude Code on 3/10/26.
//

import UIKit

final class BaccaratSettingsViewController: BaseSettingsViewController {

    // Settings state
    private var showTotals: Bool = true
    private var showBigRoad: Bool = true

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSettings()
    }

    override func setupViewController() {
        super.setupViewController()
        title = "Baccarat Settings"
    }

    private func loadSettings() {
        if UserDefaults.standard.object(forKey: BaccaratSettingsKeys.showTotals) != nil {
            showTotals = UserDefaults.standard.bool(forKey: BaccaratSettingsKeys.showTotals)
        }
        if UserDefaults.standard.object(forKey: BaccaratSettingsKeys.showBigRoad) != nil {
            showBigRoad = UserDefaults.standard.bool(forKey: BaccaratSettingsKeys.showBigRoad)
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(showTotals, forKey: BaccaratSettingsKeys.showTotals)
        UserDefaults.standard.set(showBigRoad, forKey: BaccaratSettingsKeys.showBigRoad)
        onSettingsChanged?()
    }

    // MARK: - Table View Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: // Actions
            return 2 // Game Details + Hit the ATM
        case 1: // Display
            return 2 // Show Hand Totals + Show Big Road
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return nil
        case 1:
            return "Display"
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)

        cell.textLabel?.textColor = .white
        cell.selectionStyle = .none
        cell.accessoryType = .none

        // Remove any existing subviews
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        switch indexPath.section {
        case 0: // Actions
            switch indexPath.row {
            case 0: // Game Details
                configureActionCell(cell, title: "Game Details", icon: "chart.line.uptrend.xyaxis") { [weak self] in
                    // Tap handled in didSelectRowAt
                }
            case 1: // Hit the ATM
                configureActionCell(cell, title: "Hit the ATM", icon: "creditcard") { [weak self] in
                    // Tap handled in didSelectRowAt
                }
            default:
                break
            }
        case 1: // Display Settings
            switch indexPath.row {
            case 0:
                configureSwitchCell(cell, title: "Show Hand Totals", isOn: showTotals) { [weak self] isOn in
                    self?.showTotals = isOn
                    self?.saveSettings()
                }
            case 1:
                configureSwitchCell(cell, title: "Show Big Road (History Chart)", isOn: showBigRoad) { [weak self] isOn in
                    self?.showBigRoad = isOn
                    self?.saveSettings()
                }
            default:
                break
            }
        default:
            break
        }

        return cell
    }

    // MARK: - Table View Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            if indexPath.row == 0 {
                onShowGameDetails?()
            } else if indexPath.row == 1 {
                onHitATM?()
            }
        }
    }
}
