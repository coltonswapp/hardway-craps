//
//  MPChipAnimationHelper.swift
//  hardway-craps
//

import UIKit

protocol MPChipAnimationHelperDelegate: AnyObject {
  func chipAnimationShowBetResult(amount: Int, isWin: Bool, showBonus: Bool, description: String?)
  func chipAnimationScrollToSeat(_ index: Int, animated: Bool)
  func chipAnimationRefreshButtonVisibility(for snapshot: MPBlackjackTableState.GameStateSnapshot)
  func chipAnimationCallStartNextHand()
}

final class MPChipAnimationHelper {

  // MARK: - Properties

  weak var delegate: MPChipAnimationHelperDelegate?
  let context: MPGameContext

  private(set) var isBetReconciliationRunning = false
  private(set) var isBonusBetResolutionAnimating = false
  private(set) var bonusBetResultsProcessed = false

  init(context: MPGameContext) {
    self.context = context
  }

  // MARK: - Chip Factory

  func createAnimationChip(amount: Int) -> SmallBetChip {
    let chip = SmallBetChip()
    chip.amount = amount
    chip.translatesAutoresizingMaskIntoConstraints = true
    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    let size: CGFloat = isIPad ? 30 * 1.25 : 30
    chip.frame = CGRect(x: 0, y: 0, width: size, height: size)
    chip.isHidden = false
    return chip
  }

  func createRemoteMPChip(style: MPSmallBetChipStyle, amount: Int) -> MPSmallBetChip {
    let chip = MPSmallBetChip(style: style)
    chip.translatesAutoresizingMaskIntoConstraints = true
    let chipSize: CGFloat = 30
    chip.frame = CGRect(x: 0, y: 0, width: chipSize, height: chipSize)
    chip.amount = amount
    chip.isHidden = false
    return chip
  }

  func createRemoteDot(color: UIColor) -> UIView {
    let dot = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
    dot.backgroundColor = color
    dot.layer.cornerRadius = 4
    dot.layer.shadowColor = UIColor.black.cgColor
    dot.layer.shadowOpacity = 0.3
    dot.layer.shadowRadius = 2
    dot.layer.shadowOffset = CGSize(width: 0, height: 1)
    return dot
  }

  // MARK: - Bet Reconciliation

  func setBonusBetResultsProcessed(_ value: Bool) {
    bonusBetResultsProcessed = value
  }

  func setIsBonusBetResolutionAnimating(_ value: Bool) {
    isBonusBetResolutionAnimating = value
  }

  func setIsBetReconciliationRunning(_ value: Bool) {
    isBetReconciliationRunning = value
  }

  func reconcileBets(snapshot: MPBlackjackTableState.GameStateSnapshot) {
    reconcileBetsWithResults(snapshot.handResults)
  }

  func reconcileBetsWithResults(_ results: [Int: [MPBlackjackTableState.HandResult]]) {
    guard !isBetReconciliationRunning else { return }
    guard !results.isEmpty else { return }
    isBetReconciliationRunning = true

    let mySeatIndex = context.mySeatIndex
    let bustAnimatedSeatIndices = context.bustAnimatedSeatIndices
    let currentSeatsData = context.currentSeatsData

    print(
      "BAL_BUG [reconcileBets] settlement started — preBetSettlementBalance=\(context.preBetSettlementBalance), current balance=\(context.balance)"
    )
    print("💰 [MP-VC] reconcileBets: \(results.count) seats with results")

    delegate?.chipAnimationScrollToSeat(mySeatIndex, animated: true)

    var animationDelay: TimeInterval = 0.4

    for (seatIndex, handResults) in results {
      guard let seatView = context.seatView(forIndex: seatIndex) else { continue }
      let isLocal = (seatIndex == mySeatIndex)

      for (handIdx, result) in handResults.enumerated() {
        let handView =
          handIdx < seatView.hands.count ? seatView.hands[handIdx] : seatView.primaryHand
        let alreadyAnimatedBust = bustAnimatedSeatIndices.contains(seatIndex) && result.isLoss

        if alreadyAnimatedBust {
          print("💰 [MP-VC] seat \(seatIndex) hand \(handIdx): SKIP (already animated bust)")
          continue
        }

        if result.isBlackjack && bustAnimatedSeatIndices.contains(seatIndex) {
          if let seatData = currentSeatsData[seatIndex],
            handIdx < seatData.hands.count,
            seatData.hands[handIdx].stood,
            seatData.hands[handIdx].cards.count == 2
          {
            print(
              "💰 [MP-VC] seat \(seatIndex) hand \(handIdx): SKIP (blackjack already paid out)")
            continue
          }
        }

        if result.isWin || result.isBlackjack {
          let winnings = result.netWinnings
          if isLocal {
            animateLocalPlayerWin(
              seat: seatView, hand: handView, result: result, delay: animationDelay)
            let capturedDelay = animationDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + capturedDelay + 0.3) { [weak self] in
              self?.delegate?.chipAnimationShowBetResult(
                amount: winnings, isWin: true, showBonus: result.isBlackjack,
                description: result.isBlackjack ? "BLACKJACK" : nil)
            }
          } else {
            animateRemotePlayerWin(
              seat: seatView, hand: handView, result: result, delay: animationDelay)
          }
          print(
            "💰 [MP-VC] seat \(seatIndex) hand \(handIdx): WIN +\(winnings) (bet=\(result.bet), payout=\(result.payout))"
          )
        } else if result.isLoss {
          if isLocal {
            animateLocalPlayerLoss(
              seat: seatView, hand: handView, result: result, delay: animationDelay)
            let capturedDelay = animationDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + capturedDelay + 0.3) { [weak self] in
              self?.delegate?.chipAnimationShowBetResult(
                amount: result.bet, isWin: false, showBonus: false, description: nil)
            }
          } else {
            animateRemotePlayerLoss(
              seat: seatView, hand: handView, result: result, delay: animationDelay)
          }
          print("💰 [MP-VC] seat \(seatIndex) hand \(handIdx): LOSS -\(result.bet)")
        } else if result.isPush {
          context.pushBetsBySeatIndex[seatIndex] = result.bet
          handView.broadcastAction("Push")
          if isLocal {
            animateLocalPlayerPush(
              seat: seatView, hand: handView, result: result, delay: animationDelay)
          }
          print(
            "💰 [MP-VC] seat \(seatIndex) hand \(handIdx): PUSH (bet returned: \(result.bet))")
        }

        animationDelay += 0.15
      }

      if isLocal
        && handResults.allSatisfy({ bustAnimatedSeatIndices.contains(seatIndex) && $0.isLoss })
      {
        context.balance = context.preBetSettlementBalance
        context.isBalanceFrozenForSettlement = false
        print("💰 [MP-VC] seat \(seatIndex): all hands busted, finalizing balance")
      }
    }

    let totalAnimDuration = animationDelay + 1.5
    DispatchQueue.main.asyncAfter(deadline: .now() + totalAnimDuration) { [weak self] in
      guard let self = self else { return }
      self.isBetReconciliationRunning = false

      self.delegate?.chipAnimationScrollToSeat(self.context.mySeatIndex, animated: true)

      if let snapshot = self.context.lastGameSnapshot {
        self.delegate?.chipAnimationRefreshButtonVisibility(for: snapshot)
      }

      if self.context.isHost {
        self.delegate?.chipAnimationCallStartNextHand()
      }
    }
  }

  func computeHandResultsFromSeats(snapshot: MPBlackjackTableState.GameStateSnapshot)
    -> [Int: [MPBlackjackTableState.HandResult]]
  {
    let currentSeatsData = context.currentSeatsData
    let dealerCards = snapshot.dealerCards.compactMap { context.cardFromFirebase($0) }
    let dealerTotal = context.blackjackTotal(dealerCards)
    let dealerBusted = dealerTotal > 21
    let dealerIsBlackjack = dealerCards.count == 2 && dealerTotal == 21
    var results: [Int: [MPBlackjackTableState.HandResult]] = [:]

    for (seatIndex, seatData) in currentSeatsData {
      guard let hand = seatData.hands.first, hand.bet > 0 else { continue }
      let playerCards = hand.cards.compactMap { context.cardFromFirebase($0) }
      let playerTotal = context.blackjackTotal(playerCards)
      let playerBusted = hand.busted || playerTotal > 21
      let playerIsBlackjack = playerCards.count == 2 && playerTotal == 21
      let bet = hand.bet

      let result: MPBlackjackTableState.HandResult
      if playerBusted {
        result = MPBlackjackTableState.HandResult(outcome: "lose", payout: 0, bet: bet)
      } else if playerIsBlackjack && !dealerIsBlackjack {
        let bjWin = Int(Double(bet) * 1.5)
        result = MPBlackjackTableState.HandResult(
          outcome: "blackjack", payout: bet + bjWin, bet: bet)
      } else if playerIsBlackjack && dealerIsBlackjack {
        result = MPBlackjackTableState.HandResult(outcome: "push", payout: bet, bet: bet)
      } else if dealerBusted {
        result = MPBlackjackTableState.HandResult(outcome: "win", payout: bet * 2, bet: bet)
      } else if playerTotal > dealerTotal {
        result = MPBlackjackTableState.HandResult(outcome: "win", payout: bet * 2, bet: bet)
      } else if playerTotal < dealerTotal {
        result = MPBlackjackTableState.HandResult(outcome: "lose", payout: 0, bet: bet)
      } else {
        result = MPBlackjackTableState.HandResult(outcome: "push", payout: bet, bet: bet)
      }
      results[seatIndex] = [result]
      print(
        "💰 [MP-VC] computed result for seat \(seatIndex): \(result.outcome) bet=\(bet) payout=\(result.payout)"
      )
    }
    return results
  }

  // MARK: - Local Player Animations

  func animateLocalPlayerWin(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    let hand = targetHand ?? seat.primaryHand
    let payout = result.payout
    guard payout > 0, let containerView = context.containerView, let balanceView = context.balanceView else { return }

    // Track win in session manager
    let isBlackjack = result.isBlackjack
    context.sessionManager?.recordWin(isBlackjack: isBlackjack)

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      let housePoint = CGPoint(x: containerView.bounds.midX, y: 0)
      let betPosition = hand.betControl.getBetViewPosition(in: containerView)
      let dotColor = seat.chipStyle.textColor
      let winnings = result.netWinnings

      let winChip = self.createRemoteMPChip(style: seat.chipStyle, amount: winnings)
      winChip.center = housePoint
      winChip.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
      containerView.addSubview(winChip)

      let step1 = UIViewPropertyAnimator(
        duration: 0.6, controlPoint1: CGPoint(x: 0.85, y: 0),
        controlPoint2: CGPoint(x: 0.15, y: 1)
      ) {
        winChip.center = CGPoint(x: betPosition.x + 25, y: betPosition.y)
        winChip.transform = .identity
      }

      step1.addCompletion { _ in
        winChip.playChipShimmer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
          guard let self = self else { return }
          let balanceCenter = balanceView.convert(
            CGPoint(x: balanceView.bounds.maxX - 30, y: balanceView.bounds.midY),
            to: containerView
          )

          let winDot = self.createRemoteDot(color: dotColor)
          winDot.center = winChip.center
          containerView.addSubview(winDot)
          winChip.removeFromSuperview()

          hand.betControl.betView.alpha = 0
          let betDot = self.createRemoteDot(color: dotColor)
          betDot.center = betPosition
          containerView.addSubview(betDot)

          let fly1 = UIViewPropertyAnimator(
            duration: 0.35, controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1)
          ) {
            winDot.center = balanceCenter
            winDot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
          }
          fly1.addCompletion { _ in
            winDot.removeFromSuperview()
          }

          let fly2 = UIViewPropertyAnimator(
            duration: 0.35, controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1)
          ) {
            betDot.center = balanceCenter
            betDot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
          }
          fly2.addCompletion { [weak self] _ in
            betDot.removeFromSuperview()
            hand.betControl.betAmount = 0
            hand.betControl.betView.alpha = 1
            if let ctx = self?.context {
              let finalBalance = ctx.preBetSettlementBalance + payout
              print(
                "BAL_BUG [win animation] payout=\(payout) (bet=\(result.bet)), preBetSettlementBalance=\(ctx.preBetSettlementBalance) → finalBalance=\(finalBalance)"
              )
              ctx.balance = finalBalance
              ctx.isBalanceFrozenForSettlement = false
            }
          }

          fly1.startAnimation()
          fly2.startAnimation(afterDelay: 0.06)
        }
      }
      step1.startAnimation()
    }
  }

  func animateLocalPlayerLoss(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    let hand = targetHand ?? seat.primaryHand
    guard result.bet > 0, let containerView = context.containerView else { return }

    // Track loss in session manager
    context.sessionManager?.recordLoss()

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      let betPosition = hand.betControl.getBetViewPosition(in: containerView)
      let housePoint = CGPoint(x: containerView.bounds.midX, y: 0)

      hand.betControl.betView.alpha = 0
      let dot = self.createRemoteDot(color: seat.chipStyle.textColor)
      dot.center = betPosition
      containerView.addSubview(dot)

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
        hand.betControl.betAmount = 0
      }

      let animator = UIViewPropertyAnimator(
        duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0),
        controlPoint2: CGPoint(x: 0.15, y: 1)
      ) {
        dot.center = housePoint
        dot.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
      }

      animator.addCompletion { [weak self] _ in
        UIView.animate(withDuration: 0.15) {
          dot.alpha = 0
        } completion: { [weak self] _ in
          dot.removeFromSuperview()
          hand.betControl.betView.alpha = 1
          if let ctx = self?.context {
            print(
              "BAL_BUG [loss animation] restoring preBetSettlementBalance=\(ctx.preBetSettlementBalance) (current=\(ctx.balance))"
            )
            ctx.balance = ctx.preBetSettlementBalance
            ctx.isBalanceFrozenForSettlement = false
          }
        }
      }
      animator.startAnimation()
    }
  }

  func animateLocalBustForfeit(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult
  ) {
    let hand = targetHand ?? seat.primaryHand
    guard result.bet > 0, let containerView = context.containerView else { return }

    let betPosition = hand.betControl.getBetViewPosition(in: containerView)
    let housePoint = CGPoint(x: containerView.bounds.midX, y: 0)

    hand.betControl.betView.alpha = 0
    let dot = createRemoteDot(color: seat.chipStyle.textColor)
    dot.center = betPosition
    containerView.addSubview(dot)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
      hand.betControl.betAmount = 0
    }

    let animator = UIViewPropertyAnimator(
      duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0),
      controlPoint2: CGPoint(x: 0.15, y: 1)
    ) {
      dot.center = housePoint
      dot.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
    }

    animator.addCompletion { _ in
      UIView.animate(withDuration: 0.15) {
        dot.alpha = 0
      } completion: { _ in
        dot.removeFromSuperview()
        hand.betControl.betView.alpha = 1
      }
    }
    animator.startAnimation()

    delegate?.chipAnimationShowBetResult(amount: result.bet, isWin: false, showBonus: false, description: nil)
  }

  func animateLocalPlayerPush(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    guard result.bet > 0 else { return }

    // Track push in session manager
    context.sessionManager?.recordPush()

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      let finalBalance = self.context.preBetSettlementBalance + result.payout
      print(
        "BAL_BUG [push settle] payout=\(result.payout) (bet=\(result.bet)), preBetSettlementBalance=\(self.context.preBetSettlementBalance) → finalBalance=\(finalBalance)"
      )
      self.context.balance = finalBalance
      self.context.isBalanceFrozenForSettlement = false
    }
  }

  // MARK: - Remote Player Animations

  func animateRemotePlayerWin(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    let hand = targetHand ?? seat.primaryHand
    let winnings = result.netWinnings
    guard winnings > 0, let containerView = context.containerView else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      let housePoint = CGPoint(x: containerView.bounds.midX, y: 0)
      let betPosition = hand.betControl.getBetViewPosition(in: containerView)
      let dotColor = seat.chipStyle.textColor

      let winChip = self.createRemoteMPChip(style: seat.chipStyle, amount: winnings)
      winChip.center = housePoint
      winChip.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
      containerView.addSubview(winChip)

      let step1 = UIViewPropertyAnimator(
        duration: 0.6, controlPoint1: CGPoint(x: 0.85, y: 0),
        controlPoint2: CGPoint(x: 0.15, y: 1)
      ) {
        winChip.center = CGPoint(x: betPosition.x + 25, y: betPosition.y)
        winChip.transform = .identity
      }

      step1.addCompletion { _ in
        winChip.playChipShimmer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
          guard let self = self else { return }
          guard let balView = seat.subviews.compactMap({ $0 as? MPPlayerBalanceView }).first else {
            winChip.removeFromSuperview()
            return
          }
          let balanceCenter = seat.convert(
            CGPoint(x: balView.frame.midX, y: balView.frame.midY),
            to: containerView
          )

          let winDot = self.createRemoteDot(color: dotColor)
          winDot.center = winChip.center
          containerView.addSubview(winDot)
          winChip.removeFromSuperview()

          hand.betControl.betView.alpha = 0
          let betDot = self.createRemoteDot(color: dotColor)
          betDot.center = betPosition
          containerView.addSubview(betDot)

          let fly1 = UIViewPropertyAnimator(
            duration: 0.35, controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1)
          ) {
            winDot.center = balanceCenter
            winDot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
          }
          fly1.addCompletion { _ in
            winDot.removeFromSuperview()
          }

          let fly2 = UIViewPropertyAnimator(
            duration: 0.35, controlPoint1: CGPoint(x: 0.85, y: 0),
            controlPoint2: CGPoint(x: 0.15, y: 1)
          ) {
            betDot.center = balanceCenter
            betDot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
          }
          fly2.addCompletion { _ in
            betDot.removeFromSuperview()
            hand.betControl.betAmount = 0
            hand.betControl.betView.alpha = 1
          }

          fly1.startAnimation()
          fly2.startAnimation(afterDelay: 0.06)
        }
      }
      step1.startAnimation()
    }
  }

  func animateRemotePlayerLoss(
    seat: PlayerSeat, hand targetHand: CompactPlayerHandView? = nil,
    result: MPBlackjackTableState.HandResult, delay: TimeInterval
  ) {
    let hand = targetHand ?? seat.primaryHand
    guard result.bet > 0, let containerView = context.containerView else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }

      let betPosition = hand.betControl.getBetViewPosition(in: containerView)
      let housePoint = CGPoint(x: containerView.bounds.midX, y: 0)

      hand.betControl.betView.alpha = 0
      let dot = self.createRemoteDot(color: seat.chipStyle.textColor)
      dot.center = betPosition
      containerView.addSubview(dot)

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
        hand.betControl.betAmount = 0
      }

      let animator = UIViewPropertyAnimator(
        duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0),
        controlPoint2: CGPoint(x: 0.15, y: 1)
      ) {
        dot.center = housePoint
        dot.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
      }

      animator.addCompletion { _ in
        UIView.animate(withDuration: 0.15) {
          dot.alpha = 0
        } completion: { _ in
          dot.removeFromSuperview()
          hand.betControl.betView.alpha = 1
        }
      }
      animator.startAnimation()
    }
  }

  // MARK: - Bonus Bet Animations

  func animateBonusBetResults(
    _ results: [Int: [Int: MPBlackjackTableState.BonusBetResultData]],
    isDealerOutcome: Bool,
    completion: @escaping () -> Void
  ) {
    guard !results.isEmpty else {
      completion()
      return
    }

    isBonusBetResolutionAnimating = true
    let currentSeatsData = context.currentSeatsData

    var styleToSeat: [MPSmallBetChipStyle: Int] = [:]
    for (seatIndex, seatData) in currentSeatsData {
      let style = context.chipStyle(forColorName: seatData.chipColorName)
      styleToSeat[style] = seatIndex
    }

    var winningSeatIndices: Set<Int> = []
    var losingSeatIndices: Set<Int> = []
    var winningsByIndex: [Int: Int] = [:]
    var descriptionsByIndex: [Int: String] = [:]
    for (seatIndex, betResults) in results {
      let hasWin = betResults.values.contains { $0.isWin }
      if hasWin {
        winningSeatIndices.insert(seatIndex)
        let totalWinnings = betResults.values.filter { $0.isWin }.reduce(0) { $0 + $1.payout }
        winningsByIndex[seatIndex] = totalWinnings
        let winningDescriptions = betResults.values.filter { $0.isWin }.map { $0.description }
        descriptionsByIndex[seatIndex] = winningDescriptions.first ?? ""
      } else {
        losingSeatIndices.insert(seatIndex)
      }
    }

    animateBonusBetDots(
      styleToSeat: styleToSeat,
      winningSeatIndices: winningSeatIndices,
      losingSeatIndices: losingSeatIndices,
      winningsByIndex: winningsByIndex,
      descriptionsByIndex: descriptionsByIndex,
      results: results
    ) { [weak self] in
      guard let self = self else { return }
      self.context.bonusBetControl?.clearAllBets()
      self.isBonusBetResolutionAnimating = false
      completion()
    }
  }

  func animateBonusBetDots(
    styleToSeat: [MPSmallBetChipStyle: Int],
    winningSeatIndices: Set<Int>,
    losingSeatIndices: Set<Int>,
    winningsByIndex: [Int: Int],
    descriptionsByIndex: [Int: String],
    results: [Int: [Int: MPBlackjackTableState.BonusBetResultData]],
    completion: @escaping () -> Void
  ) {
    guard let containerView = context.containerView,
      let bonusBetControl = context.bonusBetControl
    else {
      completion()
      return
    }
    let mySeatIndex = context.mySeatIndex
    let chipPositions = bonusBetControl.chipPositions(in: containerView)
    guard !chipPositions.isEmpty else {
      completion()
      return
    }

    let housePoint = CGPoint(x: containerView.bounds.midX, y: 0)
    var longestDuration: TimeInterval = 0

    for entry in chipPositions {
      guard let seatIndex = styleToSeat[entry.style] else { continue }
      let isWinner = winningSeatIndices.contains(seatIndex)
      let isLoser = losingSeatIndices.contains(seatIndex)
      guard isWinner || isLoser else { continue }

      let chipCenter = entry.center
      let betAmount = bonusBetControl.betAmount(for: entry.style)

      if isLoser {
        bonusBetControl.setChipHidden(true, for: entry.style)

        let chipView = createRemoteMPChip(style: entry.style, amount: betAmount)
        chipView.center = chipCenter
        containerView.addSubview(chipView)

        let randomDelay = Double.random(in: 0...0.15)
        UIView.animate(
          withDuration: 0.5, delay: randomDelay, options: .curveEaseIn
        ) {
          chipView.center = housePoint
          chipView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        } completion: { _ in
          UIView.animate(withDuration: 0.2) {
            chipView.alpha = 0
          } completion: { _ in
            chipView.removeFromSuperview()
          }
        }
        longestDuration = max(longestDuration, 0.5 + randomDelay + 0.2)
      } else {
        let isLocal = (seatIndex == mySeatIndex)
        let winnings = winningsByIndex[seatIndex] ?? 0
        let description = descriptionsByIndex[seatIndex] ?? ""
        let winningsOffset = CGPoint(x: -35, y: 0)
        let winningsPosition = CGPoint(
          x: chipCenter.x + winningsOffset.x, y: chipCenter.y + winningsOffset.y)

        let winChip = createRemoteMPChip(style: entry.style, amount: winnings)
        winChip.center = housePoint
        winChip.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        containerView.addSubview(winChip)

        let step1 = UIViewPropertyAnimator(
          duration: 0.6, controlPoint1: CGPoint(x: 0.85, y: 0),
          controlPoint2: CGPoint(x: 0.15, y: 1)
        ) {
          winChip.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
          winChip.center = winningsPosition
        }

        step1.addCompletion { [weak self] _ in
          guard let self = self else { return }

          if isLocal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
              self?.delegate?.chipAnimationShowBetResult(
                amount: winnings, isWin: true, showBonus: true,
                description: description.isEmpty ? nil : description
              )
            }
          }

          DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            let currentSeatsData = self.context.currentSeatsData

            bonusBetControl.setChipHidden(true, for: entry.style)
            let betChip = self.createRemoteMPChip(style: entry.style, amount: betAmount)
            betChip.center = chipCenter
            containerView.addSubview(betChip)

            let destination: CGPoint
            var remoteSeat: PlayerSeat?

            if isLocal, let balanceView = self.context.balanceView {
              destination = balanceView.convert(
                CGPoint(x: balanceView.bounds.maxX - 30, y: balanceView.bounds.midY),
                to: containerView
              )
            } else if let seat = self.context.seatView(forIndex: seatIndex),
              let balView = seat.subviews.compactMap({ $0 as? MPPlayerBalanceView }).first
            {
              remoteSeat = seat
              destination = seat.convert(
                CGPoint(x: balView.frame.midX, y: balView.frame.midY),
                to: containerView
              )
            } else {
              winChip.removeFromSuperview()
              betChip.removeFromSuperview()
              return
            }

            let totalPayout = winnings + betAmount
            let newBalanceForRemote: Int?
            if !isLocal,
              let currentBalance = currentSeatsData[seatIndex]?.balance
            {
              newBalanceForRemote = currentBalance + totalPayout
            } else {
              newBalanceForRemote = nil
            }

            let fly1 = UIViewPropertyAnimator(
              duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0),
              controlPoint2: CGPoint(x: 0.15, y: 1)
            ) {
              winChip.center = destination
              winChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            }
            fly1.addCompletion { [weak self] _ in
              guard let self = self else { return }
              winChip.removeFromSuperview()

              if isLocal {
                self.context.balance = self.context.balance + totalPayout
              } else {
                if let seat = remoteSeat, let newBalance = newBalanceForRemote {
                  seat.setBalance(newBalance, animated: true)
                }
              }
            }

            let fly2 = UIViewPropertyAnimator(
              duration: 0.5, controlPoint1: CGPoint(x: 0.85, y: 0),
              controlPoint2: CGPoint(x: 0.15, y: 1)
            ) {
              betChip.center = CGPoint(x: destination.x - 10, y: destination.y)
              betChip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            }
            fly2.addCompletion { _ in
              betChip.removeFromSuperview()
            }

            fly1.startAnimation()
            fly2.startAnimation(afterDelay: 0.1)
          }
        }
        step1.startAnimation()
        longestDuration = max(longestDuration, 0.6 + 0.4 + 0.5 + 0.1)
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + longestDuration + 0.15) {
      completion()
    }
  }

  func reconstructBonusChipsForDealerOutcome(
    results: [Int: [Int: MPBlackjackTableState.BonusBetResultData]]
  ) {
    guard let bonusBetControl = context.bonusBetControl else { return }
    let currentSeatsData = context.currentSeatsData

    bonusBetControl.clearAllBets()
    for (seatIndex, _) in results {
      guard let seatData = currentSeatsData[seatIndex] else { continue }
      let chipStyle = context.chipStyle(forColorName: seatData.chipColorName)
      let totalBonusBet = seatData.bonusBets.values.reduce(0, +)
      if totalBonusBet > 0 {
        bonusBetControl.addBet(amount: totalBonusBet, chipStyle: chipStyle, animated: false)
      }
    }
  }

  // MARK: - Blackjack Payout

  func handleBlackjackPayoutForSeat(
    seatIndex: Int, snapshot: MPBlackjackTableState.GameStateSnapshot, handIndex: Int = 0
  ) -> TimeInterval {
    let currentSeatsData = context.currentSeatsData
    guard let seatData = currentSeatsData[seatIndex],
      handIndex < seatData.hands.count
    else { return 0 }
    let hand = seatData.hands[handIndex]
    guard hand.cards.count == 2 else { return 0 }
    let cards = hand.cards.compactMap { context.cardFromFirebase($0) }
    guard cards.count == 2, context.blackjackTotal(cards) == 21 else { return 0 }
    guard let seatView = context.seatViewsByIndex[seatIndex] else { return 0 }

    if context.bustAnimatedSeatIndices.contains(seatIndex) {
      return 0
    }

    let handView =
      handIndex < seatView.hands.count ? seatView.hands[handIndex] : seatView.primaryHand

    handView.broadcastAction("Blackjack!")
    context.bustAnimatedSeatIndices.insert(seatIndex)

    let isLocal = (seatIndex == context.mySeatIndex)
    let bet = hand.bet
    let bjWin = Int(Double(bet) * 1.5)
    let payout = bet + bjWin
    let result = MPBlackjackTableState.HandResult(outcome: "blackjack", payout: payout, bet: bet)
    let delay: TimeInterval = 0.3

    if isLocal {
      if !context.isBalanceFrozenForSettlement {
        context.isBalanceFrozenForSettlement = true
        context.preBetSettlementBalance = context.balance
      }
      animateLocalPlayerWin(seat: seatView, result: result, delay: delay)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) { [weak self] in
        self?.delegate?.chipAnimationShowBetResult(
          amount: result.netWinnings, isWin: true, showBonus: true, description: "BLACKJACK")
      }
    } else {
      animateRemotePlayerWin(seat: seatView, result: result, delay: delay)
    }

    let discardDelay = delay + 1.8
    DispatchQueue.main.asyncAfter(deadline: .now() + discardDelay) { [weak self] in
      guard let self = self, let containerView = self.context.containerView else { return }
      let topLeft = CGPoint(x: 0, y: 0)
      handView.discardCards(to: topLeft, in: containerView) {}
    }

    let totalDuration = discardDelay + 0.5
    context.isBlackjackPayoutAnimating = true
    DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
      self?.context.isBlackjackPayoutAnimating = false
    }

    return totalDuration
  }

  @discardableResult
  func handlePostDealBlackjacks(snapshot: MPBlackjackTableState.GameStateSnapshot) -> TimeInterval {
    let currentSeatsData = context.currentSeatsData
    var bjDelay: TimeInterval = 0.3
    var totalDuration: TimeInterval = 0
    var foundBlackjack = false

    for (seatIndex, seatData) in currentSeatsData {
      guard let hand = seatData.hands.first,
        hand.stood,
        hand.cards.count == 2
      else { continue }
      let cards = hand.cards.compactMap { context.cardFromFirebase($0) }
      guard cards.count == 2, context.blackjackTotal(cards) == 21 else { continue }
      guard let seatView = context.seatViewsByIndex[seatIndex] else { continue }

      seatView.primaryHand.broadcastAction("Blackjack!")
      context.bustAnimatedSeatIndices.insert(seatIndex)

      let isLocal = (seatIndex == context.mySeatIndex)
      let bet = hand.bet
      let bjWin = Int(Double(bet) * 1.5)
      let payout = bet + bjWin
      let result = MPBlackjackTableState.HandResult(outcome: "blackjack", payout: payout, bet: bet)
      let delay = bjDelay

      if isLocal {
        if !context.isBalanceFrozenForSettlement {
          context.isBalanceFrozenForSettlement = true
          context.preBetSettlementBalance = context.balance
        }
        animateLocalPlayerWin(seat: seatView, result: result, delay: delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) { [weak self] in
          self?.delegate?.chipAnimationShowBetResult(
            amount: result.netWinnings, isWin: true, showBonus: true, description: "BLACKJACK")
        }
      } else {
        animateRemotePlayerWin(seat: seatView, result: result, delay: delay)
      }

      let discardDelay = delay + 1.8
      DispatchQueue.main.asyncAfter(deadline: .now() + discardDelay) { [weak self] in
        guard let self = self, let containerView = self.context.containerView else { return }
        let topLeft = CGPoint(x: 0, y: 0)
        seatView.primaryHand.discardCards(to: topLeft, in: containerView) {}
      }

      totalDuration = discardDelay + 0.5
      bjDelay += 0.3
      foundBlackjack = true
    }

    if foundBlackjack {
      context.isBlackjackPayoutAnimating = true
      DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
        self?.context.isBlackjackPayoutAnimating = false
      }
    }

    return totalDuration
  }
}
