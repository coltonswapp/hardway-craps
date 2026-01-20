//
//  ChipSelector.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

protocol ChipSelectorDelegate: AnyObject {
    func chipSelector(_ selector: ChipSelector, didSelectChipWithValue value: Int)
}

class ChipSelector: UIView, BetDropTarget {

    weak var delegate: ChipSelectorDelegate?
    var onBetReturned: ((Int) -> Void)?  // Callback when bet is returned to balance

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.distribution = .fill
        sv.alignment = .center
        sv.spacing = -20  // Negative spacing creates overlap (increased for more overlap)
        return sv
    }()

    private let selectionIndicator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = HardwayColors.yellow
        view.layer.cornerRadius = 2.5
        view.alpha = 0
        return view
    }()

    private var chipControls: [ChipControl] = []
    private(set) var selectedValue: Int = 1
    private var indicatorCenterXConstraint: NSLayoutConstraint?

    let chipValues: [Int]

    init(chipValues: [Int] = [1, 5, 25, 50, 100]) {
        self.chipValues = chipValues
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(selectionIndicator)
        addSubview(stackView)
        
        // Prevent compression - resist being compressed below our minimum size
        setContentCompressionResistancePriority(.required, for: .horizontal)

        indicatorCenterXConstraint = selectionIndicator.centerXAnchor.constraint(equalTo: leadingAnchor)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            // Remove trailing constraint to let chips overlap naturally
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),

            selectionIndicator.widthAnchor.constraint(equalToConstant: 5),
            selectionIndicator.heightAnchor.constraint(equalToConstant: 5),
            selectionIndicator.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 4),
            indicatorCenterXConstraint!
        ])

        setupChips()
        BetDragManager.shared.registerDropTarget(self)
    }
    
    deinit {
        BetDragManager.shared.unregisterDropTarget(self)
    }

    private func setupChips() {
        for (index, value) in chipValues.enumerated() {
            let chip = ChipControl(value: value)
            chip.tag = index
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            
            // Set z-position so earlier chips (like $1) appear on top and cast shadows on later ones
            // Reverse the order: first chip gets highest zPosition
            chip.layer.zPosition = CGFloat(chipValues.count - 1 - index)

            chipControls.append(chip)
            stackView.addArrangedSubview(chip)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }

    private func moveIndicatorToChip(at index: Int, animated: Bool) {
        guard index < chipControls.count, let constraint = indicatorCenterXConstraint else { return }

        let targetChip = chipControls[index]

        // Convert the chip's center to the selector's coordinate system
        let chipCenterInStackView = CGPoint(x: targetChip.frame.midX, y: targetChip.frame.midY)
        let chipCenterInSelectorView = stackView.convert(chipCenterInStackView, to: self)

        constraint.constant = chipCenterInSelectorView.x

        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                self.selectionIndicator.alpha = 1
                self.layoutIfNeeded()
            }
        } else {
            selectionIndicator.alpha = 1
            layoutIfNeeded()
        }
    }

    @objc private func chipTapped(_ sender: ChipControl) {
        guard let index = chipControls.firstIndex(where: { $0 === sender }) else { return }

        selectedValue = sender.value
        moveIndicatorToChip(at: index, animated: true)
        HapticsHelper.lightHaptic()
        delegate?.chipSelector(self, didSelectChipWithValue: sender.value)
    }

    func selectChip(withValue value: Int, animated: Bool = true) {
        guard let index = chipControls.firstIndex(where: { $0.value == value }) else { return }
        selectedValue = value
        moveIndicatorToChip(at: index, animated: animated)
    }

    func updateAvailableChips(balance: Int) {
        for chip in chipControls {
            if chip.value > balance {
                chip.alpha = 0.3
                chip.isUserInteractionEnabled = false
            } else {
                chip.alpha = 1.0
                chip.isUserInteractionEnabled = true
            }
        }
        
        // If current selected chip is no longer available, auto-select highest available chip
        if selectedValue > balance {
            // Find the highest available chip value
            let availableChips = chipControls.filter { $0.value <= balance }
            if let highestAvailableChip = availableChips.max(by: { $0.value < $1.value }) {
                selectChip(withValue: highestAvailableChip.value, animated: true)
                delegate?.chipSelector(self, didSelectChipWithValue: highestAvailableChip.value)
            }
        }
    }
    
    // MARK: - BetDropTarget
    
    func addBet(_ amount: Int) {
        // Not used for ChipSelector - we return bets to balance instead
    }
    
    func addBetWithAnimation(_ amount: Int) {
        // When a bet is dropped on ChipSelector, return it to balance
        onBetReturned?(amount)
    }
    
    func removeBet(_ amount: Int) {
        // Not used for ChipSelector
    }
    
    func highlightAsDropTarget() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            self.alpha = 0.8
        }
        HapticsHelper.superLightHaptic()
    }
    
    func unhighlightAsDropTarget() {
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.transform = .identity
            self.alpha = 1.0
        }
    }
    
    func frameInView(_ view: UIView) -> CGRect {
        guard let superview = superview else { return .zero }
        return superview.convert(frame, to: view)
    }
    
    func getBetViewPosition(in view: UIView) -> CGPoint {
        // Return center of ChipSelector as the drop position
        guard let superview = superview else { return .zero }
        return superview.convert(center, to: view)
    }
}
