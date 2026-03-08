//
//  MPDealAnimationController.swift
//  hardway-craps
//

import UIKit

protocol MPDealAnimationControllerDelegate: AnyObject {
  func dealAnimationHideTurnIndicatorDot()
  func dealAnimationUpdateTurnIndicatorDot(forSeatIndex: Int?, handIndex: Int)
  func dealAnimationUpdateInstructionLabel(_ message: String, shouldFade: Bool)
  func dealAnimationShowBonusBetControl(animated: Bool)
  func dealAnimationHideBonusBetControl(animated: Bool)
  func dealAnimationRefreshButtonVisibility(for snapshot: MPBlackjackTableState.GameStateSnapshot)
  func dealAnimationScrollToSeat(_ index: Int, animated: Bool)
  func dealAnimationScrollToSeatHand(_ index: Int, handIndex: Int, animated: Bool)
  func dealAnimationCallPlayerAction(_ action: String)
  func dealAnimationStartInsurancePhase(
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    holeCard: BlackjackHandView.Card, upCard: BlackjackHandView.Card)
  func dealAnimationPeekForDealerBlackjack(
    holeCard: BlackjackHandView.Card, upCard: BlackjackHandView.Card,
    snapshot: MPBlackjackTableState.GameStateSnapshot, completion: @escaping () -> Void)
  func dealAnimationAnimateServerResolvedDealerBlackjack(
    snapshot: MPBlackjackTableState.GameStateSnapshot)
  func dealAnimationApplyCardsWithoutDealAnimation(
    snapshot: MPBlackjackTableState.GameStateSnapshot, deckCenter: CGPoint)
  func dealAnimationAnimateBonusBetResults(
    _ results: [Int: [Int: MPBlackjackTableState.BonusBetResultData]],
    isDealerOutcome: Bool, completion: @escaping () -> Void)
  func dealAnimationGetPlayerHandsFromSeats() -> [Int: [[String: Any]]]
  func dealAnimationSeatsScrollView() -> UIScrollView
  func dealAnimationDealButton() -> UIButton
}

final class MPDealAnimationController {

  weak var delegate: MPDealAnimationControllerDelegate?
  let context: MPGameContext

  var previousCardCountsBySeat: [Int: Int] = [:]
  var previousHasStoodBySeat: [Int: Bool] = [:]

  init(context: MPGameContext) {
    self.context = context
  }

  // MARK: - Initial Deal Animation

  func runInitialDealAnimation(
    snapshot: MPBlackjackTableState.GameStateSnapshot, deckCenter: CGPoint
  ) {
    guard let delegate = delegate else { return }
    context.isDealAnimationRunning = true
    delegate.dealAnimationHideTurnIndicatorDot()
    context.cardApplyGeneration += 1
    delegate.dealAnimationUpdateInstructionLabel("Dealing cards...", shouldFade: false)

    if let bonusBetControl = context.bonusBetControl,
      bonusBetControl.isHidden && bonusBetControl.chipCount > 0
    {
      delegate.dealAnimationShowBonusBetControl(animated: false)
    }

    let playerHands = delegate.dealAnimationGetPlayerHandsFromSeats()
    for (seatIndex, hands) in playerHands {
      guard let seatView = context.seatView(forIndex: seatIndex) else { continue }
      for (handIndex, _) in hands.enumerated() {
        let handView =
          handIndex == 0
          ? seatView.primaryHand
          : (seatView.hands.count > handIndex ? seatView.hands[handIndex] : nil)
        handView?.handView.clearCards()
      }
    }
    context.dealerHandView?.setCardsWithoutAnimation([])

    guard let containerView = context.containerView else { return }
    containerView.setNeedsLayout()
    containerView.layoutIfNeeded()

    let seatsScrollView = delegate.dealAnimationSeatsScrollView()
    if let firstSeatIndex = playerHands.keys.sorted().first,
      let firstSeatView = context.seatView(forIndex: firstSeatIndex)
    {
      let seatRect = firstSeatView.convert(firstSeatView.bounds, to: seatsScrollView)
      seatsScrollView.scrollRectToVisible(seatRect, animated: false)
    }

    containerView.layoutIfNeeded()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      guard let self = self else { return }
      self.startDealAnimationSteps(snapshot: snapshot)
    }
  }

  // MARK: - Deal Steps

  private func startDealAnimationSteps(snapshot: MPBlackjackTableState.GameStateSnapshot) {
    guard let delegate = delegate,
      let containerView = context.containerView,
      let dealerHandView = context.dealerHandView,
      let deckView = context.deckView
    else { return }

    let playerHands = delegate.dealAnimationGetPlayerHandsFromSeats()
    let seatIndices = playerHands.keys.sorted()
    let mySeatIndex = context.mySeatIndex

    if playerHands.keys.contains(mySeatIndex) {
      delegate.dealAnimationScrollToSeat(mySeatIndex, animated: true)
    }

    var playerFirstCards:
      [(card: BlackjackHandView.Card, hand: CompactPlayerHandView, seatIndex: Int)] = []
    var playerSecondCards:
      [(card: BlackjackHandView.Card, hand: CompactPlayerHandView, seatIndex: Int)] = []

    for seatIndex in seatIndices {
      guard let hands = playerHands[seatIndex], !hands.isEmpty,
        let cardsRaw = hands[0][MultiplayerBlackjackKeys.HandData.cards] as? [[String: Any]],
        let seatView = context.seatView(forIndex: seatIndex)
      else {
        print("⚠️ [MultiplayerBlackjack] Skipping seat \(seatIndex) - no hands or seatView")
        continue
      }
      let hand = seatView.primaryHand
      if cardsRaw.count >= 1, let card = context.cardFromFirebase(cardsRaw[0]) {
        playerFirstCards.append((card, hand, seatIndex))
      }
      if cardsRaw.count >= 2, let card = context.cardFromFirebase(cardsRaw[1]) {
        playerSecondCards.append((card, hand, seatIndex))
      }
    }

    let dealerCard1: BlackjackHandView.Card? = snapshot.dealerCards.first.flatMap {
      context.cardFromFirebase($0)
    }
    let dealerCard2: BlackjackHandView.Card? =
      (snapshot.dealerCards.count >= 2) ? context.cardFromFirebase(snapshot.dealerCards[1]) : nil

    for (idx, step) in playerFirstCards.enumerated() {
      let delay = Double(idx) * 0.3
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self = self, let delegate = self.delegate else { return }
        if step.seatIndex == mySeatIndex {
          delegate.dealAnimationScrollToSeat(mySeatIndex, animated: true)
        }
        let deckCenter = containerView.convert(deckView.deckCenter, from: deckView)
        step.hand.dealCard(step.card, from: deckCenter, in: containerView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          let cardCount = step.hand.currentCards.count
          if cardCount > 0 {
            step.hand.revealCard(at: cardCount - 1, animated: false)
          }
          if step.hand.currentCards.isEmpty {
            print("❌ [MultiplayerBlackjack] Card not set after deal animation, setting directly")
            step.hand.setCardsWithoutAnimation([step.card])
          }
        }
      }
    }

    if let card = dealerCard1 {
      let delay = Double(playerFirstCards.count) * 0.3
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self = self else { return }
        let deckCenter = containerView.convert(deckView.deckCenter, from: deckView)
        dealerHandView.dealCardFaceDown(card, from: deckCenter, in: containerView)
      }
    }

    for (idx, step) in playerSecondCards.enumerated() {
      let delay = Double(playerFirstCards.count + 1 + idx) * 0.3
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self = self, let delegate = self.delegate else { return }
        if step.seatIndex == mySeatIndex {
          delegate.dealAnimationScrollToSeat(mySeatIndex, animated: true)
        }
        print(
          "🎴 [MultiplayerBlackjack] Dealing second card to seat \(step.seatIndex) at delay \(delay)"
        )
        let deckCenter = containerView.convert(deckView.deckCenter, from: deckView)
        print(
          "🎴 [MultiplayerBlackjack] Hand before deal: \(step.hand.currentCards.count) cards, card: \(step.card.rank) \(step.card.suit)"
        )
        step.hand.dealCard(step.card, from: deckCenter, in: containerView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak delegate] in
          print(
            "🎴 [MultiplayerBlackjack] Hand after deal animation: \(step.hand.currentCards.count) cards"
          )
          let cardCount = step.hand.currentCards.count
          if cardCount > 0 {
            step.hand.revealCard(at: cardCount - 1, animated: false)
          }
          if step.hand.currentCards.count < 2 {
            let playerHands = delegate?.dealAnimationGetPlayerHandsFromSeats() ?? [:]
            if let hands = playerHands[step.seatIndex], !hands.isEmpty,
              let cardsRaw = hands[0][MultiplayerBlackjackKeys.HandData.cards] as? [[String: Any]]
            {
              let allCards = cardsRaw.compactMap { self.context.cardFromFirebase($0) }
              step.hand.setCardsWithoutAnimation(allCards)
              for i in 0..<allCards.count {
                step.hand.revealCard(at: i, animated: false)
              }
            }
          }
        }
      }
    }

    let lastCardDelay: Double
    if let card = dealerCard2 {
      lastCardDelay = Double(playerFirstCards.count + 1 + playerSecondCards.count) * 0.3
      DispatchQueue.main.asyncAfter(deadline: .now() + lastCardDelay) { [weak self] in
        guard let self = self else { return }
        let deckCenter = containerView.convert(deckView.deckCenter, from: deckView)
        dealerHandView.dealCard(card, from: deckCenter, in: containerView)
      }
    } else {
      lastCardDelay = Double(playerFirstCards.count + 1 + playerSecondCards.count - 1) * 0.3
    }

    let completionDelay = lastCardDelay + 0.5
    DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) { [weak self] in
      guard let self = self, let delegate = self.delegate else { return }
      self.context.isDealAnimationRunning = false
      self.context.isDealInProgress = false
      delegate.dealAnimationDealButton().isEnabled = true
      guard let snapshot = self.context.lastGameSnapshot else { return }

      let dealtHands = delegate.dealAnimationGetPlayerHandsFromSeats()
      for (seatIdx, hands) in dealtHands {
        for (handIdx, handDict) in hands.enumerated() {
          let cards = (handDict[MultiplayerBlackjackKeys.HandData.cards] as? [[String: Any]] ?? [])
          let trackingKey = seatIdx * 10 + handIdx
          self.previousCardCountsBySeat[trackingKey] = cards.count
          self.previousHasStoodBySeat[trackingKey] = false
        }
      }

      let deckCenter = containerView.convert(deckView.deckCenter, from: deckView)
      delegate.dealAnimationApplyCardsWithoutDealAnimation(snapshot: snapshot, deckCenter: deckCenter)

      if snapshot.dealerHasBlackjack {
        delegate.dealAnimationAnimateServerResolvedDealerBlackjack(snapshot: snapshot)
        return
      }

      let dealerCards = dealerHandView.currentCards
      if dealerCards.count >= 2 {
        let holeCard = dealerCards[0]
        let upCard = dealerCards[1]
        if upCard.rank == .ace {
          self.resolvePairBonusBetsAfterDealIfNeeded(snapshot: snapshot) {
            delegate.dealAnimationStartInsurancePhase(
              snapshot: snapshot, holeCard: holeCard, upCard: upCard)
          }
          return
        }
        if self.context.isTenValueRank(upCard.rank) {
          delegate.dealAnimationPeekForDealerBlackjack(
            holeCard: holeCard, upCard: upCard, snapshot: snapshot
          ) { [weak self] in
            self?.runShowTurnUIAfterDeal(bjAnimDuration: 0)
          }
          return
        }
      }

      self.runShowTurnUIAfterDeal(bjAnimDuration: 0)
    }
  }

  // MARK: - Post-Deal Turn UI

  func runShowTurnUIAfterDeal(bjAnimDuration: TimeInterval) {
    guard let delegate = delegate else { return }

    let showTurnUI = { [weak self] in
      guard let self = self, let delegate = self.delegate else { return }
      guard let snapshot = self.context.lastGameSnapshot else { return }
      let phase = snapshot.phase ?? ""
      let turn = snapshot.currentTurn
      let mySeatIndex = self.context.mySeatIndex
      let isMyTurn = (turn?.seatIndex == mySeatIndex)

      if phase == MultiplayerBlackjackKeys.Phases.playerActions,
        let turn = turn,
        turn.seatIndex == mySeatIndex,
        !self.context.isActionInFlight,
        !self.context.isBlackjackPayoutAnimating
      {
        let myHandsData = self.context.currentSeatsData[mySeatIndex]?.hands ?? []
        let myHandData =
          turn.handIndex < myHandsData.count ? myHandsData[turn.handIndex] : myHandsData.first
        if let handData = myHandData,
          handData.cards.count == 2
        {
          let cards = handData.cards.compactMap { self.context.cardFromFirebase($0) }
          if cards.count == 2 && self.context.blackjackTotal(cards) == 21 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
              guard let self = self, let delegate = self.delegate else { return }
              if let currentSnapshot = self.context.lastGameSnapshot,
                let currentTurn = currentSnapshot.currentTurn,
                currentTurn.seatIndex == mySeatIndex,
                currentTurn.handIndex == turn.handIndex,
                !self.context.isActionInFlight,
                !self.context.isBlackjackPayoutAnimating
              {
                delegate.dealAnimationCallPlayerAction(MultiplayerBlackjackKeys.Actions.stand)
              }
            }
          }
        }
      }

      if phase == MultiplayerBlackjackKeys.Phases.playerActions {
        let turnMessage: String
        if isMyTurn {
          turnMessage = "Tap your hand to Hit"
        } else if let si = turn?.seatIndex,
          let name = self.context.currentSeatsData[si]?.displayLabel
        {
          turnMessage = "\(name)'s turn"
        } else {
          turnMessage = "Waiting for other players"
        }
        delegate.dealAnimationUpdateInstructionLabel(turnMessage, shouldFade: false)
        if let seatIndex = turn?.seatIndex {
          let handIndex = turn?.handIndex ?? 0
          delegate.dealAnimationScrollToSeatHand(seatIndex, handIndex: handIndex, animated: true)
        }
        delegate.dealAnimationUpdateTurnIndicatorDot(
          forSeatIndex: turn?.seatIndex, handIndex: turn?.handIndex ?? 0)
        delegate.dealAnimationRefreshButtonVisibility(for: snapshot)
      } else if phase == MultiplayerBlackjackKeys.Phases.dealerTurn {
        delegate.dealAnimationRefreshButtonVisibility(for: snapshot)
      } else if phase == MultiplayerBlackjackKeys.Phases.betweenHands {
        delegate.dealAnimationRefreshButtonVisibility(for: snapshot)
      }
    }

    let afterBjDelay = max(bjAnimDuration, 0)
    let runAfterBonusBets = { [weak self] in
      guard let self = self, let delegate = self.delegate else {
        showTurnUI()
        return
      }
      guard let snapshot = self.context.lastGameSnapshot else {
        showTurnUI()
        return
      }

      let totalBonusBets = self.context.currentSeatsData.values.reduce(0) { total, seatData in
        total + (seatData.bonusBets[0] ?? 0)
      }
      if totalBonusBets == 0 {
        delegate.dealAnimationHideBonusBetControl(animated: true)
      }

      if !snapshot.bonusBetResults.isEmpty && !self.context.bonusBetResultsProcessed {
        self.context.bonusBetResultsProcessed = true
        delegate.dealAnimationAnimateBonusBetResults(
          snapshot.bonusBetResults, isDealerOutcome: false
        ) {
          showTurnUI()
        }
      } else {
        showTurnUI()
      }
    }

    if afterBjDelay > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + afterBjDelay, execute: runAfterBonusBets)
    } else {
      runAfterBonusBets()
    }
  }

  // MARK: - Pair Bonus Resolution

  func resolvePairBonusBetsAfterDealIfNeeded(
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    completion: @escaping () -> Void
  ) {
    guard let delegate = delegate else {
      completion()
      return
    }
    let totalBonusBets = context.currentSeatsData.values.reduce(0) { total, seatData in
      total + (seatData.bonusBets[0] ?? 0)
    }
    if totalBonusBets == 0 {
      delegate.dealAnimationHideBonusBetControl(animated: true)
    }

    if !snapshot.bonusBetResults.isEmpty && !context.bonusBetResultsProcessed {
      context.bonusBetResultsProcessed = true
      delegate.dealAnimationAnimateBonusBetResults(
        snapshot.bonusBetResults, isDealerOutcome: false
      ) {
        completion()
      }
    } else {
      completion()
    }
  }
}
