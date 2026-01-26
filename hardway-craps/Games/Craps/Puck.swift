//
//  Puck.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class Puck: UIView {

    private let onLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.text = "ON"
        return label
    }()

    private let offLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.text = "OFF"
        return label
    }()

    var isOn: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 20

        addSubview(onLabel)
        addSubview(offLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 40),
            heightAnchor.constraint(equalToConstant: 40),

            onLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            onLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            offLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            offLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        if isOn {
            backgroundColor = .white
            onLabel.textColor = .black
            offLabel.isHidden = true
            onLabel.isHidden = false
            layer.borderWidth = 4
            layer.borderColor = HardwayColors.offBlack.cgColor
        } else {
            backgroundColor = .black
            offLabel.textColor = .white
            onLabel.isHidden = true
            offLabel.isHidden = false
            layer.borderWidth = 4
            layer.borderColor = HardwayColors.offBlack.cgColor
        }
    }
}
