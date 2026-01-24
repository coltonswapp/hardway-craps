//
//  BlackjackSettingsViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

final class BlackjackSettingsViewController: UITableViewController {
    
    // UserDefaults keys for settings persistence
    private enum SettingsKeys {
        static let showTotals = "BlackjackShowTotals"
        static let showDeckCount = "BlackjackShowDeckCount"
        static let showCardCount = "BlackjackShowCardCount"
        static let deckCount = "BlackjackDeckCount"
        static let rebetEnabled = "BlackjackRebetEnabled"
        static let fixedHandType = "BlackjackFixedHandType"
    }
    
    // Settings state
    private var showTotals: Bool = true
    private var showDeckCount: Bool = false
    private var showCardCount: Bool = false
    private var deckCount: Int = 1
    private var rebetEnabled: Bool = false

    // Fixed hand type for testing
    enum FixedHandType: String {
        case perfectPair = "Perfect Pair (30:1)"
        case coloredPair = "Colored Pair (10:1)"
        case mixedPair = "Mixed Pair (5:1)"
        case royalMatch = "Royal Match (25:1)"
        case suitedCards = "Suited Cards (3:1)"
        case regular = "Regular Hand"
        case random = "Random"
    }

    private var fixedHandType: FixedHandType?
    
    // UI Elements
    private var showTotalsSwitch: UISwitch!
    private var showDeckCountSwitch: UISwitch!
    private var deckCountButton: UIButton!
    
    // Callback for when settings change
    var onSettingsChanged: (() -> Void)?

    // Callback for showing game details
    var onShowGameDetails: (() -> Void)?
    
    init() {
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupViewController()
        loadSettings()
        setupTableView()
    }
    
    private func setupViewController() {
        title = "Blackjack Settings"
        
        // Configure navigation bar
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissSettings)
        )
    }
    
    private func setupTableView() {
        tableView.separatorColor = HardwayColors.surfaceGray
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
    }
    
    private func loadSettings() {
        // Load showTotals (default: true)
        if UserDefaults.standard.object(forKey: SettingsKeys.showTotals) != nil {
            showTotals = UserDefaults.standard.bool(forKey: SettingsKeys.showTotals)
        }

        // Load showDeckCount (default: false)
        if UserDefaults.standard.object(forKey: SettingsKeys.showDeckCount) != nil {
            showDeckCount = UserDefaults.standard.bool(forKey: SettingsKeys.showDeckCount)
        }

        // Load showCardCount (default: false)
        if UserDefaults.standard.object(forKey: SettingsKeys.showCardCount) != nil {
            showCardCount = UserDefaults.standard.bool(forKey: SettingsKeys.showCardCount)
        }

        // Load deckCount (default: 1)
        if UserDefaults.standard.object(forKey: SettingsKeys.deckCount) != nil {
            let savedDeckCount = UserDefaults.standard.integer(forKey: SettingsKeys.deckCount)
            if [1, 2, 4, 6].contains(savedDeckCount) {
                deckCount = savedDeckCount
            }
        }

        // Load rebetEnabled (default: false)
        if UserDefaults.standard.object(forKey: SettingsKeys.rebetEnabled) != nil {
            rebetEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.rebetEnabled)
        }

        // Load fixedHandType (default: nil/random)
        if let savedHandType = UserDefaults.standard.string(forKey: SettingsKeys.fixedHandType),
           let handType = FixedHandType(rawValue: savedHandType) {
            fixedHandType = handType
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(showTotals, forKey: SettingsKeys.showTotals)
        UserDefaults.standard.set(showDeckCount, forKey: SettingsKeys.showDeckCount)
        UserDefaults.standard.set(showCardCount, forKey: SettingsKeys.showCardCount)
        UserDefaults.standard.set(deckCount, forKey: SettingsKeys.deckCount)
        UserDefaults.standard.set(rebetEnabled, forKey: SettingsKeys.rebetEnabled)

        // Save fixedHandType (nil means random)
        if let handType = fixedHandType {
            UserDefaults.standard.set(handType.rawValue, forKey: SettingsKeys.fixedHandType)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsKeys.fixedHandType)
        }

        onSettingsChanged?()
    }
    
    @objc private func dismissSettings() {
        dismiss(animated: true)
    }
    
    // MARK: - Table View Data Source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: // Actions
            return 1
        case 1: // Display Settings
            return 3
        case 2: // Game Settings
            return 2
        case 3: // Testing
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
            return "Game"
        case 3:
            return "Testing"
        default:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        
        // Configure cell appearance
//        cell.backgroundColor = HardwayColors.surfaceGray
        cell.textLabel?.textColor = HardwayColors.label
        cell.selectionStyle = .none
        
        // Remove any existing subviews
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        
        switch indexPath.section {
        case 0: // Actions
            switch indexPath.row {
            case 0: // Game Details
                configureActionCell(cell, title: "Game Details", icon: "chart.line.uptrend.xyaxis") { [weak self] in
                    self?.onShowGameDetails?()
                }
            default:
                break
            }
        case 1: // Display Settings
            switch indexPath.row {
            case 0: // Show Hand Totals
                configureSwitchCell(cell, title: "Show Hand Totals", isOn: showTotals) { [weak self] isOn in
                    self?.showTotals = isOn
                    self?.saveSettings()
                }
            case 1: // Show Deck Count
                configureSwitchCell(cell, title: "Show Deck Count", isOn: showDeckCount) { [weak self] isOn in
                    self?.showDeckCount = isOn
                    self?.saveSettings()
                }
            case 2: // Card Counting
                configureSwitchCell(cell, title: "Card Counting", isOn: showCardCount) { [weak self] isOn in
                    self?.showCardCount = isOn
                    self?.saveSettings()
                }
            default:
                break
            }
        case 2: // Game Settings
            switch indexPath.row {
            case 0: // Deck Count
                configureDeckCountCell(cell, currentValue: deckCount) { [weak self] count in
                    self?.deckCount = count
                    self?.saveSettings()
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                }
            case 1: // Rebet
                configureSwitchCell(cell, title: "Rebet", isOn: rebetEnabled) { [weak self] isOn in
                    self?.rebetEnabled = isOn
                    self?.saveSettings()
                }
            default:
                break
            }
        case 3: // Testing
            switch indexPath.row {
            case 0: // Fixed Hands
                configureFixedHandCell(cell, currentValue: fixedHandType) { [weak self] handType in
                    self?.fixedHandType = handType
                    self?.saveSettings()
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                }
            default:
                break
            }
        default:
            break
        }
        
        return cell
    }
    
    private func configureSwitchCell(_ cell: UITableViewCell, title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        // Create label
        let label = UILabel()
        label.text = title
        label.textColor = HardwayColors.label
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Create switch
        let switchControl = UISwitch()
        switchControl.isOn = isOn
        switchControl.addAction(UIAction { action in
            if let switchControl = action.sender as? UISwitch {
                onChange(switchControl.isOn)
            }
        }, for: .valueChanged)
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to cell
        cell.contentView.addSubview(label)
        cell.contentView.addSubview(switchControl)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: switchControl.leadingAnchor, constant: -16),
            
            switchControl.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            switchControl.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])
    }
    
    private func configureDeckCountCell(_ cell: UITableViewCell, currentValue: Int, onSelection: @escaping (Int) -> Void) {
        // Create label
        let label = UILabel()
        label.text = "Deck Count"
        label.textColor = HardwayColors.label
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false

        // Create menu button
        let button = UIButton(type: .system)
        button.setTitle("\(currentValue) Deck\(currentValue == 1 ? "" : "s")", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.translatesAutoresizingMaskIntoConstraints = false

        // Create menu
        let menu = UIMenu(title: "", children: [
            UIAction(title: "1 Deck", state: currentValue == 1 ? .on : .off) { _ in
                onSelection(1)
            },
            UIAction(title: "2 Decks", state: currentValue == 2 ? .on : .off) { _ in
                onSelection(2)
            },
            UIAction(title: "4 Decks", state: currentValue == 4 ? .on : .off) { _ in
                onSelection(4)
            },
            UIAction(title: "6 Decks", state: currentValue == 6 ? .on : .off) { _ in
                onSelection(6)
            }
        ])

        button.menu = menu
        button.showsMenuAsPrimaryAction = true

        // Add to cell
        cell.contentView.addSubview(label)
        cell.contentView.addSubview(button)

        // Layout constraints
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -16),

            button.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            button.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])
    }

    private func configureFixedHandCell(_ cell: UITableViewCell, currentValue: FixedHandType?, onSelection: @escaping (FixedHandType?) -> Void) {
        // Create label
        let label = UILabel()
        label.text = "Fixed Hands"
        label.textColor = HardwayColors.label
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false

        // Create menu button
        let button = UIButton(type: .system)
        button.setTitle(currentValue?.rawValue ?? "Random", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.translatesAutoresizingMaskIntoConstraints = false

        // Create menu
        let menu = UIMenu(title: "", children: [
            UIAction(title: FixedHandType.perfectPair.rawValue, state: currentValue == .perfectPair ? .on : .off) { _ in
                onSelection(.perfectPair)
            },
            UIAction(title: FixedHandType.coloredPair.rawValue, state: currentValue == .coloredPair ? .on : .off) { _ in
                onSelection(.coloredPair)
            },
            UIAction(title: FixedHandType.mixedPair.rawValue, state: currentValue == .mixedPair ? .on : .off) { _ in
                onSelection(.mixedPair)
            },
            UIAction(title: FixedHandType.royalMatch.rawValue, state: currentValue == .royalMatch ? .on : .off) { _ in
                onSelection(.royalMatch)
            },
            UIAction(title: FixedHandType.suitedCards.rawValue, state: currentValue == .suitedCards ? .on : .off) { _ in
                onSelection(.suitedCards)
            },
            UIAction(title: FixedHandType.regular.rawValue, state: currentValue == .regular ? .on : .off) { _ in
                onSelection(.regular)
            },
            UIAction(title: FixedHandType.random.rawValue, state: currentValue == nil ? .on : .off) { _ in
                onSelection(nil)
            }
        ])

        button.menu = menu
        button.showsMenuAsPrimaryAction = true

        // Add to cell
        cell.contentView.addSubview(label)
        cell.contentView.addSubview(button)

        // Layout constraints
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -16),

            button.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            button.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])
    }
    
    private func configureActionCell(_ cell: UITableViewCell, title: String, icon: String, onTap: @escaping () -> Void) {
        // Create label
        let label = UILabel()
        label.text = title
        label.textColor = HardwayColors.label
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false

        // Create icon
        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = HardwayColors.label
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Add to cell
        cell.contentView.addSubview(iconView)
        cell.contentView.addSubview(label)

        // Make cell tappable
        cell.selectionStyle = .default
        cell.accessoryType = .disclosureIndicator

        // Layout constraints
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -16)
        ])
    }

    // MARK: - Table View Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 && indexPath.row == 0 {
            onShowGameDetails?()
        }
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = HardwayColors.label
            header.textLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        }
    }
}
