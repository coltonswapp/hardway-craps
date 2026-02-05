//
//  BaseSettingsViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/25/26.
//

import UIKit

class BaseSettingsViewController: UITableViewController {
    
    // Common callbacks
    var onSettingsChanged: (() -> Void)?
    var onShowGameDetails: (() -> Void)?
    var onHitATM: (() -> Void)?
    
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
    
    func setupViewController() {
        // Override in subclasses to set title
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissSettings)
        )
    }
    
    func setupTableView() {
        tableView.separatorColor = HardwayColors.surfaceGray
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
    }
    
    @objc func dismissSettings() {
        dismiss(animated: true)
    }
    
    // MARK: - Table View Delegate
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = HardwayColors.label
            header.textLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        }
    }
    
    // MARK: - Helper Methods
    
    func createStandardLabel(text: String, color: UIColor = .white) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = color
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    func createSecondaryLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white.withAlphaComponent(0.6)
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    func createStandardSwitch(isOn: Bool, onChange: @escaping (Bool) -> Void) -> UISwitch {
        let switchControl = UISwitch()
        switchControl.isOn = isOn
        switchControl.addAction(UIAction { action in
            if let switchControl = action.sender as? UISwitch {
                onChange(switchControl.isOn)
            }
        }, for: .valueChanged)
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        return switchControl
    }
    
    func createMenuButton(title: String, menu: UIMenu) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = .systemBlue

        let button = UIButton(configuration: configuration, primaryAction: nil)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
    
    func layoutLabelAndSwitch(label: UILabel, switchControl: UISwitch, in cell: UITableViewCell) {
        cell.contentView.addSubview(label)
        cell.contentView.addSubview(switchControl)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: switchControl.leadingAnchor, constant: -16),
            
            switchControl.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            switchControl.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])
    }
    
    func layoutLabelAndButton(label: UILabel, button: UIButton, in cell: UITableViewCell) {
        cell.contentView.addSubview(label)
        cell.contentView.addSubview(button)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -16),
            
            button.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            button.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])
    }
    
    func layoutLabelAndIcon(label: UILabel, iconView: UIImageView, in cell: UITableViewCell) {
        cell.contentView.addSubview(iconView)
        cell.contentView.addSubview(label)
        
        cell.selectionStyle = .default
        cell.accessoryType = .disclosureIndicator
        
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
    
    // MARK: - Cell Configuration Helpers
    
    func configureSwitchCell(_ cell: UITableViewCell, title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        let label = createStandardLabel(text: title)
        let switchControl = createStandardSwitch(isOn: isOn, onChange: onChange)
        layoutLabelAndSwitch(label: label, switchControl: switchControl, in: cell)
    }
    
    func configureActionCell(_ cell: UITableViewCell, title: String, icon: String, isDestructive: Bool = false, onTap: @escaping () -> Void) {
        let labelColor: UIColor = isDestructive ? .systemRed : .white
        let iconColor: UIColor = isDestructive ? .systemRed : HardwayColors.yellow
        
        let label = createStandardLabel(text: title, color: labelColor)
        
        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = iconColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        layoutLabelAndIcon(label: label, iconView: iconView, in: cell)
    }
}

// MARK: - Custom Cell Class

class SettingsTableViewCell: UITableViewCell {

//    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
//        super.init(style: style, reuseIdentifier: reuseIdentifier)
//
//        // Set a proper background configuration to prevent crashes
//        var backgroundConfig = UIBackgroundConfiguration.listGroupedCell()
//        backgroundConfig.backgroundColor = HardwayColors.surfaceGray
//        backgroundConfiguration = backgroundConfig
//    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        // Ensure background configuration is maintained during reuse
//        if backgroundConfiguration == nil {
//            var backgroundConfig = UIBackgroundConfiguration.listGroupedCell()
//            backgroundConfig.backgroundColor = HardwayColors.surfaceGray
//            backgroundConfiguration = backgroundConfig
//        }
    }
}
