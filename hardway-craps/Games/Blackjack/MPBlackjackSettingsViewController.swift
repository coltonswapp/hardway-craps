//
//  MPBlackjackSettingsViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 2/28/26.
//

import UIKit
import FirebaseFunctions
import FirebaseDatabase

final class MPBlackjackSettingsViewController: BaseSettingsViewController {

    // MARK: - Injected Data

    var tableCode: String = ""
    var seats: [Int: MPBlackjackTableState.SeatData] = [:]
    var hostPlayerId: String?
    var tableState: MPBlackjackTableState?
    var myPlayerId: String = ""

    // MARK: - Callbacks

    var onLeaveTable: (() -> Void)?
    var onPlayerRemoved: (() -> Void)?
    var onHostTransferred: (() -> Void)?
    #if DEBUG
    var onDebugHands: (() -> Void)?
    #endif

    // MARK: - Side bets

    private typealias SideBetType = BlackjackSettingsViewController.SideBetType
    var selectedSideBets: [String] = ["Royal Match"]

    /// Callback when selectedSideBets changes.
    var onSelectedSideBetsChanged: (([String]) -> Void)?
    
    // MARK: - Starting Bankroll
    
    private var startingBankroll: Int = 500
    private let bankrollOptions = [200, 500, 1000]
    
    // MARK: - Observers
    
    private var seatsObserverHandle: DatabaseHandle?
    private var gameStateObserverHandle: DatabaseHandle?
    private var currentGameState: MPBlackjackTableState.GameStateSnapshot?

    private var occupiedSeats: [(index: Int, data: MPBlackjackTableState.SeatData)] {
        seats
            .filter { $0.value.playerId != nil }
            .sorted { $0.key < $1.key }
            .map { (index: $0.key, data: $0.value) }
    }
    
    private var isHost: Bool {
        hostPlayerId == myPlayerId
    }

    // MARK: - Lifecycle

    override func setupViewController() {
        super.setupViewController()
        title = "Table Settings"
        observeSettings()
        observeSeats()
        observeGameState()
    }
    
    @MainActor deinit {
        if let handle = seatsObserverHandle, let tableState = tableState {
            tableState.removeSeatsObserver(handle: handle)
        }
        if let handle = gameStateObserverHandle, let tableState = tableState {
            tableState.removeGameStateObserver(handle: handle)
        }
    }
    
    private func observeSettings() {
        guard let tableState = tableState else { return }
        _ = tableState.observeSettings { [weak self] settings in
            guard let self = self else { return }
            if let bankroll = settings[MultiplayerBlackjackKeys.Settings.startingBankroll] as? Int,
               bankroll > 0 {
                self.startingBankroll = bankroll
                DispatchQueue.main.async {
                    self.tableView.reloadSections(IndexSet(integer: Section.tableInfo.rawValue), with: .none)
                }
            }
        }
    }
    
    private func observeSeats() {
        guard let tableState = tableState else { return }
        seatsObserverHandle = tableState.observeSeats { [weak self] seatsWithIndices in
            guard let self = self else { return }
            // Convert array of tuples to dictionary
            var newSeats: [Int: MPBlackjackTableState.SeatData] = [:]
            for (seatIndex, seatData) in seatsWithIndices {
                newSeats[seatIndex] = seatData
            }
            // Update seats property and reload players section
            DispatchQueue.main.async {
                self.seats = newSeats
                self.tableView.reloadSections(IndexSet(integer: Section.players.rawValue), with: .automatic)
            }
        }
    }
    
    private func observeGameState() {
        guard let tableState = tableState else { return }
        gameStateObserverHandle = tableState.observeGameState { [weak self] snapshot in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.currentGameState = snapshot
                self.tableView.reloadSections(IndexSet(integer: Section.players.rawValue), with: .none)
            }
        }
    }

    // MARK: - Sections

    private enum Section: Int, CaseIterable {
        case tableInfo
        case players
        case bonusBets
        case hostActions
        #if DEBUG
        case debug
        #endif
        case leave
        
        static var visibleSections: [Section] {
            Section.allCases
        }
    }
    
    private enum TableInfoRow: Int, CaseIterable {
        case tableLink
        case tableCode
        case startingBankroll
    }

    // MARK: - Table View Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .tableInfo:
            return TableInfoRow.allCases.count
        case .players:
            return occupiedSeats.count
        case .bonusBets:
            return SideBetType.allCases.count
        case .hostActions:
            return isHost ? 1 : 0
        #if DEBUG
        case .debug:
            return 1
        #endif
        case .leave:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .tableInfo:
            return "Table"
        case .players:
            return "Players"
        case .bonusBets:
            return "Bonus Bets\(isHost ? "" : " (Host Only)")"
        case .hostActions:
            return isHost ? "Host Actions" : nil
        #if DEBUG
        case .debug:
            return "Debug"
        #endif
        case .leave:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        cell.textLabel?.textColor = .white
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        guard let section = Section(rawValue: indexPath.section) else { return cell }

        switch section {
        case .tableInfo:
            guard let row = TableInfoRow(rawValue: indexPath.row) else { break }
            switch row {
            case .tableLink:
                configureTableLinkCell(cell)
            case .tableCode:
                configureTableCodeCell(cell)
            case .startingBankroll:
                configureStartingBankrollCell(cell)
            }
        case .players:
            let seatEntry = occupiedSeats[indexPath.row]
            let isCurrentTurn = currentGameState?.currentTurn?.seatIndex == seatEntry.index
            configurePlayerCell(cell, seatData: seatEntry.data, seatIndex: seatEntry.index, isTappable: isHost && seatEntry.data.playerId != myPlayerId, isCurrentTurn: isCurrentTurn)
        case .bonusBets:
            let sideBetType = SideBetType.allCases[indexPath.row]
            let isSelected = selectedSideBets.contains(sideBetType.displayName)
            configureSideBetCell(cell, sideBetType: sideBetType, isSelected: isSelected)
        case .hostActions:
            configureActionCell(cell, title: "Clear and Start New Hand", icon: "arrow.clockwise", isDestructive: false) {}
        #if DEBUG
        case .debug:
            configureActionCell(cell, title: "Debug: Fixed Hand", icon: "ladybug", isDestructive: false) {}
        #endif
        case .leave:
            configureActionCell(cell, title: "Leave Table", icon: "rectangle.portrait.and.arrow.right", isDestructive: true) {}
        }

        return cell
    }

    // MARK: - Table View Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }

        if section == .tableInfo && isHost {
            guard let row = TableInfoRow(rawValue: indexPath.row) else { return }
            if row == .startingBankroll {
                // Starting bankroll cell is handled by menu button, no action needed
            }
        } else if section == .players && isHost {
            let seatEntry = occupiedSeats[indexPath.row]
            guard let playerId = seatEntry.data.playerId, playerId != myPlayerId else { return }
            showPlayerActionSheet(playerId: playerId, playerName: seatEntry.data.displayLabel, seatIndex: seatEntry.index)
        } else if section == .bonusBets && isHost {
            handleSideBetToggle(at: indexPath.row)
        } else if section == .hostActions && isHost && indexPath.row == 0 {
            showClearAndStartNewHandConfirmation()
        }
        
        #if DEBUG
        if section == .debug && indexPath.row == 0 {
            onDebugHands?()
        }
        #endif
        
        if section == .leave && indexPath.row == 0 {
            onLeaveTable?()
        }
    }

    private func handleSideBetToggle(at row: Int) {
        let sideBetType = SideBetType.allCases[row]
        let name = sideBetType.displayName

        // Only allow 1 bonus bet selected at a time
        // If tapping the already selected bet, do nothing
        if selectedSideBets.contains(name) {
            return
        }
        
        // Replace current selection with the new one
        selectedSideBets = [name]

        tableView.reloadSections(IndexSet(integer: Section.bonusBets.rawValue), with: .automatic)
        callUpdateSelectedSideBets()
        onSelectedSideBetsChanged?(selectedSideBets)
    }

    private func callUpdateSelectedSideBets() {
        let params: [String: Any] = [
            "tableCode": tableCode,
            MultiplayerBlackjackKeys.Settings.selectedSideBets: selectedSideBets,
        ]
        let functions = Functions.functions()
        functions.httpsCallable("updateTableSettings").call(params) { _, error in
            if let error = error {
                print("⚠️ [MPBlackjackSettings] Failed to update selectedSideBets: \(error.localizedDescription)")
            } else {
                print("✅ [MPBlackjackSettings] selectedSideBets updated")
            }
        }
    }

    // MARK: - Cell Configurations

    private func configureTableLinkCell(_ cell: UITableViewCell) {
        let label = createStandardLabel(text: "Table Link")

        let copyButton = UIButton(type: .system)
        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyButton.tintColor = HardwayColors.yellow
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let urlString = "hardway-craps://table?code=\(self.tableCode)"
            UIPasteboard.general.string = urlString
            self.showCopiedFeedback(on: copyButton)
        }, for: .touchUpInside)

        cell.contentView.addSubview(label)
        cell.contentView.addSubview(copyButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            copyButton.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            copyButton.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 16),

            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func configureTableCodeCell(_ cell: UITableViewCell) {
        let label = createStandardLabel(text: "Table Code")

        let codeLabel = UILabel()
        codeLabel.text = tableCode
        codeLabel.textColor = .white
        codeLabel.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        codeLabel.translatesAutoresizingMaskIntoConstraints = false

        let copyButton = UIButton(type: .system)
        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyButton.tintColor = HardwayColors.yellow
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            UIPasteboard.general.string = self.tableCode
            self.showCopiedFeedback(on: copyButton)
        }, for: .touchUpInside)

        let rightStack = UIStackView(arrangedSubviews: [codeLabel, copyButton])
        rightStack.axis = .horizontal
        rightStack.spacing = 8
        rightStack.alignment = .center
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(label)
        cell.contentView.addSubview(rightStack)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            rightStack.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            rightStack.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 16),

            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func showCopiedFeedback(on button: UIButton) {
        let original = button.image(for: .normal)
        button.setImage(UIImage(systemName: "checkmark"), for: .normal)
        button.tintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak button] in
            button?.setImage(original, for: .normal)
            button?.tintColor = HardwayColors.yellow
        }
    }
    
    private func configureStartingBankrollCell(_ cell: UITableViewCell) {
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        
        let label = createStandardLabel(text: "Starting Bankroll")
        if !isHost { label.alpha = 0.5 }
        
        let menu = UIMenu(children: bankrollOptions.map { amount in
            UIAction(title: "$\(amount)", state: amount == startingBankroll ? .on : .off) { [weak self] _ in
                guard let self = self, self.isHost else { return }
                self.startingBankroll = amount
                self.tableView.reloadSections(IndexSet(integer: Section.tableInfo.rawValue), with: .none)
                self.callUpdateStartingBankroll()
                HapticsHelper.lightHaptic()
            }
        })
        let button = createMenuButton(title: "$\(startingBankroll)", menu: menu)
        if !isHost { button.isEnabled = false }
        
        layoutLabelAndButton(label: label, button: button, in: cell)
    }
    
    private func callUpdateStartingBankroll() {
        let params: [String: Any] = [
            "tableCode": tableCode,
            MultiplayerBlackjackKeys.Settings.startingBankroll: startingBankroll,
        ]
        let functions = Functions.functions()
        functions.httpsCallable("updateTableSettings").call(params) { _, error in
            if let error = error {
                print("⚠️ [MPBlackjackSettings] Failed to update startingBankroll: \(error.localizedDescription)")
            } else {
                print("✅ [MPBlackjackSettings] startingBankroll updated")
            }
        }
    }

    private func configurePlayerCell(_ cell: UITableViewCell, seatData: MPBlackjackTableState.SeatData, seatIndex: Int, isTappable: Bool, isCurrentTurn: Bool) {
        let isHostPlayer = seatData.playerId != nil && seatData.playerId == hostPlayerId

        let nameLabel = createStandardLabel(text: seatData.displayLabel)
        cell.contentView.addSubview(nameLabel)
        
        cell.selectionStyle = isTappable ? .default : .none

        // Create right-side views stack
        var rightViews: [UIView] = []
        
        // Add turn indicator circle if it's this player's turn
        if isCurrentTurn {
            let turnIndicator = UIView()
            turnIndicator.backgroundColor = HardwayColors.yellow
            turnIndicator.layer.cornerRadius = 6
            turnIndicator.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(turnIndicator)
            rightViews.append(turnIndicator)
            
            NSLayoutConstraint.activate([
                turnIndicator.widthAnchor.constraint(equalToConstant: 12),
                turnIndicator.heightAnchor.constraint(equalToConstant: 12)
            ])
        }
        
        // Add crown if host
        if isHostPlayer {
            let crownView = UIImageView(image: UIImage(systemName: "crown.fill"))
            crownView.tintColor = HardwayColors.yellow
            crownView.contentMode = .scaleAspectFit
            crownView.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(crownView)
            rightViews.append(crownView)
            
            NSLayoutConstraint.activate([
                crownView.widthAnchor.constraint(equalToConstant: 20),
                crownView.heightAnchor.constraint(equalToConstant: 20)
            ])
        }
        
        // Layout views
        if !rightViews.isEmpty {
            let rightStack = UIStackView(arrangedSubviews: rightViews)
            rightStack.axis = .horizontal
            rightStack.spacing = 8
            rightStack.alignment = .center
            rightStack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(rightStack)
            
            NSLayoutConstraint.activate([
                nameLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                nameLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),
                
                rightStack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                rightStack.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                nameLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                nameLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -16)
            ])
        }
    }
    
    // MARK: - Player Actions
    
    private func showPlayerActionSheet(playerId: String, playerName: String, seatIndex: Int) {
        let alert = UIAlertController(
            title: playerName,
            message: "Choose an action",
            preferredStyle: .actionSheet
        )
        
        // Add "Skip Turn" option if it's this player's turn
        if let currentTurn = currentGameState?.currentTurn,
           currentTurn.seatIndex == seatIndex,
           currentGameState?.phase == MultiplayerBlackjackKeys.Phases.playerActions {
            alert.addAction(UIAlertAction(title: "Skip Turn (Stand)", style: .default) { [weak self] _ in
                self?.skipPlayerTurn(seatIndex: seatIndex, handIndex: currentTurn.handIndex)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Make Host", style: .default) { [weak self] _ in
            self?.transferHost(to: playerId, playerName: playerName)
        })
        
        alert.addAction(UIAlertAction(title: "Remove Player", style: .destructive) { [weak self] _ in
            self?.removePlayer(playerId: playerId)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = alert.popoverPresentationController {
            if let rowIndex = occupiedSeats.firstIndex(where: { $0.data.playerId == playerId }),
               let cell = tableView.cellForRow(at: IndexPath(row: rowIndex, section: Section.players.rawValue)) {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            } else {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
        }
        
        present(alert, animated: true)
    }
    
    private func skipPlayerTurn(seatIndex: Int, handIndex: Int) {
        let functions = Functions.functions()
        let params: [String: Any] = [
            MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableCode,
            MultiplayerBlackjackKeys.FirebaseParams.seatIndex: seatIndex,
            MultiplayerBlackjackKeys.FirebaseParams.handIndex: handIndex,
            MultiplayerBlackjackKeys.FirebaseParams.action: MultiplayerBlackjackKeys.Actions.stand,
        ]
        
        functions.httpsCallable("playerAction").call(params) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    let ns = error as NSError
                    print("⚠️ [MPBlackjackSettings] skipPlayerTurn failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))")
                    self.showErrorAlert(message: "Failed to skip player turn: \(error.localizedDescription)")
                } else {
                    print("✅ [MPBlackjackSettings] Player turn skipped (stand action)")
                }
            }
        }
    }
    
    private func transferHost(to newHostPlayerId: String, playerName: String) {
        guard let tableState = tableState else { return }
        
        let confirmAlert = UIAlertController(
            title: "Make Host?",
            message: "Are you sure you want to make \(playerName) the host? You will lose host privileges.",
            preferredStyle: .alert
        )
        
        confirmAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirmAlert.addAction(UIAlertAction(title: "Make Host", style: .default) { [weak self] _ in
            tableState.transferHost(to: newHostPlayerId) { result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        self.onHostTransferred?()
                    case .failure(let error):
                        self.showErrorAlert(message: "Failed to transfer host: \(error.localizedDescription)")
                    }
                }
            }
        })
        
        present(confirmAlert, animated: true)
    }
    
    private func removePlayer(playerId: String) {
        guard let tableState = tableState else { return }
        
        // Find the seat index before removal
        guard let seatEntry = occupiedSeats.first(where: { $0.data.playerId == playerId }) else {
            showErrorAlert(message: "Player not found")
            return
        }
        let seatIndex = seatEntry.index
        
        let confirmAlert = UIAlertController(
            title: "Remove Player?",
            message: "Are you sure you want to remove this player from the table?",
            preferredStyle: .alert
        )
        
        confirmAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirmAlert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            tableState.removePlayer(playerId: playerId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        // Call Cloud Function to advance game after player removal
                        self.advanceGameAfterPlayerRemoved(seatIndex: seatIndex)
                        self.onPlayerRemoved?()
                    case .failure(let error):
                        self.showErrorAlert(message: "Failed to remove player: \(error.localizedDescription)")
                    }
                }
            }
        })
        
        present(confirmAlert, animated: true)
    }
    
    private func advanceGameAfterPlayerRemoved(seatIndex: Int) {
        let functions = Functions.functions()
        let params: [String: Any] = [
            "tableCode": tableCode,
            "removedSeatIndex": seatIndex
        ]
        functions.httpsCallable("advanceGameAfterPlayerRemoved").call(params) { _, error in
            if let error = error {
                print("⚠️ [MPBlackjackSettings] Failed to advance game after player removal: \(error.localizedDescription)")
                // Don't show error to user - removal succeeded, game advance is best-effort
            } else {
                print("✅ [MPBlackjackSettings] Game advanced after player removal")
            }
        }
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Host Actions
    
    private func showClearAndStartNewHandConfirmation() {
        let alert = UIAlertController(
            title: "Clear and Start New Hand?",
            message: "This will clear all cards, bets, and reset the game to the betting phase. Are you sure?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear and Start", style: .destructive) { [weak self] _ in
            self?.callStartNextHand()
        })
        
        present(alert, animated: true)
    }
    
    private func callStartNextHand() {
        let functions = Functions.functions()
        let params: [String: Any] = [
            MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableCode,
            MultiplayerBlackjackKeys.FirebaseParams.playerId: myPlayerId,
        ]
        
        functions.httpsCallable("startNextHand").call(params) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    let ns = error as NSError
                    print("⚠️ [MPBlackjackSettings] startNextHand failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))")
                    self.showErrorAlert(message: "Failed to clear and start new hand: \(error.localizedDescription)")
                } else {
                    print("✅ [MPBlackjackSettings] startNextHand succeeded — game will reset to betting phase")
                    // Dismiss settings view controller to show the cleared game state
                    self.dismiss(animated: true)
                }
            }
        }
    }

    // MARK: - Side Bet Cell

    private func configureSideBetCell(_ cell: UITableViewCell, sideBetType: SideBetType, isSelected: Bool) {
        let titleLabel = createStandardLabel(text: sideBetType.displayName)
        if !isHost { titleLabel.alpha = 0.5 }

        let checkmarkView = UIImageView(image: UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle"))
        checkmarkView.tintColor = isSelected ? HardwayColors.yellow : .white.withAlphaComponent(0.3)
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(titleLabel)
        cell.contentView.addSubview(checkmarkView)

        var constraints: [NSLayoutConstraint] = [
            titleLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -16),

            checkmarkView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            checkmarkView.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkView.heightAnchor.constraint(equalToConstant: 24)
        ]

        let combinations = sideBetType.cardCombinations
        if !combinations.isEmpty {
            let combinationsStack = UIStackView()
            combinationsStack.axis = .horizontal
            combinationsStack.spacing = 8
            combinationsStack.alignment = .center
            combinationsStack.distribution = .fillEqually
            combinationsStack.translatesAutoresizingMaskIntoConstraints = false

            for combination in combinations {
                let combinationView = CardCombinationView()
                combinationView.configure(cards: combination.cards, odds: combination.odds)
                combinationsStack.addArrangedSubview(combinationView)
            }

            cell.contentView.addSubview(combinationsStack)

            constraints.append(contentsOf: [
                combinationsStack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                combinationsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
                combinationsStack.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -16),
                combinationsStack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -16)
            ])
        } else {
            let descriptionLabel = createSecondaryLabel(text: "Dealer Bust. Payout depends on how many cards dealer busts with.\n\n3 cards: 2:1 • 4 cards: 2:1 • 5 cards: 4:1\n6 cards: 12:1 • 7 cards: 50:1 • 8+ cards: 250:1")
            descriptionLabel.numberOfLines = 0
            cell.contentView.addSubview(descriptionLabel)

            constraints.append(contentsOf: [
                descriptionLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
                descriptionLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -16),
                descriptionLabel.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -16)
            ])
        }

        NSLayoutConstraint.activate(constraints)
        cell.selectionStyle = isHost ? .default : .none
        cell.accessoryType = .none
    }
}
