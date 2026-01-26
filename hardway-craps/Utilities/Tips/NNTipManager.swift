//
//  NNTipManager.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/23/26.
//

import UIKit

// MARK: - Tip Arrow Edge

/// Defines which edge of the source view the tip arrow should point from
public enum TipArrowEdge {
    case top       // Tooltip above source, arrow points down
    case bottom    // Tooltip below source, arrow points up
    case leading   // Tooltip to the left of source, arrow points right
    case trailing  // Tooltip to the right of source, arrow points left
}

// MARK: - Tip Display Rules

/// Context information for evaluating tip display rules
struct TipContext {
    let currentDate: Date
    let currentScreen: String?
    let userActionCounts: [String: Int]
    let screenVisitCounts: [String: Int]
    let customData: [String: Any]
    
    init(currentDate: Date = Date(),
         currentScreen: String? = nil,
         userActionCounts: [String: Int] = [:],
         screenVisitCounts: [String: Int] = [:],
         customData: [String: Any] = [:]) {
        self.currentDate = currentDate
        self.currentScreen = currentScreen
        self.userActionCounts = userActionCounts
        self.screenVisitCounts = screenVisitCounts
        self.customData = customData
    }
}

/// Protocol for defining custom tip display rules
protocol TipDisplayRule {
    func shouldDisplay(for tipId: String, context: TipContext) -> Bool
    var description: String { get }
}

/// Rule that requires a minimum amount of time to pass before showing a tip
struct TimeBasedRule: TipDisplayRule {
    let minimumTimeInterval: TimeInterval
    let startDateKey: String
    
    init(minimumDays: Int) {
        self.minimumTimeInterval = TimeInterval(minimumDays * 24 * 60 * 60)
        self.startDateKey = "app_first_launch_date"
    }
    
    init(minimumTimeInterval: TimeInterval, startDateKey: String = "app_first_launch_date") {
        self.minimumTimeInterval = minimumTimeInterval
        self.startDateKey = startDateKey
    }
    
    func shouldDisplay(for tipId: String, context: TipContext) -> Bool {
        let startDate = UserDefaults.standard.object(forKey: startDateKey) as? Date ?? Date()
        let timeElapsed = context.currentDate.timeIntervalSince(startDate)
        return timeElapsed >= minimumTimeInterval
    }
    
    var description: String {
        let days = Int(minimumTimeInterval / (24 * 60 * 60))
        return "Show after \(days) days"
    }
}

/// Rule that requires a minimum number of visits to a specific screen
struct VisitCountRule: TipDisplayRule {
    let screenName: String
    let minimumVisits: Int
    
    func shouldDisplay(for tipId: String, context: TipContext) -> Bool {
        let visitCount = context.screenVisitCounts[screenName] ?? 0
        let shouldShow = visitCount >= minimumVisits
        print("🔍 [DEBUG] VisitCountRule for \(tipId): screenName=\(screenName), visitCount=\(visitCount), minimumVisits=\(minimumVisits), shouldShow=\(shouldShow)")
        return shouldShow
    }
    
    var description: String {
        return "Show after \(minimumVisits) visits to \(screenName)"
    }
}

/// Rule that requires a minimum number of specific user actions
struct UserActionRule: TipDisplayRule {
    let actionName: String
    let minimumCount: Int
    
    func shouldDisplay(for tipId: String, context: TipContext) -> Bool {
        let actionCount = context.userActionCounts[actionName] ?? 0
        return actionCount >= minimumCount
    }
    
    var description: String {
        return "Show after \(minimumCount) \(actionName) actions"
    }
}

/// Rule that evaluates a custom condition using a closure
struct ConditionalRule: TipDisplayRule {
    let condition: (String, TipContext) -> Bool
    let ruleDescription: String
    
    init(description: String, condition: @escaping (String, TipContext) -> Bool) {
        self.ruleDescription = description
        self.condition = condition
    }
    
    func shouldDisplay(for tipId: String, context: TipContext) -> Bool {
        return condition(tipId, context)
    }
    
    var description: String {
        return ruleDescription
    }
}

// MARK: - TipKit UIKit Wrapper
class NNTipManager {
    static let shared = NNTipManager()
    
    private init() {
        // Initialize app first launch date if not set
        if UserDefaults.standard.object(forKey: "app_first_launch_date") == nil {
            UserDefaults.standard.set(Date(), forKey: "app_first_launch_date")
        }
        
        // Setup predefined rules
        setupPredefinedRules()
    }
    
    /// Setup rules for predefined tips
    private func setupPredefinedRules() {

        // Blackjack tips rules
        // Place bet tip - show on first visit
        // (no rule needed - shows immediately)

        // Tap to hit tip - show after dealing cards (checked manually in showTips)
        // (no rule needed - controlled by game phase)

        // Bonus bets tip - show after 3 hands played
        // (no rule needed - checked manually based on handCount in showTips)
    }
    
    // Track dismissed tips using UserDefaults
    private let dismissedTipsKey = "NNDismissedTips"
    
    // Store display rules for each tip
    private var displayRules: [String: [TipDisplayRule]] = [:]
    
    // Track screen visits and user actions
    private let screenVisitCountsKey = "NNScreenVisitCounts"
    private let userActionCountsKey = "NNUserActionCounts"
    
    private var dismissedTips: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: dismissedTipsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: dismissedTipsKey)
        }
    }
    
    // MARK: - Rule Management
    
    /// Add a display rule for a specific tip
    func addRule(_ rule: TipDisplayRule, for tipId: String) {
        displayRules[tipId, default: []].append(rule)
    }
    
    /// Remove all rules for a specific tip
    func clearRules(for tipId: String) {
        displayRules.removeValue(forKey: tipId)
    }
    
    /// Get all rules for a specific tip
    func getRules(for tipId: String) -> [TipDisplayRule] {
        return displayRules[tipId] ?? []
    }
    
    // MARK: - Tracking Methods
    
    /// Track a screen visit
    func trackScreenVisit(_ screenName: String) {
        var visitCounts = UserDefaults.standard.dictionary(forKey: screenVisitCountsKey) as? [String: Int] ?? [:]
        visitCounts[screenName] = (visitCounts[screenName] ?? 0) + 1
        UserDefaults.standard.set(visitCounts, forKey: screenVisitCountsKey)
    }
    
    /// Track a user action
    func trackUserAction(_ actionName: String) {
        var actionCounts = UserDefaults.standard.dictionary(forKey: userActionCountsKey) as? [String: Int] ?? [:]
        actionCounts[actionName] = (actionCounts[actionName] ?? 0) + 1
        UserDefaults.standard.set(actionCounts, forKey: userActionCountsKey)
    }
    
    /// Get screen visit counts
    private var screenVisitCounts: [String: Int] {
        return UserDefaults.standard.dictionary(forKey: screenVisitCountsKey) as? [String: Int] ?? [:]
    }
    
    /// Get user action counts
    private var userActionCounts: [String: Int] {
        return UserDefaults.standard.dictionary(forKey: userActionCountsKey) as? [String: Int] ?? [:]
    }
    
    /// Create context for rule evaluation
    private func createContext(currentScreen: String? = nil, customData: [String: Any] = [:]) -> TipContext {
        return TipContext(
            currentDate: Date(),
            currentScreen: currentScreen,
            userActionCounts: userActionCounts,
            screenVisitCounts: screenVisitCounts,
            customData: customData
        )
    }
    
    // Check if a tip should be shown (now includes rule evaluation)
    func shouldShowTip(_ tip: NNTipModel, currentScreen: String? = nil, customData: [String: Any] = [:]) -> Bool {
        // Check if tip was already dismissed
        guard !dismissedTips.contains(tip.id) else { return false }
        
        // Check custom rules
        let rules = displayRules[tip.id] ?? []
        guard !rules.isEmpty else { return true } // No rules means show immediately
        
        let context = createContext(currentScreen: currentScreen, customData: customData)
        return rules.allSatisfy { $0.shouldDisplay(for: tip.id, context: context) }
    }
    
    // Check if a tip is currently being displayed on screen
    func isShowingTip(_ tip: NNTipModel) -> Bool {
        return activeTipViews.contains { tipView in
            if let nnTipView = tipView as? NNTipView {
                return nnTipView.tipId == tip.id
            }
            return false
        }
    }
    
    // Mark a tip as dismissed
    func dismissTip(_ tip: NNTipModel) {
        print("🔄 [Tip Debug] Dismissing tip: \(tip.id)")
        
        var dismissed = dismissedTips
        dismissed.insert(tip.id)
        dismissedTips = dismissed
        
        // Also dismiss any currently visible tooltip for this tip
        dismissActiveTipView(for: tip.id)
    }
    
    // Dismiss active tip view for a specific tip ID
    private func dismissActiveTipView(for tipId: String) {
        // Find active tip views that match this tip ID
        for tipView in activeTipViews {
            if let nnTipView = tipView as? NNTipView,
               nnTipView.tipId == tipId {
                print("✅ [Tip Debug] Found matching tip view, dismissing")
                dismissTipWithAnimation(tipView)
                break
            }
        }
    }
    
    // Reset all tips
    func resetAllTips() {
        dismissedTips = Set<String>()
        resetAllTrackingData()
        print("✅ [TipKit Debug] All tips reset")
    }
    
    // Reset all tracking data
    private func resetAllTrackingData() {
        UserDefaults.standard.removeObject(forKey: screenVisitCountsKey)
        UserDefaults.standard.removeObject(forKey: userActionCountsKey)
        UserDefaults.standard.removeObject(forKey: "app_first_launch_date")
        UserDefaults.standard.set(Date(), forKey: "app_first_launch_date")
        print("✅ [TipKit Debug] All tracking data reset")
    }
    
    // Keep track of active tip views and their observation tasks
    private var activeTipViews: [UIView] = []
    private var sequentialTipTasks: [String: Task<Void, Never>] = [:]
    
    
    
    // Simpler method for showing tips with custom positioning
    func showTip(_ tip: NNTipModel,
                        sourceView: UIView,
                        in viewController: UIViewController,
                        pinToEdge: TipArrowEdge = .top,
                        offset: CGPoint = CGPoint(x: 0, y: 8),
                        centerHorizontally: Bool = false) {

        let tipView = NNTipView(tip: tip, arrowEdge: pinToEdge)
        tipView.setSourceView(sourceView)
        tipView.setDismissHandler { [weak self] in
            // Mark tip as dismissed so it won't show again
            self?.dismissTip(tip)
            // Remove from active tips tracking (let NNTipView handle its own animation)
            if let index = self?.activeTipViews.firstIndex(of: tipView) {
                self?.activeTipViews.remove(at: index)
            }
        }
        tipView.translatesAutoresizingMaskIntoConstraints = false

        // Add to active tips tracking
        activeTipViews.append(tipView)

        viewController.view.addSubview(tipView)

        // Use the advanced constraint setup that handles 80% width
        setupConstraints(for: tipView, sourceView: sourceView, viewController: viewController, arrowEdge: pinToEdge, offset: offset, centerHorizontally: centerHorizontally)

        // Force layout and then update arrow position
        viewController.view.layoutIfNeeded()
        tipView.updateArrowPosition()

        // Animate tip appearance
        tipView.showWithAnimation()
    }
    
    
    private func dismissTipWithAnimation(_ tipView: UIView) {
        // Remove from active tips tracking
        if let index = activeTipViews.firstIndex(of: tipView) {
            activeTipViews.remove(at: index)
        }
        
        // Animate to scale 0 and fade out
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: [.curveEaseIn]) {
            tipView.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            tipView.alpha = 0.0
        } completion: { _ in
            tipView.removeFromSuperview()
        }
    }
    
    
    // Method to dismiss all active tips
    func dismissAllActiveTips() {
        for tipView in activeTipViews {
            dismissTipWithAnimation(tipView)
        }
    }
    
    
    /// Stops all sequential tip tasks (call this in viewWillDisappear)
    func stopAllTipObservations() {
        for (_, task) in sequentialTipTasks {
            task.cancel()
        }
        sequentialTipTasks.removeAll()
    }
    
    // MARK: - Sequential Tip Display
    
    /// Shows tips in a specific order, one at a time (custom implementation)
    /// - Parameters:
    ///   - tipConfigurations: Array of tip configurations in the order they should be shown
    ///   - viewController: The view controller to show the tips in
    ///   - sequenceId: Unique identifier for this tip sequence
    func showTipsSequentially(_ tipConfigurations: [(tip: NNTipModel, sourceView: UIView, arrowEdge: TipArrowEdge, offset: CGPoint)],
                             in viewController: UIViewController,
                             sequenceId: String) {
        
        // Cancel any existing sequence
        stopObservingSequence(sequenceId: sequenceId)
        
        // Start sequential display
        let sequentialTask = Task { @MainActor in
            for (index, config) in tipConfigurations.enumerated() {
                // Check if tip should be shown
                if shouldShowTip(config.tip) {
                    await showTipAndWaitForDismissal(
                        tip: config.tip,
                        sourceView: config.sourceView,
                        arrowEdge: config.arrowEdge,
                        offset: config.offset,
                        in: viewController
                    )
                }
                
                // Check if task was cancelled
                if Task.isCancelled {
                    break
                }
            }
        }
        
        // Store the sequential task
        sequentialTipTasks[sequenceId] = sequentialTask
    }
    
    /// Shows a single tip and waits for it to be dismissed
    private func showTipAndWaitForDismissal(tip: NNTipModel,
                                           sourceView: UIView,
                                           arrowEdge: TipArrowEdge,
                                           offset: CGPoint,
                                           in viewController: UIViewController) async {

        await withCheckedContinuation { continuation in
            // Ensure all UI operations happen on the main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                // Create the tip view first
                let tipView = NNTipView(tip: tip, arrowEdge: arrowEdge)
                tipView.translatesAutoresizingMaskIntoConstraints = false
                
                // Set the source view for arrow positioning
                tipView.setSourceView(sourceView)
                
                // Set up the dismiss handler after creation
                tipView.setDismissHandler { [weak self] in
                    // Mark tip as dismissed
                    self?.dismissTip(tip)
                    // Dismiss handler - called when tip is dismissed
                    continuation.resume()
                    if let index = self?.activeTipViews.firstIndex(of: tipView) {
                        self?.activeTipViews.remove(at: index)
                    }
                }
                
                // Add to view hierarchy
                viewController.view.addSubview(tipView)
                
                // Set up constraints
                self.setupConstraints(for: tipView, sourceView: sourceView, viewController: viewController, arrowEdge: arrowEdge, offset: offset)
                
                // Force layout and then update arrow position
                viewController.view.layoutIfNeeded()
                tipView.updateArrowPosition()
                
                // Animate in
                tipView.showWithAnimation()
                
                // Track this tip
                self.activeTipViews.append(tipView)
                
            }
        }
    }
    
    /// Stops observing a specific tip sequence
    /// - Parameter sequenceId: The unique identifier of the sequence to stop observing
    func stopObservingSequence(sequenceId: String) {
        sequentialTipTasks[sequenceId]?.cancel()
        sequentialTipTasks.removeValue(forKey: sequenceId)
    }
    
    
    // MARK: - Private Helper Methods
    
    
    func setupConstraints(for tipView: UIView, sourceView: UIView, viewController: UIViewController, arrowEdge: TipArrowEdge, offset: CGPoint, centerHorizontally: Bool = false) {
        var constraints: [NSLayoutConstraint] = []

        switch arrowEdge {
        case .top, .bottom:
            // For top/bottom arrows, use 80% screen width but position to align arrow with source
            let widthConstraint = tipView.widthAnchor.constraint(equalTo: viewController.view.widthAnchor, multiplier: 0.8)

            let centerXConstraint: NSLayoutConstraint

            if centerHorizontally {
                // Center the tip horizontally on screen
                centerXConstraint = tipView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor)
            } else {
                // Calculate where the source view is horizontally
                let sourceViewFrame = sourceView.superview?.convert(sourceView.frame, to: viewController.view) ?? CGRect.zero
                let sourceViewCenterX = sourceViewFrame.midX
                let viewControllerWidth = viewController.view.bounds.width
                let tooltipWidth = viewControllerWidth * 0.8

                // Calculate optimal tooltip center to keep arrow pointing to source
                let idealTooltipCenterX = sourceViewCenterX
                let minTooltipCenterX = tooltipWidth / 2 + 8 // 8pt margin
                let maxTooltipCenterX = viewControllerWidth - tooltipWidth / 2 - 8 // 8pt margin
                let clampedTooltipCenterX = max(minTooltipCenterX, min(maxTooltipCenterX, idealTooltipCenterX))

                // Create center constraint with calculated offset
                let centerXOffset = clampedTooltipCenterX - viewControllerWidth / 2
                centerXConstraint = tipView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor, constant: centerXOffset)
            }

            if arrowEdge == .top {
                // .top edge = tooltip pinned to top of source = tooltip above source
                constraints = [
                    centerXConstraint,
                    widthConstraint,
                    tipView.bottomAnchor.constraint(equalTo: sourceView.topAnchor, constant: offset.y)
                ]
            } else { // .bottom
                // .bottom edge = tooltip pinned to bottom of source = tooltip below source
                constraints = [
                    centerXConstraint,
                    widthConstraint,
                    tipView.topAnchor.constraint(equalTo: sourceView.bottomAnchor, constant: offset.y)
                ]
            }
            
        case .leading:
            constraints = [
                tipView.leadingAnchor.constraint(equalTo: sourceView.trailingAnchor, constant: offset.x),
                tipView.centerYAnchor.constraint(equalTo: sourceView.centerYAnchor, constant: offset.y)
            ]
        case .trailing:
            // For trailing arrows, especially nav bar buttons, use 80% width and position relative to source
            let widthConstraint = tipView.widthAnchor.constraint(equalTo: viewController.view.widthAnchor, multiplier: 0.8)
            constraints = [
                tipView.trailingAnchor.constraint(equalTo: sourceView.leadingAnchor, constant: -offset.x),
                tipView.centerYAnchor.constraint(equalTo: sourceView.centerYAnchor, constant: offset.y),
                widthConstraint
            ]
        }
        
        // Add boundary constraints (only for leading/trailing arrows since top/bottom have fixed width)
        if arrowEdge == .leading || arrowEdge == .trailing {
            constraints.append(contentsOf: [
                tipView.leadingAnchor.constraint(greaterThanOrEqualTo: viewController.view.leadingAnchor, constant: 8),
                tipView.trailingAnchor.constraint(lessThanOrEqualTo: viewController.view.trailingAnchor, constant: -8)
            ])
        }
        
        // Add vertical boundary constraints for all arrows
        constraints.append(contentsOf: [
            tipView.topAnchor.constraint(greaterThanOrEqualTo: viewController.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tipView.bottomAnchor.constraint(lessThanOrEqualTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
        
        NSLayoutConstraint.activate(constraints)
    }
    
}

// MARK: - Convenience Extensions
extension UIViewController {
    func showTip(_ tip: NNTipModel, for view: UIView, arrowEdge: TipArrowEdge = .top, offset: CGPoint = CGPoint(x: 0, y: 8), centerHorizontally: Bool = false) {
        NNTipManager.shared.showTip(tip, sourceView: view, in: self, pinToEdge: arrowEdge, offset: offset, centerHorizontally: centerHorizontally)
    }

    /// Track a screen visit (typically called in viewDidAppear)
    func trackScreenVisit(_ screenName: String? = nil) {
        let name = screenName ?? String(describing: type(of: self))
        NNTipManager.shared.trackScreenVisit(name)
    }

    /// Track a user action
    func trackUserAction(_ actionName: String) {
        NNTipManager.shared.trackUserAction(actionName)
    }

    /// Stops all tip observations (call this in viewWillDisappear)
    func stopAllTipObservations() {
        NNTipManager.shared.stopAllTipObservations()
    }

    /// Shows tips in a specific order, one at a time
    /// - Parameters:
    ///   - tipConfigurations: Array of tip configurations in the order they should be shown
    ///   - sequenceId: Unique identifier for this tip sequence
    func showTipsSequentially(_ tipConfigurations: [(tip: NNTipModel, sourceView: UIView, arrowEdge: TipArrowEdge, offset: CGPoint)], sequenceId: String) {
        NNTipManager.shared.showTipsSequentially(tipConfigurations, in: self, sequenceId: sequenceId)
    }

    /// Stops observing a specific tip sequence
    /// - Parameter sequenceId: The unique identifier of the sequence to stop observing
    func stopObservingSequence(sequenceId: String) {
        NNTipManager.shared.stopObservingSequence(sequenceId: sequenceId)
    }
}
