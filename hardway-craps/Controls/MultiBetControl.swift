//
//  MultiBetControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/23/25.
//

import UIKit

class MultiBetControl: PlainControl {
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = HardwayColors.label
        return label
    }()

    private let oddsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = HardwayColors.label.withAlphaComponent(0.6)
        return label
    }()
    
    private let numbersStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.isUserInteractionEnabled = false
        return stackView
    }()
    
    private let titleStack: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.isUserInteractionEnabled = false
        return stackView
    }()
    
    private let mainStack: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.isUserInteractionEnabled = false
        return stackView
    }()
    
    private var numberViews: [NumberView] = []
    
    let numbers: [Int]
    let odds: String
    private(set) var hitNumbers: Set<Int> = []
    
    init(title: String, numbers: [Int], odds: String) {
        self.numbers = numbers
        self.odds = odds
        super.init(title: nil)
        
        // Remove PlainControl's default 50pt height constraint
        var heightConstraintsToRemove: [NSLayoutConstraint] = []
        for constraint in constraints {
            if constraint.firstAttribute == .height && constraint.firstItem === self && constraint.constant == 50 {
                heightConstraintsToRemove.append(constraint)
            }
        }
        NSLayoutConstraint.deactivate(heightConstraintsToRemove)
        
        setupMultiBetView(title: title)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupMultiBetView(title: String) {
        titleLabel.text = title
        oddsLabel.text = odds
        
        // Create number views for each number
        for number in numbers {
            let numberView = NumberView(number: number)
            numberViews.append(numberView)
            numbersStackView.addArrangedSubview(numberView)
            
            // Constrain each number view to a fixed size
            NSLayoutConstraint.activate([
                numberView.widthAnchor.constraint(equalToConstant: 24),
                numberView.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        
        // Add title and numbers to titleStack
        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(numbersStackView)
        
        // Add titleStack and oddsLabel to mainStack
        mainStack.addArrangedSubview(titleStack)
        mainStack.addArrangedSubview(oddsLabel)
        
        addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            // Main stack fills horizontally and centers vertically
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            mainStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            // Title stack fills the width
            titleStack.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            titleStack.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            
            // Numbers stack view pinned to trailing edge of mainStack
            numbersStackView.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            
            // Numbers stack view height
            numbersStackView.heightAnchor.constraint(equalToConstant: 24),
            
            // Control height
            heightAnchor.constraint(equalToConstant: 70)
        ])
        
        // Set content hugging priorities: titleLabel hugs content
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        numbersStackView.setContentHuggingPriority(.required, for: .horizontal)
    }
    
    override func configureBetViewConstraints() {
        // Position bet view on trailing edge, vertically centered
        // Position it relative to the control itself, not numbersStackView
        // (numbersStackView isn't added yet when this is called)
        NSLayoutConstraint.activate([
            betView.centerYAnchor.constraint(equalTo: centerYAnchor),
            betView.centerXAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    /// Mark a number as hit
    func markNumberAsHit(_ number: Int) {
        guard numbers.contains(number) else { return }
        hitNumbers.insert(number)
        updateNumberViews()
    }
    
    /// Reset all hit numbers (e.g., when bet is won or lost)
    func resetHitNumbers() {
        hitNumbers.removeAll()
        updateNumberViews()
    }
    
    /// Check if all numbers have been hit (bet is complete)
    var isComplete: Bool {
        return hitNumbers.count == numbers.count
    }
    
    private func updateNumberViews() {
        for numberView in numberViews {
            let isHit = hitNumbers.contains(numberView.number)
            numberView.setHit(isHit)
        }
    }
}

// MARK: - NumberView

private class NumberView: UIView {
    
    private let numberLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 10, weight: .regular)
        label.textColor = HardwayColors.label
        label.backgroundColor = .clear
        return label
    }()
    
    private let checkmarkLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 8, weight: .regular)
        label.textColor = .white
        label.text = "✓"
        label.isHidden = true
        return label
    }()
    
    let number: Int
    
    init(number: Int) {
        self.number = number
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        numberLabel.text = "\(number)"
        
        // Make label circular with border - smaller size to prevent overlap
        let circleSize: CGFloat = 20
        numberLabel.layer.cornerRadius = circleSize / 2
        numberLabel.layer.borderWidth = 2
        numberLabel.layer.borderColor = HardwayColors.label.withAlphaComponent(0.5).cgColor
        numberLabel.clipsToBounds = true
        
        addSubview(numberLabel)
        addSubview(checkmarkLabel)
        
        NSLayoutConstraint.activate([
            // Number label - circular, centered
            numberLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            numberLabel.widthAnchor.constraint(equalToConstant: circleSize),
            numberLabel.heightAnchor.constraint(equalToConstant: circleSize),
            
            // Checkmark label - centered on number label
            checkmarkLabel.centerXAnchor.constraint(equalTo: numberLabel.centerXAnchor),
            checkmarkLabel.centerYAnchor.constraint(equalTo: numberLabel.centerYAnchor)
        ])
    }
    
    func setHit(_ isHit: Bool) {
        if isHit {
            numberLabel.backgroundColor = .systemBlue
            numberLabel.layer.borderColor = UIColor.systemBlue.cgColor
            numberLabel.textColor = .white
        } else {
            numberLabel.backgroundColor = .clear
            numberLabel.layer.borderColor = HardwayColors.label.withAlphaComponent(0.5).cgColor
            numberLabel.textColor = HardwayColors.label
        }
    }
}

