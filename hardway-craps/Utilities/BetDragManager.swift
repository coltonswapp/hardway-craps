//
//  BetDragManager.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

protocol BetDropTarget: AnyObject {
    func addBet(_ amount: Int)
    func addBetWithAnimation(_ amount: Int)
    func removeBet(_ amount: Int)
    func highlightAsDropTarget()
    func unhighlightAsDropTarget()
    func frameInView(_ view: UIView) -> CGRect
    func getBetViewPosition(in view: UIView) -> CGPoint
    /// Returns true if the bet is locked and can accept odds
    func hasLockedBet() -> Bool
    /// Animates the bet view slightly to the left to signal odds can be added
    func animateBetViewSlideLeftForOdds()
    /// Restores the bet view to its normal position
    func restoreBetViewPosition()
}

class BetDragManager {

    static let shared = BetDragManager()

    private var draggedChip: SmallBetChip?
    private var dragValue: Int = 0
    private var sourceControl: PlainControl?
    private var oddsSourceControl: BetDropTarget? // Track the control we're dragging odds from
    private var dropTargets: [BetDropTarget] = []
    private var currentDropTarget: BetDropTarget?
    private var originalBetViewPosition: CGPoint = .zero
    private var currentLockedBetTarget: BetDropTarget?
    private var droppedOnLockedBet: BetDropTarget? // Track if we dropped on a locked bet to prevent restore

    private init() {}

    func registerDropTarget(_ target: BetDropTarget) {
        dropTargets.append(target)
    }

    func unregisterDropTarget(_ target: BetDropTarget) {
        dropTargets.removeAll { $0 === target }
    }
    
    func setOddsSource(_ control: BetDropTarget) {
        oddsSourceControl = control
    }
    
    func hasCurrentDropTarget() -> Bool {
        return currentDropTarget != nil
    }

    func startDragging(value: Int, from point: CGPoint, in view: UIView, source: PlainControl? = nil) {
        dragValue = value
        sourceControl = source
        
        // Store original betView position for snap-back animation
        if let source = source {
            originalBetViewPosition = source.getBetViewPosition(in: view)
        }
        
        // Offset chip above finger for visibility
        let chipPosition = CGPoint(x: point.x, y: point.y - 40)

        let chip = SmallBetChip()
        chip.amount = value
        
        // Enable manual positioning for dragged chip (disable Auto Layout)
        chip.translatesAutoresizingMaskIntoConstraints = true
        
        // Set frame first to avoid flashing to origin
        let chipSize: CGFloat = 30
        chip.frame = CGRect(
            x: chipPosition.x - chipSize / 2,
            y: chipPosition.y - chipSize / 2,
            width: chipSize,
            height: chipSize
        )
        
        chip.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        chip.alpha = 0.9
        chip.isHidden = false

        view.addSubview(chip)
        draggedChip = chip

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            chip.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }
    }

    func updateDrag(to point: CGPoint) {
        guard let chip = draggedChip else { return }

        // Offset the chip above the finger so it's visible
        var chipPosition = CGPoint(x: point.x, y: point.y - 40)
        
        // Normal drag appearance (bet removal prevention is handled in PlainControl.handleBetViewPan)
        chip.alpha = 0.9
        chip.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        
        chip.center = chipPosition

        // Check if we're over a drop target (use chip's visual position, not finger position)
        guard let containerView = chip.superview else { return }

        let newTarget = dropTargets.first { target in
            let targetFrame = target.frameInView(containerView)
            return targetFrame.contains(chipPosition)
        }

        if newTarget !== currentDropTarget {
            // Restore previous locked bet position if leaving one
            if let previousLocked = currentLockedBetTarget, previousLocked !== newTarget {
                previousLocked.restoreBetViewPosition()
                currentLockedBetTarget = nil
            }
            
            currentDropTarget?.unhighlightAsDropTarget()
            currentDropTarget = newTarget
            currentDropTarget?.highlightAsDropTarget()
        }
        
        // Check proximity to betView for locked bets (separate from drop target check)
        // This allows the animation to trigger when near the bet chip, not just anywhere in the control
        if let currentTarget = currentDropTarget, currentTarget.hasLockedBet() {
            // Only check if we're dragging a chip (not moving an existing bet)
            if sourceControl == nil {
                let betViewPosition = currentTarget.getBetViewPosition(in: containerView)
                let distance = sqrt(pow(chipPosition.x - betViewPosition.x, 2) + pow(chipPosition.y - betViewPosition.y, 2))
                let proximityThreshold: CGFloat = 60 // Distance in points to trigger animation
                
                if distance <= proximityThreshold {
                    // Near the betView - animate if not already animating
                    if currentLockedBetTarget !== currentTarget {
                        currentLockedBetTarget?.restoreBetViewPosition()
                        currentTarget.animateBetViewSlideLeftForOdds()
                        currentLockedBetTarget = currentTarget
                    }
                } else {
                    // Too far from betView - restore position
                    if currentLockedBetTarget === currentTarget {
                        currentTarget.restoreBetViewPosition()
                        currentLockedBetTarget = nil
                    }
                }
            }
        } else {
            // Not over a locked bet - restore any previous locked bet animation
            if let previousLocked = currentLockedBetTarget {
                previousLocked.restoreBetViewPosition()
                currentLockedBetTarget = nil
            }
        }
    }

    func endDrag(at point: CGPoint, in view: UIView) {
        guard let chip = draggedChip else { return }

        // Capture values before cleanup
        let valueToAdd = dragValue
        let source = sourceControl
        let target = currentDropTarget
        let oddsSource = oddsSourceControl  // Capture odds source before cleanup clears it
        
        // Check if dropping on a locked bet BEFORE processing the drop
        // This ensures we mark it before cleanup is called
        if let target = target, target.hasLockedBet(), source == nil {
            droppedOnLockedBet = target
        }

        // Check if dropped on a valid target
        if let target = target {

            // Get the betView position to animate towards
            let targetPosition = target.getBetViewPosition(in: view)
            
            // Determine if this is a bet move (has source) or new bet placement
            let isBetMove = source != nil
            // Check if dropping back on the same control (no-op, just restore visibility)
            let isSameControl = source === target
            // Check if dropping odds back on the same control
            let isDroppingOddsBack = oddsSource === target
            // ChipSelector returns bets to balance ONLY if we're moving an existing bet (has source)
            let isChipSelector = target is ChipSelector
            // Check if bet can be removed (for bet moves) - check BEFORE allowing any operations
            let canRemove = source?.canRemoveBet?() ?? true
            
            // If this is a bet move and bet cannot be removed, snap back immediately
            if isBetMove && !isSameControl && !canRemove {
                // Cannot remove bet - snap back to original position immediately
                source?.betView.alpha = 1
                HapticsHelper.failureHaptic()
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8, options: .curveEaseOut) {
                    chip.center = self.originalBetViewPosition
                    chip.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                } completion: { _ in
                    chip.removeFromSuperview()
                    self.cleanup()
                }
                return
            }

            // Animate chip to target betView position and fade out quickly
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                chip.center = targetPosition
                chip.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
                chip.alpha = 0.2
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if isSameControl || isDroppingOddsBack {
                        // Dropping back on same control - ComeBetControl.handleOddsViewPan handles restoration
                        // Do nothing here - the control will restore visibility and amount itself
                    } else if isChipSelector && isBetMove {
                        // Dropping an existing bet on ChipSelector - return to balance
                        // Only allow if bet can be removed
                        if canRemove {
                            target.addBetWithAnimation(valueToAdd)
                        }
                    } else if isChipSelector && !isBetMove {
                        // Check if we're dragging odds (oddsSource is set)
                        if oddsSource != nil {
                            // Dragging odds to ChipSelector - return to balance via ChipSelector
                            target.addBetWithAnimation(valueToAdd)
                        } else {
                            // Dragging chip from ChipSelector and dropping back - just cancel, don't add money
                            // Do nothing - chip will be removed in completion block
                        }
                    } else if isBetMove {
                        // Moving bet between controls - use addBet (no balance deduction)
                        // Only allow if bet can be removed from source (already checked above)
                        if canRemove {
                            target.addBet(valueToAdd)
                            // Add animation manually
                            if let plainTarget = target as? PlainControl {
                                let originalTransform = plainTarget.betView.transform
                                UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut]) {
                                    plainTarget.betView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
                                } completion: { _ in
                                    UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                                        plainTarget.betView.transform = originalTransform
                                    }
                                }
                                HapticsHelper.lightHaptic()
                            }
                        }
                    } else {
                        // New bet placement - use addBetWithAnimation (deducts balance)
                        target.addBetWithAnimation(valueToAdd)
                        
                        // If dropping on a locked bet and addBetWithAnimation returned early (due to isDraggingOdds),
                        // ensure odds are visible if they exist
                        if target.hasLockedBet() {
                            if let comeControl = target as? ComeBetControl {
                                comeControl.ensureOddsVisible()
                            } else if let plainControl = target as? PlainControl, let stack = plainControl.oddsBetStack {
                                stack.ensureOddsVisible()
                            }
                        }
                    }
                }
                
            } completion: { _ in
                chip.removeFromSuperview()

                // If dragging from a source, handle bet removal/restoration
                if let source = source, oddsSource == nil {
                    // Regular bet drag
                    if isSameControl {
                        // Dropping back on same control - just restore visibility, don't remove bet
                        source.betView.alpha = 1
                    } else if isChipSelector && isBetMove {
                        // Dropping on ChipSelector - balance already returned via onBetReturned
                        // Just remove the bet from source without calling onBetRemoved callback
                        // updateCurrentBet() is called from onBetReturned with a delay to ensure
                        // it runs after the bet is cleared here
                        source.betAmount = 0
                        // Don't restore alpha since bet is cleared (betView will be hidden automatically)
                    } else if canRemove {
                        // Moving to different control - remove from source silently (no balance change)
                        source.removeBetSilently(valueToAdd)
                        // Restore betView alpha if bet still exists (partial removal)
                        // (betView will be hidden by isHidden property if amount is 0)
                        if source.betAmount > 0 {
                            source.betView.alpha = 1
                        }
                    }
                } else if let oddsSource = oddsSource {
                    // Dragging odds - handle removal
                    if isChipSelector {
                        // Dropping odds on ChipSelector - balance already returned via onBetReturned
                        // Clear odds from source (PlainControl with OddsBetStack or ComeBetControl)
                        if let plainControl = oddsSource as? PlainControl {
                            plainControl.oddsAmount = 0
                        } else if let comeControl = oddsSource as? ComeBetControl {
                            comeControl.oddsAmount = 0
                        }
                    } else if !isSameControl && !isDroppingOddsBack {
                        // Moved to different control - odds were already added there, remove silently
                        if let plainControl = oddsSource as? PlainControl {
                            plainControl.removeOddsSilently(valueToAdd)
                        } else if let comeControl = oddsSource as? ComeBetControl {
                            comeControl.removeBetSilently(valueToAdd)
                        }
                    }
                    // If dropping back on same control, handleOddsChipPan already handled restoration
                }
                
                // Restore locked bet position if we were hovering over one
                if let lockedBet = self.currentLockedBetTarget {
                    if lockedBet === target && target.hasLockedBet() {
                        // Dropped on the locked bet - mark it so cleanup doesn't restore
                        // The bet is already shifted left from hover, and odds addition will keep it shifted
                        self.droppedOnLockedBet = target
                        // Keep currentLockedBetTarget set so cleanup can check it
                    } else {
                        // Didn't drop on the locked bet - restore immediately
                        lockedBet.restoreBetViewPosition()
                        self.currentLockedBetTarget = nil
                    }
                }
                
                target.unhighlightAsDropTarget()
            }
        } else if let source = source {
            // No valid drop target - snap bet back to original position
            // Don't remove the bet, just restore it
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8, options: .curveEaseOut) {
                chip.center = self.originalBetViewPosition
                chip.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            } completion: { _ in
                chip.removeFromSuperview()
                source.betView.alpha = 1
                self.cleanup()
            }
        } else {
            // Invalid drop with no source - just remove chip
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                chip.alpha = 0
                chip.transform = .identity
            } completion: { _ in
                chip.removeFromSuperview()
            }
        }

        cleanup()
    }

    func cancelDrag() {
        guard let chip = draggedChip else { return }

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            chip.alpha = 0
        } completion: { _ in
            chip.removeFromSuperview()
        }

        // Restore locked bet position if we were hovering over one
        currentLockedBetTarget?.restoreBetViewPosition()
        currentLockedBetTarget = nil
        droppedOnLockedBet = nil
        
        currentDropTarget?.unhighlightAsDropTarget()
        cleanup()
    }

    private func cleanup() {
        // Restore locked bet position before cleanup, but not if we dropped on it
        // (odds addition will handle keeping it shifted)
        if let lockedBet = currentLockedBetTarget, lockedBet !== droppedOnLockedBet {
            lockedBet.restoreBetViewPosition()
        }
        currentLockedBetTarget = nil
        droppedOnLockedBet = nil
        oddsSourceControl = nil
        
        draggedChip = nil
        dragValue = 0
        sourceControl = nil
        currentDropTarget = nil
        originalBetViewPosition = .zero
    }
}
