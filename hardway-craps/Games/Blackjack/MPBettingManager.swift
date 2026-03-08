//
//  MPBettingManager.swift
//  hardway-craps
//

import FirebaseFunctions
import UIKit

protocol MPBettingManagerDelegate: AnyObject {
  func bettingManagerShowInstructionMessage(_ message: String, shouldFade: Bool)
  func bettingManagerRefreshButtonVisibility(for snapshot: MPBlackjackTableState.GameStateSnapshot)
  func bettingManagerDealButton() -> UIButton
  func bettingManagerNextHandButton() -> UIButton
  func bettingManagerSelectedChipValue() -> Int
  func bettingManagerShowDebugHandsSheet()
}

final class MPBettingManager {

  weak var delegate: MPBettingManagerDelegate?
  let context: MPGameContext
  var tableState: MPBlackjackTableState?

  private static let placeBetRemoveBetMaxRetries = 2

  init(context: MPGameContext) {
    self.context = context
  }

  // MARK: - Bet Control Callbacks

  func setupBetControlCallbacks(for seat: PlayerSeat) {
    let betControl = seat.primaryHand.betControl

    betControl.getSelectedChipValue = { [weak self] in
      return self?.delegate?.bettingManagerSelectedChipValue() ?? 5
    }

    betControl.getBalance = { [weak self] in
      return self?.context.balance ?? 0
    }

    betControl.onBetPlaced = { [weak self] amount in
      guard let self = self else { return }
      let phase = self.context.currentPhase
      let canPlaceBet = phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting
      if !canPlaceBet {
        seat.primaryHand.betControl.betAmount -= amount
        HapticsHelper.lightHaptic()
        return
      }
      let expectedBalance = self.context.balance - amount
      self.context.isBalanceFrozenForBetOperation = true
      self.context.expectedBalanceAfterBetOperation = expectedBalance
      self.context.balance -= amount

      // Track bet in session manager
      self.context.sessionManager?.trackBet(amount: amount, isMainBet: true)
      self.callPlaceBet(amount: amount, seat: seat) { [weak self] success in
        guard let self = self else { return }
        if success {
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.context.isBalanceFrozenForBetOperation = false
            self.context.expectedBalanceAfterBetOperation = nil
          }
          print("✅ [placeBet] Success - backend updated Firebase, no need to sync")
        } else {
          seat.primaryHand.betControl.betAmount -= amount
          self.context.balance += amount
          self.context.isBalanceFrozenForBetOperation = false
          self.context.expectedBalanceAfterBetOperation = nil
        }
      }
    }

    betControl.onBetRemoved = { [weak self] amount in
      guard let self = self else { return }
      let phase = self.context.currentPhase
      let canRemoveBet = phase.isEmpty || phase == MultiplayerBlackjackKeys.Phases.betting
      if !canRemoveBet {
        seat.primaryHand.betControl.betAmount += amount
        HapticsHelper.lightHaptic()
        return
      }
      let expectedBalance = self.context.balance + amount
      self.context.isBalanceFrozenForBetOperation = true
      self.context.expectedBalanceAfterBetOperation = expectedBalance
      self.context.balance += amount
      self.callRemoveBet(amount: amount, seat: seat) { [weak self] success, _ in
        guard let self = self else { return }
        if success {
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.context.isBalanceFrozenForBetOperation = false
            self.context.expectedBalanceAfterBetOperation = nil
          }
          print("✅ [removeBet] Success - backend updated Firebase, no need to sync")
        } else {
          seat.primaryHand.betControl.betAmount += amount
          self.context.balance -= amount
          self.context.isBalanceFrozenForBetOperation = false
          self.context.expectedBalanceAfterBetOperation = nil
        }
      }
    }
  }

  // MARK: - Firebase Sync

  func syncHandsToFirebase(for seat: PlayerSeat) {
    guard let tableState = tableState else { return }
    let playerId = context.playerId

    var hands: [MPBlackjackTableState.HandData] = []
    for handView in seat.hands {
      let betAmount = handView.betControl.betAmount
      if betAmount > 0 {
        hands.append(
          MPBlackjackTableState.HandData(
            bet: betAmount, cards: [], stood: false, doubled: false, busted: false,
            playerId: playerId))
      }
    }

    let totalBet = hands.reduce(0) { $0 + $1.bet }
    print("🟡 [syncHandsToFirebase] Writing betAmount=\(totalBet) to Firebase (from UI betControl)")

    tableState.updateHands(playerId: playerId, hands: hands)
    tableState.updateBalance(playerId: playerId, balance: context.balance)
  }

  // MARK: - Cloud Function Calls

  func callPlaceBet(amount: Int, seat: PlayerSeat, completion: @escaping (Bool) -> Void) {
    guard let tableState = tableState else {
      completion(false)
      return
    }
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.seatIndex: context.mySeatIndex,
      MultiplayerBlackjackKeys.FirebaseParams.amount: amount,
    ]

    func attempt(_ tryIndex: Int) {
      let currentBetBeforeCall = seat.primaryHand.betControl.betAmount
      print(
        "🔵 [placeBet] CALLING attempt \(tryIndex + 1) amount=\(amount), currentBet=\(currentBetBeforeCall)"
      )
      let functions = Functions.functions()
      functions.httpsCallable("placeBet").call(params) { [weak self] result, error in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if let error = error {
            if tryIndex < Self.placeBetRemoveBetMaxRetries {
              let delay: TimeInterval = 2.0
              print(
                "⚠️ [MultiplayerBlackjack] placeBet attempt \(tryIndex + 1) failed (e.g. cold start), retrying in \(delay)s: \(error.localizedDescription)"
              )
              DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                attempt(tryIndex + 1)
              }
              return
            }
            self.delegate?.bettingManagerShowInstructionMessage("Bet failed", shouldFade: true)
            print(
              "⚠️ [MultiplayerBlackjack] placeBet failed after \(Self.placeBetRemoveBetMaxRetries + 1) attempts: \(error.localizedDescription)"
            )
            completion(false)
            return
          }
          if let data = result?.data as? [String: Any],
            let newBalance = MPBlackjackTableState.intFromAny(
              data[MultiplayerBlackjackKeys.FirebaseResponse.newBalance]),
            let newBet = MPBlackjackTableState.intFromAny(
              data[MultiplayerBlackjackKeys.FirebaseResponse.newBet])
          {
            print("BAL_BUG [placeBet] bet=\(amount), balance \(self.context.balance) → \(newBalance)")
            print(
              "💰 [MultiplayerBlackjack] Bet placed: \(amount), new balance: \(newBalance), newBet from backend: \(newBet)"
            )
            print(
              "🔵 [placeBet] RESPONSE: backend says newBet=\(newBet), UI betAmount=\(seat.primaryHand.betControl.betAmount)"
            )
          }
          completion(true)
        }
      }
    }
    attempt(0)
  }

  func callRemoveBet(
    amount: Int, seat: PlayerSeat, completion: @escaping (Bool, Int?) -> Void
  ) {
    guard let tableState = tableState else {
      completion(false, nil)
      return
    }
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.seatIndex: context.mySeatIndex,
      MultiplayerBlackjackKeys.FirebaseParams.amount: amount,
    ]

    func attempt(_ tryIndex: Int) {
      let currentBetBeforeCall = seat.primaryHand.betControl.betAmount
      print(
        "🔴 [removeBet] CALLING attempt \(tryIndex + 1) amount=\(amount), currentBet=\(currentBetBeforeCall)"
      )
      let functions = Functions.functions()
      functions.httpsCallable("removeBet").call(params) { [weak self] result, error in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if let error = error {
            if tryIndex < Self.placeBetRemoveBetMaxRetries {
              let delay: TimeInterval = 2.0
              print(
                "⚠️ [MultiplayerBlackjack] removeBet attempt \(tryIndex + 1) failed (e.g. cold start), retrying in \(delay)s: \(error.localizedDescription)"
              )
              DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                attempt(tryIndex + 1)
              }
              return
            }
            self.delegate?.bettingManagerShowInstructionMessage(
              "Could not return chips", shouldFade: true)
            print(
              "⚠️ [MultiplayerBlackjack] removeBet failed after \(Self.placeBetRemoveBetMaxRetries + 1) attempts: \(error.localizedDescription)"
            )
            completion(false, nil)
            return
          }
          var newBet: Int?
          if let data = result?.data as? [String: Any] {
            if let nb = MPBlackjackTableState.intFromAny(
              data[MultiplayerBlackjackKeys.FirebaseResponse.newBalance]),
              let bet = MPBlackjackTableState.intFromAny(
                data[MultiplayerBlackjackKeys.FirebaseResponse.newBet])
            {
              print("BAL_BUG [removeBet] amount=\(amount), balance \(self.context.balance) → \(nb)")
              print(
                "💰 [MultiplayerBlackjack] Bet removed: \(amount), new balance: \(nb), newBet from backend: \(bet)"
              )
              print(
                "🔴 [removeBet] RESPONSE: backend says newBet=\(bet), UI betAmount=\(seat.primaryHand.betControl.betAmount)"
              )
            }
            newBet = MPBlackjackTableState.intFromAny(
              data[MultiplayerBlackjackKeys.FirebaseResponse.newBet])
          }
          completion(true, newBet)
        }
      }
    }
    attempt(0)
  }

  func callStartDeal(debugSeed: Int? = nil) {
    guard let tableState = tableState else { return }
    let functions = Functions.functions()
    var params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode
    ]
    if let debugSeed = debugSeed {
      params["debugSeed"] = debugSeed
      print("🐛 [Debug] callStartDeal with debugSeed=\(debugSeed)")
    }
    functions.httpsCallable("startDeal").call(params) { [weak self] _, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let error = error {
          self.context.isDealInProgress = false
          self.delegate?.bettingManagerDealButton().isEnabled = true
          self.delegate?.bettingManagerShowInstructionMessage("Deal failed", shouldFade: true)
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] startDeal failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
        } else {
          self.delegate?.bettingManagerShowInstructionMessage("Dealing...", shouldFade: true)
        }
      }
    }
  }

  func callSetReady(completion: @escaping (Bool) -> Void) {
    guard let tableState = tableState else {
      completion(false)
      return
    }
    let functions = Functions.functions()
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.seatIndex: context.mySeatIndex,
    ]
    functions.httpsCallable("setReady").call(params) { [weak self] _, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let error = error {
          self.delegate?.bettingManagerShowInstructionMessage("Ready failed", shouldFade: true)
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] setReady failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
          completion(false)
        } else {
          self.delegate?.bettingManagerShowInstructionMessage("Ready up", shouldFade: true)
          completion(true)
        }
      }
    }
  }

  func callRunDealer() {
    guard let tableState = tableState else { return }
    let functions = Functions.functions()
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode
    ]
    functions.httpsCallable("runDealer").call(params) { _, error in
      DispatchQueue.main.async {
        if let error = error {
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] runDealer failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
        }
      }
    }
  }

  func callResolveDealerBlackjack() {
    guard let tableState = tableState else { return }
    let functions = Functions.functions()
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode
    ]
    functions.httpsCallable("resolveDealerBlackjack").call(params) { _, error in
      DispatchQueue.main.async {
        if let error = error {
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] resolveDealerBlackjack failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
        }
      }
    }
  }

  func callStartNextHand() {
    guard let tableState = tableState else { return }
    let functions = Functions.functions()
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: tableState.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.playerId: context.playerId,
    ]
    functions.httpsCallable("startNextHand").call(params) { [weak self] _, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.delegate?.bettingManagerNextHandButton().isEnabled = true
        if let error = error {
          self.delegate?.bettingManagerShowInstructionMessage("Next hand failed", shouldFade: true)
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] startNextHand failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
        } else {
          print("💰 [MP-VC] startNextHand succeeded — waiting for phase→betting to clear cards")
        }
      }
    }
  }
}
