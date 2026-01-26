//
//  BlackjackSettingsViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

final class BlackjackSettingsViewController: BaseSettingsViewController {
    
    // UserDefaults keys for settings persistence
    private enum SettingsKeys {
        static let showTotals = "BlackjackShowTotals"
        static let showDeckCount = "BlackjackShowDeckCount"
        static let showCardCount = "BlackjackShowCardCount"
        static let deckCount = "BlackjackDeckCount"
        static let rebetEnabled = "BlackjackRebetEnabled"
        static let fixedHandType = "BlackjackFixedHandType"
        static let deckPenetration = "BlackjackDeckPenetration"
        static let selectedSideBets = "BlackjackSelectedSideBets"
    }
    
    // Settings state
    private var showTotals: Bool = true
    private var showDeckCount: Bool = false
    private var showCardCount: Bool = false
    private var deckCount: Int = 1
    private var rebetEnabled: Bool = false
    private var deckPenetration: Double? = nil // nil = full deck, -1.0 = random, otherwise percentage (0.5 = 50%, 0.75 = 75%, etc.)

    // Fixed hand type for testing
    enum FixedHandType: String {
        case perfectPair = "Perfect Pair (30:1)"
        case coloredPair = "Colored Pair (10:1)"
        case mixedPair = "Mixed Pair (5:1)"
        case royalMatch = "Royal Match (25:1)"
        case suitedCards = "Suited Cards (3:1)"
        case regular = "Regular Hand"
        case aceUp = "Ace Up"
        case dealerBlackjack = "Dealer BlackJack"
        case random = "Random"
    }

    private var fixedHandType: FixedHandType?
    
    // Side bet types
    enum SideBetType: String, CaseIterable {
        case perfectPairs = "Perfect Pairs"
        case royalMatch = "Royal Match"
        case luckyLadies = "Lucky Ladies"
        case lucky7 = "Lucky 7"
        case buster = "Buster"

        var displayName: String {
            switch self {
            case .perfectPairs: return "Perfect Pairs"
            case .royalMatch: return "Royal Match"
            case .luckyLadies: return "Lucky Ladies"
            case .lucky7: return "Lucky 7"
            case .buster: return "Buster"
            }
        }

        var description: String {
            switch self {
            case .perfectPairs: return "Simply Pairs"
            case .royalMatch: return "Suited Pair"
            case .luckyLadies: return "Two-card 20"
            case .lucky7: return "Number of 7s in player hand"
            case .buster: return "Dealer busts"
            }
        }

        var cardCombinations: [(cards: [(rank: PlayingCardView.Rank, suit: PlayingCardView.Suit)], odds: String)] {
            switch self {
            case .perfectPairs:
                return [
                    (cards: [(.ace, .hearts), (.ace, .hearts)], odds: "30:1"),
                    (cards: [(.king, .hearts), (.king, .spades)], odds: "10:1"),
                    (cards: [(.queen, .hearts), (.queen, .clubs)], odds: "5:1")
                ]
            case .royalMatch:
                return [
                    (cards: [(.king, .hearts), (.queen, .hearts)], odds: "25:1"),
                    (cards: [(.jack, .diamonds), (.ten, .diamonds)], odds: "3:1")
                ]
            case .luckyLadies:
                return [
                    (cards: [(.queen, .hearts), (.queen, .hearts)], odds: "1000:1"),
                    (cards: [(.queen, .hearts), (.queen, .diamonds)], odds: "125:1"),
                    (cards: [(.queen, .hearts), (.queen, .spades)], odds: "25:1"),
                    (cards: [(.king, .hearts), (.king, .hearts)], odds: "19:1"),
                    (cards: [(.ten, .hearts), (.ten, .hearts)], odds: "9:1"),
                    (cards: [(.ten, .hearts), (.jack, .spades)], odds: "4:1")
                ]
            case .lucky7:
                return [
                    (cards: [(.seven, .hearts), (.seven, .diamonds), (.seven, .clubs)], odds: "500:1"),
                    (cards: [(.seven, .hearts), (.seven, .hearts)], odds: "100:1"),
                    (cards: [(.seven, .hearts), (.seven, .clubs)], odds: "50:1"),
                    (cards: [(.seven, .hearts)], odds: "3:1")
                ]
            case .buster:
                // Buster doesn't show card combinations
                return []
            }
        }
    }
    
    private var selectedSideBets: [SideBetType] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadSettings()
    }
    
    override func setupViewController() {
        super.setupViewController()
        title = "Blackjack Settings"
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

        // Load deckPenetration (default: nil = full deck)
        // -1.0 = random, 0.0 = full deck, > 0 && <= 1.0 = specific percentage
        if UserDefaults.standard.object(forKey: SettingsKeys.deckPenetration) != nil {
            let savedPenetration = UserDefaults.standard.double(forKey: SettingsKeys.deckPenetration)
            if savedPenetration == -1.0 {
                deckPenetration = -1.0 // Random
            } else if savedPenetration > 0 && savedPenetration <= 1.0 {
                deckPenetration = savedPenetration
            } else if savedPenetration == 0 {
                deckPenetration = nil // 0 means full deck
            }
        }
        
        // Load selectedSideBets (default: Royal Match and Perfect Pairs)
        if let savedSideBets = UserDefaults.standard.array(forKey: SettingsKeys.selectedSideBets) as? [String] {
            selectedSideBets = savedSideBets.compactMap { SideBetType(rawValue: $0) }
        } else {
            // Default to Royal Match and Perfect Pairs
            selectedSideBets = [.royalMatch, .perfectPairs]
        }
        
        // Ensure max 2 side bets
        if selectedSideBets.count > 2 {
            selectedSideBets = Array(selectedSideBets.prefix(2))
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

        // Save deckPenetration (nil = full deck stored as 0, -1.0 = random, otherwise percentage)
        if let penetration = deckPenetration {
            UserDefaults.standard.set(penetration, forKey: SettingsKeys.deckPenetration)
        } else {
            UserDefaults.standard.set(0.0, forKey: SettingsKeys.deckPenetration) // 0 = full deck
        }
        
        // Save selectedSideBets
        let sideBetStrings = selectedSideBets.map { $0.rawValue }
        UserDefaults.standard.set(sideBetStrings, forKey: SettingsKeys.selectedSideBets)

        onSettingsChanged?()
    }
    
    // MARK: - Table View Data Source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 5
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: // Actions
            return 1
        case 1: // Display Settings
            return 3
        case 2: // Game Settings
            return 3
        case 3: // Side Bets
            return SideBetType.allCases.count
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
            return "Display"
        case 2:
            return "Game"
        case 3:
            return "Side Bets (Select 2)"
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
                    // Tap handled in didSelectRowAt
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
                configureCardCountingCell(cell, isOn: showCardCount) { [weak self] isOn in
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
            case 2: // Deck Penetration
                configureDeckPenetrationCell(cell, currentValue: deckPenetration) { [weak self] penetration in
                    self?.deckPenetration = penetration
                    self?.saveSettings()
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                }
            default:
                break
            }
        case 3: // Side Bets
            let sideBetType = SideBetType.allCases[indexPath.row]
            let isSelected = selectedSideBets.contains(sideBetType)
            configureSideBetCell(cell, sideBetType: sideBetType, isSelected: isSelected) { [weak self] in
                self?.toggleSideBet(sideBetType)
            }
        case 4: // Testing
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
    
    private func configureCardCountingCell(_ cell: UITableViewCell, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        let titleLabel = createStandardLabel(text: "Card Counting")
        let explanationLabel = createSecondaryLabel(text: "(Running Count, True Count)")
        let switchControl = createStandardSwitch(isOn: isOn, onChange: onChange)
        
        cell.contentView.addSubview(titleLabel)
        cell.contentView.addSubview(explanationLabel)
        cell.contentView.addSubview(switchControl)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: switchControl.leadingAnchor, constant: -16),
            
            explanationLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            explanationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            explanationLabel.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
            explanationLabel.trailingAnchor.constraint(lessThanOrEqualTo: switchControl.leadingAnchor, constant: -16),
            
            switchControl.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            switchControl.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])
    }
    
    private func configureDeckCountCell(_ cell: UITableViewCell, currentValue: Int, onSelection: @escaping (Int) -> Void) {
        let label = createStandardLabel(text: "Deck Count")
        
        let menu = UIMenu(title: "", children: [
            UIAction(title: "1 Deck", state: currentValue == 1 ? .on : .off) { _ in onSelection(1) },
            UIAction(title: "2 Decks", state: currentValue == 2 ? .on : .off) { _ in onSelection(2) },
            UIAction(title: "4 Decks", state: currentValue == 4 ? .on : .off) { _ in onSelection(4) },
            UIAction(title: "6 Decks", state: currentValue == 6 ? .on : .off) { _ in onSelection(6) }
        ])
        
        let button = createMenuButton(title: "\(currentValue) Deck\(currentValue == 1 ? "" : "s")", menu: menu)
        layoutLabelAndButton(label: label, button: button, in: cell)
    }

    private func configureDeckPenetrationCell(_ cell: UITableViewCell, currentValue: Double?, onSelection: @escaping (Double?) -> Void) {
        let label = createStandardLabel(text: "Deck Penetration")
        
        let displayText: String
        if let penetration = currentValue {
            displayText = penetration == -1.0 ? "Random" : "\(Int(penetration * 100))%"
        } else {
            displayText = "Full Deck"
        }
        
        let menu = UIMenu(title: "", children: [
            UIAction(title: "Full Deck", state: currentValue == nil ? .on : .off) { _ in onSelection(nil) },
            UIAction(title: "Random", state: currentValue == -1.0 ? .on : .off) { _ in onSelection(-1.0) },
            UIAction(title: "5%", state: currentValue == 0.05 ? .on : .off) { _ in onSelection(0.05) },
            UIAction(title: "50%", state: currentValue == 0.5 ? .on : .off) { _ in onSelection(0.5) },
            UIAction(title: "60%", state: currentValue == 0.6 ? .on : .off) { _ in onSelection(0.6) },
            UIAction(title: "70%", state: currentValue == 0.7 ? .on : .off) { _ in onSelection(0.7) },
            UIAction(title: "75%", state: currentValue == 0.75 ? .on : .off) { _ in onSelection(0.75) }
        ])
        
        let button = createMenuButton(title: displayText, menu: menu)
        layoutLabelAndButton(label: label, button: button, in: cell)
    }

    private func configureFixedHandCell(_ cell: UITableViewCell, currentValue: FixedHandType?, onSelection: @escaping (FixedHandType?) -> Void) {
        let label = createStandardLabel(text: "Fixed Hands")
        
        let menu = UIMenu(title: "", children: [
            UIAction(title: FixedHandType.perfectPair.rawValue, state: currentValue == .perfectPair ? .on : .off) { _ in onSelection(.perfectPair) },
            UIAction(title: FixedHandType.coloredPair.rawValue, state: currentValue == .coloredPair ? .on : .off) { _ in onSelection(.coloredPair) },
            UIAction(title: FixedHandType.mixedPair.rawValue, state: currentValue == .mixedPair ? .on : .off) { _ in onSelection(.mixedPair) },
            UIAction(title: FixedHandType.royalMatch.rawValue, state: currentValue == .royalMatch ? .on : .off) { _ in onSelection(.royalMatch) },
            UIAction(title: FixedHandType.suitedCards.rawValue, state: currentValue == .suitedCards ? .on : .off) { _ in onSelection(.suitedCards) },
            UIAction(title: FixedHandType.regular.rawValue, state: currentValue == .regular ? .on : .off) { _ in onSelection(.regular) },
            UIAction(title: FixedHandType.aceUp.rawValue, state: currentValue == .aceUp ? .on : .off) { _ in onSelection(.aceUp) },
            UIAction(title: FixedHandType.dealerBlackjack.rawValue, state: currentValue == .dealerBlackjack ? .on : .off) { _ in onSelection(.dealerBlackjack) },
            UIAction(title: FixedHandType.random.rawValue, state: currentValue == nil ? .on : .off) { _ in onSelection(nil) }
        ])
        
        let button = createMenuButton(title: currentValue?.rawValue ?? "Random", menu: menu)
        layoutLabelAndButton(label: label, button: button, in: cell)
    }
    
    private func configureSideBetCell(_ cell: UITableViewCell, sideBetType: SideBetType, isSelected: Bool, onToggle: @escaping () -> Void) {
        let titleLabel = createStandardLabel(text: sideBetType.displayName)

        let checkmarkView = UIImageView(image: UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle"))
        checkmarkView.tintColor = isSelected ? HardwayColors.yellow : .white.withAlphaComponent(0.3)
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(titleLabel)
        cell.contentView.addSubview(checkmarkView)

        var constraints: [NSLayoutConstraint] = [
            titleLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -16),

            checkmarkView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            checkmarkView.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkView.heightAnchor.constraint(equalToConstant: 24)
        ]

        // Add card combinations if available
        let combinations = sideBetType.cardCombinations
        if !combinations.isEmpty {
            let combinationsStack = UIStackView()
            combinationsStack.axis = .horizontal
            combinationsStack.spacing = 8
            combinationsStack.alignment = .center
            combinationsStack.distribution = .fillEqually
            combinationsStack.translatesAutoresizingMaskIntoConstraints = false

            for combination in combinations {
                let combinationView = CardCombinationView()
                combinationView.configure(cards: combination.cards, odds: combination.odds)
                combinationsStack.addArrangedSubview(combinationView)
            }

            cell.contentView.addSubview(combinationsStack)

            constraints.append(contentsOf: [
                combinationsStack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                combinationsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
                combinationsStack.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -16),
                combinationsStack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -16)
            ])
        } else {
            // No combinations (Buster), just add bottom constraint to titleLabel
            constraints.append(titleLabel.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12))
        }

        NSLayoutConstraint.activate(constraints)

        // Make cell tappable and clear any accessory from cell reuse
        cell.selectionStyle = .default
        cell.accessoryType = .none
    }
    
    private func toggleSideBet(_ sideBetType: SideBetType) {
        if let index = selectedSideBets.firstIndex(of: sideBetType) {
            // Deselect
            selectedSideBets.remove(at: index)
        } else {
            // Select (but max 2)
            if selectedSideBets.count < 2 {
                selectedSideBets.append(sideBetType)
            } else {
                // Replace the first one
                selectedSideBets.removeFirst()
                selectedSideBets.append(sideBetType)
            }
        }
        
        saveSettings()
        
        // Reload the entire side bets section to update all checkmarks
        let sideBetsSection = 3
        let indexPaths = (0..<SideBetType.allCases.count).map { IndexPath(row: $0, section: sideBetsSection) }
        tableView.reloadRows(at: indexPaths, with: .none)
    }
    
    // MARK: - Table View Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 && indexPath.row == 0 {
            onShowGameDetails?()
        } else if indexPath.section == 3 {
            // Side bets section
            let sideBetType = SideBetType.allCases[indexPath.row]
            toggleSideBet(sideBetType)
        }
    }
}
