//
//  MPDealerCardQueue.swift
//  hardway-craps
//

import UIKit

protocol MPDealerCardQueueDelegate: AnyObject {
  func dealerCardQueueRefreshButtonVisibility()
}

final class MPDealerCardQueue {

  // MARK: - Properties

  weak var delegate: MPDealerCardQueueDelegate?
  let context: MPGameContext

  private(set) var dealerCardQueue: [BlackjackHandView.Card] = []
  private(set) var isDealerCardAnimating = false
  private(set) var dealerCardsRenderedCount: Int = 0
  private(set) var dealerHoleRevealed = false

  init(context: MPGameContext) {
    self.context = context
  }

  // MARK: - State Setters

  func setDealerCardsRenderedCount(_ count: Int) {
    dealerCardsRenderedCount = count
  }

  func setDealerHoleRevealed(_ revealed: Bool) {
    dealerHoleRevealed = revealed
  }

  func setIsDealerCardAnimating(_ animating: Bool) {
    isDealerCardAnimating = animating
  }

  // MARK: - Queue Management

  func enqueueDealerCards(_ allCards: [BlackjackHandView.Card], holeRevealed: Bool) {
    let newCount = allCards.count
    let committedCount = dealerCardsRenderedCount + dealerCardQueue.count
    if newCount > committedCount {
      let newCards = Array(allCards[committedCount..<newCount])
      dealerCardQueue.append(contentsOf: newCards)
    }
    let phase = context.currentPhase
    let isDealerPhase =
      (phase == MultiplayerBlackjackKeys.Phases.dealerTurn
        || phase == MultiplayerBlackjackKeys.Phases.gameOver
        || phase == MultiplayerBlackjackKeys.Phases.betweenHands)
    if holeRevealed && !dealerHoleRevealed && isDealerPhase {
      dealerHoleRevealed = true
    }
    processNextDealerCard()
  }

  func processNextDealerCard() {
    guard !isDealerCardAnimating,
      let dealerHandView = context.dealerHandView
    else { return }

    let phase = context.currentPhase
    let isDealerPhase =
      (phase == MultiplayerBlackjackKeys.Phases.dealerTurn
        || phase == MultiplayerBlackjackKeys.Phases.gameOver
        || phase == MultiplayerBlackjackKeys.Phases.betweenHands)

    if dealerHoleRevealed && dealerHandView.isHoleCardHidden() && isDealerPhase {
      isDealerCardAnimating = true
      dealerHandView.revealHoleCard(animated: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        guard let self = self else { return }
        self.isDealerCardAnimating = false
        self.processNextDealerCard()
      }
      return
    }

    guard !dealerCardQueue.isEmpty else {
      if phase == MultiplayerBlackjackKeys.Phases.betweenHands
        || phase == MultiplayerBlackjackKeys.Phases.gameOver
      {
        delegate?.dealerCardQueueRefreshButtonVisibility()
      }
      return
    }
    let card = dealerCardQueue.removeFirst()
    isDealerCardAnimating = true
    dealerCardsRenderedCount += 1

    let center = context.deckCenter
    guard let containerView = context.containerView else { return }
    dealerHandView.dealCard(card, from: center, in: containerView)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      guard let self = self else { return }
      self.isDealerCardAnimating = false
      self.processNextDealerCard()
    }
  }

  func reset() {
    dealerCardQueue.removeAll()
    isDealerCardAnimating = false
    dealerCardsRenderedCount = 0
    dealerHoleRevealed = false
  }
}
