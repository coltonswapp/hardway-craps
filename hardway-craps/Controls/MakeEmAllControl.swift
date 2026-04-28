//
//  MakeEmAllControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 3/15/26.
//

import UIKit

/// A SpecialtyControl for the "Make Em All" bet.
/// Tracks all 10 numbers (2-6, 8-12) and wins when all are hit before a 7.
/// No number circles displayed — relies on Smalls/Talls controls for visual progress.
class MakeEmAllControl: SpecialtyControl {

    let numbers: [Int] = [2, 3, 4, 5, 6, 8, 9, 10, 11, 12]
    let odds: String = "175:1"
    private(set) var hitNumbers: Set<Int> = []

    init() {
        super.init(title: "All", subtitle: "175:1")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Make Em Tracking

    func markNumberAsHit(_ number: Int) {
        guard numbers.contains(number) else { return }
        hitNumbers.insert(number)
    }

    func resetHitNumbers() {
        hitNumbers.removeAll()
    }

    var isComplete: Bool {
        return hitNumbers.count == numbers.count
    }
}
