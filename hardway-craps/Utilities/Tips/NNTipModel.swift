//
//  NNTipModel.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/23/26.
//
import UIKit

// MARK: - Custom Tip Model
struct NNTipModel {
    let id: String
    let title: String
    let message: String?
    let systemImageName: String
}

protocol NNTipGroupProtocol {
    var tips: [NNTipModel] { get }
}

struct NNTipGroup: NNTipGroupProtocol {
    var tips: [NNTipModel]
    
    init(tips: [NNTipModel]) {
        self.tips = tips
    }
}

enum BlackjackTips {

    static let placeBetTip = NNTipModel(
        id: "BlackjackPlaceBetTip",
        title: "Tap to Bet",
        message: "Select a chip value and tap the bet area to place your bet. When ready, tap the Ready button.",
        systemImageName: "dollarsign.circle"
    )

    static let tapToHitTip = NNTipModel(
        id: "BlackjackTapToHitTip",
        title: "Tap to Hit",
        message: "Tap your cards to quickly hit, or use the Stand and Double buttons below.",
        systemImageName: "hand.tap"
    )

    static let bonusBetsTip = NNTipModel(
        id: "BlackjackBonusBetsTip",
        title: "Try Bonus Bets",
        message: "Try a bonus bet for bigger payouts on pairs and suited cards.",
        systemImageName: "suit.spade.fill"
    )
    
    static let drapChipTip = NNTipModel(
        id: "DragChipTip",
        title: "Drag to Remove",
        message: "In between hands, tap and drag a chip back to your chip stack to remove it.",
        systemImageName: "hand.draw.fill"
    )
    
    static let insuranceTip = NNTipModel(
        id: "BlackjackInsuranceTip",
        title: "Tap For Insurance",
        message: "When dealer's upcard is an ace, bet up to half your main bet for insurance. Pays 2:1 if dealer has Blackjack.",
        systemImageName: "shield.lefthalf.filled.badge.checkmark"
    )
    
    static let tapReadyTip = NNTipModel(
        id: "BlackjackTapReadyTip",
        title: "Tap 'Ready?' to Deal",
        message: "Once you've placed your bet, tap the 'Ready?' button to deal the cards.",
        systemImageName: "play.circle.fill"
    )

    // MARK: - Tip Groups
    static let tipGroup: NNTipGroup = NNTipGroup(
        tips: [
            placeBetTip,
            tapToHitTip,
            bonusBetsTip,
            drapChipTip,
            insuranceTip,
            tapReadyTip
        ]
    )
}

enum CrapsTips {
    
    static let tapToBetTip = NNTipModel(
        id: "CrapsTapToBetTip",
        title: "Tap to Bet",
        message: "Select a chip value and tap any bet area to place your bet. Start with the Pass Line for the best odds.",
        systemImageName: "dollarsign.circle"
    )
    
    static let comeOutRollTip = NNTipModel(
        id: "CrapsComeOutRollTip",
        title: "Come Out Roll",
        message: "Roll the dice! On 7 or 11 you win. On 2, 3, or 12 you lose. Any other number becomes your point.",
        systemImageName: "dice.fill"
    )
    
    static let betBoxNumbersTip = NNTipModel(
        id: "CrapsBetBoxNumbersTip",
        title: "Make Place Bets",
        message: "Once the point is set (puck is ON), you can place bets on individual numbers. These win when that number rolls before a 7.",
        systemImageName: "square.grid.3x3.fill"
    )
    
    static let hitPointToWinTip = NNTipModel(
        id: "CrapsHitPointToWinTip",
        title: "Hit the Point to Win",
        message: "Roll your point number again to win! If you roll a 7 before hitting the point, you lose.",
        systemImageName: "target"
    )
    
    static let dragChipTip = NNTipModel(
        id: "CrapsDragChipTip",
        title: "Drag to Remove",
        message: "Tap and drag a chip back to your chip stack to remove it from any bet. Some bets can only be removed when puck if OFF.",
        systemImageName: "hand.draw.fill"
    )
    
    // MARK: - Tip Groups
    static let tipGroup: NNTipGroup = NNTipGroup(
        tips: [
            tapToBetTip,
            comeOutRollTip,
            betBoxNumbersTip,
            hitPointToWinTip,
            dragChipTip
        ]
    )
}


