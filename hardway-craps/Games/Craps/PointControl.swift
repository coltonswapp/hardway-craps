//
//  PointControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class PointControl: PlainControl {

  // MARK: - Zone Enum

  enum Zone: Int, CaseIterable {
    case lay = 0
    case place = 1
  }

  // MARK: - Labels

  private let numberLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    label.font = .systemFont(ofSize: isIPad ? 34 : 24, weight: .medium)
    label.textColor = HardwayColors.label
    label.isUserInteractionEnabled = false
    return label
  }()

  private let oddsLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    label.font = .systemFont(ofSize: isIPad ? 18 : 12, weight: .regular)
    label.textColor = HardwayColors.label.withAlphaComponent(0.6)
    label.isUserInteractionEnabled = false
    return label
  }()

  // MARK: - Zone Labels (only visible during drag hover)

  private let layZoneLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    label.font = .systemFont(ofSize: isIPad ? 13 : 9, weight: .medium)
    label.textColor = HardwayColors.label.withAlphaComponent(0.5)
    label.text = "LAY"
    label.alpha = 0
    label.isUserInteractionEnabled = false
    return label
  }()

  private let placeZoneLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    label.font = .systemFont(ofSize: isIPad ? 13 : 9, weight: .medium)
    label.textColor = HardwayColors.label.withAlphaComponent(0.5)
    label.text = "PLACE"
    label.alpha = 0
    label.isUserInteractionEnabled = false
    return label
  }()

  // MARK: - Zone Views & Highlight Overlays

  private let layZoneView = UIView()
  private let placeZoneView = UIView()

  private let layHighlightOverlay: UIView = {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
    v.alpha = 0
    v.isUserInteractionEnabled = false
    return v
  }()

  private let placeHighlightOverlay: UIView = {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
    v.alpha = 0
    v.isUserInteractionEnabled = false
    return v
  }()

  private let topSeparator: UIView = {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.backgroundColor = HardwayColors.label.withAlphaComponent(0.15)
    v.isUserInteractionEnabled = false
    v.alpha = 0
    return v
  }()

  private let zoneStack: UIStackView = {
    let sv = UIStackView()
    sv.translatesAutoresizingMaskIntoConstraints = false
    sv.axis = .vertical
    sv.spacing = 0
    sv.distribution = .fill
    sv.alignment = .fill
    return sv
  }()

  // MARK: - Drag Tracking State

  private var highlightedZone: Zone?
  private var dragTrackingLink: CADisplayLink?
  private var originalBorderWidthForDrag: CGFloat = 0
  private var originalBorderColorForDrag: CGColor?
  private var pendingDropZone: Zone?

  // MARK: - Stored Properties

  let pointNumber: Int
  let odds: String

  override var wantsDefaultHeightConstraint: Bool { return false }

  var oddsMultiplier: Double {
    switch pointNumber {
    case 2, 12: return 6.0
    case 3, 11: return 3.0
    case 4, 10: return 2.0
    case 5, 9: return 1.5
    case 6, 8: return 1.2
    default: return 1.0
    }
  }

  var layOddsMultiplier: Double {
    switch pointNumber {
    case 2, 12: return 1.0 / 6.0
    case 3, 11: return 1.0 / 3.0
    case 4, 10: return 0.5
    case 5, 9: return 2.0 / 3.0
    case 6, 8: return 5.0 / 6.0
    default: return 1.0
    }
  }

  var isOn: Bool = false

  // MARK: - Lay Bet

  private let layBetChip = SmallBetChip()

  var layBetAmount: Int { layBetChip.amount }
  var hasLayBet: Bool { layBetChip.amount > 0 }

  var onLayBetPlaced: ((Int) -> Void)?
  var onLayBetRemoved: ((Int) -> Void)?

  // MARK: - Come Bet (with odds support)

  private var comeBetStack: OddsBetStack?

  var hasComeBet: Bool { comeBetStack != nil && comeBetStack!.betAmount > 0 }
  var comeBetAmount: Int { comeBetStack?.betAmount ?? 0 }
  var comeBetOddsAmount: Int { comeBetStack?.oddsAmount ?? 0 }

  var onComeBetOddsPlaced: ((Int, Int, Int) -> Void)?
  var onComeBetOddsRemoved: ((Int) -> Void)?

  // MARK: - Animation Offsets

  override var winningsAnimationOffset: CGPoint { CGPoint(x: 0, y: -30) }
  override var originalBetWinningsOffset: CGPoint { CGPoint(x: 0, y: -30) }

  // MARK: - Init

  init(pointNumber: Int) {
    self.pointNumber = pointNumber

    switch pointNumber {
    case 2, 12: self.odds = "6:1"
    case 3, 11: self.odds = "3:1"
    case 4, 10: self.odds = "2:1"
    case 5, 9: self.odds = "3:2"
    case 6, 8: self.odds = "6:5"
    default: self.odds = ""
    }

    super.init(title: nil)

    setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
    setContentCompressionResistancePriority(.defaultLow, for: .vertical)

    setupThreeZoneLayout()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Puck center in `container` coordinates: horizontally centered on the control; vertically at this view’s top (`topAnchor`).
  func puckCenterPosition(in container: UIView) -> CGPoint {
    layoutIfNeeded()
    return convert(CGPoint(x: bounds.midX, y: 8), to: container)
  }

  // MARK: - Three-Zone Layout

  private let backgroundContainer: UIView = {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.backgroundColor = HardwayColors.surfaceGray
    v.layer.cornerRadius = 16
    v.clipsToBounds = true
    return v
  }()

  private func setupThreeZoneLayout() {
    numberLabel.text = "\(pointNumber)"
    oddsLabel.text = odds

    backgroundColor = .clear
    layer.cornerRadius = 0
    clipsToBounds = false

    insertSubview(backgroundContainer, at: 0)
    // Keep the gray box from consuming a11y: if this is `true`, iOS won't expose `placeZoneView` /
    // `layZoneView` to automation (so `pointControlPlaceZone.*` never matches).
    backgroundContainer.isAccessibilityElement = false

    for zv in [layZoneView, placeZoneView] {
      zv.translatesAutoresizingMaskIntoConstraints = false
      zv.backgroundColor = .clear
      zv.isUserInteractionEnabled = true
    }

    zoneStack.addArrangedSubview(layZoneView)
    zoneStack.addArrangedSubview(placeZoneView)

    backgroundContainer.addSubview(zoneStack)

    // Highlight overlays inside clipping container
    layZoneView.addSubview(layHighlightOverlay)
    placeZoneView.addSubview(placeHighlightOverlay)

    // Separators
    layZoneView.addSubview(topSeparator)

    // Zone labels
    layZoneView.addSubview(layZoneLabel)
    placeZoneView.addSubview(placeZoneLabel)

    // Number + odds labels float above everything
    addSubview(numberLabel)
    addSubview(oddsLabel)

    // Lay bet chip on self (outside clipping) so it hangs off the top
    layBetChip.translatesAutoresizingMaskIntoConstraints = false
    addSubview(layBetChip)

    let isIPad = UIDevice.current.userInterfaceIdiom == .pad

    NSLayoutConstraint.activate([
      backgroundContainer.topAnchor.constraint(equalTo: topAnchor),
      backgroundContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
      backgroundContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
      backgroundContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

      zoneStack.topAnchor.constraint(equalTo: backgroundContainer.topAnchor),
      zoneStack.leadingAnchor.constraint(equalTo: backgroundContainer.leadingAnchor),
      zoneStack.trailingAnchor.constraint(equalTo: backgroundContainer.trailingAnchor),
      zoneStack.bottomAnchor.constraint(equalTo: backgroundContainer.bottomAnchor),

      // Lay zone takes ~25% of height
      layZoneView.heightAnchor.constraint(equalTo: zoneStack.heightAnchor, multiplier: 0.25),

      // Highlight overlays fill their zones
      layHighlightOverlay.topAnchor.constraint(equalTo: layZoneView.topAnchor),
      layHighlightOverlay.leadingAnchor.constraint(equalTo: layZoneView.leadingAnchor),
      layHighlightOverlay.trailingAnchor.constraint(equalTo: layZoneView.trailingAnchor),
      layHighlightOverlay.bottomAnchor.constraint(equalTo: layZoneView.bottomAnchor),

      placeHighlightOverlay.topAnchor.constraint(equalTo: placeZoneView.topAnchor),
      placeHighlightOverlay.leadingAnchor.constraint(equalTo: placeZoneView.leadingAnchor),
      placeHighlightOverlay.trailingAnchor.constraint(equalTo: placeZoneView.trailingAnchor),
      placeHighlightOverlay.bottomAnchor.constraint(equalTo: placeZoneView.bottomAnchor),

      // Separators
      topSeparator.leadingAnchor.constraint(equalTo: layZoneView.leadingAnchor),
      topSeparator.trailingAnchor.constraint(equalTo: layZoneView.trailingAnchor),
      topSeparator.bottomAnchor.constraint(equalTo: layZoneView.bottomAnchor),
      topSeparator.heightAnchor.constraint(equalToConstant: 1),

      // Number + odds: upper portion so come bet doesn't obscure them
      numberLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      numberLabel.topAnchor.constraint(equalTo: layZoneView.bottomAnchor, constant: isIPad ? 8 : 4),

      oddsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      oddsLabel.topAnchor.constraint(equalTo: numberLabel.bottomAnchor, constant: 2),

      // Zone labels centered
      layZoneLabel.centerXAnchor.constraint(equalTo: layZoneView.centerXAnchor),
      layZoneLabel.centerYAnchor.constraint(equalTo: layZoneView.centerYAnchor),

      placeZoneLabel.centerXAnchor.constraint(equalTo: placeZoneView.centerXAnchor),
      placeZoneLabel.bottomAnchor.constraint(equalTo: placeZoneView.bottomAnchor, constant: -20),

      // Lay bet chip hangs off the top
      layBetChip.centerXAnchor.constraint(equalTo: centerXAnchor),
      layBetChip.centerYAnchor.constraint(equalTo: topAnchor, constant: 8),
    ])

    repositionBetViewInPlaceZone()
    setupLayBetGestures()

    backgroundContainer.accessibilityElements = [layZoneView, placeZoneView]

    betView.isAccessibilityElement = true
    betView.accessibilityIdentifier = "pointPlaceBetChip.\(pointNumber)"
    betView.accessibilityLabel = "Place bet on \(pointNumber)"
  }

  // MARK: - PlainControl Overrides

  private var betViewPlaceConstraints: [NSLayoutConstraint] = []

  override func configureBetViewConstraints() {
    // During super.init placeZoneView isn't in the hierarchy yet.
    // Temporary constraints; repositionBetViewInPlaceZone() replaces them.
    NSLayoutConstraint.activate([
      betView.centerXAnchor.constraint(equalTo: centerXAnchor),
      betView.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  private func repositionBetViewInPlaceZone() {
    for c in constraints where c.firstItem === betView || c.secondItem === betView {
      c.isActive = false
    }
    // Place bet chip hangs off the bottom of the control
    let cx = betView.centerXAnchor.constraint(equalTo: centerXAnchor)
    let cy = betView.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -8)
    betViewPlaceConstraints = [cx, cy]
    NSLayoutConstraint.activate(betViewPlaceConstraints)
  }

  // MARK: - Touch Feedback (replicating PlainControl's touchDown / touchUp on backgroundContainer)

  private func animateTouchDown() {
    UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
      self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
    }
  }

  private func animateTouchUp() {
    UIView.animate(
      withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5,
      options: [.curveEaseInOut, .allowUserInteraction]
    ) {
      self.transform = .identity
    }
    HapticsHelper.lightHaptic()
  }

  // MARK: - Drop-Target Highlight & Drag Tracking

  override func highlightAsDropTarget() {
    originalBorderWidthForDrag = backgroundContainer.layer.borderWidth
    originalBorderColorForDrag = backgroundContainer.layer.borderColor

    UIView.animate(
      withDuration: 0.2, delay: 0,
      options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
    ) {
      self.backgroundContainer.layer.borderColor =
        UIColor.systemBlue.withAlphaComponent(0.4).cgColor
      self.backgroundContainer.layer.borderWidth = 2
    }

    showDragUI()
    startDragTracking()
    HapticsHelper.superLightHaptic()
  }

  override func unhighlightAsDropTarget() {
    stopDragTracking()
    hideDragUI()
    // `getBetViewPosition` stores highlightedZone here for drop routing; clear when drag hover ends
    // so chip taps don't later call `addBetWithAnimation` with a stale `.lay` zone.
    pendingDropZone = nil

    UIView.animate(
      withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5,
      options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]
    ) {
      self.backgroundContainer.layer.borderWidth = self.originalBorderWidthForDrag
      self.backgroundContainer.layer.borderColor = self.originalBorderColorForDrag
    }
  }

  private func showDragUI() {
    UIView.animate(withDuration: 0.15) {
      self.layZoneLabel.alpha = 1
      self.placeZoneLabel.alpha = 1
      self.topSeparator.alpha = 1
    }
  }

  private func hideDragUI() {
    UIView.animate(withDuration: 0.15) {
      self.layZoneLabel.alpha = 0
      self.placeZoneLabel.alpha = 0
      self.topSeparator.alpha = 0
    }
    unhighlightAllZones()
    highlightedZone = nil
  }

  // MARK: - Per-Zone Highlight Tracking (mirroring TriZoneBetControl)

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
    guard let window = self.window else { return }

    var rootView: UIView = window
    for subview in rootView.subviews.reversed() {
      if let chip = subview as? SmallBetChip, chip.transform.a > 1.0 {
        let localPoint = rootView.convert(chip.center, to: backgroundContainer)
        updateZoneHighlight(at: localPoint)
        return
      }
    }

    if let rootVC = window.rootViewController {
      var topView: UIView = rootVC.view
      while let parent = topView.superview, parent !== window {
        topView = parent
      }
      for subview in topView.subviews.reversed() {
        if let chip = subview as? SmallBetChip, chip.transform.a > 1.0 {
          let localPoint = topView.convert(chip.center, to: backgroundContainer)
          updateZoneHighlight(at: localPoint)
          return
        }
      }
    }
  }

  private func updateZoneHighlight(at localPoint: CGPoint) {
    var newZone: Zone? = nil
    let zones: [(Zone, UIView)] = [(.lay, layZoneView), (.place, placeZoneView)]
    for (zone, zoneView) in zones {
      if zoneView.frame.contains(localPoint) {
        newZone = zone
        break
      }
    }

    if newZone != highlightedZone {
      if let old = highlightedZone {
        setZoneHighlighted(old, highlighted: false)
      }
      if let zone = newZone {
        setZoneHighlighted(zone, highlighted: true)
        HapticsHelper.superLightHaptic()
      }
      highlightedZone = newZone
    }
  }

  private func setZoneHighlighted(_ zone: Zone, highlighted: Bool) {
    let overlay: UIView
    switch zone {
    case .lay: overlay = layHighlightOverlay
    case .place: overlay = placeHighlightOverlay
    }
    UIView.animate(
      withDuration: 0.15, delay: 0,
      options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
    ) {
      overlay.alpha = highlighted ? 1 : 0
    }
  }

  private func unhighlightAllZones() {
    for zone in Zone.allCases {
      setZoneHighlighted(zone, highlighted: false)
    }
  }

  // MARK: - BetDropTarget zone-aware drop

  override func getBetViewPosition(in view: UIView) -> CGPoint {
    pendingDropZone = highlightedZone
    if highlightedZone == .lay {
      return layBetChip.superview?.convert(layBetChip.center, to: view)
        ?? super.getBetViewPosition(in: view)
    }
    return super.getBetViewPosition(in: view)
  }

  override func addBet(_ amount: Int) {
    let zone = pendingDropZone ?? .place
    pendingDropZone = nil
    switch zone {
    case .lay:
      addLayBet(amount)
    case .place:
      super.addBet(amount)
    }
  }

  override func addBetWithAnimation(_ amount: Int) {
    let zone = pendingDropZone ?? .place
    pendingDropZone = nil
    switch zone {
    case .lay:
      addLayBetWithAnimation(amount)
    case .place:
      placeBetWithAnimation(amount)
    }
  }

  private func placeBetWithAnimation(_ amount: Int) {
    super.addBetWithAnimation(amount)
  }

  /// Handles moving a place bet to the lay zone when dragging within the same control.
  /// Returns true if the move was performed (place bet existed, drop zone was lay).
  /// Does not call onLayBetPlaced — balance unchanged since we're moving, not adding.
  func handleMoveFromPlaceToLay(amount: Int) -> Bool {
    guard pendingDropZone == .lay else { return false }
    guard betAmount >= amount else { return false }
    guard !isOn else { return false }

    super.removeBetSilently(amount)
    addLayBet(amount)
    HapticsHelper.lightHaptic()
    return true
  }

  /// Handles moving a lay bet to the place zone when dragging within the same control.
  /// Returns true if the move was performed (lay bet existed, drop zone was place).
  /// Does not call onLayBetPlaced/onLayBetRemoved — balance unchanged since we're moving, not adding.
  func handleMoveFromLayToPlace(amount: Int) -> Bool {
    guard pendingDropZone == .place else { return false }
    guard layBetChip.amount >= amount else { return false }
    guard !isOn else { return false }

    removeLayBetSilently(amount)
    super.addBet(amount)
    HapticsHelper.lightHaptic()
    return true
  }

  /// Handles a lay bet dropped on the same PointControl. Returns true if a zone move (lay→place) was performed.
  /// When false, caller/pan handler restores lay chip alpha (drop back on lay zone).
  func handleLayBetDroppedOnSelf(amount: Int) -> Bool {
    return handleMoveFromLayToPlace(amount: amount)
  }

  // MARK: - Lay Bet Gestures

  private func setupLayBetGestures() {
    let layTap = UITapGestureRecognizer(target: self, action: #selector(handleLayZoneTap))
    layZoneView.addGestureRecognizer(layTap)

    let layChipTap = UITapGestureRecognizer(target: self, action: #selector(handleLayZoneTap))
    layBetChip.addGestureRecognizer(layChipTap)
    layBetChip.isUserInteractionEnabled = true

    let layPan = UIPanGestureRecognizer(target: self, action: #selector(handleLayBetChipPan(_:)))
    layBetChip.addGestureRecognizer(layPan)
    layChipTap.require(toFail: layPan)

    let placeTap = UITapGestureRecognizer(target: self, action: #selector(handlePlaceZoneTap))
    placeZoneView.addGestureRecognizer(placeTap)

    layZoneView.accessibilityIdentifier = "pointControlLayZone.\(pointNumber)"
    layZoneView.isAccessibilityElement = true
    layZoneView.accessibilityLabel = "Lay \(pointNumber)"

    placeZoneView.accessibilityIdentifier = "pointControlPlaceZone.\(pointNumber)"
    placeZoneView.isAccessibilityElement = true
    placeZoneView.accessibilityLabel = "Place \(pointNumber)"

    layZoneLabel.isAccessibilityElement = false
    placeZoneLabel.isAccessibilityElement = false

    // Touch-down press recognisers for scale-down feel.
    // The long press must allow tap gestures to fire simultaneously.
    for zoneView in [layZoneView, placeZoneView] {
      let press = UILongPressGestureRecognizer(target: self, action: #selector(handleZonePress(_:)))
      press.minimumPressDuration = 0
      press.cancelsTouchesInView = false
      press.delegate = self
      zoneView.addGestureRecognizer(press)
    }
  }

  @objc private func handleZonePress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      animateTouchDown()
    case .ended, .cancelled, .failed:
      UIView.animate(
        withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5,
        options: [.curveEaseInOut, .allowUserInteraction]
      ) {
        self.transform = .identity
      }
    default:
      break
    }
  }

  @objc private func handleLayZoneTap() {
    guard !isOn else {
      HapticsHelper.lightHaptic()
      return
    }
    guard let getValue = getSelectedChipValue else { return }
    let value = getValue()

    if let getBalance = getBalance {
      if value > getBalance() {
        HapticsHelper.lightHaptic()
        return
      }
    }

    animateTouchUp()
    addLayBetWithAnimation(value)
  }

  @objc private func handlePlaceZoneTap() {
    guard let getValue = getSelectedChipValue else { return }
    let value = getValue()

    if let getBalance = getBalance {
      if value > getBalance() {
        HapticsHelper.lightHaptic()
        return
      }
    }

    animateTouchUp()
    placeBetWithAnimation(value)
  }

  @objc private func handleLayBetChipPan(_ gesture: UIPanGestureRecognizer) {
    guard layBetChip.amount > 0 else { return }

    var rootView: UIView? = self
    while let parent = rootView?.superview { rootView = parent }
    guard let containerView = rootView else { return }

    let location = gesture.location(in: containerView)

    switch gesture.state {
    case .began:
      layBetChip.alpha = 0
      draggedLayAmount = layBetChip.amount
      BetDragManager.shared.startDragging(
        value: layBetChip.amount, from: location, in: containerView, source: nil, layBetSource: self
      )
    case .changed:
      BetDragManager.shared.updateDrag(to: location)
    case .ended:
      let amountToRemove = draggedLayAmount
      // Check BetDragManager's current target BEFORE endDrag clears it
      let droppedOnChipSelector = BetDragManager.shared.isCurrentDropTargetChipSelector()
      let myFrame = controlFrameInView(containerView)
      let isDroppingOnSelf = myFrame.contains(location)

      BetDragManager.shared.endDrag(at: location, in: containerView)
      draggedLayAmount = 0

      if droppedOnChipSelector && amountToRemove > 0 {
        layBetChip.clearBet()
        onLayBetRemoved?(amountToRemove)
      } else if isDroppingOnSelf {
        layBetChip.alpha = 1
      } else {
        layBetChip.alpha = 1
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self = self else { return }
        if self.layBetChip.amount > 0 && self.layBetChip.alpha == 0 {
          self.layBetChip.alpha = 1
        }
      }
    case .cancelled, .failed:
      BetDragManager.shared.cancelDrag()
      draggedLayAmount = 0
      layBetChip.alpha = 1
    default:
      break
    }
  }

  private var draggedLayAmount: Int = 0

  private func findChipSelectorFrame(in view: UIView) -> CGRect {
    for subview in view.subviews {
      if let chipSelector = subview as? ChipSelector {
        return view.convert(chipSelector.bounds, from: chipSelector)
      }
      let frame = findChipSelectorFrame(in: subview)
      if frame != .zero { return frame }
    }
    return .zero
  }

  private func controlFrameInView(_ view: UIView) -> CGRect {
    guard let superview = superview else { return .zero }
    return superview.convert(frame, to: view)
  }

  // MARK: - Lay Bet API

  func addLayBet(_ amount: Int) {
    guard !isOn else { return }
    layBetChip.addToBet(amount)
    layBetChip.alpha = 1
    layBetChip.isHidden = false
    bringSubviewToFront(layBetChip)
  }

  func addLayBetWithAnimation(_ amount: Int) {
    guard !isOn else { return }
    layBetChip.addToBet(amount)
    layBetChip.alpha = 1
    layBetChip.isHidden = false
    bringSubviewToFront(layBetChip)

    onLayBetPlaced?(amount)

    let original = layBetChip.transform
    UIView.animate(withDuration: 0.05, delay: 0, options: .curveEaseOut) {
      self.layBetChip.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
    } completion: { _ in
      UIView.animate(
        withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5,
        options: .curveEaseInOut
      ) {
        self.layBetChip.transform = original
      }
    }
    HapticsHelper.lightHaptic()
  }

  func removeLayBet(_ amount: Int) {
    let old = layBetChip.amount
    layBetChip.addToBet(-amount)
    let removed = old - layBetChip.amount
    if removed > 0 { onLayBetRemoved?(removed) }
  }

  func removeLayBetSilently(_ amount: Int) {
    layBetChip.addToBet(-amount)
    if layBetChip.amount == 0 { layBetChip.alpha = 1 }
  }

  func setDirectLayBet(_ amount: Int) {
    layBetChip.amount = amount
    if amount > 0 {
      layBetChip.alpha = 1
      layBetChip.isHidden = false
      bringSubviewToFront(layBetChip)
    }
  }

  func clearLayBet() {
    let amount = layBetChip.amount
    layBetChip.clearBet()
    if amount > 0 { onLayBetRemoved?(amount) }
  }

  func clearLayBetSilently() {
    layBetChip.clearBet()
  }

  func getLayBetChipPosition(in view: UIView) -> CGPoint {
    guard let sv = layBetChip.superview else { return .zero }
    return sv.convert(layBetChip.center, to: view)
  }

  func hideLayBetChip() { layBetChip.alpha = 0 }
  func showLayBetChip() { layBetChip.alpha = 1 }

  // MARK: - Come Bet Support

  func addComeBet(
    amount: Int, getSelectedChipValue: @escaping () -> Int, getBalance: @escaping () -> Int
  ) {
    if comeBetStack == nil {
      comeBetStack = OddsBetStack(layout: .horizontal)
      comeBetStack?.useCenteredHorizontalLayout()
      comeBetStack?.parentControl = self
      addSubview(comeBetStack!)

      comeBetStack?.getSelectedChipValue = getSelectedChipValue
      comeBetStack?.getBalance = getBalance
      comeBetStack?.onBetPlaced = { [weak self] _ in let _ = self }
      comeBetStack?.onBetRemoved = { [weak self] _ in let _ = self }
      comeBetStack?.onOddsPlaced = { [weak self] amount, previousOddsAmount in
        guard let self = self else { return }
        self.onComeBetOddsPlaced?(amount, previousOddsAmount, self.pointNumber)
      }
      comeBetStack?.onOddsRemoved = { [weak self] amount in
        self?.onComeBetOddsRemoved?(amount)
      }

      setupComeBetConstraints()
    }

    comeBetStack?.betAmount = amount
    comeBetStack?.lockBet()
  }

  func clearComeBet() {
    let oddsToReturn = comeBetStack?.oddsAmount ?? 0
    if oddsToReturn > 0 { onComeBetOddsRemoved?(oddsToReturn) }
    comeBetStack?.removeFromSuperview()
    comeBetStack = nil
  }

  func clearComeBetSilently() {
    comeBetStack?.removeFromSuperview()
    comeBetStack = nil
  }

  private func setupComeBetConstraints() {
    guard let stack = comeBetStack else { return }
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.topAnchor.constraint(equalTo: oddsLabel.bottomAnchor, constant: 12),
    ])
  }

  func updateComeBetStackPosition() {}

  // MARK: - Convenience Methods

  func addComeBetOdds(amount: Int) { comeBetStack?.addOddsWithAnimation(amount) }
  func setComeBetOddsAmount(_ amount: Int) { comeBetStack?.oddsAmount = amount }

  func getComeBetPosition(in view: UIView) -> CGPoint {
    guard let stack = comeBetStack else { return .zero }
    return stack.getBetPosition(in: view)
  }

  func getComeBetOddsPosition(in view: UIView) -> CGPoint {
    guard let stack = comeBetStack else { return .zero }
    return stack.getOddsPosition(in: view)
  }

  func hideComeBetChip() { comeBetStack?.betChip.alpha = 0 }
  func showComeBetChip() { comeBetStack?.betChip.alpha = 1 }
  func hideComeBetOddsChip() { comeBetStack?.oddsChip.alpha = 0 }

  // MARK: - Clear All (includes lay bets)

  override func clearAll() {
    super.clearAll()
    let layAmount = layBetChip.amount
    layBetChip.clearBet()
    if layAmount > 0 { onLayBetRemoved?(layAmount) }
  }

  // MARK: - Touch Handling

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    // Come bet OddsBetStack gets first priority
    if let stack = comeBetStack {
      let stackPoint = convert(point, to: stack)
      if let hitView = stack.hitTest(stackPoint, with: event) {
        return hitView
      }
    }

    // Lay bet chip
    if layBetChip.amount > 0 {
      let layChipPoint = convert(point, to: layBetChip)
      let expandedLayBounds = layBetChip.bounds.insetBy(dx: -5, dy: -5)
      if expandedLayBounds.contains(layChipPoint) {
        return layBetChip
      }
    }

    // Place bet chip (inherited betView)
    if betView.amount > 0 {
      let betViewPoint = convert(point, to: betView)
      let expandedBetBounds = betView.bounds.insetBy(dx: -5, dy: -5)
      if expandedBetBounds.contains(betViewPoint) {
        return betView
      }
    }

    // Zone routing via backgroundContainer coordinate space
    let containerPoint = convert(point, to: backgroundContainer)
    let stackPoint = backgroundContainer.convert(containerPoint, to: zoneStack)
    if layZoneView.frame.contains(stackPoint) {
      return layZoneView
    }
    if placeZoneView.frame.contains(stackPoint) {
      return placeZoneView
    }

    return super.hitTest(point, with: event)
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    if layBetChip.amount > 0 {
      let layPoint = convert(point, to: layBetChip)
      if layBetChip.bounds.insetBy(dx: -10, dy: -10).contains(layPoint) {
        return true
      }
    }
    if betView.amount > 0 {
      let bvPoint = convert(point, to: betView)
      if betView.bounds.insetBy(dx: -10, dy: -10).contains(bvPoint) {
        return true
      }
    }
    if let stack = comeBetStack {
      let stackPoint = convert(point, to: stack)
      if stack.bounds.insetBy(dx: -10, dy: -10).contains(stackPoint) {
        return true
      }
    }
    return super.point(inside: point, with: event)
  }
}

// MARK: - UIGestureRecognizerDelegate

extension PointControl: UIGestureRecognizerDelegate {
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    if gestureRecognizer is UILongPressGestureRecognizer {
      return true
    }
    return false
  }
}
