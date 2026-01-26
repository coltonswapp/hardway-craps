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
    private let startGameButton = UIButton(type: .system)
    private let blackjackButton = UIButton(type: .system)
    private let ctaStackView = UIStackView()
    
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
        
        // Add bottom content inset to prevent content from going under the CTA buttons
        // Button height (55 * 2) + spacing (12) + bottom margin (16) = 138pt
        tableView.contentInset.bottom = 150
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupStartGameButtons() {
        startGameButton.setTitle("Craps", for: .normal)
        startGameButton.addTarget(self, action: #selector(startGameTapped), for: .touchUpInside)
        
        blackjackButton.setTitle("Black Jack", for: .normal)
        blackjackButton.addTarget(self, action: #selector(blackjackTapped), for: .touchUpInside)
        
        [startGameButton, blackjackButton].forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
            button.backgroundColor = HardwayColors.surfaceGray
            button.setTitleColor(HardwayColors.label, for: .normal)
            button.layer.cornerRadius = 12
        }
        
        ctaStackView.translatesAutoresizingMaskIntoConstraints = false
        ctaStackView.axis = .vertical
        ctaStackView.alignment = .fill
        ctaStackView.distribution = .fillEqually
        ctaStackView.spacing = 12
        ctaStackView.addArrangedSubview(startGameButton)
        ctaStackView.addArrangedSubview(blackjackButton)
        
        view.addSubview(ctaStackView)
        
        NSLayoutConstraint.activate([
            ctaStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            ctaStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ctaStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            startGameButton.heightAnchor.constraint(equalToConstant: 55),
            blackjackButton.heightAnchor.constraint(equalToConstant: 55)
        ])
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

            // Create new BlackjackGameplayViewController with the resumed session
            let gameplayVC = BlackjackGameplayViewController(resumingSession: session)

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

