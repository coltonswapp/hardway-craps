//
//  MainViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class MainViewController: UIViewController {

    private var tableView: UITableView!
    private var sessions: [GameSession] = []
    private let startGameButton = NNPrimaryLabeledButton(title: "Craps")
    private let blackjackButton = NNPrimaryLabeledButton(title: "Black Jack")
    private let ctaContainer = UIView()
    private let ctaStackView = UIStackView()
    private var visualEffectView: UIVisualEffectView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Game Sessions"
        
        setupNavigationBar()
        setupTableView()
        setupStartGameButtons()
        loadSessions()
    }
    
    private func setupNavigationBar() {
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(showSettings)
        )
        navigationItem.rightBarButtonItem = settingsButton
    }

    @objc private func showSettings() {
        let settingsVC = AppSettingsViewController()
        let navController = UINavigationController(rootViewController: settingsVC)
        present(navController, animated: true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSessions()
    }
    
    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .black
        tableView.separatorColor = .darkGray
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SessionTableViewCell.self, forCellReuseIdentifier: "SessionCell")

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupStartGameButtons() {
        // Configure buttons
        startGameButton.addTarget(self, action: #selector(startGameTapped), for: .touchUpInside)
        blackjackButton.addTarget(self, action: #selector(blackjackTapped), for: .touchUpInside)

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

        // Setup stack view
        ctaStackView.translatesAutoresizingMaskIntoConstraints = false
        ctaStackView.axis = .vertical
        ctaStackView.alignment = .fill
        ctaStackView.distribution = .fillEqually
        ctaStackView.spacing = 12
        ctaStackView.addArrangedSubview(startGameButton)
        ctaStackView.addArrangedSubview(blackjackButton)

        ctaContainer.addSubview(ctaStackView)

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

            // Stack view positioned within container with more top padding for taller blur
            ctaStackView.leadingAnchor.constraint(equalTo: ctaContainer.leadingAnchor, constant: 16),
            ctaStackView.trailingAnchor.constraint(equalTo: ctaContainer.trailingAnchor, constant: -16),
            ctaStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            ctaStackView.topAnchor.constraint(equalTo: ctaContainer.topAnchor, constant: 40),

            // Button heights
            startGameButton.heightAnchor.constraint(equalToConstant: 55),
            blackjackButton.heightAnchor.constraint(equalToConstant: 55)
        ])

        // Add bottom content inset to table view to prevent content from going under the CTA container
        // Calculate the height dynamically after layout
        view.layoutIfNeeded()
        let containerHeight = ctaStackView.frame.height + 56 // 40pt top + 16pt bottom padding
        tableView.contentInset.bottom = containerHeight + 20 // Add extra 20pt buffer
        tableView.scrollIndicatorInsets.bottom = containerHeight - 20// Match scroll indicator to content inset
    }
    
    @objc private func startGameTapped() {
        let gameplayVC = CrapsGameplayViewController()
        navigationController?.pushViewController(gameplayVC, animated: true)
    }
    
    @objc private func blackjackTapped() {
        let gameplayVC = BlackjackGameplayViewController()
        navigationController?.pushViewController(gameplayVC, animated: true)
    }
    
    private func loadSessions() {
        sessions = SessionPersistenceManager.shared.loadAllSessions()
        tableView.reloadData()
    }
}

extension MainViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sessions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SessionCell", for: indexPath) as! SessionTableViewCell
        cell.configure(with: sessions[indexPath.row])
        return cell
    }
}

extension MainViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let session = sessions[indexPath.row]
        let detailViewController = GameDetailViewController(session: session, canContinueSession: true)

        // Set up callback for continuing session
        detailViewController.onContinueSession = { [weak self, weak detailViewController] in
            guard let self = self,
                  let navController = self.navigationController else { return }

            // Create appropriate gameplay view controller with the resumed session
            let gameplayVC: UIViewController
            if session.isBlackjackSession {
                gameplayVC = BlackjackGameplayViewController(resumingSession: session)
            } else {
                gameplayVC = CrapsGameplayViewController(resumingSession: session)
            }

            // Pop the detail view controller and push the gameplay view controller
            navController.popViewController(animated: false)
            navController.pushViewController(gameplayVC, animated: true)
        }

        navigationController?.pushViewController(detailViewController, animated: true)
    }
}

// MARK: - Session Table View Cell

class SessionTableViewCell: UITableViewCell {
    
    private let gameTypeLabel = UILabel()
    private let dateLabel = UILabel()
    private let durationLabel = UILabel()
    private let playerTypeLabel = UILabel()
    private let resultLabel = UILabel()
    private let stackView = UIStackView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCell() {
        backgroundColor = .black
        contentView.backgroundColor = .black
        selectionStyle = .none
        
        // Configure game type label
        gameTypeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        gameTypeLabel.textColor = HardwayColors.yellow
        gameTypeLabel.numberOfLines = 1
        
        // Configure date label
        dateLabel.font = .systemFont(ofSize: 12, weight: .regular)
        dateLabel.textColor = .lightGray
        dateLabel.numberOfLines = 1
        
        // Configure duration label
        durationLabel.font = .systemFont(ofSize: 16, weight: .medium)
        durationLabel.textColor = .white
        durationLabel.numberOfLines = 1
        
        // Configure result label
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.font = .systemFont(ofSize: 16, weight: .medium)
        resultLabel.textAlignment = .right
        
        // Configure stack view
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 4
        stackView.alignment = .leading
        stackView.addArrangedSubview(gameTypeLabel)
        stackView.addArrangedSubview(dateLabel)
        stackView.addArrangedSubview(durationLabel)
        
        contentView.addSubview(stackView)
        contentView.addSubview(resultLabel)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: resultLabel.leadingAnchor, constant: -16),
            
            resultLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            resultLabel.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
            resultLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
        ])
    }
    
    func configure(with session: GameSession) {
        // Configure game type label
        gameTypeLabel.text = session.isBlackjackSession ? "BLACKJACK" : "CRAPS"
        
        dateLabel.text = session.formattedDate
        let durationPart = session.formattedDurationWithRolls
        let playerType = session.playerType
        
        durationLabel.text = "\(durationPart), \(playerType.rawValue)"
        
        // Configure result label to show ending balance with text color
        let isWin = session.endingBalance > 200
        resultLabel.text = "$\(session.endingBalance)"
        resultLabel.textColor = isWin ? .white : .systemRed
        resultLabel.backgroundColor = .clear
        
        // Ensure labels are visible
        gameTypeLabel.isHidden = false
        dateLabel.isHidden = false
        durationLabel.isHidden = false
        resultLabel.isHidden = false
    }
}

