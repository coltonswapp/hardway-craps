//
//  MPInsuranceManager.swift
//  hardway-craps
//

import UIKit

protocol MPInsuranceManagerDelegate: AnyObject {
  func insuranceUpdateInstructionLabel(_ text: String, shouldFade: Bool)
  func insuranceRefreshButtonVisibility(for snapshot: MPBlackjackTableState.GameStateSnapshot)
  func insuranceHideBonusBetControl(animated: Bool)
  func insuranceCallResolveDealerBlackjack()
  func insuranceCallStartNextHand()
  func insuranceScrollToSeat(_ index: Int, animated: Bool)
  func insuranceShowBetResult(amount: Int, isWin: Bool, showBonus: Bool, description: String?)
  func insuranceAnimateLocalPlayerLoss(
    seat: PlayerSeat, result: MPBlackjackTableState.HandResult, delay: TimeInterval)
  func insuranceAnimateLocalPlayerPush(
    seat: PlayerSeat, result: MPBlackjackTableState.HandResult, delay: TimeInterval)
  func insuranceAnimateRemotePlayerLoss(
    seat: PlayerSeat, result: MPBlackjackTableState.HandResult, delay: TimeInterval)
  func insuranceCreateRemoteDot(color: UIColor) -> UIView
  func insurancePhaseResolved(
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    holeCard: BlackjackHandView.Card,
    upCard: BlackjackHandView.Card)
}

final class MPInsuranceManager {

  // MARK: - Properties

  weak var delegate: MPInsuranceManagerDelegate?
  let context: MPGameContext
  var tableState: MPBlackjackTableState?

  private(set) var isInsurancePhaseActive = false
  private(set) var localInsuranceBetAmount: Int = 0
  private(set) var pendingInsuranceSnapshot: MPBlackjackTableState.GameStateSnapshot?
  private(set) var pendingInsuranceHoleCard: BlackjackHandView.Card?
  private(set) var pendingInsuranceUpCard: BlackjackHandView.Card?
  var previousInsuranceBySeat: [Int: Int] = [:]

  init(context: MPGameContext) {
    self.context = context
  }

  // MARK: - Phase Lifecycle

  func startInsurancePhase(
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    holeCard: BlackjackHandView.Card,
    upCard: BlackjackHandView.Card
  ) {
    guard let continueButton = context.continueButton else { return }
    isInsurancePhaseActive = true

    continueButton.setTitleColor(.white, for: .normal)

    localInsuranceBetAmount = 0
    previousInsuranceBySeat.removeAll()
    pendingInsuranceSnapshot = snapshot
    pendingInsuranceHoleCard = holeCard
    pendingInsuranceUpCard = upCard

    guard let insuranceControl = context.insuranceControl else { return }
    insuranceControl.onTapped = { [weak self] in
      self?.handleInsuranceControlTapped()
    }

    insuranceControl.isHidden = false
    insuranceControl.alpha = 0
    UIView.animate(withDuration: 0.3) {
      insuranceControl.alpha = 1
    }

    updateInsuranceStatusLabel()
    delegate?.insuranceRefreshButtonVisibility(for: snapshot)
    delegate?.insuranceUpdateInstructionLabel(
      "Insurance? Tap the shield, or Continue", shouldFade: false)
  }

  func handleInsuranceControlTapped() {
    guard isInsurancePhaseActive,
      let insuranceControl = context.insuranceControl,
      let tableState = tableState
    else { return }
    let mySeatIndex = context.mySeatIndex
    let playerId = context.playerId

    if localInsuranceBetAmount > 0 {
      let refund = localInsuranceBetAmount
      context.balance += refund
      localInsuranceBetAmount = 0
      let myStyle = context.chipStyle(forColorName: context.myChipColorName)
      insuranceControl.removeInsuranceBet(for: myStyle)
      previousInsuranceBySeat[mySeatIndex] = 0
      tableState.placeInsuranceBet(seatIndex: mySeatIndex, amount: 0)
      tableState.updateBalance(playerId: playerId, balance: context.balance)
      updateInsuranceStatusLabel()
      return
    }

    guard let defaultSeat = context.defaultSeat else { return }
    let mainBet = defaultSeat.primaryHand.betControl.betAmount
    let insuranceAmount = mainBet / 2
    guard insuranceAmount > 0, context.balance >= insuranceAmount else {
      HapticsHelper.lightHaptic()
      return
    }

    context.balance -= insuranceAmount
    localInsuranceBetAmount = insuranceAmount
    let myStyle = context.chipStyle(forColorName: context.myChipColorName)
    insuranceControl.addInsuranceBet(amount: insuranceAmount, chipStyle: myStyle)
    previousInsuranceBySeat[mySeatIndex] = insuranceAmount
    tableState.placeInsuranceBet(seatIndex: mySeatIndex, amount: insuranceAmount)
    tableState.updateBalance(playerId: playerId, balance: context.balance)
    updateInsuranceStatusLabel()
  }

  func handleContinueButtonTapped() {
    guard isInsurancePhaseActive, let tableState = tableState else { return }
    HapticsHelper.lightHaptic()
    let mySeatIndex = context.mySeatIndex

    if localInsuranceBetAmount > 0 {
      tableState.placeInsuranceBet(seatIndex: mySeatIndex, amount: localInsuranceBetAmount)
    } else {
      tableState.declineInsurance(seatIndex: mySeatIndex)
    }

    if let continueButton = context.continueButton {
      UIView.animate(withDuration: 0.2) {
        continueButton.setTitleColor(.systemBlue, for: .normal)
      }
    }

    updateInsuranceStatusLabel()
    checkIfAllPlayersDecidedInsurance()
  }

  func checkIfAllPlayersDecidedInsurance() {
    guard isInsurancePhaseActive else { return }
    let currentSeatsData = context.currentSeatsData

    let allDecided = currentSeatsData.allSatisfy { $0.value.insuranceDecided }
    guard allDecided else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self = self,
        let result = self.resolveInsurancePhase()
      else { return }
      self.delegate?.insurancePhaseResolved(
        snapshot: result.snapshot, holeCard: result.holeCard, upCard: result.upCard)
      self.clearPendingInsurance()
    }
  }

  @discardableResult
  func resolveInsurancePhase() -> (
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    holeCard: BlackjackHandView.Card,
    upCard: BlackjackHandView.Card
  )? {
    guard isInsurancePhaseActive else { return nil }
    guard let snapshot = pendingInsuranceSnapshot,
      let holeCard = pendingInsuranceHoleCard,
      let upCard = pendingInsuranceUpCard
    else { return nil }

    isInsurancePhaseActive = false

    if let continueButton = context.continueButton {
      continueButton.setTitleColor(.white, for: .normal)
      continueButton.isHidden = true
      continueButton.alpha = 0
    }

    return (snapshot: snapshot, holeCard: holeCard, upCard: upCard)
  }

  func clearPendingInsurance() {
    pendingInsuranceSnapshot = nil
    pendingInsuranceHoleCard = nil
    pendingInsuranceUpCard = nil
  }

  func hideInsuranceControl(animated: Bool) {
    guard let control = context.insuranceControl, !control.isHidden else { return }

    if animated {
      UIView.animate(
        withDuration: 0.3,
        animations: {
          control.alpha = 0
        }
      ) { _ in
        control.isHidden = true
        control.clearAllBets()
        control.updateTitle("Insurance")
      }
    } else {
      control.isHidden = true
      control.alpha = 0
      control.clearAllBets()
      control.updateTitle("Insurance")
    }
  }

  func updateInsuranceStatusLabel() {
    guard let continueButton = context.continueButton,
      let label = continueButton.viewWithTag(999) as? UILabel
    else { return }
    if isInsurancePhaseActive {
      let hasInsurance = localInsuranceBetAmount > 0
      label.text = hasInsurance ? "Insured" : "Not Insured"
      label.textColor =
        hasInsurance
        ? HardwayColors.label.withAlphaComponent(0.9)
        : HardwayColors.label.withAlphaComponent(0.5)
    } else {
      label.text = ""
    }
  }

  // MARK: - State Setters

  func setLocalInsuranceBetAmount(_ amount: Int) {
    localInsuranceBetAmount = amount
  }

  // MARK: - Reset

  func resetForNewHand() {
    isInsurancePhaseActive = false
    localInsuranceBetAmount = 0
    previousInsuranceBySeat.removeAll()
    pendingInsuranceSnapshot = nil
    pendingInsuranceHoleCard = nil
    pendingInsuranceUpCard = nil
  }

  // MARK: - Dealer Blackjack Resolution

  func peekForDealerBlackjack(
    holeCard: BlackjackHandView.Card,
    upCard: BlackjackHandView.Card,
    snapshot: MPBlackjackTableState.GameStateSnapshot,
    continueWithNormalFlow: @escaping () -> Void
  ) {
    guard let delegate = delegate,
      let dealerHandView = context.dealerHandView,
      let insuranceControl = context.insuranceControl,
      let tableState = tableState,
      let containerView = context.containerView
    else { return }

    let hasDealerBlackjack = context.blackjackTotal([holeCard, upCard]) == 21

    if hasDealerBlackjack {
      dealerHandView.revealHoleCard(animated: true)

      let localSeatData = context.currentSeatsData[context.mySeatIndex]
      let insuranceBet = max(localInsuranceBetAmount, localSeatData?.insuranceBet ?? 0)
      let anyInsuranceBets = insuranceControl.chipCount > 0 || insuranceBet > 0

      if insuranceBet > 0 {
        let insuranceWin = insuranceBet * 2
        context.balance += insuranceWin
        tableState.updateBalance(playerId: context.playerId, balance: context.balance)
      }
      localInsuranceBetAmount = 0

      // Sync rendered count so the observer doesn't re-deal existing cards
      let dealerCardQueueRenderedCount = dealerHandView.currentCards.count
      // This needs to be set via a provider since dealerCardQueue is a separate manager
      onDealerCardsRenderedCountChanged?(dealerCardQueueRenderedCount)
      delegate.insuranceCallResolveDealerBlackjack()

      if !context.isBalanceFrozenForSettlement {
        context.isBalanceFrozenForSettlement = true
        context.preBetSettlementBalance = context.balance
      }

      var styleToSeat: [MPSmallBetChipStyle: Int] = [:]
      for (seatIndex, seatData) in context.currentSeatsData {
        if seatData.insuranceBet > 0 {
          styleToSeat[context.chipStyle(forColorName: seatData.chipColorName)] = seatIndex
        }
      }

      for (seatIndex, seatData) in context.currentSeatsData {
        guard seatData.hands.first?.bet ?? 0 > 0 else { continue }
        context.bustAnimatedSeatIndices.insert(seatIndex)
      }

      let insuranceDisplayDuration: TimeInterval
      if anyInsuranceBets {
        insuranceControl.updateTitle("Insurance Pays!")
        delegate.insuranceUpdateInstructionLabel("Dealer Blackjack! Insurance pays 2:1", shouldFade: false)
        insuranceControl.playWinAnimation()
        if insuranceBet > 0 {
          delegate.insuranceShowBetResult(amount: insuranceBet * 2, isWin: true, showBonus: false, description: "INSURANCE")
        }
        insuranceDisplayDuration = 2.0
      } else {
        delegate.insuranceUpdateInstructionLabel("Dealer Blackjack!", shouldFade: false)
        insuranceDisplayDuration = 0.8
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + insuranceDisplayDuration) { [weak self] in
        guard let self = self, let delegate = self.delegate else { return }

        self.animateInsurancePayoutDots(styleToSeat: styleToSeat) { [weak self] in
          guard let self = self else { return }
          insuranceControl.animateChipsAway { [weak self] in
            self?.hideInsuranceControl(animated: true)
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.resolveMainBetsAfterDealerBlackjack()
          }
        }
      }
    } else {
      dealerHandView.playSpreadAnimation()

      if localInsuranceBetAmount > 0 || insuranceControl.chipCount > 0 {
        delegate.insuranceUpdateInstructionLabel("No dealer blackjack. Insurance lost.", shouldFade: true)
        localInsuranceBetAmount = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
          guard let self = self, let insuranceControl = self.context.insuranceControl else { return }
          insuranceControl.animateChipsAway {
            self.hideInsuranceControl(animated: true)
          }
        }
      } else {
        hideInsuranceControl(animated: true)
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        continueWithNormalFlow()
      }
    }
  }

  func animateServerResolvedDealerBlackjack(
    snapshot: MPBlackjackTableState.GameStateSnapshot
  ) {
    guard let delegate = delegate,
      let dealerHandView = context.dealerHandView,
      let containerView = context.containerView
    else { return }

    dealerHandView.revealHoleCard(animated: true)
    delegate.insuranceUpdateInstructionLabel("Dealer Blackjack!", shouldFade: false)
    onDealerCardsRenderedCountChanged?(dealerHandView.currentCards.count)

    let totalBonusBets = context.currentSeatsData.values.reduce(0) { total, seatData in
      total + (seatData.bonusBets[0] ?? 0)
    }
    if totalBonusBets == 0 {
      delegate.insuranceHideBonusBetControl(animated: true)
    }

    if !context.isBalanceFrozenForSettlement {
      context.isBalanceFrozenForSettlement = true
      context.preBetSettlementBalance = context.balance
    }

    var animationDelay: TimeInterval = 0.6
    let topLeft = CGPoint(x: 0, y: 0)
    var maxDelay: TimeInterval = 0.6

    for (seatIndex, seatData) in context.currentSeatsData {
      guard let hand = seatData.hands.first, hand.bet > 0 else { continue }
      guard let seatView = context.seatView(forIndex: seatIndex) else { continue }
      let cards = hand.cards.compactMap { context.cardFromFirebase($0) }
      let playerIsBlackjack = cards.count == 2 && context.blackjackTotal(cards) == 21
      if playerIsBlackjack {
        seatView.primaryHand.broadcastAction("Blackjack!")
      }
      let bet = hand.bet
      let result: MPBlackjackTableState.HandResult =
        playerIsBlackjack
        ? MPBlackjackTableState.HandResult(outcome: "push", payout: bet, bet: bet)
        : MPBlackjackTableState.HandResult(outcome: "lose", payout: 0, bet: bet)

      context.bustAnimatedSeatIndices.insert(seatIndex)
      let isLocal = (seatIndex == context.mySeatIndex)
      let delay = animationDelay

      if result.isPush {
        context.pushBetsBySeatIndex[seatIndex] = result.bet
        seatView.primaryHand.broadcastAction("Push")
        if isLocal {
          delegate.insuranceAnimateLocalPlayerPush(seat: seatView, result: result, delay: delay)
        }
      } else {
        if isLocal {
          delegate.insuranceAnimateLocalPlayerLoss(seat: seatView, result: result, delay: delay)
          DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) {
            delegate.insuranceShowBetResult(amount: result.bet, isWin: false, showBonus: false, description: nil)
          }
        } else {
          delegate.insuranceAnimateRemotePlayerLoss(seat: seatView, result: result, delay: delay)
        }
      }

      let discardDelay = delay + 1.2
      DispatchQueue.main.asyncAfter(deadline: .now() + discardDelay) {
        seatView.primaryHand.discardCards(to: topLeft, in: containerView) {}
      }
      maxDelay = max(maxDelay, discardDelay + 0.5)
      animationDelay += 0.15
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + maxDelay) { [weak self] in
      guard let self = self, let delegate = self.delegate else { return }
      guard let snapshot = self.context.lastGameSnapshot else { return }
      delegate.insuranceRefreshButtonVisibility(for: snapshot)
      delegate.insuranceScrollToSeat(self.context.mySeatIndex, animated: true)
      if self.context.isHost {
        delegate.insuranceCallStartNextHand()
      }
    }
  }

  func resolveMainBetsAfterDealerBlackjack() {
    guard let delegate = delegate, let containerView = context.containerView else { return }
    var animationDelay: TimeInterval = 0.3
    let topLeft = CGPoint(x: 0, y: 0)

    for (seatIndex, seatData) in context.currentSeatsData {
      guard let hand = seatData.hands.first, hand.bet > 0 else { continue }
      guard let seatView = context.seatView(forIndex: seatIndex) else { continue }
      let cards = hand.cards.compactMap { context.cardFromFirebase($0) }
      let playerIsBlackjack = cards.count == 2 && context.blackjackTotal(cards) == 21
      if playerIsBlackjack {
        seatView.primaryHand.broadcastAction("Blackjack!")
      }
      let bet = hand.bet
      let result: MPBlackjackTableState.HandResult =
        playerIsBlackjack
        ? MPBlackjackTableState.HandResult(outcome: "push", payout: bet, bet: bet)
        : MPBlackjackTableState.HandResult(outcome: "lose", payout: 0, bet: bet)

      context.bustAnimatedSeatIndices.insert(seatIndex)
      let isLocal = (seatIndex == context.mySeatIndex)
      let delay = animationDelay

      if result.isPush {
        context.pushBetsBySeatIndex[seatIndex] = result.bet
        seatView.primaryHand.broadcastAction("Push")
        if isLocal {
          delegate.insuranceAnimateLocalPlayerPush(seat: seatView, result: result, delay: delay)
        }
      } else {
        if isLocal {
          delegate.insuranceAnimateLocalPlayerLoss(seat: seatView, result: result, delay: delay)
          DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) {
            delegate.insuranceShowBetResult(amount: result.bet, isWin: false, showBonus: false, description: nil)
          }
        } else {
          delegate.insuranceAnimateRemotePlayerLoss(seat: seatView, result: result, delay: delay)
        }
      }

      let discardDelay = delay + 1.2
      DispatchQueue.main.asyncAfter(deadline: .now() + discardDelay) {
        seatView.primaryHand.discardCards(to: topLeft, in: containerView) {}
      }
      animationDelay += 0.15
    }
  }

  func animateInsurancePayoutDots(
    styleToSeat: [MPSmallBetChipStyle: Int],
    completion: @escaping () -> Void
  ) {
    guard let delegate = delegate,
      let containerView = context.containerView,
      let insuranceControl = context.insuranceControl
    else {
      completion()
      return
    }

    let chipPositions = insuranceControl.chipPositions(in: containerView)
    guard !chipPositions.isEmpty else {
      completion()
      return
    }

    var longestFlight: TimeInterval = 0

    for entry in chipPositions {
      guard let seatIndex = styleToSeat[entry.style] else { continue }
      let dotColor = entry.style.strokeColor
      let isLocal = (seatIndex == context.mySeatIndex)

      let destination: CGPoint
      if isLocal, let balanceView = context.balanceView {
        destination = balanceView.convert(
          CGPoint(x: balanceView.bounds.maxX - 30, y: balanceView.bounds.midY),
          to: containerView
        )
      } else if let seat = context.seatView(forIndex: seatIndex),
        let balView = seat.subviews.compactMap({ $0 as? MPPlayerBalanceView }).first
      {
        destination = seat.convert(
          CGPoint(x: balView.frame.midX, y: balView.frame.midY),
          to: containerView
        )
      } else {
        continue
      }

      let dot = delegate.insuranceCreateRemoteDot(color: dotColor)
      dot.center = entry.center
      dot.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
      containerView.addSubview(dot)

      let flightDuration: TimeInterval = 0.4
      let fly = UIViewPropertyAnimator(
        duration: flightDuration,
        controlPoint1: CGPoint(x: 0.85, y: 0),
        controlPoint2: CGPoint(x: 0.15, y: 1)
      ) {
        dot.center = destination
        dot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
      }
      fly.addCompletion { _ in
        dot.removeFromSuperview()
      }
      fly.startAnimation()
      longestFlight = max(longestFlight, flightDuration)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + longestFlight + 0.1) {
      completion()
    }
  }

  /// Callback for syncing dealer card rendered count to the dealer card queue manager
  var onDealerCardsRenderedCountChanged: ((Int) -> Void)?
}
