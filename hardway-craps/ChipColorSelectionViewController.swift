//
//  ChipColorSelectionViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/23/26.
//

import UIKit

final class ChipColorSelectionViewController: UITableViewController {
    
    // MARK: - Chip Color Management
    
    private struct ChipColorKeys {
        static let chipColor = "ChipColor"
    }
    
    var selectedChipColor: String {
        get {
            return UserDefaults.standard.string(forKey: ChipColorKeys.chipColor) ?? "cyan"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ChipColorKeys.chipColor)
        }
    }
    
    private let chipValues = [1, 5, 25, 50, 100]
    
    /// Get the currently selected color set name
    private var selectedColorSetName: String {
        // First try to get the color set name directly (new system)
        if let colorSetName = UserDefaults.standard.string(forKey: "ChipColorSetName"),
           ChipColorSet.named(colorSetName) != nil {
            return colorSetName
        }
        
        // Fall back to mapping old color keys to new color set names (backward compatibility)
        let colorKey = selectedChipColor
        switch colorKey.lowercased() {
        case "cyan": return "Cyan"
        case "green": return "Green"
        case "grey", "gray": return "Grey"
        case "purple": return "Purple"
        case "red": return "Red"
        case "yellow": return "Yellow"
        default: return "Cyan"
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
        
        title = "Chip Tint Color"
        view.backgroundColor = .systemGroupedBackground
        
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorColor = .separator
        tableView.register(ChipColorCell.self, forCellReuseIdentifier: "ChipColorCell")
        tableView.rowHeight = 70
    }
    
    // MARK: - Table View Data Source
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ChipColorSet.all.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChipColorCell", for: indexPath) as! ChipColorCell
        
        let colorSet = ChipColorSet.all[indexPath.row]
        let isSelected = colorSet.name == selectedColorSetName
        
        cell.configure(
            colorSet: colorSet,
            chipValues: chipValues,
            isSelected: isSelected
        )
        
        return cell
    }
    
    // MARK: - Table View Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let colorSet = ChipColorSet.all[indexPath.row]
        
        // Store the color set name directly (new system)
        UserDefaults.standard.set(colorSet.name, forKey: "ChipColorSetName")
        
        // Also update the old color key for backward compatibility
        // Map color set name back to old color key if possible
        let colorKey: String
        switch colorSet.name.lowercased() {
        case "cyan": colorKey = "cyan"
        case "green": colorKey = "green"
        case "grey", "gray": colorKey = "grey"
        case "purple": colorKey = "purple"
        case "red": colorKey = "red"
        case "yellow": colorKey = "yellow"
        default: colorKey = "cyan" // Default for unmapped color sets
        }
        selectedChipColor = colorKey
        
        // Reload all cells to update selection indicators
        tableView.reloadData()
        
        HapticsHelper.lightHaptic()
    }
}

// MARK: - Chip Color Cell

final class ChipColorCell: UITableViewCell {
    
    private let chipStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.distribution = .fill
        stackView.alignment = .center
        stackView.spacing = -10  // Negative spacing creates overlap (increased for more overlap)
        return stackView
    }()
    
    private let checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "checkmark")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCell() {
        selectionStyle = .default
        backgroundColor = .secondarySystemGroupedBackground
        
        contentView.addSubview(chipStackView)
        contentView.addSubview(checkmarkImageView)
        
        NSLayoutConstraint.activate([
            chipStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            chipStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chipStackView.heightAnchor.constraint(equalToConstant: 45),
            
            checkmarkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            checkmarkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(colorSet: ChipColorSet, chipValues: [Int], isSelected: Bool) {
        checkmarkImageView.isHidden = !isSelected
        
        // Clear existing chip views
        chipStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Create programmatic chip views
        for (index, value) in chipValues.enumerated() {
            let chip = ProgrammaticChipView(value: value, size: 45, colorSet: colorSet)
            chip.translatesAutoresizingMaskIntoConstraints = false
            chip.isUserInteractionEnabled = false // Disable interaction in selection view
            
            // Set z-position so earlier chips appear on top (like ChipSelector)
            chip.layer.zPosition = CGFloat(chipValues.count - 1 - index)
            
            chipStackView.addArrangedSubview(chip)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        chipStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        checkmarkImageView.isHidden = true
    }
}
