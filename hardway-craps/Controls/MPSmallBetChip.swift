//
//  MPSmallBetChip.swift
//  hardway-craps
//
//  Multiplayer bet chip with yellow, red, blue, and green player styles.
//

import UIKit

enum MPSmallBetChipStyle {
    case yellow
    case red
    case blue
    case green

    var textColor: UIColor {
        switch self {
        case .yellow: return HardwayColors.hardwaysYellow
        case .red: return HardwayColors.mpChipRedText
        case .blue: return HardwayColors.mpChipBlueText
        case .green: return HardwayColors.mpChipGreenText
        }
    }

    var strokeColor: UIColor {
        switch self {
        case .yellow: return HardwayColors.mpChipYellowStroke
        case .red: return HardwayColors.mpChipRedStroke
        case .blue: return HardwayColors.mpChipBlueStroke
        case .green: return HardwayColors.mpChipGreenStroke
        }
    }
}

class MPSmallBetChip: UIView, BetChipViewProtocol {

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        return label
    }()

    private let normalBackgroundColor = HardwayColors.betGray
    private let lockedBackgroundColor: UIColor = {
        return HardwayColors.betGray.darker(by: 6.0)
    }()

    // MARK: - CADisplayLink animation state
    private var displayLink: CADisplayLink?
    private var animationStartTime: CFTimeInterval = 0
    private var startAmount: Int = 0
    private var targetAmount: Int = 0
    private static let animationDuration: CFTimeInterval = 0.3

    var style: MPSmallBetChipStyle {
        didSet {
            amountLabel.textColor = style.textColor
            layer.borderColor = style.strokeColor.cgColor
        }
    }

    var amount: Int = 0 {
        didSet {
            amountLabel.text = "\(amount)"
            isHidden = amount == 0
            accessibilityValue = "\(amount)"
        }
    }

    func setLocked(_ locked: Bool) {
        backgroundColor = locked ? lockedBackgroundColor : normalBackgroundColor
    }

    init(style: MPSmallBetChipStyle) {
        self.style = style
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let baseHeight: CGFloat = 30
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let height: CGFloat = isIPad ? baseHeight * 1.25 : baseHeight

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = HardwayColors.betGray

        amountLabel.textColor = style.textColor
        layer.borderColor = style.strokeColor.cgColor
        layer.borderWidth = 2

        alpha = 1.0
        isOpaque = true

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = isIPad ? 5 * 1.25 : 5
        layer.shadowOffset = CGSize(width: 0, height: isIPad ? 3 * 1.25 : 3)

        amountLabel.font = .systemFont(ofSize: isIPad ? 12 * 1.25 : 12, weight: .semibold)

        isHidden = true

        addSubview(amountLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: height),
            heightAnchor.constraint(equalToConstant: height),

            amountLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            amountLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func addToBet(_ value: Int) {
        amount = max(0, amount + value)
    }

    func clearBet() {
        amount = 0
    }

    func setAmount(_ newAmount: Int, animated: Bool) {
        displayLink?.invalidate()
        displayLink = nil

        guard animated, amount != newAmount, newAmount != 0 else {
            amount = newAmount
            return
        }

        let oldAmount = amount
        isHidden = false

        startAmount = oldAmount
        targetAmount = newAmount
        animationStartTime = CACurrentMediaTime()

        displayLink = CADisplayLink(target: self, selector: #selector(tickAmountAnimation))
        displayLink?.add(to: .main, forMode: .common)

        if newAmount > oldAmount {
            UIView.animate(withDuration: 0.1) {
                self.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                UIView.animate(withDuration: 0.2) {
                    self.transform = .identity
                }
            }
        }
    }

    @objc private func tickAmountAnimation() {
        let elapsed = CACurrentMediaTime() - animationStartTime
        if elapsed >= Self.animationDuration {
            amount = targetAmount
            displayLink?.invalidate()
            displayLink = nil
        } else {
            let progress = elapsed / Self.animationDuration
            let eased = progress * (2.0 - progress)
            let current = startAmount + Int(Double(targetAmount - startAmount) * eased)
            amountLabel.text = "\(current)"
        }
    }
    
    /// Play a quick shimmer animation on the chip
    func playChipShimmer() {
        let shimmer = CAGradientLayer()
        shimmer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.4).cgColor,
            UIColor.white.withAlphaComponent(0.4).cgColor,
            UIColor.clear.cgColor
        ]
        shimmer.locations = [0, 0.3, 0.7, 1]

        let angle = 10 * CGFloat.pi / 180
        shimmer.startPoint = CGPoint(x: 0.5 - cos(angle) * 0.5, y: 0.5 - sin(angle) * 0.5)
        shimmer.endPoint   = CGPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)
        shimmer.frame = bounds
        shimmer.cornerRadius = layer.cornerRadius
        shimmer.masksToBounds = true

        layer.addSublayer(shimmer)

        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.8, -0.6, -0.4, -0.2]
        animation.toValue   = [1.2, 1.4, 1.6, 1.8]
        animation.duration  = 0.3  // Faster shimmer for chips
        animation.repeatCount = 1
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { shimmer.removeFromSuperlayer() }
        shimmer.add(animation, forKey: "shimmer")
        CATransaction.commit()
    }
}
