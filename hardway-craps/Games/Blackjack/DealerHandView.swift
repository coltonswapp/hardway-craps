//
//  DealerHandView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/15/26.
//

import UIKit

final class DealerHandView: BlackjackHandView {

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(stackDirection: .up, hidesFirstCard: true, scale: 0.8)
        self.frame = frame

        // Disable tap actions for dealer hand (but keep pan gesture enabled)
        self.canTap = { false }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @discardableResult
    func revealHoleCard(animated: Bool = true) -> Bool {
        return revealFirstCard(animated: animated)
    }
    
    func isHoleCardHidden() -> Bool {
        // Check if dealer has cards and the first card is still hidden
        return currentCards.count >= 2 && isFirstCardFaceDown()
    }
}
