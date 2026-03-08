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
    func hasLockedBet() -> Bool {
        return false
    }
    
    func animateBetViewSlideLeftForOdds() {
        //
    }
    
    func restoreBetViewPosition() {
        //
    }
    

    weak var delegate: ChipSelectorDelegate?
    var onBetReturned: ((Int) -> Void)?  // Callback when bet is returned to balance

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.distribution = .fill  // Fill available space
        sv.alignment = .center
        sv.spacing = -22  // Negative spacing creates overlap (increased for more overlap)
        sv.clipsToBounds = false  // Allow chips to extend beyond bounds when overlapping
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

    private var chipControls: [ProgrammaticChipView] = []
    private(set) var selectedValue: Int = 5
    private var indicatorCenterXConstraint: NSLayoutConstraint?
    private var hasInitializedIndicator = false

    private(set) var chipValues: [Int]
    let chipSize: CGFloat

    init(chipValues: [Int] = [1, 5, 25, 50, 100], chipSize: CGFloat = 60) {
        self.chipValues = chipValues
        self.chipSize = chipSize
        super.init(frame: .zero)
        setupView()
    }
    
    /// Creates a compact ChipSelector that removes the smallest and largest chips,
    /// leaving only the middle 3 chips.
    convenience init(compact chipValues: [Int] = [1, 5, 25, 50, 100], chipSize: CGFloat = 60) {
        guard chipValues.count >= 3 else {
            // If less than 3 chips, use all of them
            self.init(chipValues: chipValues, chipSize: chipSize)
            return
        }
        
        // Remove smallest and largest, keep the middle chips
        let sortedValues = chipValues.sorted()
        let compactValues = Array(sortedValues.dropFirst().dropLast())
        self.init(chipValues: compactValues, chipSize: chipSize)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        clipsToBounds = false  // Allow chips to extend beyond bounds when overlapping
        addSubview(selectionIndicator)
        addSubview(stackView)
        
        // Prevent compression - resist being compressed below our minimum size
        setContentCompressionResistancePriority(.required, for: .horizontal)

        indicatorCenterXConstraint = selectionIndicator.centerXAnchor.constraint(equalTo: leadingAnchor)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
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
        let colorSet = ChipColorSet.current
        for (index, value) in chipValues.enumerated() {
            let chip = ProgrammaticChipView(value: value, size: chipSize, colorSet: colorSet)
            chip.tag = index
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            
            // Prevent chips from stretching - maintain their fixed size
            chip.setContentHuggingPriority(.required, for: .horizontal)
            chip.setContentHuggingPriority(.required, for: .vertical)
            chip.setContentCompressionResistancePriority(.required, for: .horizontal)
            chip.setContentCompressionResistancePriority(.required, for: .vertical)
            
            // Set z-position so earlier chips (like $1) appear on top and cast shadows on later ones
            // Reverse the order: first chip gets highest zPosition
            chip.layer.zPosition = CGFloat(chipValues.count - 1 - index)

            chipControls.append(chip)
            stackView.addArrangedSubview(chip)
        }
    }

    override var intrinsicContentSize: CGSize {
        // Calculate the width based on chip size and overlap
        // Formula: (chipSize * numberOfChips) - (overlap * (numberOfChips - 1))
        let numberOfChips = CGFloat(chipValues.count)
        let overlap: CGFloat = 22  // Matches the negative spacing
        let width = (chipSize * numberOfChips) - (overlap * (numberOfChips - 1))
        let height = chipSize + 13  // chipSize + indicator spacing
        return CGSize(width: width, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Update indicator position whenever layout changes (including rotation)
        if hasInitializedIndicator {
            // Already initialized - just update position for current layout
            if let index = chipControls.firstIndex(where: { $0.value == selectedValue }) {
                moveIndicatorToChip(at: index, animated: false)
            }
        } else {
            // First time - try to initialize
            tryInitializeIndicator()
        }
    }
    
    private func tryInitializeIndicator() {
        guard !hasInitializedIndicator, !chipControls.isEmpty else { return }
        
        guard let index = chipControls.firstIndex(where: { $0.value == selectedValue }) else { return }
        
        let targetChip = chipControls[index]
        
        // Check if chip has valid frame
        guard targetChip.frame.width > 0 && targetChip.frame.height > 0 else {
            // Frames not ready yet, will retry on next layout
            return
        }
        
        // Frames are ready, initialize indicator
        hasInitializedIndicator = true
        moveIndicatorToChip(at: index, animated: false)
    }
    
    /// Call this method after the view has been added to the hierarchy and laid out
    func initializeIndicatorPosition() {
        // Force layout first to ensure frames are calculated
        layoutIfNeeded()
        
        // Try to initialize immediately
        tryInitializeIndicator()
        
        // If still not initialized (frames not ready), defer and try again
        if !hasInitializedIndicator {
            DispatchQueue.main.async { [weak self] in
                self?.tryInitializeIndicator()
            }
        }
    }

    private func moveIndicatorToChip(at index: Int, animated: Bool) {
        guard index < chipControls.count, let constraint = indicatorCenterXConstraint else { return }

        let targetChip = chipControls[index]
        
        // Ensure chip has a valid frame before positioning indicator
        guard targetChip.frame.width > 0 && targetChip.frame.height > 0 else { return }

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

    @objc private func chipTapped(_ sender: ProgrammaticChipView) {
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

    func selectedChipCenter(in coordinateSpace: UIView) -> CGPoint {
        guard let chip = chipControls.first(where: { $0.value == selectedValue }) else {
            return convert(center, to: coordinateSpace)
        }
        let chipCenter = CGPoint(x: chip.frame.midX, y: chip.frame.midY)
        return stackView.convert(chipCenter, to: coordinateSpace)
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

    /// Single call-site for balance changes. Updates chip availability and transitions
    /// the chip set when balance crosses the $2K threshold.
    func updateBalance(_ balance: Int) {
        updateAvailableChips(balance: balance)

        let newValues = balance >= 2000 ? [5, 25, 50, 100, 500] : [1, 5, 25, 50, 100]
        transitionToChipValues(newValues, animated: true)
    }

    // MARK: - Chip Set Transitions

    /// Replaces the displayed chip set, preserving the current selection where possible.
    /// When a brand-new chip denomination appears on the right (the "unlocked" case),
    /// a shimmer sweeps across it to draw the user's attention.
    func transitionToChipValues(_ newValues: [Int], animated: Bool) {
        guard newValues != chipValues else { return }

        // Determine if a new chip is being introduced on the right end
        let newChipValue: Int? = {
            guard animated else { return nil }
            let addedValues = Set(newValues).subtracting(Set(chipValues))
            return addedValues.count == 1 ? addedValues.first : nil
        }()

        swapChips(to: newValues)

        if let newValue = newChipValue,
           let chip = chipControls.first(where: { $0.value == newValue }) {
            // Ensure chip is laid out before playing shimmer
            chip.layoutIfNeeded()
            chip.playShimmer()
        }
    }


    /// Update the chip color set for all chips in the selector
    func updateColorSet(_ colorSet: ChipColorSet) {
        print("🎨 [ChipSelector] updateColorSet called with color: '\(colorSet.name)', chipControls count: \(chipControls.count)")
        // Update UserDefaults so ChipColorSet.current reflects the new color
        UserDefaults.standard.set(colorSet.name, forKey: "ChipColorSetName")
        
        // Update all existing chips with the new color set
        for chip in chipControls {
            colorSet.apply(to: chip)
        }
        
        // Update selection indicator color if needed
        selectionIndicator.backgroundColor = colorSet.textColor
        print("   ✅ Applied color set to \(chipControls.count) chips")
    }

    // MARK: In-place chip swap (no animation)

    private func swapChips(to newValues: [Int]) {
        // Preserve the current selection if the value still exists in the new set
        let preservedSelection = newValues.contains(selectedValue) ? selectedValue : nil

        chipValues = newValues

        // Remove existing chips
        chipControls.forEach { $0.removeFromSuperview() }
        chipControls = []
        stackView.arrangedSubviews.forEach { stackView.removeArrangedSubview($0); $0.removeFromSuperview() }

        let colorSet = ChipColorSet.current
        for (index, value) in newValues.enumerated() {
            let chip = ProgrammaticChipView(value: value, size: chipSize, colorSet: colorSet)
            chip.tag = index
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chip.setContentHuggingPriority(.required, for: .horizontal)
            chip.setContentHuggingPriority(.required, for: .vertical)
            chip.setContentCompressionResistancePriority(.required, for: .horizontal)
            chip.setContentCompressionResistancePriority(.required, for: .vertical)
            chip.layer.zPosition = CGFloat(newValues.count - 1 - index)
            chipControls.append(chip)
            stackView.addArrangedSubview(chip)
        }

        hasInitializedIndicator = false
        if let value = preservedSelection {
            selectedValue = value
        } else if let first = chipControls.first {
            // Previously selected value no longer exists; fall back to the first chip
            selectedValue = first.value
        }
        initializeIndicatorPosition()
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
