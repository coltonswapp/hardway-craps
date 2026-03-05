//
//  MPCreateTableViewController.swift
//  hardway-craps
//

import FirebaseFunctions
import UIKit

final class MPCreateTableViewController: UIViewController {

    // MARK: - Settings State

    private var selectedBankroll: Int = 500
    private var selectedDeckCount: Int = 1
    private var selectedSideBets: [String] = ["Royal Match"]

    private let bankrollOptions = [200, 500, 1000]
    private let deckCountOptions = [1, 2, 4, 6]

    private var isCreating = false

    private typealias SideBetType = BlackjackSettingsViewController.SideBetType

    // MARK: - Views

    private var tableView: UITableView!
    private let createButton = NNPrimaryLabeledButton(title: "Create Table")
    private let ctaContainer = UIView()
    private let ctaStackView = UIStackView()
    private var visualEffectView: UIVisualEffectView?

    // MARK: - Sections

    private enum Section: Int, CaseIterable {
        case gameSettings
        case sideBets
    }

    private enum GameSettingsRow: Int, CaseIterable {
        case bankroll
        case deckCount
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "Create a Table"
        setupTableView()
        setupStartGameButtons()
    }

    // MARK: - Table View Setup

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorColor = HardwayColors.surfaceGray
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Floating CTA (copied from MainViewController)

    private func setupStartGameButtons() {
        createButton.addTarget(self, action: #selector(createTableTapped), for: .touchUpInside)

        visualEffectView = UIVisualEffectView()
        guard let visualEffectView = visualEffectView,
              let maskImage = UIImage(named: "testBG3") else { return }

        visualEffectView.effect = UIBlurEffect.variableBlurEffect(radius: 16, maskImage: maskImage)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(visualEffectView)

        ctaContainer.translatesAutoresizingMaskIntoConstraints = false
        ctaContainer.backgroundColor = .clear
        view.addSubview(ctaContainer)

        ctaStackView.translatesAutoresizingMaskIntoConstraints = false
        ctaStackView.axis = .vertical
        ctaStackView.alignment = .fill
        ctaStackView.distribution = .fillEqually
        ctaStackView.spacing = 12
        ctaStackView.addArrangedSubview(createButton)

        ctaContainer.addSubview(ctaStackView)

        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: ctaContainer.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            ctaContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ctaContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ctaContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            ctaStackView.leadingAnchor.constraint(equalTo: ctaContainer.leadingAnchor, constant: 16),
            ctaStackView.trailingAnchor.constraint(equalTo: ctaContainer.trailingAnchor, constant: -16),
            ctaStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            ctaStackView.topAnchor.constraint(equalTo: ctaContainer.topAnchor, constant: 40),

            createButton.heightAnchor.constraint(equalToConstant: 55),
        ])

        view.layoutIfNeeded()
        let containerHeight = ctaStackView.frame.height + 56
        tableView.contentInset.bottom = containerHeight + 20
        tableView.scrollIndicatorInsets.bottom = containerHeight - 20
    }

    // MARK: - Cell Configuration

    private func configureBankrollCell(_ cell: UITableViewCell) {
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        let label = makeLabel("Bankroll")
        let menu = UIMenu(children: bankrollOptions.map { amount in
            UIAction(title: "$\(amount)", state: amount == selectedBankroll ? .on : .off) { [weak self] _ in
                self?.selectedBankroll = amount
                self?.tableView.reloadSections(IndexSet(integer: Section.gameSettings.rawValue), with: .none)
                HapticsHelper.lightHaptic()
            }
        })
        let button = makeMenuButton(title: "$\(selectedBankroll)", menu: menu)
        layoutLabelAndButton(label, button: button, in: cell)
    }

    private func configureDeckCountCell(_ cell: UITableViewCell) {
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        let label = makeLabel("Decks")
        let menu = UIMenu(children: deckCountOptions.map { count in
            UIAction(title: "\(count)", state: count == selectedDeckCount ? .on : .off) { [weak self] _ in
                self?.selectedDeckCount = count
                self?.tableView.reloadSections(IndexSet(integer: Section.gameSettings.rawValue), with: .none)
                HapticsHelper.lightHaptic()
            }
        })
        let button = makeMenuButton(title: "\(selectedDeckCount)", menu: menu)
        layoutLabelAndButton(label, button: button, in: cell)
    }

    private func configureSideBetCell(_ cell: UITableViewCell, sideBetType: SideBetType, isSelected: Bool) {
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.selectionStyle = .default
        cell.accessoryType = .none

        let titleLabel = makeLabel(sideBetType.displayName)
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
            checkmarkView.heightAnchor.constraint(equalToConstant: 24),
        ]

        let combinations = sideBetType.cardCombinations
        if !combinations.isEmpty {
            // For layouts with many combinations (like Lucky Ladies with 6), use 2 rows of 3
            let containerStack = UIStackView()
            containerStack.axis = .vertical
            containerStack.spacing = 8
            containerStack.alignment = .fill
            containerStack.distribution = .fillEqually
            containerStack.translatesAutoresizingMaskIntoConstraints = false
            
            // Split combinations into rows of 3
            let itemsPerRow = 3
            var currentRow: UIStackView?
            
            for (index, combo) in combinations.enumerated() {
                if index % itemsPerRow == 0 {
                    // Create a new row
                    currentRow = UIStackView()
                    currentRow?.axis = .horizontal
                    currentRow?.spacing = 8
                    currentRow?.alignment = .center
                    currentRow?.distribution = .fillEqually
                    currentRow?.translatesAutoresizingMaskIntoConstraints = false
                    containerStack.addArrangedSubview(currentRow!)
                }
                
                let v = CardCombinationView()
                v.configure(cards: combo.cards, odds: combo.odds)
                currentRow?.addArrangedSubview(v)
            }
            
            cell.contentView.addSubview(containerStack)
            constraints += [
                containerStack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                containerStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
                containerStack.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -16),
                containerStack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -16),
            ]
        } else {
            let desc = makeSecondaryLabel("Dealer Bust. Payout depends on how many cards dealer busts with.\n\n3 cards: 2:1 • 4 cards: 2:1 • 5 cards: 4:1\n6 cards: 12:1 • 7 cards: 50:1 • 8+ cards: 250:1")
            desc.numberOfLines = 0
            cell.contentView.addSubview(desc)
            constraints += [
                desc.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                desc.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
                desc.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -16),
                desc.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -16),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeSecondaryLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white.withAlphaComponent(0.6)
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeMenuButton(title: String, menu: UIMenu) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = .systemBlue
        let button = UIButton(configuration: config, primaryAction: nil)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func layoutLabelAndButton(_ label: UILabel, button: UIButton, in cell: UITableViewCell) {
        cell.contentView.addSubview(label)
        cell.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -16),
            button.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            button.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
        ])
    }

    // MARK: - Side Bet Toggle

    private func handleSideBetToggle(at row: Int) {
        let name = SideBetType.allCases[row].displayName
        if let idx = selectedSideBets.firstIndex(of: name) {
            selectedSideBets.remove(at: idx)
        } else {
            // Only allow 1 side bet
            selectedSideBets.removeAll()
            selectedSideBets.append(name)
        }
        tableView.reloadSections(IndexSet(integer: Section.sideBets.rawValue), with: .automatic)
        HapticsHelper.lightHaptic()
    }

    // MARK: - Create Table

    @objc private func createTableTapped() {
        guard !isCreating else { return }
        isCreating = true
        createButton.isEnabled = false
        createButton.setTitle("Creating...")

        let params: [String: Any] = [
            "deckCount": selectedDeckCount,
            "bonusBetsEnabled": !selectedSideBets.isEmpty,
            "selectedSideBets": selectedSideBets,
            "startingBankroll": selectedBankroll,
        ]

        Functions.functions().httpsCallable("createTable").call(params) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCreating = false
                self.createButton.isEnabled = true
                self.createButton.setTitle("Create Table")

                if let error {
                    self.showErrorAlert(message: "Failed to create table: \(error.localizedDescription)")
                    return
                }
                guard let data = result?.data as? [String: Any],
                      let tableCode = data["tableCode"] as? String else {
                    self.showErrorAlert(message: "Unexpected response from server.")
                    return
                }
                self.launchGame(tableCode: tableCode)
            }
        }
    }

    private func launchGame(tableCode: String) {
        let vc = MultiplayerBlackjackViewController(tableCode: tableCode, bankroll: selectedBankroll)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension MPCreateTableViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .gameSettings: return GameSettingsRow.allCases.count
        case .sideBets: return SideBetType.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .gameSettings: return "Game Settings"
        case .sideBets: return "Side Bets"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .gameSettings: return nil
        case .sideBets: return "Players can place side bets during the betting phase. Max 1."
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        cell.textLabel?.textColor = .white
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.accessoryView = nil

        guard let section = Section(rawValue: indexPath.section) else { return cell }
        switch section {
        case .gameSettings:
            guard let row = GameSettingsRow(rawValue: indexPath.row) else { break }
            switch row {
            case .bankroll: configureBankrollCell(cell)
            case .deckCount: configureDeckCountCell(cell)
            }
        case .sideBets:
            let sideBetType = SideBetType.allCases[indexPath.row]
            configureSideBetCell(cell, sideBetType: sideBetType, isSelected: selectedSideBets.contains(sideBetType.displayName))
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .sideBets else { return }
        handleSideBetToggle(at: indexPath.row)
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = HardwayColors.label
            header.textLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        }
    }
}
