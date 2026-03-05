//
//  SceneDelegate.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit
import FirebaseDatabase

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var pendingURL: URL?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let windowScene = (scene as? UIWindowScene) else { return }
        window = UIWindow(frame: windowScene.coordinateSpace.bounds)
        window?.windowScene = windowScene
        window?.rootViewController = UINavigationController(rootViewController: MainViewController())
        window?.makeKeyAndVisible()
        
        // Handle URL if app was launched from a URL
        if let urlContext = connectionOptions.urlContexts.first {
            handleIncomingURL(urlContext.url)
        }
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        
        // If the window hasn't finished initialization yet, store for later
        // This handles cases where a URL is opened while the app is still starting up
        if window == nil {
            self.pendingURL = url
        } else {
            handleIncomingURL(url)
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "hardway-craps",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.host == "table",
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return
        }
        
        // Validate and join the table
        validateAndJoinTable(code: code)
    }
    
    private func validateAndJoinTable(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmed.count == 4, trimmed.allSatisfy(\.isNumber) else {
            showErrorAlert(message: "Please enter a valid 4-digit code.")
            return
        }
        
        let ref = Database.database().reference().child("mp_blackjack/table/\(trimmed)")
        ref.observeSingleEvent(of: .value) { [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self else { return }
                if snapshot.exists() {
                    self.launchGame(tableCode: trimmed, bankroll: AppSettingsViewController.startingBankroll)
                } else {
                    self.showErrorAlert(message: "Table \(trimmed) not found. Check the code and try again.")
                }
            }
        }
    }
    
    private func launchGame(tableCode: String, bankroll: Int) {
        guard let navController = window?.rootViewController as? UINavigationController else {
            // If navigation controller isn't ready, try again after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.launchGame(tableCode: tableCode, bankroll: bankroll)
            }
            return
        }
        
        // Navigate directly to the multiplayer blackjack game
        // The table has already been validated, so we can join automatically
        let gameVC = MultiplayerBlackjackViewController(tableCode: tableCode, bankroll: bankroll)
        navController.setViewControllers([MainViewController(), gameVC], animated: true)
    }
    
    private func showErrorAlert(message: String) {
        guard let navController = window?.rootViewController as? UINavigationController else { return }
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        navController.present(alert, animated: true)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        
        // Handle any pending URL that was stored before the window was ready
        if let pendingURL = pendingURL {
            self.pendingURL = nil
            handleIncomingURL(pendingURL)
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}

