//
//  PointStack.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class PointStack: UIView {

    private let stackView: UIStackView = {
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

    let pointNumbers = [4, 5, 6, 8, 9, 10]

    private(set) var currentPoint: Int?

    var getSelectedChipValue: (() -> Int)?
    var getBalance: (() -> Int)?
    var onBetPlaced: ((Int) -> Void)?
    var onBetRemoved: ((Int) -> Void)?
    var onComeBetOddsPlaced: ((Int, Int, Int) -> Void)?  // (amount, previousOddsAmount, pointNumber)
    var onComeBetOddsRemoved: ((Int) -> Void)?

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(stackView)
        addSubview(puck)

        puckCenterXConstraint = puck.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 8)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            puck.centerYAnchor.constraint(equalTo: topAnchor, constant: 12),
            puckCenterXConstraint!
        ])

        setupPointControls()
        // Puck starts visible but in OFF state
    }

    private func setupPointControls() {
        for number in pointNumbers {
            let pointControl = PointControl(pointNumber: number)
            pointControl.translatesAutoresizingMaskIntoConstraints = false
            // Set low content hugging priority so PointControls can expand vertically
            pointControl.setContentHuggingPriority(.defaultLow, for: .vertical)
            pointControl.getSelectedChipValue = { [weak self] in
                return self?.getSelectedChipValue?() ?? 1
            }
            pointControl.getBalance = { [weak self] in
                return self?.getBalance?() ?? 200
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

            pointControls.append(pointControl)
            stackView.addArrangedSubview(pointControl)
        }
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

        // Move puck back to resting position (left edge)
        guard let constraint = puckCenterXConstraint else { return }
        constraint.constant = 0

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.layoutIfNeeded()
        }
    }

    func getPointControl(for number: Int) -> PointControl? {
        return pointControls.first { $0.pointNumber == number }
    }

    private func movePuckToPoint(_ pointControl: PointControl, animated: Bool) {
        guard let constraint = puckCenterXConstraint else { return }

        puck.isHidden = false
        puck.isOn = true

        // Calculate the center X position of the point control
        let pointCenterX = pointControl.frame.midX

        constraint.constant = pointCenterX

        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                self.layoutIfNeeded()
            }
        } else {
            layoutIfNeeded()
        }
    }

    // MARK: - Come Bet Convenience Methods
    
    /// Clears all come bets from all point controls (used on seven-out)
    func clearAllComeBets() {
        for pointControl in pointControls {
            if pointControl.hasComeBet {
                pointControl.clearComeBet()
            }
        }
    }
    
    /// Returns the total come bet amount across all point controls (bet + odds)
    func getComeBetTotal() -> Int {
        return pointControls.reduce(0) { $0 + $1.comeBetAmount + $1.comeBetOddsAmount }
    }
    
    /// Returns all point controls that currently have a come bet
    func getPointControlsWithComeBets() -> [PointControl] {
        return pointControls.filter { $0.hasComeBet }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        // Update puck position if a point is active
        if let activePoint = pointControls.first(where: { $0.isOn }) {
            movePuckToPoint(activePoint, animated: false)
        }
    }
}
