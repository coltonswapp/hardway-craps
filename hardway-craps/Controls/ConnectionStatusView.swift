//
//  ConnectionStatusView.swift
//  hardway-craps
//

import UIKit

class ConnectionStatusView: UIView {

    private let spinner = NNLoadingSpinner()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.9)
        layer.cornerRadius = 12

        alpha = 0
        isHidden = true

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.configure(with: HardwayColors.yellow)
        spinner.setSpeed(duration: 0.7)
        addSubview(spinner)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Reconnecting..."
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = HardwayColors.label
        addSubview(label)

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 20),
            spinner.heightAnchor.constraint(equalToConstant: 20),

            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    func show() {
        guard isHidden else { return }
        isHidden = false
        UIView.animate(withDuration: 0.25) {
            self.alpha = 1
        }
    }

    func hide() {
        guard !isHidden else { return }
        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0
        }, completion: { _ in
            self.isHidden = true
        })
    }
}
