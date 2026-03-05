//
//  PlayerSeat.swift
//  hardway-craps
//
//  A seat representing one player: name, balance, and 1–N blackjack hands (split support).
//  Layout inspired by BlackjackHandPlayground (balance above horizontal hand stack).
//

import UIKit

final class PlayerSeat: UIView {

  // MARK: - Constants

  static let maxHandsPerSeat = 4
  private static let handSpacing: CGFloat = 16
  private static let singleHandWidth: CGFloat = 180
  private static let seatHeight: CGFloat = 170

  // MARK: - Subviews

  private let balanceView: MPPlayerBalanceView = {
    let v = MPPlayerBalanceView()
    v.translatesAutoresizingMaskIntoConstraints = false
    return v
  }()

  private lazy var readyCheckmarkView: UIView = {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.isUserInteractionEnabled = false

    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
    let image = UIImage(systemName: "checkmark", withConfiguration: config)
    let iv = UIImageView(image: image)
    iv.translatesAutoresizingMaskIntoConstraints = false
    iv.tintColor = .white
    iv.contentMode = .scaleAspectFit
    container.addSubview(iv)

    NSLayoutConstraint.activate([
      iv.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      iv.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      iv.widthAnchor.constraint(equalToConstant: 20),
      iv.heightAnchor.constraint(equalToConstant: 20),
    ])

    container.alpha = 0
    container.isHidden = true
    return container
  }()

  private let handsStackView: UIStackView = {
    let v = UIStackView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.axis = .horizontal
    v.alignment = .bottom
    v.distribution = .fillEqually
    v.spacing = 16
    return v
  }()

  private let primaryHandView: CompactPlayerHandView
  private var additionalHandViews: [CompactPlayerHandView] = []

  // Split hand indicator lines
  private let leftLineView: UIView = {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.backgroundColor = UIColor.white.withAlphaComponent(0.2)
    v.isHidden = true
    return v
  }()

  private let rightLineView: UIView = {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.backgroundColor = UIColor.white.withAlphaComponent(0.2)
    v.isHidden = true
    return v
  }()

  // MARK: - Public

  /// Chip style for this player's bet controls
  var chipStyle: MPSmallBetChipStyle

  /// When true, seat is read-only (remote player): bet control visible but disabled, hand can spread but not tap.
  var isRemote: Bool = false {
    didSet {
      for hand in hands {
        hand.betControl.isUserInteractionEnabled = !isRemote
        setRemoteOpacity(for: hand.betControl, isRemote: isRemote)
        if isRemote {
          hand.canTap = { false }
        }
      }
    }
  }

  /// Display name for this seat (e.g. "You" or "Colton S.").
  var nameText: String {
    get { balanceView.nameText }
    set { balanceView.nameText = newValue }
  }

  /// Update balance display; use animated: true for changes from network/sync.
  func setBalance(_ balance: Int?, animated: Bool) {
    balanceView.setBalance(balance, animated: animated)
  }

  /// The first (main) hand. Use for deal, hit, stand, etc.
  var primaryHand: CompactPlayerHandView {
    primaryHandView
  }

  /// All hands (primary + any split hands), in play order.
  var hands: [CompactPlayerHandView] {
    [primaryHandView] + additionalHandViews
  }

  /// Show or hide the ready checkmark over the card area.
  func showReadyCheckmark(_ show: Bool, animated: Bool = true) {
    if show {
      readyCheckmarkView.isHidden = false
      if animated {
        readyCheckmarkView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(
          withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8,
          options: .curveEaseOut
        ) {
          self.readyCheckmarkView.alpha = 1
          self.readyCheckmarkView.transform = .identity
        }
      } else {
        readyCheckmarkView.alpha = 1
        readyCheckmarkView.transform = .identity
      }
    } else {
      if animated {
        UIView.animate(
          withDuration: 0.2,
          animations: {
            self.readyCheckmarkView.alpha = 0
            self.readyCheckmarkView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
          }
        ) { _ in
          self.readyCheckmarkView.isHidden = true
          self.readyCheckmarkView.transform = .identity
        }
      } else {
        readyCheckmarkView.alpha = 0
        readyCheckmarkView.isHidden = true
      }
    }
  }

  /// Add an additional hand at a given index (e.g. after split). Returns the new hand view.
  @discardableResult
  func addHand(at index: Int? = nil, chipStyle style: MPSmallBetChipStyle? = nil)
    -> CompactPlayerHandView
  {
    let handView = CompactPlayerHandView(mpChipStyle: style ?? chipStyle)
    handView.translatesAutoresizingMaskIntoConstraints = false
    handView.betControl.isUserInteractionEnabled = !isRemote
    if isRemote {
      handView.canTap = { false }
      setRemoteOpacity(for: handView.betControl, isRemote: true)
    }

    let insertionIndex = (index ?? additionalHandViews.count)
    additionalHandViews.insert(handView, at: insertionIndex)

    let stackIndex = insertionIndex + 1
    handsStackView.insertArrangedSubview(
      handView, at: min(stackIndex, handsStackView.arrangedSubviews.count))
    updateHandsStackWidth()
    updateSplitHandIndicators()
    return handView
  }

  /// Remove a specific additional hand by index (0-based among additional hands).
  func removeAdditionalHand(at index: Int) {
    guard index >= 0 && index < additionalHandViews.count else { return }
    let view = additionalHandViews.remove(at: index)
    handsStackView.removeArrangedSubview(view)
    view.removeFromSuperview()
    updateHandsStackWidth()
    updateSplitHandIndicators()
  }

  /// Remove all additional (split) hands, restoring single-hand layout.
  func removeAllAdditionalHands() {
    for view in additionalHandViews {
      handsStackView.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    additionalHandViews.removeAll()
    updateHandsStackWidth()
    updateSplitHandIndicators()
  }

  // Legacy compatibility
  func addSecondHand(_ handView: CompactPlayerHandView) {
    guard additionalHandViews.isEmpty else { return }
    handView.translatesAutoresizingMaskIntoConstraints = false
    handView.betControl.isUserInteractionEnabled = !isRemote
    if isRemote {
      handView.canTap = { false }
      setRemoteOpacity(for: handView.betControl, isRemote: true)
    }
    additionalHandViews.append(handView)
    handsStackView.addArrangedSubview(handView)
    updateHandsStackWidth()
    updateSplitHandIndicators()
  }

  func removeSecondHand() {
    removeAllAdditionalHands()
  }

  // MARK: - Init

  init(chipStyle: MPSmallBetChipStyle = .yellow) {
    self.chipStyle = chipStyle
    self.primaryHandView = CompactPlayerHandView(mpChipStyle: chipStyle)
    super.init(frame: .zero)
    setupView()
  }

  convenience override init(frame: CGRect) {
    self.init(chipStyle: .yellow)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    primaryHandView.translatesAutoresizingMaskIntoConstraints = false
    handsStackView.addArrangedSubview(primaryHandView)

    addSubview(balanceView)
    addSubview(handsStackView)
    addSubview(readyCheckmarkView)
    addSubview(leftLineView)
    addSubview(rightLineView)

    handsStackViewWidthConstraint = handsStackView.widthAnchor.constraint(
      equalToConstant: Self.singleHandWidth)

    NSLayoutConstraint.activate([
      handsStackView.topAnchor.constraint(equalTo: topAnchor),
      handsStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
      handsStackView.heightAnchor.constraint(equalToConstant: Self.seatHeight),
      handsStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
      handsStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
      handsStackViewWidthConstraint!,

      readyCheckmarkView.topAnchor.constraint(equalTo: handsStackView.topAnchor),
      readyCheckmarkView.leadingAnchor.constraint(equalTo: handsStackView.leadingAnchor),
      readyCheckmarkView.trailingAnchor.constraint(equalTo: handsStackView.trailingAnchor),
      readyCheckmarkView.bottomAnchor.constraint(equalTo: handsStackView.bottomAnchor),

      balanceView.topAnchor.constraint(equalTo: handsStackView.bottomAnchor, constant: 8),
      balanceView.centerXAnchor.constraint(equalTo: centerXAnchor),
      balanceView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
      balanceView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
      balanceView.bottomAnchor.constraint(equalTo: bottomAnchor),

      // Left line: from balance view leading to hands stack leading
      leftLineView.centerYAnchor.constraint(equalTo: balanceView.centerYAnchor),
      leftLineView.leadingAnchor.constraint(equalTo: handsStackView.leadingAnchor, constant: 20),
      leftLineView.trailingAnchor.constraint(equalTo: balanceView.leadingAnchor, constant: -12),
      leftLineView.heightAnchor.constraint(equalToConstant: 1),

      // Right line: from balance view trailing to hands stack trailing
      rightLineView.centerYAnchor.constraint(equalTo: balanceView.centerYAnchor),
      rightLineView.leadingAnchor.constraint(equalTo: balanceView.trailingAnchor, constant: 12),
      rightLineView.trailingAnchor.constraint(
        equalTo: handsStackView.trailingAnchor, constant: -20),
      rightLineView.heightAnchor.constraint(equalToConstant: 1),
    ])
  }

  private var handsStackViewWidthConstraint: NSLayoutConstraint!

  /// External width constraint (set by the VC). Updated automatically when hands are added/removed.
  private var externalWidthConstraint: NSLayoutConstraint?

  /// The preferred width of this seat given its current hand count.
  var preferredWidth: CGFloat {
    let count = hands.count
    if count <= 1 { return Self.singleHandWidth }
    return Self.singleHandWidth * CGFloat(count) + Self.handSpacing * CGFloat(count - 1)
  }

  /// Install (or replace) a width constraint on this seat, kept in sync with hand count.
  func installWidthConstraint(constant: CGFloat) {
    externalWidthConstraint?.isActive = false
    let c = widthAnchor.constraint(equalToConstant: constant)
    c.isActive = true
    externalWidthConstraint = c
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateHandsStackWidth()
    updateSplitHandIndicators()
  }

  private func updateSplitHandIndicators() {
    let hasSplitHands = hands.count > 1
    leftLineView.isHidden = !hasSplitHands
    rightLineView.isHidden = !hasSplitHands
  }

  private func updateHandsStackWidth() {
    let newWidth = preferredWidth
    // Update external seat width first so the seat expands before the inner stack lays out
    if let ext = externalWidthConstraint, ext.constant != newWidth {
      ext.constant = newWidth
    }
    handsStackViewWidthConstraint.constant = newWidth
  }

  /// Set opacity for remote player bet controls: control at 50%, chip at 100%
  private func setRemoteOpacity(for betControl: PlainControl, isRemote: Bool) {
    if isRemote {
      betControl.alpha = 0.5
      betControl.betView.alpha = 1.0
    } else {
      betControl.alpha = 1.0
      betControl.betView.alpha = 1.0
    }
  }
}
