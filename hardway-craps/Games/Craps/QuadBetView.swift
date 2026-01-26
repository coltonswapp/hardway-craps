//
//  QuadBetView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class QuadBetView: UIView {
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = HardwayColors.label
        return label
    }()
    
    private(set) var betStack: UIStackView!
    
    var title: String? {
        didSet {
            titleLabel.text = title
        }
    }
    
    init(title: String? = nil) {
        self.title = title
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        
        // Create the bet stack (will be populated externally)
        betStack = UIStackView()
        betStack.translatesAutoresizingMaskIntoConstraints = false
        betStack.axis = .horizontal
        betStack.distribution = .fillEqually
        betStack.spacing = 8
        
        // Create container stack for title and bet stack
        let containerStack = UIStackView()
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.axis = .vertical
        containerStack.spacing = 12
        containerStack.alignment = .fill
        containerStack.distribution = .fill
        
        // Add title and bet stack to container
        containerStack.addArrangedSubview(titleLabel)
        containerStack.addArrangedSubview(betStack)
        
        addSubview(containerStack)
        
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            titleLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        titleLabel.text = title
    }
}

