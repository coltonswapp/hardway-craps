//
//  SmallControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/23/25.
//

import UIKit

class SmallControl: PlainControl {

    /// Hardways / horn use their own layout; skip `PlainControl`’s empty title label.
    override var usesCustomTitleLayout: Bool { true }

    private let dieImageView1: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let dieImageView2: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let oddsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        // Device-specific font size
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        label.font = .systemFont(ofSize: isIPad ? 15 : 13, weight: .regular)
        label.textColor = HardwayColors.label.withAlphaComponent(0.6)
        return label
    }()
    
    private let diceStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.isUserInteractionEnabled = false
        return stackView
    }()
    
    private let contentStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.isUserInteractionEnabled = false
        return stackView
    }()
    
    let dieValue1: Int
    let dieValue2: Int
    let odds: String

    /// Horn cells are very narrow; hiding the payout while a bet is active frees space for the chip.
    let hidesOddsWhileBetting: Bool

    private var contentStackCenterXConstraint: NSLayoutConstraint?

    init(dieValue1: Int, dieValue2: Int, odds: String, hidesOddsWhileBetting: Bool = false) {
        self.dieValue1 = dieValue1
        self.dieValue2 = dieValue2
        self.odds = odds
        self.hidesOddsWhileBetting = hidesOddsWhileBetting
        super.init(title: nil)
        setupSmallControlView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupSmallControlView() {
        // Device-specific die size: smaller on iPhone, larger on iPad
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let dieSize: CGFloat = isIPad ? 35 : 32

        // Set spacing
        diceStackView.spacing = 4
        contentStackView.spacing = 12

        // Set die images
        dieImageView1.image = UIImage(named: "hardway-die-\(dieValue1)")
        dieImageView2.image = UIImage(named: "hardway-die-\(dieValue2)")
        oddsLabel.text = odds

        // Style the control to match action buttons
        backgroundColor = HardwayColors.surfaceGray
        layer.cornerRadius = 16
        clipsToBounds = true
        layer.borderWidth = 1.5
        layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor

        // Add dice to dice stack view
        diceStackView.addArrangedSubview(dieImageView1)
        diceStackView.addArrangedSubview(dieImageView2)

        // Add dice stack and odds label to content stack view
        contentStackView.addArrangedSubview(diceStackView)
        contentStackView.addArrangedSubview(oddsLabel)

        addSubview(contentStackView)

        let cx = contentStackView.centerXAnchor.constraint(equalTo: centerXAnchor)
        contentStackCenterXConstraint = cx

        NSLayoutConstraint.activate([
            // Die images - original size
            dieImageView1.widthAnchor.constraint(equalToConstant: dieSize),
            dieImageView1.heightAnchor.constraint(equalToConstant: dieSize),

            dieImageView2.widthAnchor.constraint(equalToConstant: dieSize),
            dieImageView2.heightAnchor.constraint(equalToConstant: dieSize),

            cx,
            contentStackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        bringSubviewToFront(betView)
    }

    override func configureBetViewConstraints() {
        NSLayoutConstraint.activate([
            betView.centerYAnchor.constraint(equalTo: centerYAnchor),
            betView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
    }

    // MARK: - Content shift / Horn odds visibility

    /// Hardways: slide dice + odds toward the leading edge on iPhone when a bet is present.
    /// Horn: hide payout text while a bet is active (cells are too narrow for the slide).
    override func betAmountDidChange() {
        let hasBet = betAmount > 0

        let targetOddsHidden = hidesOddsWhileBetting && hasBet
        let oddsNeedsUpdate = hidesOddsWhileBetting && oddsLabel.isHidden != targetOddsHidden

        let targetCenterX = targetContentCenterXOffset(hasBet: hasBet)
        let centerNeedsUpdate = contentStackCenterXConstraint?.constant != targetCenterX

        guard oddsNeedsUpdate || centerNeedsUpdate else { return }

        UIView.animate(
            withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 1.0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            if oddsNeedsUpdate {
                self.oddsLabel.isHidden = targetOddsHidden
            }
            if centerNeedsUpdate {
                self.contentStackCenterXConstraint?.constant = targetCenterX
            }
            self.layoutIfNeeded()
        }
    }

    /// Horizontal offset for `contentStackView` so dice don’t drift when the odds column hides (Horn).
    /// Full row centered: dice leading edge at `centerX - W/2`. After odds collapse, same leading edge
    /// requires shifting the narrower stack by `-(W - wDice)/2 = -(odds + spacing)/2`.
    private func targetContentCenterXOffset(hasBet: Bool) -> CGFloat {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { return 0 }

        if hidesOddsWhileBetting {
            guard hasBet else { return 0 }
            let oddsWidth: CGFloat =
                oddsLabel.bounds.width > 1
                ? oddsLabel.bounds.width
                : oddsLabel.intrinsicContentSize.width
            return -(oddsWidth + contentStackView.spacing) / 2
        }

        return hasBet ? -14 : 0
    }
}

