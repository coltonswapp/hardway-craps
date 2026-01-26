//
//  AppSettingsViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/23/26.
//

import UIKit

final class AppSettingsViewController: UITableViewController {

    enum Section: Int, CaseIterable {
        case general
        case appearance
        case debug

        var title: String? {
            switch self {
            case .general: return "GENERAL"
            case .appearance: return "APPEARANCE"
            case .debug: return "DEBUG"
            }
        }
    }

    enum GeneralRow: Int, CaseIterable {
        case playerTypes

        var title: String {
            switch self {
            case .playerTypes: return "Player Types"
            }
        }

        var iconName: String {
            switch self {
            case .playerTypes: return "person.3.fill"
            }
        }
    }

    enum AppearanceRow: Int, CaseIterable {
        case chipColor

        var title: String {
            switch self {
            case .chipColor: return "Chip Tint Color"
            }
        }

        var iconName: String {
            switch self {
            case .chipColor: return "paintpalette.fill"
            }
        }
    }

    enum DebugRow: Int, CaseIterable {
        case resetTips
        case clearSessions

        var title: String {
            switch self {
            case .resetTips: return "Reset All Tips"
            case .clearSessions: return "Clear All Sessions"
            }
        }

        var iconName: String {
            switch self {
            case .resetTips: return "arrow.clockwise"
            case .clearSessions: return "trash"
            }
        }

        var isDestructive: Bool {
            switch self {
            case .resetTips: return false
            case .clearSessions: return true
            }
        }
    }
    
    // MARK: - Chip Color Management
    
    private struct ChipColorKeys {
        static let chipColor = "ChipColor"
    }
    
    private var selectedChipColor: String {
        get {
            return UserDefaults.standard.string(forKey: ChipColorKeys.chipColor) ?? "cyan"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ChipColorKeys.chipColor)
        }
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupViewController()
        setupTableView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Reload table view to update chip preview when returning from color selection
        tableView.reloadData()
    }

    private func setupViewController() {
        title = "Settings"

        // Configure navigation bar
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissSettings)
        )
    }

    private func setupTableView() {
        // Use standard iOS grouped table view appearance
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorColor = .separator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ChipColorCell")
    }

    @objc private func dismissSettings() {
        dismiss(animated: true)
    }

    // MARK: - Table View Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }

        switch section {
        case .general:
            return GeneralRow.allCases.count
        case .appearance:
            return AppearanceRow.allCases.count
        case .debug:
            return DebugRow.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sectionTitle = Section(rawValue: section)?.title else { return nil }
        
        let headerView = UIView()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = sectionTitle
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .left
        
        headerView.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -4)
        ])
        
        return headerView
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 32
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        // Add footer text for debug section
        if section == Section.debug.rawValue {
            return "These options are for testing and debugging purposes."
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .general:
            return configureGeneralCell(at: indexPath)
        case .appearance:
            return configureAppearanceCell(at: indexPath)
        case .debug:
            return configureDebugCell(at: indexPath)
        }
    }

    private func configureGeneralCell(at indexPath: IndexPath) -> UITableViewCell {
        guard let row = GeneralRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        configureCell(cell, icon: row.iconName, title: row.title)
        cell.accessoryType = .disclosureIndicator

        return cell
    }

    private func configureAppearanceCell(at indexPath: IndexPath) -> UITableViewCell {
        guard let row = AppearanceRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }

        switch row {
        case .chipColor:
            return configureChipColorCell(at: indexPath)
        }
    }
    
    private func configureChipColorCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChipColorCell", for: indexPath)
        
        // Configure title
        cell.textLabel?.text = AppearanceRow.chipColor.title
        cell.textLabel?.font = .systemFont(ofSize: 17)
        cell.textLabel?.textColor = .white
        
        // Configure icon
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        if let symbolImage = UIImage(systemName: AppearanceRow.chipColor.iconName, withConfiguration: iconConfig) {
            let iconColor = UIColor.systemBlue
            cell.imageView?.image = symbolImage.withTintColor(iconColor, renderingMode: .alwaysOriginal)
            cell.imageView?.tintColor = iconColor
        }
        
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        
        return cell
    }

    private func configureDebugCell(at indexPath: IndexPath) -> UITableViewCell {
        guard let row = DebugRow(rawValue: indexPath.row) else {
            return UITableViewCell()
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        configureCell(cell, icon: row.iconName, title: row.title, isDestructive: row.isDestructive)
        cell.accessoryType = .disclosureIndicator

        return cell
    }
    
    private func configureCell(_ cell: UITableViewCell, icon: String, title: String, isDestructive: Bool = false) {
        // Configure cell with standard iOS Settings style
        cell.textLabel?.text = title
        cell.textLabel?.font = .systemFont(ofSize: 17)
        cell.textLabel?.textColor = isDestructive ? .systemRed : .label
        cell.selectionStyle = .default
        
        // Configure icon with tint color
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        guard let symbolImage = UIImage(systemName: icon, withConfiguration: iconConfig) else {
            cell.imageView?.image = nil
            return
        }
        
        // Apply tint color (blue for normal, red for destructive)
        let iconColor = isDestructive ? UIColor.systemRed : UIColor.systemBlue
        cell.imageView?.image = symbolImage.withTintColor(iconColor, renderingMode: .alwaysOriginal)
        cell.imageView?.tintColor = iconColor
    }

    // MARK: - Table View Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .general:
            handleGeneralRowSelection(at: indexPath)
        case .appearance:
            handleAppearanceRowSelection(at: indexPath)
        case .debug:
            handleDebugRowSelection(at: indexPath)
        }
    }

    private func handleGeneralRowSelection(at indexPath: IndexPath) {
        guard let row = GeneralRow(rawValue: indexPath.row) else { return }

        switch row {
        case .playerTypes:
            let playerTypesVC = PlayerTypesViewController()
            navigationController?.pushViewController(playerTypesVC, animated: true)
        }
    }
    
    private func handleAppearanceRowSelection(at indexPath: IndexPath) {
        guard let row = AppearanceRow(rawValue: indexPath.row) else { return }

        switch row {
        case .chipColor:
            let chipColorVC = ChipColorSelectionViewController()
            navigationController?.pushViewController(chipColorVC, animated: true)
        }
    }

    private func handleDebugRowSelection(at indexPath: IndexPath) {
        guard let row = DebugRow(rawValue: indexPath.row) else { return }

        switch row {
        case .resetTips:
            showResetTipsConfirmation()
        case .clearSessions:
            showClearSessionsConfirmation()
        }
    }

    private func showResetTipsConfirmation() {
        let alert = UIAlertController(
            title: "Reset All Tips?",
            message: "This will reset all tips so they appear again from the beginning. This is useful for testing the tip system.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .default) { _ in
            self.resetAllTips()
        })

        present(alert, animated: true)
    }

    private func showClearSessionsConfirmation() {
        let alert = UIAlertController(
            title: "Clear All Sessions?",
            message: "This will permanently delete all saved game sessions. This action cannot be undone.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { _ in
            self.clearAllSessions()
        })

        present(alert, animated: true)
    }

    private func resetAllTips() {
        NNTipManager.shared.resetAllTips()

        // Show success feedback
        let alert = UIAlertController(
            title: "Tips Reset",
            message: "All tips have been reset. You'll see them again as you use the app.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)

        // Provide haptic feedback
        HapticsHelper.lightHaptic()
    }

    private func clearAllSessions() {
        SessionPersistenceManager.shared.clearAllSessions()

        // Show success feedback
        let alert = UIAlertController(
            title: "Sessions Cleared",
            message: "All game sessions have been deleted.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)

        // Provide haptic feedback
        HapticsHelper.lightHaptic()
    }
}

