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
    private let scrollView = GameDetailScrollView()
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

        // Match UITableView-style layout (e.g. AppSettingsViewController): extend under the navigation bar
        // so content scrolls beneath it; safe-area padding comes from automatic content inset adjustment.
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
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

        // MARK: - Game Section
        stackView.addArrangedSubview(buildGameSection())

        // MARK: - Balance Section
        stackView.addArrangedSubview(buildBalanceSection())

        // MARK: - Rolls / Hands Section
        stackView.addArrangedSubview(buildRollsSection())

        // MARK: - ATM Section
        if session.totalATMAmount > 0 {
            stackView.addArrangedSubview(buildATMSection())
        }

        // MARK: - Bet Mix
        if !session.betMixBreakdown.isEmpty {
            stackView.addArrangedSubview(buildBetMixSection())
        }

        if canContinueSession && session.endingBalance > 0 {
            setupFloatingContinueButton()
        }
    }

    // MARK: - Section Builders

    private func makeSectionCard(title: String, content: () -> [UIView]) -> UIView {
        let wrapper = UIStackView()
        wrapper.axis = .vertical
        wrapper.spacing = 8

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        wrapper.addArrangedSubview(titleLabel)

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = HardwayColors.surfaceGray
        card.layer.cornerRadius = 12

        let innerStack = UIStackView()
        innerStack.axis = .vertical
        innerStack.spacing = 12
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        for view in content() {
            innerStack.addArrangedSubview(view)
        }

        card.addSubview(innerStack)
        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            innerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            innerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            innerStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        wrapper.addArrangedSubview(card)
        return wrapper
    }

    private func makeStatRow(_ stats: [(String, String)]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        for (title, value) in stats {
            row.addArrangedSubview(StatColumnView(title: title, value: value))
        }
        return row
    }

    private func buildGameSection() -> UIView {
        makeSectionCard(title: "Game") {
            if session.isBlackjackSession {
                let blackjacks = session.blackjackMetrics?.blackjacksHit ?? 0
                let doubles = session.blackjackMetrics?.doublesDown ?? 0
                return [
                    makeStatRow([
                        ("Win Rate", formatPercent(session.winRate)),
                        ("Wins", "\(session.winningHandsCount)"),
                        ("Losses", "\(session.losingHandsCount)"),
                    ]),
                    makeStatRow([
                        ("Blackjacks", "\(blackjacks)"),
                        ("Doubles", "\(doubles)"),
                    ]),
                ]
            } else if session.isBaccaratSession {
                let metrics = session.baccaratMetrics
                return [
                    makeStatRow([
                        ("Win Rate", formatPercent(session.winRate)),
                        ("Banker Wins", "\(metrics?.bankerWins ?? 0)"),
                        ("Player Wins", "\(metrics?.playerWins ?? 0)"),
                    ]),
                    makeStatRow([
                        ("Ties", "\(metrics?.ties ?? 0)"),
                        ("Naturals", "\(metrics?.naturals ?? 0)"),
                    ]),
                ]
            } else {
                return [
                    makeStatRow([
                        ("Win Rate", formatPercent(session.winRate)),
                        ("Win Streak", "\(session.longestWinStreak)"),
                        ("Loss Streak", "\(session.longestLossStreak)"),
                        ("Points Hit", "\(session.pointsHitValue)"),
                    ]),
                ]
            }
        }
    }

    private func buildBalanceSection() -> UIView {
        makeSectionCard(title: "Balance") {
            let statsRow = makeStatRow([
                ("Avg Bet", formatCurrency(session.averageBetSize)),
                ("Swing", formatCurrency(Double(session.biggestSwing))),
                ("High", formatCurrency(Double(session.balanceHigh))),
                ("Low", formatCurrency(Double(session.balanceLow))),
            ])

            let chartContainer = UIView()
            chartContainer.translatesAutoresizingMaskIntoConstraints = false
            chartContainer.heightAnchor.constraint(equalToConstant: 220).isActive = true

            let chartView = GameDetailChartView(
                balanceHistory: session.balanceHistoryValue,
                betSizeHistory: session.betSizeHistoryValue,
                atmVisitIndices: session.atmVisitIndices ?? [],
                isBlackjack: session.isBlackjackSession || session.isBaccaratSession,
                lockParentVerticalScrollWhileDragging: { [weak self] lockScroll in
                    self?.scrollView.isScrollEnabled = !lockScroll
                }
            )
            let hostingController = UIHostingController(rootView: chartView)
            chartHostingController = hostingController
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.backgroundColor = .clear

            addChild(hostingController)
            chartContainer.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: chartContainer.topAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: chartContainer.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: chartContainer.trailingAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: chartContainer.bottomAnchor),
            ])
            hostingController.didMove(toParent: self)

            return [statsRow, chartContainer]
        }
    }

    private func buildRollsSection() -> UIView {
        let isCraps = !session.isBlackjackSession && !session.isBaccaratSession
        let sectionTitle = (session.isBlackjackSession || session.isBaccaratSession) ? "Hands" : "Rolls"

        return makeSectionCard(title: sectionTitle) {
            var views: [UIView] = []

            if isCraps {
                let sevensPct = session.rollCountValue > 0
                    ? Double(session.sevensRolledValue) / Double(session.rollCountValue) * 100
                    : 0.0
                views.append(makeStatRow([
                    ("Rolls", "\(session.rollCountValue)"),
                    ("Time", session.formattedDuration),
                    ("Avg / Roll", formatTimePerRoll(session.timePerRoll)),
                    ("7s", "\(session.sevensRolledValue) (\(String(format: "%.0f%%", sevensPct)))"),
                ]))
            } else {
                views.append(makeStatRow([
                    ("Hands", "\(session.handCountValue)"),
                    ("Time", session.formattedDuration),
                    ("Avg / Hand", formatTimePerHand(session.timePerHand)),
                ]))
            }

            if isCraps {
                let histogramContainer = UIView()
                histogramContainer.translatesAutoresizingMaskIntoConstraints = false
                histogramContainer.heightAnchor.constraint(equalToConstant: 220).isActive = true

                let diceChartView = DiceOutcomeHistogramChartView(
                    counts: session.crapsDiceHistogramBins,
                    lockParentVerticalScrollWhileDragging: { [weak self] lockScroll in
                        self?.scrollView.isScrollEnabled = !lockScroll
                    }
                )
                let diceHostingController = UIHostingController(rootView: diceChartView)
                diceHostingController.view.translatesAutoresizingMaskIntoConstraints = false
                diceHostingController.view.backgroundColor = .clear

                addChild(diceHostingController)
                histogramContainer.addSubview(diceHostingController.view)
                NSLayoutConstraint.activate([
                    diceHostingController.view.topAnchor.constraint(equalTo: histogramContainer.topAnchor),
                    diceHostingController.view.leadingAnchor.constraint(equalTo: histogramContainer.leadingAnchor),
                    diceHostingController.view.trailingAnchor.constraint(equalTo: histogramContainer.trailingAnchor),
                    diceHostingController.view.bottomAnchor.constraint(equalTo: histogramContainer.bottomAnchor),
                ])
                diceHostingController.didMove(toParent: self)

                views.append(histogramContainer)
            }

            return views
        }
    }

    private func buildATMSection() -> UIView {
        makeSectionCard(title: "ATM") {
            let net = session.trueNetResult
            let sign = net >= 0 ? "+" : "-"
            return [
                makeStatRow([
                    ("Visits", "\(session.atmVisitsCount)"),
                    ("Total ATM", formatCurrency(Double(session.totalATMAmount))),
                    ("True Net", "\(sign)$\(abs(net))"),
                ]),
            ]
        }
    }

    private func buildBetMixSection() -> UIView {
        makeSectionCard(title: "Bet Mix") {
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
            return [betMixStack]
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

/// `UIScrollView.panGestureRecognizer` must use the scroll view itself as its delegate. Subclassing
/// allows `shouldRecognizeSimultaneouslyWith` so embedded SwiftUI chart drags do not block scrolling.
private final class GameDetailScrollView: UIScrollView, UIGestureRecognizerDelegate {
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentInsetAdjustmentBehavior = .automatic
        panGestureRecognizer.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private final class StatColumnView: UIView {
    init(title: String, value: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        titleLabel.textColor = .lightGray
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .center
        valueLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
