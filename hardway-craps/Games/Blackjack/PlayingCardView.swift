//
//  PlayingCardView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

final class PlayingCardView: UIView {
    
    enum Suit: CaseIterable {
        case clubs
        case hearts
        case diamonds
        case spades
        
        var imageName: String {
            switch self {
            case .clubs:
                return "club-suit"
            case .hearts:
                return "heart-suit"
            case .diamonds:
                return "diamond-suit"
            case .spades:
                return "spade-suit"
            }
        }
        
        var color: UIColor {
            switch self {
            case .hearts, .diamonds:
                return HardwayColors.suitRed
            case .clubs, .spades:
                return HardwayColors.suitBlack
            }
        }
    }
    
    enum Rank: String, CaseIterable {
        case ace = "A"
        case king = "K"
        case queen = "Q"
        case jack = "J"
        case ten = "10"
        case nine = "9"
        case eight = "8"
        case seven = "7"
        case six = "6"
        case five = "5"
        case four = "4"
        case three = "3"
        case two = "2"
    }
    
    private let backView = UIView()
    private let valueLabel = UILabel()
    private let suitImageView = UIImageView()
    
    private var labelTopConstraint: NSLayoutConstraint!
    private var labelLeadingConstraint: NSLayoutConstraint!
    private var imageLeadingConstraint: NSLayoutConstraint!
    private var imageBottomConstraint: NSLayoutConstraint!
    private var suitWidthConstraint: NSLayoutConstraint!
    private var suitHeightConstraint: NSLayoutConstraint!

    private static let baseSuitSize: CGFloat = 24
    private var isFaceDown = false
    
    var isFaceDownCard: Bool {
        return isFaceDown
    }
    
    var padding: CGFloat = 8 {
        didSet {
            labelTopConstraint.constant = padding
            labelLeadingConstraint.constant = padding
            imageLeadingConstraint.constant = padding
            imageBottomConstraint.constant = -padding
        }
    }

    /// Scale factor for the suit image (1.0 = default 24pt). Used for compact layouts.
    var suitScale: CGFloat = 1.0 {
        didSet {
            guard suitScale != oldValue else { return }
            applySuitSize()
        }
    }

    /// Scale factor for the whole card face (value + suit). Used when the card view is sized down (e.g. count-based scaling in compact hand) so the content scales with the card.
    var contentScale: CGFloat = 1.0 {
        didSet {
            guard contentScale != oldValue else { return }
            applyContentScale()
        }
    }

    /// Scale factor for the value label only (1.0 = same as contentScale). Used in compact layouts to make the rank character smaller.
    var valueScale: CGFloat = 1.0 {
        didSet {
            guard valueScale != oldValue else { return }
            applyContentScale()
        }
    }

    private static let baseValueFontSize: CGFloat = 30

    private func applySuitSize() {
        let size = Self.baseSuitSize * suitScale * contentScale
        suitWidthConstraint.constant = size
        suitHeightConstraint.constant = size
    }

    private func applyContentScale() {
        valueLabel.font = .systemFont(ofSize: Self.baseValueFontSize * contentScale * valueScale, weight: .semibold)
        applySuitSize()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(rank: Rank, suit: Suit) {
        let attributes: [NSAttributedString.Key: Any] = [
            .kern: -1.5,
            .foregroundColor: suit.color
        ]
        valueLabel.attributedText = NSAttributedString(string: rank.rawValue, attributes: attributes)
        suitImageView.image = UIImage(named: suit.imageName)?.withRenderingMode(.alwaysTemplate)
        suitImageView.tintColor = suit.color
    }

    func configureCutCard() {
        // Configure as a pure red cut card
        backgroundColor = UIColor.systemRed
        valueLabel.alpha = 0
        suitImageView.alpha = 0
        backView.alpha = 0
    }
    
    func setFaceDown(_ faceDown: Bool, animated: Bool = false) {
        guard faceDown != isFaceDown else { return }
        isFaceDown = faceDown
        
        let updateAppearance = {
            self.backView.alpha = faceDown ? 1 : 0
            self.valueLabel.alpha = faceDown ? 0 : 1
            self.suitImageView.alpha = faceDown ? 0 : 1
        }
        
        if animated {
            let transition: UIView.AnimationOptions = faceDown ? .transitionFlipFromRight : .transitionFlipFromLeft
            UIView.transition(with: self, duration: 0.35, options: [transition, .showHideTransitionViews], animations: {
                updateAppearance()
            })
        } else {
            updateAppearance()
        }
    }
    
    private func setupView() {
        backgroundColor = HardwayColors.surfaceWhite
        layer.cornerRadius = 8
        layer.masksToBounds = true
        
        backView.translatesAutoresizingMaskIntoConstraints = false
        backView.backgroundColor = HardwayColors.surfaceGray
        backView.layer.cornerRadius = 8
        backView.layer.masksToBounds = true
        backView.layer.borderWidth = 1
        backView.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
        backView.alpha = 0
        
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        valueLabel.textAlignment = .right
        valueLabel.clipsToBounds = false
        
        suitImageView.translatesAutoresizingMaskIntoConstraints = false
        suitImageView.contentMode = .scaleAspectFit
        
        addSubview(backView)
        addSubview(valueLabel)
        addSubview(suitImageView)
        
        labelTopConstraint = valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: padding)
        labelLeadingConstraint = valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding)
        imageLeadingConstraint = suitImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding)
        imageBottomConstraint = suitImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding)
        
        NSLayoutConstraint.activate([
            backView.topAnchor.constraint(equalTo: topAnchor),
            backView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            labelTopConstraint,
            labelLeadingConstraint,
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -padding),
            
            imageLeadingConstraint,
            imageBottomConstraint
        ])
        suitWidthConstraint = suitImageView.widthAnchor.constraint(equalToConstant: Self.baseSuitSize)
        suitHeightConstraint = suitImageView.heightAnchor.constraint(equalToConstant: Self.baseSuitSize)
        NSLayoutConstraint.activate([suitWidthConstraint, suitHeightConstraint])
    }
}
