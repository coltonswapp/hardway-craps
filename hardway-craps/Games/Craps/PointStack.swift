//
//  PointStack.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class PointStack: UIView {

  /// More than six point numbers (crapless): top row 2–6, bottom row 8–12. Standard six points stay one row.
  private let rootStack: UIStackView = {
    let sv = UIStackView()
    sv.translatesAutoresizingMaskIntoConstraints = false
    sv.axis = .horizontal
    sv.distribution = .fillEqually
    sv.alignment = .fill
    sv.spacing = 8
    return sv
  }()

  private var pointControls: [PointControl] = []
  private let puck = Puck()
  private var puckCenterXConstraint: NSLayoutConstraint?
  private var puckCenterYConstraint: NSLayoutConstraint?
  private var twoRowMinimumHeightConstraint: NSLayoutConstraint?

  /// Resting puck position when no point (OFF), in PointStack coordinates.
  private let puckRestCenterX: CGFloat = 0
  private let puckRestCenterY: CGFloat = 12

  private(set) var pointNumbers: [Int]

  private(set) var currentPoint: Int?

  var getSelectedChipValue: (() -> Int)?
  var getBalance: (() -> Int)?
  var onBetPlaced: ((Int) -> Void)?
  var onBetRemoved: ((Int) -> Void)?
  var onComeBetOddsPlaced: ((Int, Int, Int) -> Void)?  // (amount, previousOddsAmount, pointNumber)
  var onComeBetOddsRemoved: ((Int) -> Void)?
  var onLayBetPlaced: ((Int) -> Void)?
  var onLayBetRemoved: ((Int) -> Void)?

  init(pointNumbers: [Int] = [4, 5, 6, 8, 9, 10]) {
    self.pointNumbers = pointNumbers
    super.init(frame: .zero)
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    addSubview(rootStack)
    addSubview(puck)

    puckCenterXConstraint = puck.centerXAnchor.constraint(equalTo: leadingAnchor, constant: puckRestCenterX)
    puckCenterYConstraint = puck.centerYAnchor.constraint(equalTo: topAnchor, constant: puckRestCenterY)

    setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
    setContentCompressionResistancePriority(.defaultLow, for: .vertical)

    rootStack.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
    rootStack.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

    NSLayoutConstraint.activate([
      rootStack.topAnchor.constraint(equalTo: topAnchor),
      rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
      rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
      rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),

      puckCenterYConstraint!,
      puckCenterXConstraint!,
    ])

    setupPointControls()
  }

  /// True when points are shown as two horizontal rows (low / high split at 7).
  private static func usesTwoRowLayout(for numbers: [Int]) -> Bool {
    guard numbers.count > 6 else { return false }
    let low = numbers.filter { $0 < 7 }
    let high = numbers.filter { $0 > 7 }
    return !low.isEmpty && !high.isEmpty
  }

  private func makeHorizontalRowStack() -> UIStackView {
    let row = UIStackView()
    row.translatesAutoresizingMaskIntoConstraints = false
    row.axis = .horizontal
    row.distribution = .fillEqually
    row.alignment = .fill
    row.spacing = 8
    row.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
    row.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return row
  }

  private func makePointControl(number: Int) -> PointControl {
    let pointControl = PointControl(pointNumber: number)
    pointControl.translatesAutoresizingMaskIntoConstraints = false
    pointControl.setContentHuggingPriority(.defaultLow, for: .vertical)
    pointControl.getSelectedChipValue = { [weak self] in
      self?.getSelectedChipValue?() ?? 1
    }
    pointControl.getBalance = { [weak self] in
      self?.getBalance?() ?? 200
    }
    pointControl.onBetPlaced = { [weak self] amount in
      self?.onBetPlaced?(amount)
    }
    pointControl.onBetRemoved = { [weak self] amount in
      self?.onBetRemoved?(amount)
    }
    pointControl.onComeBetOddsPlaced = { [weak self] amount, previousOddsAmount, pointNumber in
      self?.onComeBetOddsPlaced?(amount, previousOddsAmount, pointNumber)
    }
    pointControl.onComeBetOddsRemoved = { [weak self] amount in
      self?.onComeBetOddsRemoved?(amount)
    }
    pointControl.onLayBetPlaced = { [weak self] amount in
      self?.onLayBetPlaced?(amount)
    }
    pointControl.onLayBetRemoved = { [weak self] amount in
      self?.onLayBetRemoved?(amount)
    }
    return pointControl
  }

  private func clearStackAndControls() {
    for pc in pointControls {
      pc.removeFromSuperview()
    }
    pointControls.removeAll()

    for sub in rootStack.arrangedSubviews {
      rootStack.removeArrangedSubview(sub)
      sub.removeFromSuperview()
    }
  }

  private func setupPointControls() {
    clearStackAndControls()

    twoRowMinimumHeightConstraint?.isActive = false
    twoRowMinimumHeightConstraint = nil

    let twoRows = Self.usesTwoRowLayout(for: pointNumbers)

    if twoRows {
      let minH = heightAnchor.constraint(greaterThanOrEqualToConstant: 168)
      minH.priority = .required
      minH.isActive = true
      twoRowMinimumHeightConstraint = minH
      rootStack.axis = .vertical
      rootStack.distribution = .fillEqually
      rootStack.spacing = 8

      let topRow = makeHorizontalRowStack()
      let bottomRow = makeHorizontalRowStack()

      let topNums = pointNumbers.filter { $0 < 7 }
      let bottomNums = pointNumbers.filter { $0 > 7 }

      for number in topNums {
        let pointControl = makePointControl(number: number)
        pointControls.append(pointControl)
        topRow.addArrangedSubview(pointControl)
        pointControl.heightAnchor.constraint(equalTo: topRow.heightAnchor).isActive = true
      }

      for number in bottomNums {
        let pointControl = makePointControl(number: number)
        pointControls.append(pointControl)
        bottomRow.addArrangedSubview(pointControl)
        pointControl.heightAnchor.constraint(equalTo: bottomRow.heightAnchor).isActive = true
      }

      rootStack.addArrangedSubview(topRow)
      rootStack.addArrangedSubview(bottomRow)
    } else {
      rootStack.axis = .horizontal
      rootStack.distribution = .fillEqually
      rootStack.spacing = 8

      for number in pointNumbers {
        let pointControl = makePointControl(number: number)
        pointControls.append(pointControl)
        rootStack.addArrangedSubview(pointControl)
        pointControl.heightAnchor.constraint(equalTo: rootStack.heightAnchor).isActive = true
      }
    }
  }

  func setPointNumbers(_ pointNumbers: [Int]) {
    guard self.pointNumbers != pointNumbers else { return }
    self.pointNumbers = pointNumbers
    currentPoint = nil
    puck.isOn = false

    setupPointControls()
    setNeedsLayout()
    layoutIfNeeded()
  }

  func setPoint(_ number: Int) {
    currentPoint = number
    pointControls.forEach { $0.isOn = false }
    if let pointControl = pointControls.first(where: { $0.pointNumber == number }) {
      pointControl.isOn = true
      movePuckToPoint(pointControl, animated: true)
    }
  }

  func clearPoint() {
    currentPoint = nil
    pointControls.forEach { $0.isOn = false }
    puck.isOn = false

    puckCenterXConstraint?.constant = puckRestCenterX
    puckCenterYConstraint?.constant = puckRestCenterY

    UIView.animate(
      withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5,
      options: .curveEaseInOut
    ) {
      self.layoutIfNeeded()
    }
  }

  func getPointControl(for number: Int) -> PointControl? {
    return pointControls.first { $0.pointNumber == number }
  }

  private func movePuckToPoint(_ pointControl: PointControl, animated: Bool) {
    guard let xConstraint = puckCenterXConstraint, let yConstraint = puckCenterYConstraint else { return }

    puck.isHidden = false
    puck.isOn = true

    // Point controls live inside nested row stack views; convert to PointStack coords.
    // Y: puck center aligns with the point control’s top (not its vertical center).
    let pos = pointControl.puckCenterPosition(in: self)
    xConstraint.constant = pos.x
    yConstraint.constant = pos.y

    if animated {
      UIView.animate(
        withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5,
        options: .curveEaseInOut
      ) {
        self.layoutIfNeeded()
      }
    } else {
      layoutIfNeeded()
    }
  }

  // MARK: - Come Bet Convenience Methods

  func clearAllComeBets() {
    for pointControl in pointControls {
      if pointControl.hasComeBet {
        pointControl.clearComeBet()
      }
    }
  }

  func getComeBetTotal() -> Int {
    return pointControls.reduce(0) { $0 + $1.comeBetAmount + $1.comeBetOddsAmount }
  }

  func getPointControlsWithComeBets() -> [PointControl] {
    return pointControls.filter { $0.hasComeBet }
  }

  // MARK: - Lay Bet Convenience Methods

  func clearAllLayBets() {
    for pointControl in pointControls {
      if pointControl.hasLayBet {
        pointControl.clearLayBet()
      }
    }
  }

  func clearAllLayBetsSilently() {
    for pointControl in pointControls {
      if pointControl.hasLayBet {
        pointControl.clearLayBetSilently()
      }
    }
  }

  func getLayBetTotal() -> Int {
    return pointControls.reduce(0) { $0 + $1.layBetAmount }
  }

  func getPointControlsWithLayBets() -> [PointControl] {
    return pointControls.filter { $0.hasLayBet }
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if let activePoint = pointControls.first(where: { $0.isOn }) {
      movePuckToPoint(activePoint, animated: false)
    }
  }
}
