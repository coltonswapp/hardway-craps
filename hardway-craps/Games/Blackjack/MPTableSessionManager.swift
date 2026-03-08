//
//  MPTableSessionManager.swift
//  hardway-craps
//

import FirebaseDatabase
import UIKit

protocol MPTableSessionManagerDelegate: AnyObject {
  func sessionManagerRemoveConnectionObserver()
  func sessionManagerPresentAlert(_ alert: UIAlertController, animated: Bool)
  func sessionManagerPopToRoot(animated: Bool)
  func sessionManagerPopViewController(animated: Bool)
}

final class MPTableSessionManager {

  weak var delegate: MPTableSessionManagerDelegate?
  let context: MPGameContext
  var tableState: MPBlackjackTableState?

  init(context: MPGameContext) {
    self.context = context
  }

  func handlePlayerRemoved() {
    guard let delegate = delegate, let tableState = tableState else { return }

    if let handle = context.seatsObserverHandle {
      tableState.removeSeatsObserver(handle: handle)
      context.seatsObserverHandle = nil
    }
    if let handle = context.gameStateObserverHandle {
      tableState.removeGameStateObserver(handle: handle)
      context.gameStateObserverHandle = nil
    }
    if let handle = context.hostPlayerIdObserverHandle {
      tableState.removeHostPlayerIdObserver(handle: handle)
      context.hostPlayerIdObserverHandle = nil
    }
    delegate.sessionManagerRemoveConnectionObserver()

    let alert = UIAlertController(
      title: "Removed from Table",
      message: "You have been removed from the table by the host.",
      preferredStyle: .alert
    )

    alert.addAction(
      UIAlertAction(title: "OK", style: .default) { [weak delegate] _ in
        delegate?.sessionManagerPopToRoot(animated: true)
      })

    delegate.sessionManagerPresentAlert(alert, animated: true)
  }

  func showLeaveTableConfirmation(popToRootOnLeave: Bool = true) {
    guard let delegate = delegate else { return }

    let alert = UIAlertController(
      title: "Leave Table?",
      message:
        "Are you sure you want to leave the table? Your seat will be freed for other players.",
      preferredStyle: .alert
    )

    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "Leave", style: .destructive) { [weak self] _ in
        self?.leaveTable(popToRoot: popToRootOnLeave)
      })

    delegate.sessionManagerPresentAlert(alert, animated: true)
  }

  func leaveTable(popToRoot: Bool = true) {
    guard let delegate = delegate, let tableState = tableState else { return }

    if let handle = context.seatsObserverHandle {
      tableState.removeSeatsObserver(handle: handle)
      context.seatsObserverHandle = nil
    }
    if let handle = context.hostPlayerIdObserverHandle {
      tableState.removeHostPlayerIdObserver(handle: handle)
      context.hostPlayerIdObserverHandle = nil
    }
    delegate.sessionManagerRemoveConnectionObserver()

    let playerId = context.playerId
    tableState.leaveTable(playerId: playerId) { [weak delegate] result in
      DispatchQueue.main.async {
        guard let delegate = delegate else { return }
        switch result {
        case .success:
          print("✅ [MultiplayerBlackjack] Successfully left table")
        case .failure(let error):
          print("⚠️ [MultiplayerBlackjack] Error leaving table: \(error)")
        }
        if popToRoot {
          delegate.sessionManagerPopToRoot(animated: true)
        } else {
          delegate.sessionManagerPopViewController(animated: true)
        }
      }
    }
  }
}
