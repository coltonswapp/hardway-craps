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

    // MARK: - Tip Groups
    static let tipGroup: NNTipGroup = NNTipGroup(
        tips: [
            placeBetTip,
            tapToHitTip,
            bonusBetsTip,
            drapChipTip,
            insuranceTip
        ]
    )
}


