//
//  MPBonusBetControl.swift
//  hardway-craps
//
//  Single-bet multiplayer bonus bet control. Modeled on MPInsuranceControl:
//  title + description on the left, overlapping MPSmallBetChip per player on the right.
//  Tap to place, drag local chip to remove.
//

import UIKit

final class MPBonusBetControl: UIView {

    private struct LayoutConstants {
        static let chipOverlapSpacing: CGFloat = -8
        static let cornerRadius: CGFloat = 18
        static let chipTrailingPadding: CGFloat = 12
        static let titleLeadingPadding: CGFloat = 14
        static let dragYOffset: CGFloat = -30
    }

    // MARK: - Subviews

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = HardwayColors.label
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .regular)
        label.textColor = HardwayColors.label.withAlphaComponent(0.7)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let labelStack: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.alignment = .leading
        sv.distribution = .fill
        sv.spacing = 2
        return sv
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

    // MARK: - Data

    private var chips: [(style: MPSmallBetChipStyle, chip: MPSmallBetChip)] = []

    var chipCount: Int { chips.count }

    /// Tap callback — VC uses this to place the local player's bet.
    var onTapped: (() -> Void)?

    /// Called when the local player drags their chip off the control to remove their bet.
    var onBetDragRemoved: ((_ amount: Int) -> Void)?

    /// The local player's chip style, so the control knows which chip is draggable.
    var localChipStyle: MPSmallBetChipStyle?

    // Drag state
    private var dragChipSnapshot: UIView?
    private var dragOriginalCenter: CGPoint = .zero
    private var isDragging = false

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
        layer.borderWidth = 1.5
        layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
        clipsToBounds = false
        isHidden = false

        labelStack.addArrangedSubview(titleLabel)
        labelStack.addArrangedSubview(descriptionLabel)

        addSubview(labelStack)
        addSubview(chipsStackView)

        NSLayoutConstraint.activate([
            labelStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.titleLeadingPadding),
            labelStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelStack.trailingAnchor.constraint(lessThanOrEqualTo: chipsStackView.leadingAnchor, constant: -12),

            chipsStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LayoutConstants.chipTrailingPadding),
            chipsStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chipsStackView.leadingAnchor.constraint(greaterThanOrEqualTo: labelStack.trailingAnchor, constant: 12),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    // MARK: - Configuration

    func configure(title: String, description: String) {
        titleLabel.text = title
        descriptionLabel.text = description
        descriptionLabel.isHidden = description.isEmpty
    }

    // MARK: - Tap

    @objc private func handleTap() {
        HapticsHelper.lightHaptic()
        onTapped?()
    }

    // MARK: - Drag to remove

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let localStyle = localChipStyle,
              let entry = chips.first(where: { $0.style == localStyle }) else { return }
        let chip = entry.chip

        switch gesture.state {
        case .began:
            let touchInChips = gesture.location(in: chipsStackView)
            let chipFrame = chip.frame
            let hitArea = chipFrame.insetBy(dx: -10, dy: -10)
            guard hitArea.contains(touchInChips) else { return }

            isDragging = true
            dragOriginalCenter = chip.convert(CGPoint(x: chip.bounds.midX, y: chip.bounds.midY), to: superview ?? self)

            let snapshot = chip.snapshotView(afterScreenUpdates: false) ?? UIView()
            snapshot.frame = chip.convert(chip.bounds, to: superview ?? self)
            snapshot.layer.cornerRadius = chip.layer.cornerRadius
            snapshot.layer.shadowColor = UIColor.black.cgColor
            snapshot.layer.shadowOpacity = 0.3
            snapshot.layer.shadowRadius = 4
            snapshot.layer.shadowOffset = CGSize(width: 0, height: 2)
            (superview ?? self).addSubview(snapshot)
            dragChipSnapshot = snapshot

            chip.alpha = 0.3
            UIView.animate(withDuration: 0.15) {
                snapshot.center.y += LayoutConstants.dragYOffset
                snapshot.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            }

        case .changed:
            guard isDragging, let snapshot = dragChipSnapshot else { return }
            let translation = gesture.translation(in: superview ?? self)
            snapshot.center = CGPoint(x: dragOriginalCenter.x + translation.x,
                                     y: dragOriginalCenter.y + translation.y + LayoutConstants.dragYOffset)

        case .ended, .cancelled:
            guard isDragging else { return }
            isDragging = false

            guard let snapshot = dragChipSnapshot else { return }
            let snapshotCenter = snapshot.center
            let controlFrame = (superview ?? self).convert(bounds, from: self)
            let isOutside = !controlFrame.contains(snapshotCenter)

            if isOutside, let entry = chips.first(where: { $0.style == localStyle }) {
                let amount = entry.chip.amount
                UIView.animate(withDuration: 0.25, animations: {
                    snapshot.alpha = 0
                    snapshot.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                }) { _ in
                    snapshot.removeFromSuperview()
                }
                removeBet(for: localStyle)
                onBetDragRemoved?(amount)
            } else {
                if let entry = chips.first(where: { $0.style == localStyle }) {
                    entry.chip.alpha = 1
                }
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8, options: .curveEaseOut, animations: {
                    snapshot.center = self.dragOriginalCenter
                    snapshot.transform = .identity
                }) { _ in
                    snapshot.removeFromSuperview()
                }
            }
            dragChipSnapshot = nil

        default:
            break
        }
    }

    // MARK: - Public API

    func addBet(amount: Int, chipStyle: MPSmallBetChipStyle, animated: Bool = true) {
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
            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                chip.alpha = 1
                chip.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            } completion: { _ in
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
                    chip.transform = .identity
                } completion: { _ in
                    chip.playChipShimmer()
                }
            }
            playControlPulse()
        }
    }

    /// Set the total bet amount for a chip style (used for remote sync).
    func setBetAmount(amount: Int, chipStyle: MPSmallBetChipStyle, animated: Bool = true) {
        if let existing = chips.first(where: { $0.style == chipStyle }) {
            if amount == 0 {
                removeBet(for: chipStyle, animated: animated)
            } else {
                existing.chip.amount = amount
                if animated {
                    animateChipBounce(existing.chip)
                    existing.chip.playChipShimmer()
                }
            }
            return
        }
        if amount > 0 {
            addBet(amount: amount, chipStyle: chipStyle, animated: animated)
        }
    }

    func removeBet(for chipStyle: MPSmallBetChipStyle, animated: Bool = true) {
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

    func betAmount(for chipStyle: MPSmallBetChipStyle) -> Int {
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

    /// Animate a dot from an origin point to the matching chip, then call onArrival.
    /// If chipStyle is provided, the dot targets that specific chip's position.
    /// If the chip doesn't exist yet, targets where it will appear at the trailing edge of the stack.
    func animateDotToChips(from origin: CGPoint, in containerView: UIView, dotColor: UIColor, chipStyle: MPSmallBetChipStyle? = nil, onArrival: @escaping () -> Void) {
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

        let destination: CGPoint
        if let style = chipStyle,
           let existing = chips.first(where: { $0.style == style }) {
            destination = containerView.convert(existing.chip.center, from: chipsStackView)
        } else {
            destination = containerView.convert(
                CGPoint(x: chipsStackView.frame.midX, y: chipsStackView.frame.midY),
                from: self
            )
        }

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

        animator.addCompletion { _ in
            dot.removeFromSuperview()
        }
        animator.startAnimation()
    }

    func playControlPulse() {
        let original = transform
        UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = original.scaledBy(x: 1.02, y: 1.02)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.4, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.transform = original
            }
        }
    }

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

    /// Hide or show the chip for a given style (used to hide the original while an animation chip is in flight).
    func setChipHidden(_ hidden: Bool, for chipStyle: MPSmallBetChipStyle) {
        guard let entry = chips.first(where: { $0.style == chipStyle }) else { return }
        entry.chip.alpha = hidden ? 0 : 1
    }

    func chipPositions(in coordinateView: UIView) -> [(style: MPSmallBetChipStyle, center: CGPoint)] {
        chips.map { entry in
            let center = coordinateView.convert(entry.chip.center, from: chipsStackView)
            return (style: entry.style, center: center)
        }
    }

    func chipsCenter(in coordinateView: UIView) -> CGPoint {
        return convert(
            CGPoint(x: chipsStackView.frame.midX, y: chipsStackView.frame.midY),
            to: coordinateView
        )
    }

    // MARK: - Private

    private func animateChipBounce(_ chip: MPSmallBetChip) {
        // Match PlainControl animation: scale to 1.15x then spring back
        let original = chip.transform
        UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            chip.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
                chip.transform = original
            }
        }
    }
}
