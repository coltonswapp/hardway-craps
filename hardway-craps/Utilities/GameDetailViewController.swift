//
//  GameDetailViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/14/26.
//

import UIKit
import SwiftUI

final class GameDetailViewController: UIViewController {
    private let session: GameSession
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private var chartHostingController: UIHostingController<GameDetailChartView>?
    private let canContinueSession: Bool
    var onContinueSession: (() -> Void)?

    // CTA container components
    private let ctaContainer = UIView()
    private var continueButton: NNPrimaryLabeledButton?
    private var visualEffectView: UIVisualEffectView?

    init(session: GameSession, canContinueSession: Bool = false) {
        self.session = session
        self.canContinueSession = canContinueSession
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Game Details"

        setupLayout()
        populateContent()
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .vertical
        stackView.spacing = 16

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    private func populateContent() {
        let headerLabel = UILabel()
        headerLabel.text = session.formattedDate
        headerLabel.textColor = .lightGray
        headerLabel.font = .systemFont(ofSize: 13, weight: .medium)
        stackView.addArrangedSubview(headerLabel)

        let statGrid = UIStackView()
        statGrid.axis = .vertical
        statGrid.spacing = 12

        if session.isBlackjackSession {
            // Blackjack-specific stats
            let row1 = UIStackView()
            row1.axis = .horizontal
            row1.spacing = 12
            row1.distribution = .fillEqually
            row1.addArrangedSubview(StatCardView(title: "Hands", value: "\(session.handCountValue)"))
            row1.addArrangedSubview(StatCardView(title: "Time Playing", value: session.formattedDuration))

            let row2 = UIStackView()
            row2.axis = .horizontal
            row2.spacing = 12
            row2.distribution = .fillEqually
            row2.addArrangedSubview(StatCardView(title: "Win Rate", value: formatPercent(session.winRate)))
            row2.addArrangedSubview(StatCardView(title: "Avg Bet", value: formatCurrency(session.averageBetSize)))

            let row3 = UIStackView()
            row3.axis = .horizontal
            row3.spacing = 12
            row3.distribution = .fillEqually
            row3.addArrangedSubview(StatCardView(title: "Biggest Swing", value: formatCurrency(Double(session.biggestSwing))))
            row3.addArrangedSubview(StatCardView(title: "Time / Hand", value: formatTimePerHand(session.timePerHand)))

            let row4 = UIStackView()
            row4.axis = .horizontal
            row4.spacing = 12
            row4.distribution = .fillEqually
            row4.addArrangedSubview(StatCardView(title: "Wins", value: "\(session.winningHandsCount)"))
            row4.addArrangedSubview(StatCardView(title: "Losses", value: "\(session.losingHandsCount)"))

            let row5 = UIStackView()
            row5.axis = .horizontal
            row5.spacing = 12
            row5.distribution = .fillEqually
            if let metrics = session.blackjackMetrics {
                row5.addArrangedSubview(StatCardView(title: "Blackjacks", value: "\(metrics.blackjacksHit)"))
                row5.addArrangedSubview(StatCardView(title: "Doubles", value: "\(metrics.doublesDown)"))
            } else {
                row5.addArrangedSubview(StatCardView(title: "Blackjacks", value: "0"))
                row5.addArrangedSubview(StatCardView(title: "Doubles", value: "0"))
            }

            let row6 = UIStackView()
            row6.axis = .horizontal
            row6.spacing = 12
            row6.distribution = .fillEqually
            if session.atmVisitsCount > 0 {
                row6.addArrangedSubview(StatCardView(title: "ATM Visits", value: "\(session.atmVisitsCount)"))
                // Add empty spacer to keep layout balanced
                let spacer = UIView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                row6.addArrangedSubview(spacer)
            }

            statGrid.addArrangedSubview(row1)
            statGrid.addArrangedSubview(row2)
            statGrid.addArrangedSubview(row3)
            statGrid.addArrangedSubview(row4)
            statGrid.addArrangedSubview(row5)
            if session.atmVisitsCount > 0 {
                statGrid.addArrangedSubview(row6)
            }
        } else {
            // Craps-specific stats
            let row1 = UIStackView()
            row1.axis = .horizontal
            row1.spacing = 12
            row1.distribution = .fillEqually
            row1.addArrangedSubview(StatCardView(title: "Rolls", value: "\(session.rollCountValue)"))
            row1.addArrangedSubview(StatCardView(title: "Time Rolling", value: session.formattedDuration))

            let row2 = UIStackView()
            row2.axis = .horizontal
            row2.spacing = 12
            row2.distribution = .fillEqually
            row2.addArrangedSubview(StatCardView(title: "Win Rate", value: formatPercent(session.winRate)))
            row2.addArrangedSubview(StatCardView(title: "Avg Bet", value: formatCurrency(session.averageBetSize)))

            let row3 = UIStackView()
            row3.axis = .horizontal
            row3.spacing = 12
            row3.distribution = .fillEqually
            row3.addArrangedSubview(StatCardView(title: "Biggest Swing", value: formatCurrency(Double(session.biggestSwing))))
            row3.addArrangedSubview(StatCardView(title: "Time / Roll", value: formatTimePerRoll(session.timePerRoll)))

            let row4 = UIStackView()
            row4.axis = .horizontal
            row4.spacing = 12
            row4.distribution = .fillEqually
            row4.addArrangedSubview(StatCardView(title: "Win Streak", value: "\(session.longestWinStreak)"))
            row4.addArrangedSubview(StatCardView(title: "Loss Streak", value: "\(session.longestLossStreak)"))

            let row5 = UIStackView()
            row5.axis = .horizontal
            row5.spacing = 12
            row5.distribution = .fillEqually
            row5.addArrangedSubview(StatCardView(title: "Sevens Rolled", value: "\(session.sevensRolledValue)"))
            row5.addArrangedSubview(StatCardView(title: "Points Hit", value: "\(session.pointsHitValue)"))

            let row6 = UIStackView()
            row6.axis = .horizontal
            row6.spacing = 12
            row6.distribution = .fillEqually
            if session.atmVisitsCount > 0 {
                row6.addArrangedSubview(StatCardView(title: "ATM Visits", value: "\(session.atmVisitsCount)"))
                // Add empty spacer to keep layout balanced
                let spacer = UIView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                row6.addArrangedSubview(spacer)
            }

            statGrid.addArrangedSubview(row1)
            statGrid.addArrangedSubview(row2)
            statGrid.addArrangedSubview(row3)
            statGrid.addArrangedSubview(row4)
            statGrid.addArrangedSubview(row5)
            if session.atmVisitsCount > 0 {
                statGrid.addArrangedSubview(row6)
            }
        }

        stackView.addArrangedSubview(statGrid)

        let graphTitle = UILabel()
        graphTitle.text = session.isBlackjackSession ? "Balance Over Hands" : "Balance Over Rolls"
        graphTitle.textColor = .white
        graphTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        stackView.addArrangedSubview(graphTitle)

        let chartContainer = UIView()
        chartContainer.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.backgroundColor = HardwayColors.surfaceGray
        chartContainer.layer.cornerRadius = 12
        chartContainer.heightAnchor.constraint(equalToConstant: 240).isActive = true

        let chartView = GameDetailChartView(
            balanceHistory: session.balanceHistoryValue,
            betSizeHistory: session.betSizeHistoryValue,
            atmVisitIndices: session.atmVisitIndices ?? [],
            isBlackjack: session.isBlackjackSession
        )
        let hostingController = UIHostingController(rootView: chartView)
        chartHostingController = hostingController
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        chartContainer.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: chartContainer.topAnchor, constant: 8),
            hostingController.view.leadingAnchor.constraint(equalTo: chartContainer.leadingAnchor, constant: 8),
            hostingController.view.trailingAnchor.constraint(equalTo: chartContainer.trailingAnchor, constant: -8),
            hostingController.view.bottomAnchor.constraint(equalTo: chartContainer.bottomAnchor, constant: -8)
        ])
        hostingController.didMove(toParent: self)

        stackView.addArrangedSubview(chartContainer)

        let xAxisLabel = UILabel()
        xAxisLabel.text = session.isBlackjackSession ? "Hands" : "Rolls"
        xAxisLabel.textColor = .lightGray
        xAxisLabel.font = .systemFont(ofSize: 12, weight: .regular)
        xAxisLabel.textAlignment = .center
        stackView.addArrangedSubview(xAxisLabel)

        if !session.betMixBreakdown.isEmpty {
            let betMixTitle = UILabel()
            betMixTitle.text = "Bet Mix"
            betMixTitle.textColor = .white
            betMixTitle.font = .systemFont(ofSize: 16, weight: .semibold)
            stackView.addArrangedSubview(betMixTitle)

            let betMixStack = UIStackView()
            betMixStack.axis = .vertical
            betMixStack.spacing = 6
            betMixStack.alignment = .leading

            for item in session.betMixBreakdown {
                let label = UILabel()
                label.textColor = HardwayColors.label
                label.font = .systemFont(ofSize: 13, weight: .regular)
                label.text = "\(item.label): \(formatPercent(item.percent)) (\(formatCurrency(Double(item.amount))))"
                betMixStack.addArrangedSubview(label)
            }
            stackView.addArrangedSubview(betMixStack)
        }

        // Add "Continue Session" button if this is a session with remaining balance and continuation is allowed
        if canContinueSession && session.endingBalance > 0 {
            setupFloatingContinueButton()
        }
    }

    private func setupFloatingContinueButton() {
        // Setup variable blur effect view
        visualEffectView = UIVisualEffectView()
        guard let visualEffectView = visualEffectView,
              let maskImage = UIImage(named: "testBG3") else { return }

        visualEffectView.effect = UIBlurEffect.variableBlurEffect(radius: 16, maskImage: maskImage)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(visualEffectView)

        // Setup container
        ctaContainer.translatesAutoresizingMaskIntoConstraints = false
        ctaContainer.backgroundColor = .clear
        view.addSubview(ctaContainer)

        // Create button
        let button = NNPrimaryLabeledButton(title: "Continue Session")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(continueSessionTapped), for: .touchUpInside)
        continueButton = button

        ctaContainer.addSubview(button)

        NSLayoutConstraint.activate([
            // Blur view extends from bottom of container to bottom of screen
            visualEffectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: ctaContainer.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Container stretches to bottom
            ctaContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ctaContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ctaContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Button positioned within container with more top padding for taller blur
            button.leadingAnchor.constraint(equalTo: ctaContainer.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: ctaContainer.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: ctaContainer.topAnchor, constant: 40),
            button.heightAnchor.constraint(equalToConstant: 55)
        ])

        // Add bottom content inset to scroll view to prevent content from going under the CTA container
        view.layoutIfNeeded()
        let containerHeight = button.frame.height + 56 // 40pt top + 16pt bottom padding
        scrollView.contentInset.bottom = containerHeight + 20 // Add extra 20pt buffer
        scrollView.scrollIndicatorInsets.bottom = containerHeight - 20 // Match scroll indicator to content inset
    }

    @objc private func continueSessionTapped() {
        onContinueSession?()
    }

    private func formatPercent(_ value: Double) -> String {
        return String(format: "%.0f%%", value * 100)
    }

    private func formatCurrency(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return "$\(rounded)"
    }

    private func formatTimePerRoll(_ value: TimeInterval) -> String {
        if value == 0 { return "0s" }
        return String(format: "%.1fs", value)
    }
    
    private func formatTimePerHand(_ value: TimeInterval) -> String {
        if value == 0 { return "0s" }
        return String(format: "%.1fs", value)
    }
}

private final class StatCardView: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    init(title: String, value: String) {
        super.init(frame: .zero)
        setupView()
        configure(title: title, value: value)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = HardwayColors.surfaceGray
        layer.cornerRadius = 12

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .lightGray
        titleLabel.numberOfLines = 2

        valueLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.numberOfLines = 1

        addSubview(titleLabel)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    private func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
    }
}
