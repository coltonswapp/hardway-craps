//
//  TriZoneBetControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 3/14/26.
//

import UIKit

/// A bet control with 3 tappable zones arranged vertically or horizontally.
/// Each zone has its own label and bet chip, allowing independent bets.
/// Example usage: C & E bet (Craps / C&E / Eleven)
class TriZoneBetControl: UIControl, BetDropTarget {

  // MARK: - Types

  enum Axis {
    case vertical
    case horizontal
  }

  struct ZoneConfig {
    let title: String
  }

  enum Zone: Int, CaseIterable {
    case top = 0
    case middle = 1
    case bottom = 2
  }

  // MARK: - ZoneDragSource (per-zone BetDragSource wrapper)

  /// Lightweight wrapper that lets a single zone act as a BetDragSource for the drag manager.
  class ZoneDragSource: BetDragSource {
    weak var triZone: TriZoneBetControl?
    let zone: Zone

    var betAmount: Int {
      get { triZone?.betAmount(for: zone) ?? 0 }
      set {
        guard let triZone = triZone else { return }
        let current = triZone.betAmount(for: zone)
        if newValue == 0 && current > 0 {
          triZone.removeBetFromZoneSilently(current, zone: zone)
        }
      }
    }

    var betView: BetChipView! {
      triZone?.zoneViews[zone.rawValue].betChip
    }

    var canRemoveBet: (() -> Bool)? { return { true } }

    init(triZone: TriZoneBetControl, zone: Zone) {
      self.triZone = triZone
      self.zone = zone
    }

    func removeBetSilently(_ amount: Int) {
      triZone?.removeBetFromZoneSilently(amount, zone: zone)
    }

    func getBetViewPosition(in view: UIView) -> CGPoint {
      guard let triZone = triZone else { return .zero }
      let chip = triZone.zoneViews[zone.rawValue].betChip
      return chip.superview?.convert(chip.center, to: view) ?? .zero
    }
  }

  // MARK: - Properties

  let axis: Axis
  private let configs: [ZoneConfig]
  private(set) var zoneViews: [ZoneView] = []
  /// Per-zone drag sources for dragging bets away
  private var zoneDragSources: [ZoneDragSource] = []
  /// Clipping container for background + rounded corners; chips live outside this
  private let backgroundContainer = UIView()
  private let mainStack = UIStackView()

  /// Store the original border properties to restore after drag interaction
  private var originalBorderWidth: CGFloat = 0
  private var originalBorderColor: CGColor?

  /// Currently highlighted zone during drag
  private var highlightedZone: Zone?
  /// Display link for tracking drag position during highlight
  private var dragTrackingLink: CADisplayLink?

  // Callbacks
  var getSelectedChipValue: (() -> Int)?
  var getBalance: (() -> Int)?
  /// Called when a bet is placed in any zone: (amount, zone)
  var onBetPlaced: ((Int, Zone) -> Void)?
  /// Called when a bet is removed from any zone: (amount, zone)
  var onBetRemoved: ((Int, Zone) -> Void)?

  // MARK: - Init

  init(zones: [ZoneConfig], axis: Axis = .vertical) {
    precondition(zones.count == 3, "TriZoneBetControl requires exactly 3 zones")
    self.configs = zones
    self.axis = axis
    super.init(frame: .zero)
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    stopDragTracking()
    BetDragManager.shared.unregisterDropTarget(self)
  }

  // MARK: - Setup

  private func setupView() {
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .clear
    clipsToBounds = false

    // Background container clips at rounded corners (background, highlights, separators)
    backgroundContainer.translatesAutoresizingMaskIntoConstraints = false
    backgroundContainer.backgroundColor = HardwayColors.surfaceGray
    backgroundContainer.layer.cornerRadius = 18
    backgroundContainer.clipsToBounds = true
    addSubview(backgroundContainer)

    mainStack.translatesAutoresizingMaskIntoConstraints = false
    mainStack.axis = axis == .vertical ? .vertical : .horizontal
    mainStack.spacing = 0
    mainStack.distribution = .fillEqually
    mainStack.alignment = .fill
    backgroundContainer.addSubview(mainStack)

    for (index, config) in configs.enumerated() {
      let zone = Zone(rawValue: index)!
      let isLast = index == configs.count - 1
      let zoneView = ZoneView(config: config, zone: zone, axis: axis, isLastZone: isLast)
      zoneView.onTap = { [weak self] tappedZone in
        self?.handleZoneTap(tappedZone)
      }
      zoneViews.append(zoneView)
      mainStack.addArrangedSubview(zoneView)
    }

    NSLayoutConstraint.activate([
      backgroundContainer.topAnchor.constraint(equalTo: topAnchor),
      backgroundContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
      backgroundContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
      backgroundContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

      mainStack.topAnchor.constraint(equalTo: backgroundContainer.topAnchor),
      mainStack.leadingAnchor.constraint(equalTo: backgroundContainer.leadingAnchor),
      mainStack.trailingAnchor.constraint(equalTo: backgroundContainer.trailingAnchor),
      mainStack.bottomAnchor.constraint(equalTo: backgroundContainer.bottomAnchor),
    ])

    // Reparent bet chips to self (outside clipping container) so they can overflow
    for (index, zoneView) in zoneViews.enumerated() {
      let chip = zoneView.betChip
      chip.removeFromSuperview()
      addSubview(chip)

      if axis == .horizontal {
        NSLayoutConstraint.activate([
          chip.centerXAnchor.constraint(equalTo: zoneView.centerXAnchor),
          chip.topAnchor.constraint(equalTo: zoneView.topAnchor, constant: -12),
        ])
      } else {
        NSLayoutConstraint.activate([
          chip.trailingAnchor.constraint(equalTo: zoneView.trailingAnchor, constant: -8),
          chip.centerYAnchor.constraint(equalTo: zoneView.centerYAnchor),
        ])
      }

      // Add pan gesture to bet chip for drag-to-remove
      let zone = Zone(rawValue: index)!
      let dragSource = ZoneDragSource(triZone: self, zone: zone)
      zoneDragSources.append(dragSource)

      let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleBetChipPan(_:)))
      chip.addGestureRecognizer(panGesture)
      chip.isUserInteractionEnabled = true

      // Add tap gesture so taps still pass through to the zone
      let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBetChipTap(_:)))
      chip.addGestureRecognizer(tapGesture)
      tapGesture.require(toFail: panGesture)
    }

    BetDragManager.shared.registerDropTarget(self)
  }

  // MARK: - Zone Interaction

  private func handleZoneTap(_ zone: Zone) {
    guard let getValue = getSelectedChipValue else { return }
    let value = getValue()

    if let getBalance = getBalance {
      let balance = getBalance()
      if value > balance {
        HapticsHelper.lightHaptic()
        return
      }
    }

    addBetToZone(value, zone: zone, animated: true)
  }

  // MARK: - Public API

  func betAmount(for zone: Zone) -> Int {
    return zoneViews[zone.rawValue].betChip.amount
  }

  var totalBetAmount: Int {
    return zoneViews.reduce(0) { $0 + $1.betChip.amount }
  }

  /// Same as tapping to add chips, except `notifyPlacedCallback` skips `onBetPlaced` (used when moving chips already wagered).
  func addBetToZone(_ amount: Int, zone: Zone, animated: Bool = false, notifyPlacedCallback: Bool = true) {
    let zoneView = zoneViews[zone.rawValue]
    zoneView.betChip.addToBet(amount)
    zoneView.updateTitleAlignment()
    if notifyPlacedCallback {
      onBetPlaced?(amount, zone)
    }

    if animated {
      let chip = zoneView.betChip
      chip.alpha = 1
      chip.isHidden = false
      bringSubviewToFront(chip)

      let original = chip.transform
      UIView.animate(withDuration: 0.05, delay: 0, options: .curveEaseOut) {
        chip.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
      } completion: { _ in
        UIView.animate(
          withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5,
          options: .curveEaseInOut
        ) {
          chip.transform = original
        }
      }
      HapticsHelper.lightHaptic()
    }
  }

  func removeBetFromZone(_ amount: Int, zone: Zone) {
    let zoneView = zoneViews[zone.rawValue]
    let old = zoneView.betChip.amount
    zoneView.betChip.addToBet(-amount)
    zoneView.updateTitleAlignment()
    let removed = old - zoneView.betChip.amount
    if removed > 0 {
      onBetRemoved?(removed, zone)
    }
  }

  func clearZone(_ zone: Zone) {
    let zoneView = zoneViews[zone.rawValue]
    let amount = zoneView.betChip.amount
    zoneView.betChip.clearBet()
    zoneView.updateTitleAlignment()
    if amount > 0 {
      onBetRemoved?(amount, zone)
    }
  }

  func clearAll() {
    for zone in Zone.allCases {
      clearZone(zone)
    }
  }

  /// Remove bet silently (without triggering onBetRemoved callback).
  /// Used by BetDragManager when moving bets between controls.
  func removeBetFromZoneSilently(_ amount: Int, zone: Zone) {
    let zoneView = zoneViews[zone.rawValue]
    zoneView.betChip.addToBet(-amount)
    zoneView.updateTitleAlignment()
    // Restore alpha so the chip is visible if a new bet is placed later.
    // When amount hits 0, isHidden takes over visibility; alpha must be
    // ready for the next addToBet call that un-hides the chip.
    if zoneView.betChip.amount == 0 {
      zoneView.betChip.alpha = 1
    }
  }

  // MARK: - Bet Chip Drag-to-Remove

  /// Finds which zone a bet chip belongs to
  private func zoneForChip(_ chip: SmallBetChip) -> Zone? {
    for (index, zoneView) in zoneViews.enumerated() {
      if zoneView.betChip === chip {
        return Zone(rawValue: index)
      }
    }
    return nil
  }

  @objc private func handleBetChipPan(_ gesture: UIPanGestureRecognizer) {
    guard let chip = gesture.view as? SmallBetChip,
      let zone = zoneForChip(chip),
      chip.amount > 0
    else { return }

    let dragSource = zoneDragSources[zone.rawValue]

    // Find root view for drag coordinate space
    var rootView: UIView? = self
    while let parent = rootView?.superview {
      rootView = parent
    }
    guard let containerView = rootView else { return }

    let location = gesture.location(in: containerView)

    switch gesture.state {
    case .began:
      chip.alpha = 0
      BetDragManager.shared.startDragging(
        value: chip.amount,
        from: location,
        in: containerView,
        source: dragSource
      )
    case .changed:
      BetDragManager.shared.updateDrag(to: location)
    case .ended:
      BetDragManager.shared.endDrag(at: location, in: containerView)
      // Fallback: restore chip visibility if drag didn't handle it
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak chip] in
        guard let chip = chip else { return }
        if chip.amount > 0 && chip.alpha == 0 {
          chip.alpha = 1
        }
      }
    case .cancelled, .failed:
      BetDragManager.shared.cancelDrag()
      chip.alpha = 1
    default:
      break
    }
  }

  @objc private func handleBetChipTap(_ gesture: UITapGestureRecognizer) {
    guard let chip = gesture.view as? SmallBetChip,
      let zone = zoneForChip(chip)
    else { return }
    handleZoneTap(zone)
  }

  // MARK: - Drag Tracking (per-zone highlight)

  private func startDragTracking() {
    guard dragTrackingLink == nil else { return }
    dragTrackingLink = CADisplayLink(target: self, selector: #selector(trackDragPosition))
    dragTrackingLink?.add(to: .main, forMode: .common)
  }

  private func stopDragTracking() {
    dragTrackingLink?.invalidate()
    dragTrackingLink = nil
    unhighlightAllZones()
    highlightedZone = nil
  }

  @objc private func trackDragPosition() {
    // Find the dragged chip in BetDragManager by looking for it in the window
    guard let window = self.window else { return }

    // The dragged chip is the topmost SmallBetChip added to the root view
    // BetDragManager adds it to the container view (root view)
    // We can find it by checking BetDragManager's state
    guard BetDragManager.shared.hasCurrentDropTarget() || true else {
      // Manager has no active target info, but we're highlighted so drag is active
      return
    }

    // Find the dragged chip — it's a SmallBetChip that's a direct subview of the root view
    // with transform scale > 1 (dragged chips are scaled to 1.3)
    var rootView: UIView = window
    for subview in rootView.subviews.reversed() {
      if let chip = subview as? SmallBetChip, chip.transform.a > 1.0 {
        let chipCenter = chip.center
        let localPoint = rootView.convert(chipCenter, to: self)
        updateZoneHighlight(at: localPoint)
        return
      }
    }

    // Also check the window's rootViewController's view
    if let rootVC = window.rootViewController {
      var topView: UIView = rootVC.view
      // Walk up to find the actual root
      while let parent = topView.superview, parent !== window {
        topView = parent
      }
      for subview in topView.subviews.reversed() {
        if let chip = subview as? SmallBetChip, chip.transform.a > 1.0 {
          let chipCenter = chip.center
          let localPoint = topView.convert(chipCenter, to: self)
          updateZoneHighlight(at: localPoint)
          return
        }
      }
    }
  }

  private func updateZoneHighlight(at localPoint: CGPoint) {
    var newZone: Zone? = nil
    for (index, zoneView) in zoneViews.enumerated() {
      if zoneView.frame.contains(localPoint) {
        newZone = Zone(rawValue: index)
        break
      }
    }

    if newZone != highlightedZone {
      // Unhighlight old
      if let old = highlightedZone {
        zoneViews[old.rawValue].setHighlighted(false)
      }
      // Highlight new
      if let new = newZone {
        zoneViews[new.rawValue].setHighlighted(true)
        HapticsHelper.superLightHaptic()
      }
      highlightedZone = newZone
    }
  }

  private func unhighlightAllZones() {
    for zoneView in zoneViews {
      zoneView.setHighlighted(false)
    }
  }

  // MARK: - BetDropTarget

  var betAmount: Int {
    get { totalBetAmount }
    set { /* Not applicable for multi-zone */  }
  }

  /// The zone that was highlighted when the drop began.
  /// Captured in `getBetViewPosition` (called first by BetDragManager.endDrag)
  /// so that subsequent `addBet`/`addBetWithAnimation` calls use the correct
  /// zone even if the CADisplayLink or unhighlight clears `highlightedZone`.
  private var pendingDropZone: Zone?

  func frameInView(_ view: UIView) -> CGRect {
    guard let superview = superview else { return .zero }
    return superview.convert(frame, to: view)
  }

  func getBetViewPosition(in view: UIView) -> CGPoint {
    // Capture the zone at drop time so addBet/addBetWithAnimation use it later
    pendingDropZone = highlightedZone

    if let zone = highlightedZone {
      let chip = zoneViews[zone.rawValue].betChip
      // Bet chips are reparented to `self`, not the zone view — convert from the chip's superview
      return chip.superview?.convert(chip.center, to: view) ?? .zero
    }
    // Fallback to center
    guard let superview = superview else { return .zero }
    return superview.convert(center, to: view)
  }

  func addBet(_ amount: Int) {
    let zone = pendingDropZone ?? highlightedZone ?? .middle
    pendingDropZone = nil
    addBetToZone(amount, zone: zone)
  }

  /// Reposition stakes already deducted from balance (drag from another betting control).
  func addTransferredBet(_ amount: Int) {
    let zone = pendingDropZone ?? highlightedZone ?? .middle
    pendingDropZone = nil
    addBetToZone(amount, zone: zone, animated: true, notifyPlacedCallback: false)
  }

  func addBetWithAnimation(_ amount: Int) {
    let zone = pendingDropZone ?? highlightedZone ?? .middle
    pendingDropZone = nil
    addBetToZone(amount, zone: zone, animated: true)
  }

  func removeBet(_ amount: Int) {
    let zone = pendingDropZone ?? highlightedZone ?? .middle
    pendingDropZone = nil
    removeBetFromZone(amount, zone: zone)
  }

  func highlightAsDropTarget() {
    originalBorderWidth = backgroundContainer.layer.borderWidth
    originalBorderColor = backgroundContainer.layer.borderColor

    UIView.animate(
      withDuration: 0.2, delay: 0,
      options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
    ) {
      self.backgroundContainer.layer.borderColor =
        UIColor.systemBlue.withAlphaComponent(0.4).cgColor
      self.backgroundContainer.layer.borderWidth = 2
    }

    // Start tracking drag position for per-zone highlighting
    startDragTracking()
    HapticsHelper.superLightHaptic()
  }

  func unhighlightAsDropTarget() {
    stopDragTracking()

    UIView.animate(
      withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5,
      options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]
    ) {
      self.backgroundContainer.layer.borderWidth = self.originalBorderWidth
      self.backgroundContainer.layer.borderColor = self.originalBorderColor
    }
  }

  func hasLockedBet() -> Bool { return false }
  func animateBetViewSlideLeftForOdds() {}
  func restoreBetViewPosition() {}

  // MARK: - Hit Testing

  /// Determine which zone a point falls in (in local coordinates)
  func zone(at point: CGPoint) -> Zone? {
    for (index, zoneView) in zoneViews.enumerated() {
      if zoneView.frame.contains(point) {
        return Zone(rawValue: index)
      }
    }
    return nil
  }
}

// MARK: - ZoneView

class ZoneView: UIView {

  let zone: TriZoneBetControl.Zone
  let betChip: SmallBetChip
  var onTap: ((TriZoneBetControl.Zone) -> Void)?

  private let layoutAxis: TriZoneBetControl.Axis
  private var titleCenterXConstraint: NSLayoutConstraint?
  private var titleLeadingConstraint: NSLayoutConstraint?
  // Horizontal-specific: title shifts down when bet is placed
  private var titleCenterYConstraint: NSLayoutConstraint?
  private var titleBottomConstraint: NSLayoutConstraint?

  private let highlightOverlay: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
    view.alpha = 0
    view.isUserInteractionEnabled = false
    return view
  }()

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    label.font = .systemFont(ofSize: isIPad ? 22.5 : 16, weight: .regular)
    label.textColor = HardwayColors.label
    return label
  }()

  /// Separator between zones (bottom border for vertical, trailing border for horizontal)
  private let separatorBorder: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = HardwayColors.label.withAlphaComponent(0.15)
    view.isUserInteractionEnabled = false
    return view
  }()

  init(
    config: TriZoneBetControl.ZoneConfig, zone: TriZoneBetControl.Zone,
    axis: TriZoneBetControl.Axis = .vertical, isLastZone: Bool = false
  ) {
    self.zone = zone
    self.layoutAxis = axis
    self.betChip = SmallBetChip()
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false
    clipsToBounds = false

    titleLabel.text = config.title
    titleLabel.textAlignment = axis == .horizontal ? .center : .left

    addSubview(highlightOverlay)
    addSubview(titleLabel)
    addSubview(separatorBorder)

    NSLayoutConstraint.activate([
      highlightOverlay.topAnchor.constraint(equalTo: topAnchor),
      highlightOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
      highlightOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
      highlightOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    if axis == .horizontal {
      // Horizontal layout: title centered, shifts down when bet chip appears on top
      titleCenterXConstraint = titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
      titleCenterXConstraint?.isActive = true

      titleCenterYConstraint = titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
      titleBottomConstraint = titleLabel.bottomAnchor.constraint(
        equalTo: bottomAnchor, constant: -6)
      titleCenterYConstraint?.isActive = true

      NSLayoutConstraint.activate([
        // Vertical separator on trailing edge
        separatorBorder.topAnchor.constraint(equalTo: topAnchor),
        separatorBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
        separatorBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
        separatorBorder.widthAnchor.constraint(equalToConstant: 1.0),
      ])
    } else {
      // Vertical layout (original)
      titleCenterXConstraint = titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
      titleLeadingConstraint = titleLabel.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: 12)
      titleCenterXConstraint?.isActive = true

      NSLayoutConstraint.activate([
        titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

        // Horizontal separator on bottom edge
        separatorBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
        separatorBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
        separatorBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
        separatorBorder.heightAnchor.constraint(equalToConstant: 1.0),
      ])
    }

    // Hide separator on the last zone
    if isLastZone {
      separatorBorder.isHidden = true
    }

    isUserInteractionEnabled = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateTitleAlignment() {
    let hasBet = betChip.amount > 0

    UIView.animate(
      withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 1.0,
      options: [.curveEaseInOut, .allowUserInteraction]
    ) {
      if self.layoutAxis == .horizontal {
        // Shift title down to make room for chip on top
        self.titleCenterYConstraint?.isActive = !hasBet
        self.titleBottomConstraint?.isActive = hasBet
      } else {
        // Shift title left to make room for chip on right
        self.titleCenterXConstraint?.isActive = !hasBet
        self.titleLeadingConstraint?.isActive = hasBet
        self.titleLabel.textAlignment = hasBet ? .left : .center
      }
      self.layoutIfNeeded()
    }
  }

  func setHighlighted(_ highlighted: Bool) {
    UIView.animate(
      withDuration: 0.15, delay: 0,
      options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
    ) {
      self.highlightOverlay.alpha = highlighted ? 1 : 0
    }
  }

  // MARK: - Touch Handling (matching PlainControl's springy feel)

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
      self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesEnded(touches, with: event)
    // Check if touch ended inside this zone
    if let touch = touches.first {
      let location = touch.location(in: self)
      if bounds.contains(location) {
        onTap?(zone)
      }
    }
    springBack()
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesCancelled(touches, with: event)
    springBack()
  }

  private func springBack() {
    UIView.animate(
      withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5,
      options: [.curveEaseInOut, .allowUserInteraction]
    ) {
      self.transform = .identity
    }
    HapticsHelper.lightHaptic()
  }
}
