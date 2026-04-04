//
//  CrapsGameplayViewController+Layout.swift
//  hardway-craps
//
//  Created for iPad layout adaptation
//

import UIKit

// MARK: - Layout Mode

enum LayoutMode: Int {
  case iPhonePortrait = 0
  case iPadPortrait = 1
  case iPadLandscape = 2
}

// MARK: - Layout Extension

extension CrapsGameplayViewController {

  // MARK: - Layout Mode Detection

  var currentLayoutMode: LayoutMode {
    guard UIDevice.current.userInterfaceIdiom == .pad else {
      return .iPhonePortrait
    }
    let isLandscape = view.bounds.width > view.bounds.height
    return isLandscape ? .iPadLandscape : .iPadPortrait
  }

  // MARK: - Persistent Container Views (created once, reused across rotations)

  /// Left container for iPad landscape (holds gameContainerView)
  private var landscapeLeftContainer: UIView {
    if let existing = objc_getAssociatedObject(self, &AssociatedKeys.landscapeLeftContainer)
      as? UIView
    {
      return existing
    }
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    objc_setAssociatedObject(
      self, &AssociatedKeys.landscapeLeftContainer, container, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return container
  }

  /// Right container for iPad landscape (bonus bets)
  private var landscapeRightContainer: UIView {
    if let existing = objc_getAssociatedObject(self, &AssociatedKeys.landscapeRightContainer)
      as? UIView
    {
      return existing
    }
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    objc_setAssociatedObject(
      self, &AssociatedKeys.landscapeRightContainer, container, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return container
  }

  // MARK: - Constraint Storage (cached safely since containers persist)

  private var iPhoneConstraints: [NSLayoutConstraint] {
    get {
      objc_getAssociatedObject(self, &AssociatedKeys.iPhoneConstraints) as? [NSLayoutConstraint]
        ?? []
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.iPhoneConstraints, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  private var iPadPortraitConstraints: [NSLayoutConstraint] {
    get {
      objc_getAssociatedObject(self, &AssociatedKeys.iPadPortraitConstraints)
        as? [NSLayoutConstraint] ?? []
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.iPadPortraitConstraints, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  private var iPadLandscapeConstraints: [NSLayoutConstraint] {
    get {
      objc_getAssociatedObject(self, &AssociatedKeys.iPadLandscapeConstraints)
        as? [NSLayoutConstraint] ?? []
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.iPadLandscapeConstraints, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
      )
    }
  }

  private var currentActiveConstraints: [NSLayoutConstraint] {
    get {
      objc_getAssociatedObject(self, &AssociatedKeys.currentActiveConstraints)
        as? [NSLayoutConstraint] ?? []
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.currentActiveConstraints, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
      )
    }
  }

  private var previousLayoutMode: LayoutMode? {
    get {
      if let rawValue = objc_getAssociatedObject(self, &AssociatedKeys.previousLayoutMode) as? Int {
        return LayoutMode(rawValue: rawValue)
      }
      return nil
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.previousLayoutMode, newValue?.rawValue,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  private var iPadContainersCreated: Bool {
    get { objc_getAssociatedObject(self, &AssociatedKeys.iPadContainersCreated) as? Bool ?? false }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.iPadContainersCreated, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  // MARK: - One-time iPad Container Setup

  /// Creates all persistent container views for iPad layouts. Called once.
  private func ensureIPadContainersExist() {
    guard !iPadContainersCreated else { return }
    iPadContainersCreated = true

    // Add containers to the main view (they'll be hidden/shown via isHidden)
    view.addSubview(landscapeLeftContainer)
    view.addSubview(landscapeRightContainer)

    // Start all hidden
    landscapeLeftContainer.isHidden = true
    landscapeRightContainer.isHidden = true
  }

  // MARK: - Apply Layout

  func applyLayout(for mode: LayoutMode) {
    // Ensure containers exist (no-op after first call)
    if UIDevice.current.userInterfaceIdiom == .pad {
      ensureIPadContainersExist()
    }

    // Deactivate current constraints
    NSLayoutConstraint.deactivate(currentActiveConstraints)
    currentActiveConstraints = []

    // Show/hide containers based on mode BEFORE reparenting and constraining
    // This ensures they're in the correct state when constraints are activated
    if UIDevice.current.userInterfaceIdiom == .pad {
      landscapeLeftContainer.isHidden = (mode != .iPadLandscape)
      landscapeRightContainer.isHidden = (mode != .iPadLandscape)
    }

    // Move controls to correct parents for the new mode
    reparentControls(for: mode)

    // Configure scroll view direction and page control visibility
    configureScrollViewForMode(mode)
    // Page control hidden only in iPad portrait (no scrolling there)

    // Build constraints — iPhone can be cached since it's stable;
    // iPad constraints are rebuilt each time because rebuildBetViews
    // dynamically restructures the view hierarchy.
    var newConstraints: [NSLayoutConstraint] = []

    switch mode {
    case .iPhonePortrait:
      if iPhoneConstraints.isEmpty {
        iPhoneConstraints = buildIPhoneConstraints()
      }
      newConstraints = iPhoneConstraints

    case .iPadPortrait:
      iPadPortraitConstraints = buildIPadPortraitConstraints()
      newConstraints = iPadPortraitConstraints

    case .iPadLandscape:
      iPadLandscapeConstraints = buildIPadLandscapeConstraints()
      newConstraints = iPadLandscapeConstraints
    }

    // Update control heights & spacing inside gameContainerView for this mode
    updateGameContainerHeights(for: mode)

    // Tighter spacing between balance and chip selector on iPad landscape (less vertical room)
    let balanceChipSpacing: CGFloat = (mode == .iPadLandscape) ? 2 : 4
    bottomBar.setBalanceChipSpacing(balanceChipSpacing)

    print("🎯 applyLayout(\(mode)): Activating \(newConstraints.count) constraints")
    NSLayoutConstraint.activate(newConstraints)
    currentActiveConstraints = newConstraints

    // Adjust z-order for the layout mode
    updateZOrder(for: mode)

    // Force layout update to ensure frames are calculated
    view.setNeedsLayout()
    view.layoutIfNeeded()

    // Only rebuild bet views if layout mode actually changed
    let layoutModeChanged = previousLayoutMode != mode
    if layoutModeChanged {
      rebuildBetViews(for: mode)
      previousLayoutMode = mode
    }

    // Control widths are now handled internally by gameContainerView

    // DEBUG: Print constraint info after activation
    if mode == .iPadLandscape {
      print("🎯 LANDSCAPE DEBUG:")
      print("  topBar frame: \(topStackView.frame)")
      print("  topBar bounds: \(topStackView.bounds)")
      print("  landscapeLeftContainer frame: \(landscapeLeftContainer.frame)")
      print("  landscapeLeftContainer bounds: \(landscapeLeftContainer.bounds)")
      print("  landscapeLeftContainer.isHidden: \(landscapeLeftContainer.isHidden)")
      print("  gameContainerView frame: \(gameContainerView.frame)")
      print("  gameContainerView bounds: \(gameContainerView.bounds)")
      print("  gameContainerView superview: \(String(describing: gameContainerView.superview))")
      print("  bottomBar frame: \(bottomStackView.frame)")
      print("  view.bounds: \(view.bounds)")
    }
    if let gameContainer = gameContainerView {
      print("🎯 After applyLayout - gameContainerView frame: \(gameContainer.frame)")
      print("🎯 After applyLayout - pointStack frame: \(pointStack.frame)")
    }
  }

  // MARK: - Z-Order Management

  /// Adjusts the z-order of views based on layout mode to prevent blocking interactions
  private func updateZOrder(for mode: LayoutMode) {
    switch mode {
    case .iPhonePortrait, .iPadPortrait:
      // Default z-order: dice at back, bottomStack in middle, topStack on top
      view.bringSubviewToFront(flipDiceContainer)
      view.bringSubviewToFront(bottomStackView)
      view.bringSubviewToFront(topStackView)

    case .iPadLandscape:
      // Landscape z-order: dice should be on top of bottomStack to prevent blocking
      view.bringSubviewToFront(bottomStackView)
      view.bringSubviewToFront(flipDiceContainer)
      view.bringSubviewToFront(topStackView)
    }
  }

  // MARK: - Reparent Controls

  /// Moves containers to their correct parent views for the given layout mode.
  /// Individual controls stay inside gameContainerView - only the container moves.
  private func reparentControls(for mode: LayoutMode) {
    switch mode {
    case .iPhonePortrait:
      // Game container and bets container go directly into main view
      reparent(gameContainerView, to: view)
      reparent(betsContainerView, to: view)

    case .iPadPortrait:
      // Game container and bets container go in main view
      reparent(gameContainerView, to: view)
      reparent(betsContainerView, to: view)

    case .iPadLandscape:
      // Left container: game container
      reparent(gameContainerView, to: landscapeLeftContainer)

      // Right container: bonus bets
      reparent(betsContainerView, to: landscapeRightContainer)
    }
  }

  /// Moves a view to a new parent only if needed (avoids unnecessary remove/add cycles).
  private func reparent(_ child: UIView, to parent: UIView, asArranged: Bool = false) {
    if child.superview !== parent {
      child.removeFromSuperview()
      if asArranged, let stack = parent as? UIStackView {
        stack.addArrangedSubview(child)
      } else {
        parent.addSubview(child)
      }
    }
  }

  // MARK: - Scroll View Configuration

  private func configureScrollViewForMode(_ mode: LayoutMode) {
    guard let betsScrollView = betsScrollView else { return }
    // Hide scroll view only on iPad portrait (no scrolling)
    // Show scroll view on iPhone and iPad landscape (with scrolling)
    betsScrollView.isHidden = (mode == .iPadPortrait)
    betsScrollView.isPagingEnabled = true  // Enable paging for both iPhone and iPad landscape
  }

  // MARK: - Build iPhone Constraints

  private func buildIPhoneConstraints() -> [NSLayoutConstraint] {
    var constraints: [NSLayoutConstraint] = []

    // Top stack view
    constraints.append(contentsOf: [
      topStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      topStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      topStackTopConstraint,
      instructionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
      currentBetView.widthAnchor.constraint(equalToConstant: 100),
    ])

    // Bonus bets container - fixed height at top
    constraints.append(contentsOf: [
      betsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      betsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      betsContainerView.topAnchor.constraint(equalTo: topStackView.bottomAnchor, constant: 12),
      // Device-specific: iPhone needs 156pt (136pt scroll + 20pt pageControl), iPad needs 188pt
      betsContainerView.heightAnchor.constraint(
        equalToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 188 : 156),

      betsScrollView.leadingAnchor.constraint(equalTo: betsContainerView.leadingAnchor),
      betsScrollView.trailingAnchor.constraint(equalTo: betsContainerView.trailingAnchor),
      betsScrollView.topAnchor.constraint(equalTo: betsContainerView.topAnchor),
      betsScrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -8),
      // Device-specific: iPhone needs 136pt (16pt title + 12pt spacing + 2×50pt controls + 8pt spacing)
      // iPad needs 168pt (16pt title + 12pt spacing + 2×65pt controls + 8pt spacing)
      betsScrollView.heightAnchor.constraint(
        equalToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 168 : 136),

      pageControl.centerXAnchor.constraint(equalTo: betsContainerView.centerXAnchor),
      pageControl.bottomAnchor.constraint(equalTo: betsContainerView.bottomAnchor),
      pageControl.heightAnchor.constraint(equalToConstant: 20),

      scrollContentView.leadingAnchor.constraint(
        equalTo: betsScrollView.contentLayoutGuide.leadingAnchor),
      scrollContentView.trailingAnchor.constraint(
        equalTo: betsScrollView.contentLayoutGuide.trailingAnchor),
      scrollContentView.topAnchor.constraint(equalTo: betsScrollView.contentLayoutGuide.topAnchor),
      scrollContentView.bottomAnchor.constraint(
        equalTo: betsScrollView.contentLayoutGuide.bottomAnchor),
      scrollContentView.heightAnchor.constraint(equalTo: betsScrollView.heightAnchor),
    ])

    // Game container - spans full width below bonus bets, above bottom stack
    let gameContainerConstraints = [
      gameContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      gameContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      gameContainerView.topAnchor.constraint(equalTo: betsContainerView.bottomAnchor, constant: 12),
      gameContainerView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -18),
    ]
    constraints.append(contentsOf: gameContainerConstraints)
    print(
      "📐 iPhone: gameContainerView constraints - top: betsContainer.bottom+12, bottom: bottomStack.top-24"
    )

    // Bottom stack view - sized to content (60pt on iPhone, full height on iPad)
    let chipHeight: CGFloat =
      UIDevice.current.userInterfaceIdiom == .pad ? chipSelector.chipSize + 13 : 60
    constraints.append(contentsOf: [
      bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      bottomStackView.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
      chipSelector.heightAnchor.constraint(equalToConstant: chipHeight),
      // No width constraints - let bottomStack size naturally to its content
    ])

    // Dice container
    constraints.append(contentsOf: [
      flipDiceContainer.leadingAnchor.constraint(equalTo: bottomStackView.trailingAnchor, constant: 16),
      flipDiceContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      flipDiceContainer.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 0),
      flipDiceContainer.heightAnchor.constraint(equalToConstant: 80),
      flipDiceContainer.widthAnchor.constraint(
        equalTo: view.widthAnchor, multiplier: 0.4, constant: -16),
    ])

    return constraints
  }

  // MARK: - Build iPad Portrait Constraints

  private func buildIPadPortraitConstraints() -> [NSLayoutConstraint] {
    var constraints: [NSLayoutConstraint] = []

    // Top stack view
    constraints.append(contentsOf: [
      topStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      topStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      topStackTopConstraint,
      instructionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
      currentBetView.widthAnchor.constraint(equalToConstant: 100),
    ])

    // Bonus bets container - 2x2 grid, no scrolling (iPad portrait)
    // Container will size naturally to fit the grid content
    constraints.append(contentsOf: [
      betsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      betsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      betsContainerView.topAnchor.constraint(equalTo: topStackView.bottomAnchor, constant: 12),
      betsContainerView.bottomAnchor.constraint(
        lessThanOrEqualTo: gameContainerView.topAnchor, constant: -24),
    ])

    // Game container - spans full width below bonus bets, above bottom stack
    let gameContainerConstraints = [
      gameContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      gameContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      gameContainerView.topAnchor.constraint(equalTo: betsContainerView.bottomAnchor, constant: 24),
      gameContainerView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -18),
    ]
    constraints.append(contentsOf: gameContainerConstraints)
    print(
      "📐 iPad Portrait: gameContainerView constraints - top: betsContainer.bottom+50, bottom: bottomStack.top-24"
    )

    // Bottom stack view - sized to content
    let chipHeight: CGFloat = chipSelector.chipSize + 13
    constraints.append(contentsOf: [
      bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      bottomStackView.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
      chipSelector.heightAnchor.constraint(equalToConstant: chipHeight),
      // No width constraints - let bottomStack size naturally to its content
    ])

    // Dice container - centered on screen for iPad portrait
    let diceHeight: CGFloat = 100
    let diceWidth: CGFloat = 250
    constraints.append(contentsOf: [
      flipDiceContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      flipDiceContainer.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 0),
      flipDiceContainer.heightAnchor.constraint(equalToConstant: diceHeight),
      flipDiceContainer.widthAnchor.constraint(equalToConstant: diceWidth),
    ])

    return constraints
  }

  // MARK: - Build iPad Landscape Constraints

  private func buildIPadLandscapeConstraints() -> [NSLayoutConstraint] {
    var constraints: [NSLayoutConstraint] = []

    let leftC = landscapeLeftContainer
    let rightC = landscapeRightContainer

    // Top stack view - constrain height to prevent it from growing too tall in landscape
    constraints.append(contentsOf: [
      topStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      topStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      topStackTopConstraint,
      topStackView.heightAnchor.constraint(lessThanOrEqualToConstant: 60),  // Max height in landscape
      instructionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
      instructionLabel.heightAnchor.constraint(lessThanOrEqualToConstant: 60),  // Max height for instruction label
      currentBetView.widthAnchor.constraint(equalToConstant: 100),
    ])

    // Container layout: Both halves independently constrained to topStack and bottomStack
    // This ensures they don't affect each other's sizing
    constraints.append(contentsOf: [
      // Left container: 50% width, independent vertical constraints
      leftC.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      leftC.topAnchor.constraint(equalTo: topStackView.bottomAnchor, constant: 12),
      leftC.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -8),
      leftC.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),

      // Right container: 50% width, INDEPENDENT vertical constraints (not tied to leftC)
      rightC.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      rightC.topAnchor.constraint(equalTo: topStackView.bottomAnchor, constant: 12),  // Independent!
      rightC.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -8),  // Independent!
      rightC.leadingAnchor.constraint(equalTo: leftC.trailingAnchor),
      rightC.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
    ])

    // Left container: game container fills it completely
    let gameContainerConstraints = [
      gameContainerView.leadingAnchor.constraint(equalTo: leftC.leadingAnchor),
      gameContainerView.trailingAnchor.constraint(equalTo: leftC.trailingAnchor),
      gameContainerView.topAnchor.constraint(equalTo: leftC.topAnchor),
      gameContainerView.bottomAnchor.constraint(equalTo: leftC.bottomAnchor),
    ]
    constraints.append(contentsOf: gameContainerConstraints)
    print(
      "📐 iPad Landscape: gameContainerView constraints - fills landscapeLeftContainer completely")
    print("📐 landscapeLeftContainer: top=topStack.bottom+12, bottom=bottomStack.top-8, width=50%")
    print(
      "📐 landscapeRightContainer: top=topStack.bottom+12, bottom=bottomStack.top-8, width=50% (INDEPENDENT)"
    )

    // Right container: Bonus bets in single column (no scrolling, no actions)
    // Add padding to match the left side
    constraints.append(contentsOf: [
      betsContainerView.leadingAnchor.constraint(equalTo: rightC.leadingAnchor, constant: 8),
      betsContainerView.trailingAnchor.constraint(equalTo: rightC.trailingAnchor, constant: -16),
      betsContainerView.topAnchor.constraint(equalTo: rightC.topAnchor),
      betsContainerView.bottomAnchor.constraint(equalTo: rightC.bottomAnchor),
      // Column stack is constrained inside betsContainerView in rebuildBetViews
    ])

    // Dice container: centered, bottom edge - slightly scaled up for iPad
    let diceHeight: CGFloat = 100
    let diceWidth: CGFloat = 250
    constraints.append(contentsOf: [
      flipDiceContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      flipDiceContainer.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 0),
      flipDiceContainer.heightAnchor.constraint(equalToConstant: diceHeight),
      flipDiceContainer.widthAnchor.constraint(equalToConstant: diceWidth),
    ])

    // Bottom stack view: bottom-left, compact height in landscape to maximize game area
    let chipHeight: CGFloat = chipSelector.chipSize + 9
    let bottomBarHeight = chipHeight + 30 + 12  // chipSelector + balanceView + spacing
    constraints.append(contentsOf: [
      bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      bottomStackView.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
      bottomStackView.heightAnchor.constraint(equalToConstant: bottomBarHeight),
      chipSelector.heightAnchor.constraint(equalToConstant: chipHeight),
    ])

    return constraints
  }

}

// MARK: - Associated Object Keys

private struct AssociatedKeys {
  static var iPhoneConstraints = "iPhoneConstraints"
  static var iPadPortraitConstraints = "iPadPortraitConstraints"
  static var iPadLandscapeConstraints = "iPadLandscapeConstraints"
  static var currentActiveConstraints = "currentActiveConstraints"
  static var previousLayoutMode = "previousLayoutMode"
  static var landscapeLeftContainer = "landscapeLeftContainer"
  static var landscapeRightContainer = "landscapeRightContainer"
  static var iPadContainersCreated = "iPadContainersCreated"
}

private extension UIStackView {
  func setBalanceChipSpacing(_ spacing: CGFloat) {
    self.spacing = spacing
  }
}
