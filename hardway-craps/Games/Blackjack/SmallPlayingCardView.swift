//
//  SmallPlayingCardView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/25/26.
//

import UIKit

final class SmallPlayingCardView: UIView {

    private let valueLabel = UILabel()
    private let suitImageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(rank: PlayingCardView.Rank, suit: PlayingCardView.Suit) {
        valueLabel.text = rank.rawValue
        valueLabel.textColor = suit.color
        suitImageView.image = UIImage(named: suit.imageName)?.withRenderingMode(.alwaysTemplate)
        suitImageView.tintColor = suit.color
    }

    private func setupView() {
        backgroundColor = HardwayColors.surfaceWhite
        layer.cornerRadius = 4
        layer.masksToBounds = false

        // Add shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 5

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .systemFont(ofSize: 14, weight: .heavy)
        valueLabel.textAlignment = .left

        suitImageView.translatesAutoresizingMaskIntoConstraints = false
        suitImageView.contentMode = .scaleAspectFit

        addSubview(valueLabel)
        addSubview(suitImageView)

        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),

            suitImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            suitImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            suitImageView.widthAnchor.constraint(equalToConstant: 9),
            suitImageView.heightAnchor.constraint(equalToConstant: 9)
        ])
    }
}
