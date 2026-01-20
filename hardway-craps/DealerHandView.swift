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
//        backgroundColor = .red.withAlphaComponent(0.2)
    }
    
    override init(frame: CGRect) {
        super.init(stackDirection: .up, hidesFirstCard: true, scale: 0.8)
        self.frame = frame
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
