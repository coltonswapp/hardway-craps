//
//  MPHandResetManager.swift
//  hardway-craps
//

import UIKit

protocol MPHandResetManagerDelegate: AnyObject {
  func handResetResetDealerCardQueue()
  func handResetSyncHandsToFirebase(for seat: PlayerSeat)
  func handResetHideInsuranceControl(animated: Bool)
  func handResetShowBonusBetControl(animated: Bool)
  func handResetResetInsuranceManager()
  func handResetClearTableInsurance()
  func handResetClearTableBonusBets()
}

final class MPHandResetManager {

  weak var delegate: MPHandResetManagerDelegate?
  let context: MPGameContext

  var previousHandsByIndex: [Int: [MPBlackjackTableState.HandData]] = [:]
  var previousBalanceByIndex: [Int: Int] = [:]
  var previousHandCountsBySeat: [Int: Int] = [:]
  var localBonusBetAmount: Int = 0
  var previousBonusBetsBySeat: [Int: Int] = [:]

  /// Callbacks for resetting state owned by other managers
  var onResetBetReconciliation: (() -> Void)?
  var onResetOptimisticState: (() -> Void)?
  var onResetPreviousCardCounts: (() -> Void)?

  init(context: MPGameContext) {
    self.context = context
  }

  // MARK: - Card Clearing

  func clearAllCardsForNewHand(isForcedReset: Bool = false, isBettingPhase: Bool = false) {
    guard let delegate = delegate,
      let dealerHandView = context.dealerHandView,
      let containerView = context.containerView
    else { return }

    delegate.handResetResetDealerCardQueue()

    let dealerCards = dealerHandView.currentCards
    var playerHandsToDiscard: [(hand: CompactPlayerHandView, cards: [BlackjackHandView.Card])] = []
    for (_, seatView) in context.seatViewsByIndex {
      for hand in seatView.hands {
        let cards = hand.handView.currentCards
        if !cards.isEmpty {
          playerHandsToDiscard.append((hand: hand, cards: cards))
        }
      }
    }

    guard !dealerCards.isEmpty || !playerHandsToDiscard.isEmpty else {
      performCardClearingCleanup(isForcedReset: isForcedReset, isBettingPhase: isBettingPhase)
      return
    }

    let topLeftPoint = CGPoint(x: 0, y: 0)
    var completedDiscards = 0
    let totalDiscards = (dealerCards.isEmpty ? 0 : 1) + playerHandsToDiscard.count

    func checkCompletion() {
      completedDiscards += 1
      if completedDiscards >= totalDiscards {
        self.performCardClearingCleanup(isForcedReset: isForcedReset, isBettingPhase: isBettingPhase)
      }
    }

    if !dealerCards.isEmpty {
      dealerHandView.discardCards(to: topLeftPoint, in: containerView) {
        checkCompletion()
      }
    } else {
      checkCompletion()
    }

    for (hand, _) in playerHandsToDiscard {
      hand.discardCards(to: topLeftPoint, in: containerView) {
        checkCompletion()
      }
    }
  }

  func performCardClearingCleanup(isForcedReset: Bool = false, isBettingPhase: Bool = false) {
    guard let delegate = delegate,
      let dealerHandView = context.dealerHandView
    else { return }

    delegate.handResetResetDealerCardQueue()
    dealerHandView.setCardsWithoutAnimation([])

    var seatsWithSplitHands: [(seatView: PlayerSeat, seatIndex: Int)] = []

    for (seatIndex, seatView) in context.seatViewsByIndex {
      for hand in seatView.hands {
        hand.clearCards()
      }

      if seatView.hands.count > 1 {
        seatsWithSplitHands.append((seatView: seatView, seatIndex: seatIndex))
      } else {
        applyBetResetForSeat(
          seatView: seatView, seatIndex: seatIndex,
          isForcedReset: isForcedReset, isBettingPhase: isBettingPhase)
      }
    }

    if seatsWithSplitHands.isEmpty {
      finishCardClearingCleanup(isForcedReset: isForcedReset)
    } else {
      animateSplitHandCollapse(
        seats: seatsWithSplitHands,
        isForcedReset: isForcedReset,
        isBettingPhase: isBettingPhase
      ) { [weak self] in
        self?.finishCardClearingCleanup(isForcedReset: isForcedReset)
      }
    }
  }

  private func applyBetResetForSeat(
    seatView: PlayerSeat, seatIndex: Int,
    isForcedReset: Bool, isBettingPhase: Bool
  ) {
    let primaryHand = seatView.primaryHand
    if isForcedReset {
      primaryHand.betControl.betAmount = 0
      context.pushBetsBySeatIndex.removeValue(forKey: seatIndex)
      print("💰 [MP-VC] Forced reset: clearing bet for seat \(seatIndex)")
    } else if let pushBet = context.pushBetsBySeatIndex[seatIndex], pushBet > 0 {
      primaryHand.betControl.setBetAmount(pushBet, animated: true)
      print("💰 [MP-VC] Restoring push bet \(pushBet) for seat \(seatIndex)")
      if seatIndex == context.mySeatIndex {
        delegate?.handResetSyncHandsToFirebase(for: seatView)
      }
      context.pushBetsBySeatIndex.removeValue(forKey: seatIndex)
    } else {
      let firebaseBet = context.currentSeatsData[seatIndex]?.hands.first?.bet ?? 0
      if isBettingPhase && firebaseBet > 0 {
        primaryHand.betControl.setBetAmount(firebaseBet, animated: false)
        print(
          "💰 [MP-VC] Preserving Firebase bet \(firebaseBet) for seat \(seatIndex) during card clearing"
        )
      } else {
        primaryHand.betControl.betAmount = 0
      }
    }
  }

  func animateSplitHandCollapse(
    seats: [(seatView: PlayerSeat, seatIndex: Int)],
    isForcedReset: Bool = false,
    isBettingPhase: Bool = false,
    completion: @escaping () -> Void
  ) {
    let additionalHands = seats.flatMap { $0.seatView.hands.dropFirst() }
    UIView.animate(
      withDuration: 0.25, delay: 0, options: .curveEaseIn,
      animations: {
        for hand in additionalHands {
          hand.alpha = 0
          hand.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
      }
    ) { [weak self] _ in
      guard let self = self else {
        completion()
        return
      }

      for (seatView, seatIndex) in seats {
        seatView.removeAllAdditionalHands()
        self.applyBetResetForSeat(
          seatView: seatView, seatIndex: seatIndex,
          isForcedReset: isForcedReset, isBettingPhase: isBettingPhase)
      }

      UIView.animate(
        withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5,
        animations: {
          for (seatView, _) in seats {
            seatView.layoutIfNeeded()
            seatView.superview?.layoutIfNeeded()
          }
        }
      ) { _ in
        completion()
      }
    }
  }

  func finishCardClearingCleanup(isForcedReset: Bool = false) {
    guard let delegate = delegate,
      let insuranceControl = context.insuranceControl,
      let bonusBetControl = context.bonusBetControl
    else { return }

    context.activeHandIndex = 0
    previousHandsByIndex.removeAll()
    previousBalanceByIndex.removeAll()
    onResetPreviousCardCounts?()
    previousHandCountsBySeat.removeAll()
    print(
      "BAL_BUG [clearAllCards] unfreezing balance — current balance: \(context.balance), preBetSettlementBalance: \(context.preBetSettlementBalance)"
    )
    context.isBalanceFrozenForSettlement = false
    context.preBetSettlementBalance = 0
    context.lastGameSnapshot = nil
    context.previousGameSnapshot = nil
    onResetBetReconciliation?()
    onResetOptimisticState?()

    insuranceControl.clearAllBets()
    delegate.handResetHideInsuranceControl(animated: false)
    delegate.handResetResetInsuranceManager()
    delegate.handResetClearTableInsurance()

    bonusBetControl.clearAllBets()
    localBonusBetAmount = 0
    previousBonusBetsBySeat.removeAll()
    context.bonusBetResultsProcessed = false
    delegate.handResetClearTableBonusBets()
    delegate.handResetShowBonusBetControl(animated: false)

    if isForcedReset {
      context.pushBetsBySeatIndex.removeAll()
      print("💰 [MP-VC] Forced reset: cleared all push bets")
    }
  }
}
