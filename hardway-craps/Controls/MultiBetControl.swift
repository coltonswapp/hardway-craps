//
//  MultiBetControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/23/25.
//

import UIKit

class MultiBetControl: PlainControl {

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .left
    label.font = .systemFont(ofSize: 16, weight: .regular)
    label.textColor = HardwayColors.label
    return label
  }()

  var controlTitle: String? {
    get { titleLabel.text }
    set { titleLabel.text = newValue }
  }

  private let oddsLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .left
    label.font = .systemFont(ofSize: 12, weight: .regular)
    label.textColor = HardwayColors.label.withAlphaComponent(0.5)
    return label
  }()

  private let numbersStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .horizontal
    stackView.spacing = 4
    stackView.alignment = .center
    stackView.distribution = .fillEqually
    stackView.isUserInteractionEnabled = false
    return stackView
  }()

  /// Top row: title + odds side by side
  private let titleStack: UIStackView = {
    let stackView = UIStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .horizontal
    stackView.spacing = 6
    stackView.alignment = .firstBaseline
    stackView.distribution = .fill
    stackView.isUserInteractionEnabled = false
    return stackView
  }()

  /// Vertical stack: titleStack on top, numbers below
  private let mainStack: UIStackView = {
    let stackView = UIStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.spacing = 2
    stackView.alignment = .center
    stackView.distribution = .fill
    stackView.isUserInteractionEnabled = false
    return stackView
  }()

  private var numberViews: [NumberView] = []
  private var mainStackCenterYConstraint: NSLayoutConstraint?

  let numbers: [Int]
  let odds: String
  private(set) var hitNumbers: Set<Int> = []

  init(title: String, numbers: [Int], odds: String) {
    self.numbers = numbers
    self.odds = odds
    super.init(title: nil)

    // Remove PlainControl's default height constraint (50pt iPhone, 65pt iPad)
    var heightConstraintsToRemove: [NSLayoutConstraint] = []
    for constraint in constraints {
      if constraint.firstAttribute == .height && constraint.firstItem === self {
        heightConstraintsToRemove.append(constraint)
      }
    }
    NSLayoutConstraint.deactivate(heightConstraintsToRemove)

    setupMultiBetView(title: title)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupMultiBetView(title: String) {
    titleLabel.text = title
    oddsLabel.text = odds

    // Style the control to match SmallControl
    backgroundColor = HardwayColors.surfaceGray
    layer.cornerRadius = 16
    clipsToBounds = false

    // Create number views for each number (compact size to fit in 60% column)
    let numberSize: CGFloat = 18
    for number in numbers {
      let numberView = NumberView(number: number, size: numberSize)
      numberViews.append(numberView)
      numbersStackView.addArrangedSubview(numberView)

      NSLayoutConstraint.activate([
        numberView.widthAnchor.constraint(equalToConstant: numberSize),
        numberView.heightAnchor.constraint(equalToConstant: numberSize),
      ])
    }

    // Top row: title + odds inline
    titleStack.addArrangedSubview(titleLabel)
    titleStack.addArrangedSubview(oddsLabel)

    // Main stack: title row on top, numbers below
    mainStack.addArrangedSubview(titleStack)
    mainStack.addArrangedSubview(numbersStackView)

    addSubview(mainStack)

    mainStackCenterYConstraint = mainStack.centerYAnchor.constraint(equalTo: centerYAnchor)

    NSLayoutConstraint.activate([
      mainStack.centerXAnchor.constraint(equalTo: centerXAnchor),
      mainStackCenterYConstraint!,
      mainStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
      mainStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

      numbersStackView.heightAnchor.constraint(equalToConstant: 18),

      // Device-specific control height: iPhone 58pt, iPad 78pt (taller to fit stacked title + numbers)
      heightAnchor.constraint(
        equalToConstant: UIDevice.current.userInterfaceIdiom == .pad ? 78 : 58),
    ])

    titleLabel.setContentHuggingPriority(.required, for: .horizontal)
    oddsLabel.setContentHuggingPriority(.required, for: .horizontal)
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
    let targetOffset: CGFloat = hasBet ? -12 : 0

    guard mainStackCenterYConstraint?.constant != targetOffset else { return }

    UIView.animate(
      withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 1.0,
      options: [.curveEaseInOut, .allowUserInteraction]
    ) {
      self.mainStackCenterYConstraint?.constant = targetOffset
      self.layoutIfNeeded()
    }
  }

  /// Mark a number as hit
  func markNumberAsHit(_ number: Int) {
    guard numbers.contains(number) else { return }
    hitNumbers.insert(number)
    updateNumberViews()
  }

  /// Reset all hit numbers (e.g., when bet is won or lost)
  func resetHitNumbers() {
    hitNumbers.removeAll()
    updateNumberViews()
  }

  /// Check if all numbers have been hit (bet is complete)
  var isComplete: Bool {
    return hitNumbers.count == numbers.count
  }

  private func updateNumberViews() {
    for numberView in numberViews {
      let isHit = hitNumbers.contains(numberView.number)
      numberView.setHit(isHit)
    }
  }
}

// MARK: - NumberView

class NumberView: UIView {

  private let numberLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 10, weight: .regular)
    label.textColor = HardwayColors.label
    label.backgroundColor = .clear
    return label
  }()

  private let checkmarkLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 8, weight: .regular)
    label.textColor = .white
    label.text = "✓"
    label.isHidden = true
    return label
  }()

  let number: Int
  private let circleSize: CGFloat

  init(number: Int, size: CGFloat = 20) {
    self.number = number
    self.circleSize = size
    super.init(frame: .zero)
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    numberLabel.text = "\(number)"
    numberLabel.font = .systemFont(ofSize: circleSize * 0.5, weight: .regular)

    numberLabel.layer.cornerRadius = circleSize / 2
    numberLabel.layer.borderWidth = circleSize > 18 ? 2 : 1.5
    numberLabel.layer.borderColor = HardwayColors.label.withAlphaComponent(0.5).cgColor
    numberLabel.clipsToBounds = true

    checkmarkLabel.font = .systemFont(ofSize: circleSize * 0.4, weight: .regular)

    addSubview(numberLabel)
    addSubview(checkmarkLabel)

    NSLayoutConstraint.activate([
      numberLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      numberLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      numberLabel.widthAnchor.constraint(equalToConstant: circleSize),
      numberLabel.heightAnchor.constraint(equalToConstant: circleSize),

      // Checkmark label - centered on number label
      checkmarkLabel.centerXAnchor.constraint(equalTo: numberLabel.centerXAnchor),
      checkmarkLabel.centerYAnchor.constraint(equalTo: numberLabel.centerYAnchor),
    ])
  }

  func setHit(_ isHit: Bool) {
    if isHit {
      numberLabel.backgroundColor = .systemBlue
      numberLabel.layer.borderColor = UIColor.systemBlue.cgColor
      numberLabel.textColor = .white
    } else {
      numberLabel.backgroundColor = .clear
      numberLabel.layer.borderColor = HardwayColors.label.withAlphaComponent(0.5).cgColor
      numberLabel.textColor = HardwayColors.label
    }
  }
}
