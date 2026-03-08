//
//  MPPlayerActionHandler.swift
//  hardway-craps
//

import FirebaseFunctions
import UIKit

protocol MPPlayerActionHandlerDelegate: AnyObject {
  func actionHandlerRefreshButtonVisibility(for snapshot: MPBlackjackTableState.GameStateSnapshot)
  func actionHandlerUpdateTurnIndicatorDot(forSeatIndex: Int?, handIndex: Int)
  func actionHandlerHideTurnIndicatorDot()
  func actionHandlerSetStandButtonDisabled(_ disabled: Bool)
  func actionHandlerSetDoubleButtonDisabled(_ disabled: Bool)
  func actionHandlerHideSplitButton()
  func actionHandlerShowInstructionMessage(_ message: String, shouldFade: Bool)
  func actionHandlerAnimateLocalBustForfeit(
    seat: PlayerSeat, hand: CompactPlayerHandView, result: MPBlackjackTableState.HandResult)
  func actionHandlerWireHandTapHandlers(for hand: CompactPlayerHandView, handIndex: Int)
}

final class MPPlayerActionHandler {

  // MARK: - Properties

  weak var delegate: MPPlayerActionHandlerDelegate?
  let context: MPGameContext

  private(set) var deckProvider: DeterministicDeckProvider?
  private(set) var optimisticDeckIndex: Int = 0
  private(set) var optimisticCardsForMyHand: [BlackjackHandView.Card] = []
  private(set) var isActionInFlight = false
  private(set) var actionInFlightTimeoutWorkItem: DispatchWorkItem?

  init(context: MPGameContext) {
    self.context = context
  }

  // MARK: - State Management

  func setDeckProvider(_ provider: DeterministicDeckProvider?) {
    deckProvider = provider
  }

  func setOptimisticDeckIndex(_ index: Int) {
    optimisticDeckIndex = index
  }

  func clearOptimisticCards() {
    optimisticCardsForMyHand.removeAll()
  }

  func setIsActionInFlight(_ value: Bool) {
    isActionInFlight = value
  }

  func cancelTimeout() {
    actionInFlightTimeoutWorkItem?.cancel()
    actionInFlightTimeoutWorkItem = nil
  }

  func resetState() {
    optimisticCardsForMyHand.removeAll()
    isActionInFlight = false
    actionInFlightTimeoutWorkItem?.cancel()
    actionInFlightTimeoutWorkItem = nil
  }

  // MARK: - Server Call

  func sendPlayerActionToServer(
    action: String, handIndex serverHandIndex: Int? = nil, originalBetForDouble: Int?
  ) {
    let functions = Functions.functions()
    let params: [String: Any] = [
      MultiplayerBlackjackKeys.FirebaseParams.tableCode: context.tableCode,
      MultiplayerBlackjackKeys.FirebaseParams.seatIndex: context.mySeatIndex,
      MultiplayerBlackjackKeys.FirebaseParams.handIndex:
        serverHandIndex ?? context.activeHandIndex,
      MultiplayerBlackjackKeys.FirebaseParams.action: action,
    ]
    functions.httpsCallable("playerAction").call(params) {
      [weak self, originalBetForDouble] _, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let error = error {
          self.delegate?.actionHandlerShowInstructionMessage(
            "\(action.capitalized) failed", shouldFade: true)
          let ns = error as NSError
          print(
            "⚠️ [MultiplayerBlackjack] playerAction(\(action)) failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))"
          )
          if action == MultiplayerBlackjackKeys.Actions.split {
            guard let defaultSeat = self.context.defaultSeat else { return }
            let seatHands = defaultSeat.hands
            let activeIdx = self.context.activeHandIndex
            let hand =
              activeIdx < seatHands.count
              ? seatHands[activeIdx] : defaultSeat.primaryHand
            let betAmount = hand.betControl.betAmount
            self.context.balance += betAmount
            print("💰 [split rollback] Restored bet \(betAmount) to balance \(self.context.balance)")
          } else if !self.optimisticCardsForMyHand.isEmpty {
            guard let defaultSeat = self.context.defaultSeat else { return }
            let seatHands = defaultSeat.hands
            let activeIdx = self.context.activeHandIndex
            let hand =
              activeIdx < seatHands.count
              ? seatHands[activeIdx] : defaultSeat.primaryHand
            let rollback = Array(
              hand.currentCards.dropLast(self.optimisticCardsForMyHand.count))
            hand.setCardsWithoutAnimation(rollback)
            if action == MultiplayerBlackjackKeys.Actions.double,
              let originalBet = originalBetForDouble
            {
              print(
                "BAL_BUG [double rollback] restoring bet \(originalBet) to balance \(self.context.balance) → \(self.context.balance + originalBet)"
              )
              self.context.balance += originalBet
              hand.betControl.betAmount = originalBet
              print("💰 [double rollback] Restored bet to \(originalBet)")
            }
          }
          self.optimisticCardsForMyHand.removeAll()
          self.optimisticDeckIndex = self.context.lastGameSnapshot?.deckIndex ?? 0
          self.isActionInFlight = false
          self.actionInFlightTimeoutWorkItem?.cancel()
          if let s = self.context.lastGameSnapshot {
            self.delegate?.actionHandlerRefreshButtonVisibility(for: s)
          }
        } else {
          let noOptimisticState =
            (action == MultiplayerBlackjackKeys.Actions.stand
              || action == MultiplayerBlackjackKeys.Actions.split)
          if noOptimisticState {
            self.isActionInFlight = false
            self.actionInFlightTimeoutWorkItem?.cancel()
            self.actionInFlightTimeoutWorkItem = nil
            if let s = self.context.lastGameSnapshot {
              self.delegate?.actionHandlerRefreshButtonVisibility(for: s)
            }
          }
        }
      }
    }

    let timeout = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      DispatchQueue.main.async {
        if self.isActionInFlight {
          self.isActionInFlight = false
          self.actionInFlightTimeoutWorkItem = nil
          if let s = self.context.lastGameSnapshot {
            self.delegate?.actionHandlerRefreshButtonVisibility(for: s)
          }
        }
      }
    }
    actionInFlightTimeoutWorkItem = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
  }

  // MARK: - Optimistic Card Prediction

  func predictAndDealCard(
    action: String,
    hand: CompactPlayerHandView,
    serverHandIndex: Int,
    originalBetForDouble: Int?
  ) {
    guard let provider = deckProvider,
      let card = provider.card(at: optimisticDeckIndex),
      let bjCard = context.blackjackCard(from: card)
    else {
      print(
        "⚠️ [MultiplayerBlackjack] Optimistic deck exhausted at index \(optimisticDeckIndex), sending action to server without animation"
      )
      sendPlayerActionToServer(
        action: action, handIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
      return
    }

    let deckCenter = context.deckCenter
    guard let containerView = context.containerView else { return }

    optimisticDeckIndex += 1
    optimisticCardsForMyHand.append(bjCard)

    if action == MultiplayerBlackjackKeys.Actions.double {
      hand.dealCard(bjCard, from: deckCenter, in: containerView)
      let bet = originalBetForDouble ?? hand.betControl.betAmount
      print("BAL_BUG [double] deducting bet \(bet) from balance \(context.balance) → \(context.balance - bet)")
      context.balance -= bet
      hand.betControl.setBetAmount(bet * 2, animated: true)
      print("💰 [double] Optimistically updated bet to \(bet * 2)")
    } else {
      hand.dealCard(bjCard, from: deckCenter, in: containerView)
    }

    let newTotal = context.blackjackTotal(hand.currentCards)
    if newTotal > 21 {
      handleBust(hand: hand, action: action, serverHandIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
    } else if newTotal == 21 {
      handleHitTo21(hand: hand, action: action, serverHandIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
    } else if action == MultiplayerBlackjackKeys.Actions.hit {
      isActionInFlight = false
      delegate?.actionHandlerSetStandButtonDisabled(false)
      delegate?.actionHandlerSetDoubleButtonDisabled(true)
    }

    if newTotal <= 21 || (newTotal > 21 && action == MultiplayerBlackjackKeys.Actions.hit) {
      if newTotal <= 21 && newTotal != 21 {
        sendPlayerActionToServer(
          action: action, handIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
      }
    }
  }

  private func handleBust(
    hand: CompactPlayerHandView,
    action: String,
    serverHandIndex: Int,
    originalBetForDouble: Int?
  ) {
    guard let defaultSeat = context.defaultSeat,
      let containerView = context.containerView
    else { return }
    let mySeatIndex = context.mySeatIndex

    hand.broadcastAction("Bust!")
    context.bustAnimatedSeatIndices.insert(mySeatIndex)

    let bustBet = hand.betControl.betAmount
    if bustBet > 0 {
      let bustResult = MPBlackjackTableState.HandResult(
        outcome: "lose", payout: 0, bet: bustBet)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        guard let self = self else { return }
        self.delegate?.actionHandlerAnimateLocalBustForfeit(
          seat: defaultSeat, hand: hand, result: bustResult)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
          let topLeft = CGPoint(x: 0, y: 0)
          hand.discardCards(to: topLeft, in: containerView) {}
        }
      }
    }

    let seatHands = defaultSeat.hands
    let activeIdx = context.activeHandIndex
    if activeIdx + 1 < seatHands.count {
      context.activeHandIndex = activeIdx + 1
      delegate?.actionHandlerUpdateTurnIndicatorDot(
        forSeatIndex: mySeatIndex, handIndex: activeIdx + 1)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        guard let self = self else { return }
        self.isActionInFlight = false
        if let snapshot = self.context.lastGameSnapshot {
          self.delegate?.actionHandlerRefreshButtonVisibility(for: snapshot)
        }
      }
    }

    sendPlayerActionToServer(
      action: action, handIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
  }

  private func handleHitTo21(
    hand: CompactPlayerHandView,
    action: String,
    serverHandIndex: Int,
    originalBetForDouble: Int?
  ) {
    guard let defaultSeat = context.defaultSeat else { return }
    let mySeatIndex = context.mySeatIndex
    let activeIdx = context.activeHandIndex
    let seatHands = defaultSeat.hands
    let hasNextSplitHand = activeIdx + 1 < seatHands.count

    if hasNextSplitHand {
      context.activeHandIndex = activeIdx + 1
      delegate?.actionHandlerUpdateTurnIndicatorDot(
        forSeatIndex: mySeatIndex, handIndex: activeIdx + 1)
    } else {
      delegate?.actionHandlerUpdateTurnIndicatorDot(forSeatIndex: nil, handIndex: 0)
      delegate?.actionHandlerHideTurnIndicatorDot()
    }

    let delayForHitTo21: TimeInterval = hasNextSplitHand ? 0.4 : 1.0
    if hasNextSplitHand {
      isActionInFlight = false
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + delayForHitTo21) { [weak self] in
      self?.sendPlayerActionToServer(
        action: action, handIndex: serverHandIndex, originalBetForDouble: originalBetForDouble)
      if hasNextSplitHand, let snapshot = self?.context.lastGameSnapshot {
        self?.delegate?.actionHandlerRefreshButtonVisibility(for: snapshot)
      }
    }
  }
}
