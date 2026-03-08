//
//  MPGameContext.swift
//  hardway-craps
//

import FirebaseDatabase
import UIKit

final class MPGameContext {

  // MARK: - Player Identity

  var mySeatIndex: Int = 0
  var myChipColorName: String = "Cyan"
  var playerId: String = ""
  var tableCode: String = ""

  // MARK: - Balance

  var balance: Int = 0 {
    didSet { onBalanceChanged?(balance) }
  }
  var onBalanceChanged: ((Int) -> Void)?
  var preBetSettlementBalance: Int = 0
  var isBalanceFrozenForSettlement: Bool = false
  var isBalanceFrozenForBetOperation: Bool = false
  var expectedBalanceAfterBetOperation: Int?

  // MARK: - Seat Data

  var currentSeatsData: [Int: MPBlackjackTableState.SeatData] = [:]
  var seatViewsByIndex: [Int: PlayerSeat] = [:]
  var bustAnimatedSeatIndices: Set<Int> = []
  var pushBetsBySeatIndex: [Int: Int] = [:]

  // MARK: - Game State

  var lastGameSnapshot: MPBlackjackTableState.GameStateSnapshot?
  var previousGameSnapshot: MPBlackjackTableState.GameStateSnapshot?
  var activeHandIndex: Int = 0
  var isHost: Bool = false

  // MARK: - Animation / Action State

  var isDealAnimationRunning = false
  var isDealInProgress = false
  var isBlackjackPayoutAnimating = false
  var cardApplyGeneration: Int = 0
  var bonusBetResultsProcessed = false

  /// Closures that resolve to live manager state (set by VC during setupManagers)
  var isActionInFlightProvider: (() -> Bool)?
  var isActionInFlight: Bool { isActionInFlightProvider?() ?? false }

  // MARK: - Firebase Observers

  var seatsObserverHandle: DatabaseHandle?
  var gameStateObserverHandle: DatabaseHandle?
  var hostPlayerIdObserverHandle: DatabaseHandle?

  // MARK: - UI References (set once during setup)

  weak var containerView: UIView?
  weak var dealerHandView: DealerHandView?
  weak var defaultSeat: PlayerSeat?
  weak var balanceView: BalanceView?
  weak var deckView: DeckView?
  weak var insuranceControl: MPInsuranceControl?
  weak var bonusBetControl: MPBonusBetControl?
  weak var continueButton: UIButton?
  weak var instructionLabel: InstructionLabel?

  // MARK: - Session Manager (for tracking gameplay stats)

  weak var sessionManager: MPBlackjackSessionManager?

  // MARK: - Convenience

  var currentPhase: String {
    lastGameSnapshot?.phase ?? ""
  }

  var deckCenter: CGPoint {
    guard let deckView = deckView, let container = containerView else { return .zero }
    return container.convert(deckView.deckCenter, from: deckView)
  }

  func seatView(forIndex index: Int) -> PlayerSeat? {
    seatViewsByIndex[index]
  }

  // MARK: - Card Utilities

  func cardFromFirebase(_ dict: [String: Any]) -> BlackjackHandView.Card? {
    guard let rankRaw = dict[MultiplayerBlackjackKeys.CardData.rank] as? String,
      let suitRaw = dict[MultiplayerBlackjackKeys.CardData.suit] as? String
    else { return nil }
    let rank = PlayingCardView.Rank(rawValue: rankRaw) ?? .ace
    let suit: PlayingCardView.Suit
    switch suitRaw.lowercased() {
    case "hearts": suit = .hearts
    case "clubs": suit = .clubs
    case "diamonds": suit = .diamonds
    case "spades": suit = .spades
    default: suit = .spades
    }
    return BlackjackHandView.Card(
      rank: rank, suit: suit,
      isCutCard: (dict[MultiplayerBlackjackKeys.CardData.isCutCard] as? Bool) ?? false)
  }

  func blackjackCard(from providerCard: DeterministicDeckProvider.Card) -> BlackjackHandView.Card? {
    cardFromFirebase([
      MultiplayerBlackjackKeys.CardData.rank: providerCard.rank,
      MultiplayerBlackjackKeys.CardData.suit: providerCard.suit,
    ])
  }

  func blackjackTotal(_ cards: [BlackjackHandView.Card]) -> Int {
    var total = 0
    var aces = 0
    for card in cards {
      switch card.rank {
      case .ace:
        aces += 1
        total += 11
      case .king, .queen, .jack, .ten: total += 10
      case .nine: total += 9
      case .eight: total += 8
      case .seven: total += 7
      case .six: total += 6
      case .five: total += 5
      case .four: total += 4
      case .three: total += 3
      case .two: total += 2
      }
    }
    while total > 21 && aces > 0 {
      total -= 10
      aces -= 1
    }
    return total
  }

  func isTenValueRank(_ rank: PlayingCardView.Rank) -> Bool {
    rank == .ten || rank == .jack || rank == .queen || rank == .king
  }

  // MARK: - Chip Style

  func chipStyle(forColorName colorName: String) -> MPSmallBetChipStyle {
    switch colorName {
    case "Yellow Green": return .yellow
    case "Cyan": return .blue
    case "Green": return .green
    case "Red": return .red
    default:
      switch colorName.lowercased() {
      case "yellow", "yellow green": return .yellow
      case "cyan", "blue": return .blue
      case "green": return .green
      case "red": return .red
      default: return .yellow
      }
    }
  }
}
