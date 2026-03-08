//
//  MPInsuranceControl.swift
//  hardway-craps
//
//  Multi-player insurance control bar. Shows a shield icon + "Insurance" title on the left,
//  and overlapping MPSmallBetChip instances on the right for each player who opts in.
//

import UIKit

final class MPInsuranceControl: UIView {

    private struct LayoutConstants {
        static let chipOverlapSpacing: CGFloat = -8
        static let cornerRadius: CGFloat = 14
        static let iconSize: CGFloat = 22
        static let chipTrailingPadding: CGFloat = 12
        static let titleLeadingPadding: CGFloat = 14
    }

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iv.image = UIImage(systemName: "shield.pattern.checkered", withConfiguration: config)
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Insurance"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = HardwayColors.label
        return label
    }()

    private let chipsStackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.alignment = .center
        sv.distribution = .fill
        sv.spacing = LayoutConstants.chipOverlapSpacing
        return sv
    }()

    private var chips: [(style: MPSmallBetChipStyle, chip: MPSmallBetChip)] = []

    var chipCount: Int { chips.count }

    var onTapped: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = HardwayColors.surfaceGray
        layer.cornerRadius = LayoutConstants.cornerRadius
        clipsToBounds = false
        isHidden = true

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(chipsStackView)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.titleLeadingPadding),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: LayoutConstants.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: LayoutConstants.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            chipsStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LayoutConstants.chipTrailingPadding),
            chipsStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chipsStackView.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.transform = .identity
            }
        }
        HapticsHelper.lightHaptic()
        onTapped?()
    }

    // MARK: - Public API

    func addInsuranceBet(amount: Int, chipStyle: MPSmallBetChipStyle, animated: Bool = true) {
        if let existing = chips.first(where: { $0.style == chipStyle }) {
            existing.chip.addToBet(amount)
            if animated {
                animateChipBounce(existing.chip)
                existing.chip.playChipShimmer()
            }
            return
        }

        let chip = MPSmallBetChip(style: chipStyle)
        chip.isHidden = false
        chip.amount = amount
        chip.layer.zPosition = CGFloat(chips.count)

        chipsStackView.addArrangedSubview(chip)
        chips.append((style: chipStyle, chip: chip))

        if animated {
            chip.alpha = 0
            chip.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            UIView.animate(withDuration: 0.12, delay: 0, options: .curveEaseOut) {
                chip.alpha = 1
                chip.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            } completion: { _ in
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.6, options: .curveEaseInOut) {
                    chip.transform = .identity
                } completion: { _ in
                    chip.playChipShimmer()
                }
            }
            playControlPulse()
        }
    }

    func removeInsuranceBet(for chipStyle: MPSmallBetChipStyle, animated: Bool = true) {
        guard let index = chips.firstIndex(where: { $0.style == chipStyle }) else { return }
        let chip = chips[index].chip
        chips.remove(at: index)

        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
                chip.alpha = 0
                chip.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            } completion: { _ in
                chip.removeFromSuperview()
            }
        } else {
            chip.removeFromSuperview()
        }
    }

    func insuranceBetAmount(for chipStyle: MPSmallBetChipStyle) -> Int {
        chips.first(where: { $0.style == chipStyle })?.chip.amount ?? 0
    }

    func clearAllBets(animated: Bool = false) {
        if animated {
            let chipsToRemove = chips
            chips.removeAll()
            for (_, chip) in chipsToRemove {
                UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
                    chip.alpha = 0
                    chip.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                } completion: { _ in
                    chip.removeFromSuperview()
                }
            }
        } else {
            for (_, chip) in chips {
                chip.removeFromSuperview()
            }
            chips.removeAll()
        }
    }

    func animateChipsAway(completion: (() -> Void)? = nil) {
        guard !chips.isEmpty else {
            completion?()
            return
        }
        let chipsToAnimate = chips
        chips.removeAll()

        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseIn) {
            for (_, chip) in chipsToAnimate {
                chip.alpha = 0
                chip.transform = CGAffineTransform(translationX: 0, y: -40).scaledBy(x: 0.3, y: 0.3)
            }
        } completion: { _ in
            for (_, chip) in chipsToAnimate {
                chip.removeFromSuperview()
            }
            completion?()
        }
    }

    /// Animate a small dot from an origin point to this control's chip area, then call onArrival.
    func animateDotToChips(from origin: CGPoint, in containerView: UIView, dotColor: UIColor, onArrival: @escaping () -> Void) {
        let dotSize: CGFloat = 8
        let dot = UIView(frame: CGRect(x: 0, y: 0, width: dotSize, height: dotSize))
        dot.backgroundColor = dotColor
        dot.layer.cornerRadius = dotSize / 2
        dot.alpha = 0
        dot.layer.shadowColor = UIColor.black.cgColor
        dot.layer.shadowOpacity = 0.3
        dot.layer.shadowRadius = 2
        dot.layer.shadowOffset = CGSize(width: 0, height: 1)

        containerView.addSubview(dot)
        containerView.bringSubviewToFront(dot)
        dot.center = origin

        let destination = containerView.convert(
            CGPoint(x: chipsStackView.frame.midX, y: chipsStackView.frame.midY),
            from: self
        )

        let animator = UIViewPropertyAnimator(
            duration: 0.3,
            controlPoint1: CGPoint(x: 0.25, y: 0.1),
            controlPoint2: CGPoint(x: 0.25, y: 1.0)
        ) {
            dot.center = destination
            dot.alpha = 1.0
            dot.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }

        let updateDelay = 0.3 * 0.95
        DispatchQueue.main.asyncAfter(deadline: .now() + updateDelay) {
            onArrival()
        }

        animator.addCompletion { position in
            dot.removeFromSuperview()
        }
        animator.startAnimation()
    }

    /// Subtle pulse on the entire control when a new bet chip appears.
    func playControlPulse() {
        let original = transform
        UIView.animate(withDuration: 0.08, delay: 0, options: .curveEaseOut) {
            self.transform = original.scaledBy(x: 1.02, y: 1.02)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.4, options: .curveEaseInOut) {
                self.transform = original
            }
        }
    }

    /// Celebratory animation on all chips when insurance pays out.
    /// Chips scale up with a spring, each gets a shimmer, then calls completion.
    func playWinAnimation(completion: (() -> Void)? = nil) {
        guard !chips.isEmpty else {
            completion?()
            return
        }

        for (i, entry) in chips.enumerated() {
            let chip = entry.chip
            let delay = Double(i) * 0.08
            UIView.animate(withDuration: 0.15, delay: delay, options: .curveEaseOut) {
                chip.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
            } completion: { _ in
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.6, options: .curveEaseInOut) {
                    chip.transform = .identity
                } completion: { _ in
                    chip.playChipShimmer()
                }
            }
        }

        let totalDuration = Double(chips.count) * 0.08 + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            completion?()
        }
    }

    func updateTitle(_ text: String) {
        titleLabel.text = text
    }

    /// Returns the center point (in the given coordinate space) for each chip, keyed by style.
    func chipPositions(in coordinateView: UIView) -> [(style: MPSmallBetChipStyle, center: CGPoint)] {
        chips.map { entry in
            let center = coordinateView.convert(entry.chip.center, from: chipsStackView)
            return (style: entry.style, center: center)
        }
    }

    // MARK: - Private

    private func animateChipBounce(_ chip: MPSmallBetChip) {
        let original = chip.transform
        UIView.animate(withDuration: 0.08, delay: 0, options: .curveEaseOut) {
            chip.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                chip.transform = original
            }
        }
    }
}
