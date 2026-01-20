//
//  BetResultManager.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/16/26.
//

import UIKit

final class BetResultManager {
    static let shared = BetResultManager()
    
    private var resultWindow: PassthroughWindow?
    
    private init() {}
    
    private func setupResultWindow() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isHidden = false
        
        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear
        window.rootViewController = rootVC
        
        self.resultWindow = window
    }
    
    func showBetResult(amount: Int, isWin: Bool, showBonus: Bool = false) {
        if resultWindow == nil {
            setupResultWindow()
        }

        guard let rootView = resultWindow?.rootViewController?.view else { return }

        let betResultContainer = BetResultContainer()
        betResultContainer.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(betResultContainer)

        NSLayoutConstraint.activate([
            betResultContainer.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            betResultContainer.centerYAnchor.constraint(equalTo: rootView.centerYAnchor)
        ])

        // Animate the bet result container
        betResultContainer.animateToAmount(amount, isWin: isWin, showBonus: showBonus)
        betResultContainer.show(isWin: isWin) {
            betResultContainer.removeFromSuperview()
        }
    }
}

extension UIViewController {
    func showBetResult(amount: Int, isWin: Bool, showBonus: Bool = false) {
        BetResultManager.shared.showBetResult(amount: amount, isWin: isWin, showBonus: showBonus)
    }
}
