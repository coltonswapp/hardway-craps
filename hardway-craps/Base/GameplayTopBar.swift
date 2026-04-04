//
//  GameplayTopBar.swift
//  hardway-craps
//

import UIKit

class GameplayTopBar: UIView {

    private(set) var leadingView: UIView?
    private(set) var trailingView: UIView?

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.distribution = .fill
        sv.alignment = .top
        sv.spacing = 16
        return sv
    }()

    var topConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(leadingView: UIView, trailingView: UIView? = nil) {
        self.leadingView = leadingView
        self.trailingView = trailingView

        stackView.arrangedSubviews.forEach { stackView.removeArrangedSubview($0); $0.removeFromSuperview() }

        leadingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stackView.addArrangedSubview(leadingView)

        if let trailing = trailingView {
            trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
            trailing.setContentHuggingPriority(.required, for: .horizontal)
            stackView.addArrangedSubview(trailing)
        }
    }

    func installConstraints(in parent: UIView) {
        parent.addSubview(self)
        topConstraint = topAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.topAnchor, constant: 12)
        NSLayoutConstraint.activate([
            topConstraint,
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 16),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -16),
        ])
    }
}
