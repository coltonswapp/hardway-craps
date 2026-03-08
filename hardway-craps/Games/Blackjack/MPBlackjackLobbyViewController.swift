//
//  MPBlackjackLobbyViewController.swift
//  hardway-craps
//

import FirebaseDatabase
import UIKit

final class MPBlackjackLobbyViewController: UIViewController {

    // MARK: - UI

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let createTableButton = UIButton(type: .system)
    private let joinTableButton = UIButton(type: .system)
    private let buttonStack = UIStackView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Multiplayer Blackjack"
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        titleLabel.text = "Blackjack"
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = "Create a new table or join an existing one."
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = HardwayColors.label
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureButton(
            createTableButton,
            title: "Create a Table",
            icon: "plus.circle.fill",
            style: .primary)

        configureButton(
            joinTableButton,
            title: "Join a Table",
            icon: "person.badge.plus",
            style: .secondary)

        createTableButton.addTarget(self, action: #selector(createTableTapped), for: .touchUpInside)
        joinTableButton.addTarget(self, action: #selector(joinTableTapped), for: .touchUpInside)

        buttonStack.axis = .vertical
        buttonStack.spacing = 12
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.addArrangedSubview(createTableButton)
        buttonStack.addArrangedSubview(joinTableButton)

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -8),

            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -32),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            buttonStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 20),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            createTableButton.heightAnchor.constraint(equalToConstant: 54),
            joinTableButton.heightAnchor.constraint(equalToConstant: 54),
        ])
    }

    private enum ButtonStyle { case primary, secondary }

    private func configureButton(_ button: UIButton, title: String, icon: String, style: ButtonStyle) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePlacement = .leading
        config.imagePadding = 8
        config.cornerStyle = .large

        switch style {
        case .primary:
            config.baseBackgroundColor = HardwayColors.yellow
            config.baseForegroundColor = .black
        case .secondary:
            config.baseBackgroundColor = HardwayColors.surfaceGray
            config.baseForegroundColor = .white
        }

        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Actions

    @objc private func createTableTapped() {
        let createVC = MPCreateTableViewController()
        navigationController?.pushViewController(createVC, animated: true)
    }

    @objc private func joinTableTapped() {
        showJoinTableAlert()
    }

    // MARK: - Join Table Flow

    private func showJoinTableAlert() {
        let alert = UIAlertController(
            title: "Join a Table",
            message: "Enter the 4-digit table code.",
            preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = "0000"
            textField.keyboardType = .numberPad
            textField.textAlignment = .center
            textField.font = .monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        }

        let joinAction = UIAlertAction(title: "Join", style: .default) { [weak self, weak alert] _ in
            guard let self, let code = alert?.textFields?.first?.text else { return }
            self.validateAndJoinTable(code: code)
        }

        alert.addAction(joinAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func validateAndJoinTable(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count == 4, trimmed.allSatisfy(\.isNumber) else {
            showError("Please enter a valid 4-digit code.")
            return
        }

        let ref = Database.database().reference().child("mp_blackjack/table/\(trimmed)")
        ref.observeSingleEvent(of: .value) { [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self else { return }
                if snapshot.exists() {
                    self.launchGame(tableCode: trimmed, bankroll: AppSettingsViewController.startingBankroll)
                } else {
                    self.showError("Table \(trimmed) not found. Check the code and try again.")
                }
            }
        }
    }

    private func launchGame(tableCode: String, bankroll: Int) {
        let vc = MultiplayerBlackjackViewController(tableCode: tableCode, bankroll: bankroll)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
