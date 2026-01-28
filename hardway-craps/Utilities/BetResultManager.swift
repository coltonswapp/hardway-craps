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
    private var activeContainers: [BetResultContainer] = []
    private let containerHeight: CGFloat = 80
    private let containerSpacing: CGFloat = 20
    
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
    
    func showBetResult(amount: Int, isWin: Bool, showBonus: Bool = false, description: String? = nil) {
        if resultWindow == nil {
            setupResultWindow()
        }

        guard let rootView = resultWindow?.rootViewController?.view else { return }

        let betResultContainer = BetResultContainer()
        betResultContainer.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(betResultContainer)
        
        // Calculate vertical offset based on currently showing containers
        // Each container is 80pt tall with 20pt spacing, so we stack them vertically
        let verticalOffset = calculateVerticalOffset()
        
        NSLayoutConstraint.activate([
            betResultContainer.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            betResultContainer.centerYAnchor.constraint(equalTo: rootView.centerYAnchor, constant: verticalOffset)
        ])
        
        // Track this container
        activeContainers.append(betResultContainer)

        // Animate the bet result container
        betResultContainer.animateToAmount(amount, isWin: isWin, showBonus: showBonus, description: description)
        betResultContainer.show(isWin: isWin) { [weak self] in
            betResultContainer.removeFromSuperview()
            // Remove from active containers tracking
            self?.removeContainer(betResultContainer)
        }
    }
    
    private func calculateVerticalOffset() -> CGFloat {
        // Calculate offset based on number of active containers
        // Each container is 80pt tall, with 20pt spacing between them
        // Stack them vertically downward: first at center (0), second below (+100), third below that (+200), etc.
        // This creates a natural stacking effect where new containers appear below existing ones
        let count = activeContainers.count
        return CGFloat(count) * (containerHeight + containerSpacing)
    }
    
    private func removeContainer(_ container: BetResultContainer) {
        if let index = activeContainers.firstIndex(where: { $0 === container }) {
            activeContainers.remove(at: index)
        }
    }
}

extension UIViewController {
    func showBetResult(amount: Int, isWin: Bool, showBonus: Bool = false, description: String? = nil) {
        BetResultManager.shared.showBetResult(amount: amount, isWin: isWin, showBonus: showBonus, description: description)
    }
}
