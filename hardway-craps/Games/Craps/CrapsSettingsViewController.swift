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
        static let rebetEnabled = "CrapsRebetEnabled"
        static let hardwaysEnabled = "CrapsHardwaysEnabled"
        static let makeEmEnabled = "CrapsMakeEmEnabled"
        static let hornEnabled = "CrapsHornEnabled"
    }

    // Settings state
    private var rebetEnabled: Bool = false
    private var hardwaysEnabled: Bool = true
    private var makeEmEnabled: Bool = true
    private var hornEnabled: Bool = true

    // Additional callbacks
    var onFixedRoll: ((Int) -> Void)?

    override init() {
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
        // Load rebetEnabled (default: false)
        if UserDefaults.standard.object(forKey: SettingsKeys.rebetEnabled) != nil {
            rebetEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.rebetEnabled)
        }

        // Load hardwaysEnabled (default: true)
        if UserDefaults.standard.object(forKey: SettingsKeys.hardwaysEnabled) != nil {
            hardwaysEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.hardwaysEnabled)
        }

        // Load makeEmEnabled (default: true)
        if UserDefaults.standard.object(forKey: SettingsKeys.makeEmEnabled) != nil {
            makeEmEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.makeEmEnabled)
        }

        // Load hornEnabled (default: true)
        if UserDefaults.standard.object(forKey: SettingsKeys.hornEnabled) != nil {
            hornEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.hornEnabled)
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(rebetEnabled, forKey: SettingsKeys.rebetEnabled)
        UserDefaults.standard.set(hardwaysEnabled, forKey: SettingsKeys.hardwaysEnabled)
        UserDefaults.standard.set(makeEmEnabled, forKey: SettingsKeys.makeEmEnabled)
        UserDefaults.standard.set(hornEnabled, forKey: SettingsKeys.hornEnabled)
        onSettingsChanged?()
    }

    // MARK: - Table View Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 5
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: // Actions
            return 1  // Only "Game Details" now
        case 1: // Game Settings
            return 1
        case 2: // Bonus Bets
            return 3
        case 3: // Explainer
            return 8
        case 4: // Testing
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
            return "Game"
        case 2:
            return "Bonus Bets"
        case 3:
            return "Craps Explainer"
        case 4:
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
        cell.accessoryType = .none // Clear any accessory from cell reuse

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
            default:
                break
            }
        case 1: // Game Settings
            switch indexPath.row {
            case 0: // Rebet
                configureSwitchCell(cell, title: "Rebet", isOn: rebetEnabled) { [weak self] isOn in
                    self?.rebetEnabled = isOn
                    self?.saveSettings()
                }
            default:
                break
            }
        case 2: // Bonus Bets
            switch indexPath.row {
            case 0: // Hardways
                configureSwitchCell(cell, title: "Hardways", isOn: hardwaysEnabled) { [weak self] isOn in
                    self?.hardwaysEnabled = isOn
                    self?.saveSettings()
                }
            case 1: // Make Em
                configureSwitchCell(cell, title: "Make Em'", isOn: makeEmEnabled) { [weak self] isOn in
                    self?.makeEmEnabled = isOn
                    self?.saveSettings()
                }
            case 2: // Horn
                configureSwitchCell(cell, title: "Horn", isOn: hornEnabled) { [weak self] isOn in
                    self?.hornEnabled = isOn
                    self?.saveSettings()
                }
            default:
                break
            }
        case 3: // Explainer
            configureExplainerCell(cell, at: indexPath.row)
        case 4: // Testing
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
    
    private func configureExplainerCell(_ cell: UITableViewCell, at row: Int) {
        let explainerItems: [(title: String, subtitle: String)] = [
            ("Pass Line", "Wins on 7 or 11 on the come out roll, loses on 2, 3, or 12. If a point is established, wins when the point is rolled again before a 7."),
            ("Come Out Roll", "The first roll of a new round. If 7 or 11 is rolled, pass line bets win. If 2, 3, or 12 is rolled, pass line bets lose."),
            ("Point", "When a point is established (4, 5, 6, 8, 9, or 10), you must roll that number again before rolling a 7 to win your pass line bet. The puck shows OFF when no point is set, and ON with the point number displayed."),
            ("Field", "A one-time bet that wins on 2, 3, 4, 9, 10, 11, or 12. Loses on 5, 6, 7, or 8. Pays double on 2 or 12."),
            ("Pass Line Odds", "An additional bet placed behind your pass line bet after a point is established. Pays true odds with no house edge."),
            ("Don't Pass", "Opposite of pass line. Wins on 2 or 3, loses on 7 or 11, pushes on 12. After a point is established, wins if a 7 is rolled before the point."),
            ("Hardways & Horn", "Hardways are pairs: hard 4 (2-2), hard 6 (3-3), hard 8 (4-4), hard 10 (5-5). Hardway bets stay active until the soft number is rolled or a 7. Horn is a one-time bet on 2, 3, 11, or 12."),
            ("Make Em'", "Bet that ALL numbers in either the small (2, 3, 4, 5, 6) or tall (8, 9, 10, 11, 12) will be rolled before a 7. Also known as 'All Small' or 'All Tall'.")
        ]
        
        guard row < explainerItems.count else { return }
        
        let item = explainerItems[row]
        let titleLabel = createStandardLabel(text: item.title)
        let subtitleLabel = createSecondaryLabel(text: item.subtitle)
        subtitleLabel.numberOfLines = 0
        
        cell.contentView.addSubview(titleLabel)
        cell.contentView.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            
            subtitleLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            subtitleLabel.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
        ])
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
            }
        }
    }

}
