//
//  SpecialtyControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 3/18/26.
//

import UIKit

/// A PlainControl with configurable title and subtitle.
/// Used for specialty bets like Make Em All and Any Horn that display
/// a primary label and secondary odds/info label.
class SpecialtyControl: PlainControl {

  /// Use same height as MultiBetControl (58pt iPhone, 78pt iPad)
  override var wantsDefaultHeightConstraint: Bool { return false }

  override var usesCustomTitleLayout: Bool { return true }

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 16, weight: .regular)
    label.textColor = HardwayColors.label
    return label
  }()

  private let subtitleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = HardwayColors.label.withAlphaComponent(0.5)
    return label
  }()

  private let labelStack: UIStackView = {
    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 2
    stack.alignment = .center
    stack.isUserInteractionEnabled = false
    return stack
  }()

  private var labelStackCenterYConstraint: NSLayoutConstraint?

  var specialtyTitle: String? {
    get { titleLabel.text }
    set { titleLabel.text = newValue }
  }

  var specialtySubtitle: String? {
    get { subtitleLabel.text }
    set { subtitleLabel.text = newValue }
  }

  /// - Parameter usesFixedControlHeight: When false, no height constraint is applied; pin height externally (e.g. horn row).
  init(title: String, subtitle: String?, usesFixedControlHeight: Bool = true) {
    super.init(title: nil)
    shouldAnimateTitleShift = false
    self.titleLabel.text = title
    if let subtitle {
      self.subtitleLabel.text = subtitle
    }

    setupStyle(usesFixedControlHeight: usesFixedControlHeight)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupStyle(usesFixedControlHeight: Bool) {
    backgroundColor = HardwayColors.surfaceGray
    layer.cornerRadius = 16
    clipsToBounds = false

    labelStack.addArrangedSubview(titleLabel)
    if subtitleLabel.text != nil {
      labelStack.addArrangedSubview(subtitleLabel)
    }

    addSubview(labelStack)

    labelStackCenterYConstraint = labelStack.centerYAnchor.constraint(equalTo: centerYAnchor)

    let controlHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 78 : 58
    var constraints: [NSLayoutConstraint] = [
      labelStack.centerXAnchor.constraint(equalTo: centerXAnchor),
      labelStackCenterYConstraint!,
    ]
    if usesFixedControlHeight {
      constraints.append(heightAnchor.constraint(equalToConstant: controlHeight))
    }
    NSLayoutConstraint.activate(constraints)
  }

  override func configureBetViewConstraints() {
    NSLayoutConstraint.activate([
      betView.centerXAnchor.constraint(equalTo: centerXAnchor),
      betView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
    ])
  }

  // MARK: - Content Shift

  override func betAmountDidChange() {
    let hasBet = betAmount > 0
    let targetOffset: CGFloat = hasBet ? -16 : 0

    guard labelStackCenterYConstraint?.constant != targetOffset else { return }

    UIView.animate(
      withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 1.0,
      options: [.curveEaseInOut, .allowUserInteraction]
    ) {
      self.labelStackCenterYConstraint?.constant = targetOffset
      self.layoutIfNeeded()
    }
  }
}
