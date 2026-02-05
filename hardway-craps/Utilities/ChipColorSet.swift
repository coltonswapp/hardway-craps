//
//  ChipColorSet.swift
//  hardway-craps
//
//  Created by Colton Swapp on 2/5/26.
//

import UIKit

/// A color set for programmatic chips containing background, ring, and text colors
struct ChipColorSet {
    let name: String
    let backgroundColor: UIColor
    let ring1Color: UIColor
    let ring2Color: UIColor
    let textColor: UIColor
    
    /// Applies this color set to a ProgrammaticChipView
    func apply(to chipView: ProgrammaticChipView) {
        chipView.chipBackgroundColor = backgroundColor
        chipView.ring1Color = ring1Color
        chipView.ring2Color = ring2Color
        chipView.textColor = textColor
    }
}

extension ChipColorSet {
    /// Predefined color sets for chips
    
    /// Yellow/Green theme (current test colors)
    static let yellowGreen = ChipColorSet(
        name: "Yellow Green",
        backgroundColor: UIColor(red: 78/255, green: 78/255, blue: 41/255, alpha: 1.0),
        ring1Color: UIColor(red: 133/255, green: 133/255, blue: 0/255, alpha: 1.0),
        ring2Color: UIColor(red: 255/255, green: 255/255, blue: 55/255, alpha: 1.0),
        textColor: UIColor(red: 255/255, green: 255/255, blue: 73/255, alpha: 1.0)
    )
    
    /// Cyan theme
    static let cyan = ChipColorSet(
        name: "Cyan",
        backgroundColor: UIColor(red: 20/255, green: 60/255, blue: 80/255, alpha: 1.0),
        ring1Color: UIColor(red: 0/255, green: 150/255, blue: 200/255, alpha: 1.0),
        ring2Color: UIColor(red: 100/255, green: 220/255, blue: 255/255, alpha: 1.0),
        textColor: UIColor(red: 150/255, green: 240/255, blue: 255/255, alpha: 1.0)
    )
    
    /// Green theme
    static let green = ChipColorSet(
        name: "Green",
        backgroundColor: UIColor(red: 20/255, green: 60/255, blue: 20/255, alpha: 1.0),
        ring1Color: UIColor(red: 0/255, green: 150/255, blue: 0/255, alpha: 1.0),
        ring2Color: UIColor(red: 100/255, green: 255/255, blue: 100/255, alpha: 1.0),
        textColor: UIColor(red: 150/255, green: 255/255, blue: 150/255, alpha: 1.0)
    )
    
    /// Red theme
    static let red = ChipColorSet(
        name: "Red",
        backgroundColor: UIColor(red: 80/255, green: 20/255, blue: 20/255, alpha: 1.0),
        ring1Color: UIColor(red: 180/255, green: 0/255, blue: 0/255, alpha: 1.0),
        ring2Color: UIColor(red: 255/255, green: 100/255, blue: 100/255, alpha: 1.0),
        textColor: UIColor(red: 255/255, green: 150/255, blue: 150/255, alpha: 1.0)
    )
    
    /// Purple theme
    static let purple = ChipColorSet(
        name: "Purple",
        backgroundColor: UIColor(red: 60/255, green: 20/255, blue: 70/255, alpha: 1.0),
        ring1Color: UIColor(red: 150/255, green: 0/255, blue: 200/255, alpha: 1.0),
        ring2Color: UIColor(red: 220/255, green: 100/255, blue: 255/255, alpha: 1.0),
        textColor: UIColor(red: 240/255, green: 150/255, blue: 255/255, alpha: 1.0)
    )
    
    /// Grey theme
    static let grey = ChipColorSet(
        name: "Grey",
        backgroundColor: UIColor(red: 50/255, green: 50/255, blue: 50/255, alpha: 1.0),
        ring1Color: UIColor(red: 120/255, green: 120/255, blue: 120/255, alpha: 1.0),
        ring2Color: UIColor(red: 200/255, green: 200/255, blue: 200/255, alpha: 1.0),
        textColor: UIColor(red: 240/255, green: 240/255, blue: 240/255, alpha: 1.0)
    )
    
    /// Blue theme (original migrated colors)
    static let blue = ChipColorSet(
        name: "Blue",
        backgroundColor: UIColor(red: 0/255, green: 58/255, blue: 66/255, alpha: 1.0),
        ring1Color: UIColor(red: 0/255, green: 90/255, blue: 91/255, alpha: 1.0),
        ring2Color: UIColor(red: 0/255, green: 170/255, blue: 179/255, alpha: 1.0),
        textColor: UIColor(red: 0/255, green: 175/255, blue: 176/255, alpha: 1.0)
    )
    
    /// Orange theme
    static let orange = ChipColorSet(
        name: "Orange",
        backgroundColor: UIColor(red: 111/255, green: 57/255, blue: 19/255, alpha: 1.0),
        ring1Color: UIColor(red: 145/255, green: 80/255, blue: 0/255, alpha: 1.0),
        ring2Color: UIColor(red: 255/255, green: 131/255, blue: 36/255, alpha: 1.0),
        textColor: UIColor(red: 255/255, green: 131/255, blue: 36/255, alpha: 1.0)
    )

    static let greenOriginal = ChipColorSet(
        name: "Green Original",
        backgroundColor: UIColor(red: 0/255, green: 66/255, blue: 12/255, alpha: 1.0),
        ring1Color: UIColor(red: 0/255, green: 179/255, blue: 3/255, alpha: 1.0),
        ring2Color: UIColor(red: 36/255, green: 91/255, blue: 0/255, alpha: 1.0),
        textColor: UIColor(red: 14/255, green: 206/255, blue: 0/255, alpha: 1.0)
    )
    static let redOriginal = ChipColorSet(
        name: "Red Original",
        backgroundColor: UIColor(red: 66/255, green: 0/255, blue: 0/255, alpha: 1.0),
        ring1Color: UIColor(red: 103/255, green: 0/255, blue: 0/255, alpha: 1.0),
        ring2Color: UIColor(red: 195/255, green: 39/255, blue: 39/255, alpha: 1.0),
        textColor: UIColor(red: 191/255, green: 0/255, blue: 0/255, alpha: 1.0)
    )

    static let offBlack = ChipColorSet(
        name: "OffBlack",
        backgroundColor: UIColor(red: 40/255, green: 40/255, blue: 40/255, alpha: 1.0),
        ring1Color: UIColor(red: 75/255, green: 75/255, blue: 75/255, alpha: 1.0),
        ring2Color: UIColor(red: 120/255, green: 120/255, blue: 120/255, alpha: 1.0),
        textColor: UIColor(red: 120/255, green: 120/255, blue: 120/255, alpha: 1.0)
    )

    /// All available color sets
    static let all: [ChipColorSet] = [
        .yellowGreen,
        .cyan,
        .green,
        .red,
        .purple,
        .grey,
        .blue,
        .orange,
        .greenOriginal,
        .redOriginal,
        .offBlack        
    ]
    
    /// Get a color set by name
    static func named(_ name: String) -> ChipColorSet? {
        return all.first { $0.name.lowercased() == name.lowercased() }
    }
    
    /// Get the currently selected color set from UserDefaults
    static var current: ChipColorSet {
        // First try to get the color set name directly (new system)
        if let colorSetName = UserDefaults.standard.string(forKey: "ChipColorSetName"),
           let colorSet = named(colorSetName) {
            return colorSet
        }
        
        // Fall back to mapping old color keys to new color set names (backward compatibility)
        let colorKey = UserDefaults.standard.string(forKey: "ChipColor") ?? "cyan"
        let colorSetName: String
        switch colorKey.lowercased() {
        case "cyan": colorSetName = "Cyan"
        case "green": colorSetName = "Green"
        case "grey", "gray": colorSetName = "Grey"
        case "purple": colorSetName = "Purple"
        case "red": colorSetName = "Red"
        case "yellow": colorSetName = "Yellow"
        default: colorSetName = "Cyan"
        }
        return named(colorSetName) ?? .cyan
    }
}
