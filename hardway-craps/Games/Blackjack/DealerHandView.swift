//
//  DealerHandView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

final class DealerHandView: BlackjackHandView {

  /// Scale factor for dealer cards (matches compact player hand approach)
  private static let dealerScale: CGFloat = 0.7
  /// Suit icon scale for cards (1.0 = full size). Smaller values give a more compact look.
  private static let dealerSuitScale: CGFloat = 0.7
  /// Less padding around value and suit on the card face (default elsewhere is 8).
  private static let dealerCardPadding: CGFloat = 4
  /// Scale factor for the value label only (1.0 = same as contentScale).
  private static let dealerValueScale: CGFloat = 0.9
  /// Scale factor for the total label (matches dealer card scale)
  private static let dealerTotalLabelScale: CGFloat = 0.9

  /// Scale down cards when many are dealt so 5–7+ fit properly. 1.0 for ≤4 cards, then step down.
  private static func countBasedScaleFactor(for cardCount: Int) -> CGFloat {
    switch cardCount {
    case 0...4: return 1.0
    case 5: return 0.88
    case 6: return 0.78
    case 7: return 0.70
    default: return max(0.6, 0.70 - CGFloat(cardCount - 7) * 0.05)
    }
  }

  convenience init() {
    self.init(frame: .zero)
  }

  override init(frame: CGRect) {
    super.init(
      stackDirection: .up,
      hidesFirstCard: true,
      scale: Self.dealerScale,
      suitScale: Self.dealerSuitScale,
      cardPadding: Self.dealerCardPadding,
      valueScale: Self.dealerValueScale
    )
    self.frame = frame

    // Set count-based scaling to match compact player hand behavior
    self.countBasedScaleFactor = { Self.countBasedScaleFactor(for: $0) }

    // Scale the total label to match dealer card scale
    self.setTotalLabelScale(Self.dealerTotalLabelScale)

    // Disable tap actions for dealer hand (but keep pan gesture enabled)
    self.canTap = { false }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @discardableResult
  func revealHoleCard(animated: Bool = true) -> Bool {
    // Try the hidesFirstCard path first (isFirstCardHidden flag)
    if revealFirstCard(animated: animated) {
      return true
    }
    // Fallback: the card may have been dealt via dealCardFaceDown (faceDownCardIndices)
    // rather than the hidesFirstCard flow. Use revealCard(at:) to flip it.
    if isFirstCardFaceDown() {
      return revealCard(at: 0, animated: animated)
    }
    return false
  }

  func isHoleCardHidden() -> Bool {
    return currentCards.count >= 2 && isFirstCardFaceDown()
  }
}
