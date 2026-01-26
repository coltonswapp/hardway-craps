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
    
    private let chipColors: [(name: String, colorKey: String)] = [
        ("Cyan", "cyan"),
        ("Green", "green"),
        ("Grey", "grey"),
        ("Purple", "purple"),
        ("Red", "red"),
        ("Yellow", "yellow"),
    ]
    
    private let chipValues = [1, 5, 25, 50, 100]
    
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
        return chipColors.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChipColorCell", for: indexPath) as! ChipColorCell
        
        let colorOption = chipColors[indexPath.row]
        let isSelected = colorOption.colorKey == selectedChipColor
        
        cell.configure(
            colorKey: colorOption.colorKey,
            chipValues: chipValues,
            isSelected: isSelected
        )
        
        return cell
    }
    
    // MARK: - Table View Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let colorOption = chipColors[indexPath.row]
        selectedChipColor = colorOption.colorKey
        
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
        stackView.spacing = -35  // Negative spacing creates overlap (increased for more overlap)
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
            chipStackView.heightAnchor.constraint(equalToConstant: 50),
            
            checkmarkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            checkmarkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(colorKey: String, chipValues: [Int], isSelected: Bool) {
        checkmarkImageView.isHidden = !isSelected
        
        // Clear existing chip views
        chipStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Create chip image views using individual color assets
        for (index, value) in chipValues.enumerated() {
            let chipImageView = UIImageView()
            chipImageView.translatesAutoresizingMaskIntoConstraints = false
            chipImageView.contentMode = .scaleAspectFit
            
            // Load chip image with color suffix
            chipImageView.image = UIImage(named: "hardway-chip-\(value)-\(colorKey)")
            
            // Set z-position so earlier chips appear on top (like ChipSelector)
            chipImageView.layer.zPosition = CGFloat(chipValues.count - 1 - index)
            
            // Add shadow for overlapping effect (like ChipSelector)
            chipImageView.layer.shadowColor = UIColor.black.cgColor
            chipImageView.layer.shadowOffset = CGSize(width: 2, height: 2)
            chipImageView.layer.shadowRadius = 4
            chipImageView.layer.shadowOpacity = 0.3
            chipImageView.layer.masksToBounds = false
            
            chipStackView.addArrangedSubview(chipImageView)
            
            NSLayoutConstraint.activate([
                chipImageView.widthAnchor.constraint(equalToConstant: 65),
                chipImageView.heightAnchor.constraint(equalToConstant: 65)
            ])
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        chipStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        checkmarkImageView.isHidden = true
    }
}
