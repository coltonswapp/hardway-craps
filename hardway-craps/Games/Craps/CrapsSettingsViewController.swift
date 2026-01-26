//
//  CrapsSettingsViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/23/26.
//

import UIKit

final class CrapsSettingsViewController: BaseSettingsViewController {

    // UserDefaults keys for settings persistence
    private enum SettingsKeys {
        static let showPlaystyle = "CrapsShowPlaystyle"
    }

    // Settings state
    private var showPlaystyle: Bool = false

    // Additional callbacks
    var onEndSession: (() -> Void)?
    var onFixedRoll: ((Int) -> Void)?

    init(showPlaystyle: Bool) {
        self.showPlaystyle = showPlaystyle
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSettings()
    }

    override func setupViewController() {
        super.setupViewController()
        title = "Craps Settings"
    }

    private func loadSettings() {
        // Load showPlaystyle (default: false)
        if UserDefaults.standard.object(forKey: SettingsKeys.showPlaystyle) != nil {
            showPlaystyle = UserDefaults.standard.bool(forKey: SettingsKeys.showPlaystyle)
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(showPlaystyle, forKey: SettingsKeys.showPlaystyle)
        onSettingsChanged?()
    }

    // MARK: - Table View Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: // Actions
            return 2
        case 1: // Display Settings
            return 1
        case 2: // Testing
            return 1
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return nil // No header for Actions section
        case 1:
            return "Display"
        case 2:
            return "Testing"
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)

        // Configure cell appearance
        cell.textLabel?.textColor = .white
        cell.selectionStyle = .none

        // Remove any existing subviews
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        switch indexPath.section {
        case 0: // Actions
            switch indexPath.row {
            case 0: // Game Details
                configureActionCell(cell, title: "Game Details", icon: "chart.line.uptrend.xyaxis") { [weak self] in
                    self?.dismiss(animated: true) {
                        self?.onShowGameDetails?()
                    }
                }
            case 1: // End Session
                configureActionCell(cell, title: "End Session", icon: "stop.circle", isDestructive: true) { [weak self] in
                    self?.dismiss(animated: true) {
                        self?.onEndSession?()
                    }
                }
            default:
                break
            }
        case 1: // Display Settings
            switch indexPath.row {
            case 0: // Show Playstyle
                configureSwitchCell(cell, title: "Show Playstyle", isOn: showPlaystyle) { [weak self] isOn in
                    self?.showPlaystyle = isOn
                    self?.saveSettings()
                }
            default:
                break
            }
        case 2: // Testing
            switch indexPath.row {
            case 0: // Fixed Roll
                configureFixedRollCell(cell) { [weak self] total in
                    self?.dismiss(animated: true) {
                        self?.onFixedRoll?(total)
                    }
                }
            default:
                break
            }
        default:
            break
        }

        return cell
    }

    private func configureFixedRollCell(_ cell: UITableViewCell, onSelection: @escaping (Int) -> Void) {
        let label = createStandardLabel(text: "Fixed Roll", color: HardwayColors.label)
        
        let menuItems = (2...12).map { total in
            UIAction(title: "\(total)") { _ in onSelection(total) }
        }
        let menu = UIMenu(title: "", children: menuItems)
        
        let button = createMenuButton(title: "Select Roll", menu: menu)
        layoutLabelAndButton(label: label, button: button, in: cell)
    }

    // MARK: - Table View Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            if indexPath.row == 0 {
                // Game Details
                dismiss(animated: true) { [weak self] in
                    self?.onShowGameDetails?()
                }
            } else if indexPath.row == 1 {
                // End Session
                dismiss(animated: true) { [weak self] in
                    self?.onEndSession?()
                }
            }
        }
    }

}
