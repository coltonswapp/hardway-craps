//
//  GameSessionEmptyStateView.swift
//  hardway-craps
//
//  Empty list state for game session picker pages: SF Symbol, title, and subtitle.
//

import UIKit

/// Shown when a game page has no saved sessions: icon, game title, and short description.
struct GameSessionEmptyStateContent {
  let iconSystemName: String
  let title: String
  let subtitle: String
}

final class GameSessionEmptyStateView: UIView {

  private let iconConfiguration: UIImage.SymbolConfiguration = {
    let font = UIFont.systemFont(ofSize: 52, weight: .medium)
    return UIImage.SymbolConfiguration(font: font)
  }()

  private let iconView: UIImageView = {
    let iv = UIImageView()
    iv.translatesAutoresizingMaskIntoConstraints = false
    iv.contentMode = .scaleAspectFit
    iv.tintColor = UIColor.white.withAlphaComponent(0.42)
    return iv
  }()

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 20, weight: .semibold)
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    return label
  }()

  private let subtitleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 15, weight: .regular)
    label.textColor = HardwayColors.label
    label.textAlignment = .center
    label.numberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    return label
  }()

  private let stack: UIStackView = {
    let s = UIStackView()
    s.translatesAutoresizingMaskIntoConstraints = false
    s.axis = .vertical
    s.alignment = .center
    s.spacing = 12
    return s
  }()

  /// Target column width on typical phones; shrinks automatically when margins leave less space.
  private static let textColumnMaxWidth: CGFloat = 248

  private var centerYConstraint: NSLayoutConstraint?
  private let stackWidthConstraint: NSLayoutConstraint

  init(content: GameSessionEmptyStateContent) {
    stackWidthConstraint = stack.widthAnchor.constraint(equalToConstant: Self.textColumnMaxWidth)

    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    isUserInteractionEnabled = false
    backgroundColor = .clear
    directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 28, bottom: 0, trailing: 28)

    configure(content: content)

    stack.addArrangedSubview(iconView)
    stack.addArrangedSubview(titleLabel)
    stack.addArrangedSubview(subtitleLabel)
    stack.setCustomSpacing(16, after: iconView)

    addSubview(stack)

    let cy = stack.centerYAnchor.constraint(equalTo: centerYAnchor)
    centerYConstraint = cy

    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      cy,
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
      stackWidthConstraint,
      iconView.widthAnchor.constraint(equalToConstant: 64),
      iconView.heightAnchor.constraint(equalToConstant: 64),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let marginTotal = directionalLayoutMargins.leading + directionalLayoutMargins.trailing
    let cw = floor(min(Self.textColumnMaxWidth, bounds.width - marginTotal))
    let clamped = max(148, cw)
    stackWidthConstraint.constant = clamped
    titleLabel.preferredMaxLayoutWidth = clamped
    subtitleLabel.preferredMaxLayoutWidth = clamped
  }

  func configure(content: GameSessionEmptyStateContent) {
    iconView.image = UIImage(systemName: content.iconSystemName, withConfiguration: iconConfiguration)
    titleLabel.text = content.title
    subtitleLabel.text = content.subtitle
  }

  /// Nudges the stack toward the visible “list” center when the table uses asymmetric content insets (tab bar + bottom CTA).
  func setVerticalCenterOffset(_ offset: CGFloat) {
    centerYConstraint?.constant = offset
  }
}
