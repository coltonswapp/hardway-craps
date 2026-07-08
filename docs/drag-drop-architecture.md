# Drag/Drop Architecture — Agent Handoff

This document describes how **hardway-craps** implements drag-and-drop for betting chips. It is intended for another agent building a similar system in a different project.

## Summary

The app uses a **custom pan-gesture drag system**, not UIKit's `UIDragInteraction` / `UIDropInteraction`. A singleton coordinator (`BetDragManager`) owns the full drag lifecycle. Individual controls implement small protocols for geometry and bet mutations, and forward `UIPanGestureRecognizer` events to the manager.

---

## Key Files

| File | Purpose |
|------|---------|
| `hardway-craps/Utilities/BetDragManager.swift` | Central coordinator: ghost chip, hit-testing, drop resolution, animations |
| `hardway-craps/Controls/PlainControl.swift` | Reference implementation of `BetDropTarget` + `BetDragSource` |
| `hardway-craps/Controls/ChipSelector.swift` | Drop target for returning bets to bankroll; hosts draggable chip buttons |
| `hardway-craps/Controls/ProgrammaticChipView.swift` | Draggable chip in selector (new bet, no source) |
| `hardway-craps/Controls/OddsBetStack.swift` | Nested bet + odds chips with separate pan handlers |
| `hardway-craps/Controls/ComeBetControl.swift` | Variant with separate bet/odds drag sources |
| `hardway-craps/Games/Craps/PointControl.swift` | Extended drop logic (place ↔ lay zone moves) |

---

## Protocols

### `BetDropTarget`

Anything that can receive a dropped chip implements this:

```swift
protocol BetDropTarget: AnyObject {
    func addBet(_ amount: Int)                          // Transfer: no balance change
    func addBetWithAnimation(_ amount: Int)             // New bet: deduct balance + bounce
    func removeBet(_ amount: Int)
    func highlightAsDropTarget()
    func unhighlightAsDropTarget()
    func frameInView(_ view: UIView) -> CGRect          // Hit-test rect in container coords
    func getBetViewPosition(in view: UIView) -> CGPoint // Where ghost chip animates to
    func hasLockedBet() -> Bool
    func animateBetViewSlideLeftForOdds()               // Proximity hint for odds placement
    func restoreBetViewPosition()
}
```

### `BetDragSource`

Controls that hold an existing bet and can be dragged away:

```swift
protocol BetDragSource: AnyObject {
    var betAmount: Int { get set }
    var betView: BetChipView! { get }
    var canRemoveBet: (() -> Bool)? { get }
    func removeBetSilently(_ amount: Int)               // Move: no balance refund
    func getBetViewPosition(in view: UIView) -> CGPoint // Snap-back origin
}
```

---

## Drag Lifecycle

```
Pan .began
  → startDragging(value:from:in:source:)
      • Create floating SmallBetChip in root VC view
      • Offset chip ~40pt above finger
      • Hide source chip (alpha = 0) if source != nil
      • Store source, original position for snap-back

Pan .changed
  → updateDrag(to:)
      • Move ghost chip
      • Hit-test chip CENTER (not finger) against registered drop targets
      • highlight / unhighlight current target
      • Optional: proximity animation when near locked bet (odds hint)

Pan .ended
  → endDrag(at:in:)
      • Resolve drop (see decision tree below)
      • Animate ghost to target position or snap back
      • Mutate source/target bet state
      • Remove ghost chip, cleanup

Pan .cancelled / .failed
  → cancelDrag()
      • Fade out ghost, restore highlights, cleanup
```

---

## Registration Pattern

Drop targets register in `setupView` and unregister in `deinit`:

```swift
// PlainControl.setupView()
BetDragManager.shared.registerDropTarget(self)

// PlainControl.deinit
BetDragManager.shared.unregisterDropTarget(self)
```

No central wiring in the view controller — each control self-registers.

---

## Gesture Wiring (Standard Pattern)

Every draggable view uses the same pan handler shape:

```swift
@objc private func handleBetViewPan(_ gesture: UIPanGestureRecognizer) {
    guard betAmount > 0 else { return }
    guard canRemoveBet?() ?? true else { return }

    // Walk up to root VC view so ghost chip isn't clipped by scroll views
    var rootView: UIView? = self
    while let parent = rootView?.superview { rootView = parent }
    guard let containerView = rootView else { return }

    let location = gesture.location(in: containerView)

    switch gesture.state {
    case .began:
        betView.alpha = 0
        BetDragManager.shared.startDragging(
            value: betAmount, from: location, in: containerView, source: self
        )
    case .changed:
        BetDragManager.shared.updateDrag(to: location)
    case .ended:
        BetDragManager.shared.endDrag(at: location, in: containerView)
    case .cancelled, .failed:
        BetDragManager.shared.cancelDrag()
        betView.alpha = 1
    default: break
    }
}
```

**Tap vs drag:** attach tap with `tapGesture.require(toFail: panGesture)` so quick taps still fire.

---

## Drag Sources by Type

| Source | Pan on | `source` param | Balance effect |
|--------|--------|----------------|----------------|
| Chip selector chip | `ProgrammaticChipView` | `nil` | Deducted on successful drop via `addBetWithAnimation` |
| Existing bet on control | `betView` / `betChip` | `BetDragSource` (self) | No change — silent remove + add |
| Odds chip | `oddsChip` / `oddsView` | `nil` + `setOddsSource()` | Depends on target |
| Lay bet (PointControl) | lay chip pan | `nil` + `layBetSource` | Zone-specific |

---

## Drop Resolution (`endDrag`)

The manager branches on **source presence**, **target type**, and **same-control check**:

| Scenario | Source | Target | Action |
|----------|--------|--------|--------|
| New bet from selector | `nil` | Any bet control | `target.addBetWithAnimation(amount)` |
| Move bet between controls | `BetDragSource` | Different control | `target.addBet` + `source.removeBetSilently` |
| Return bet to bankroll | `BetDragSource` | `ChipSelector` | `ChipSelector.addBetWithAnimation` → `onBetReturned` |
| Drop back on same control | `BetDragSource` | Same control | Restore source visibility, no-op |
| Drop selector chip on selector | `nil` | `ChipSelector` | Cancel (balance never deducted) |
| Invalid drop (no target) | `BetDragSource` | none | Spring snap-back to `originalBetViewPosition` |
| Invalid drop (no target) | `nil` (selector) | none | Fade out ghost |
| Odds → different control | odds source set | Different control | `addBet` / `addTransferredBet`, silent odds remove |
| Odds → ChipSelector | odds source set | `ChipSelector` | Return to balance |
| Locked bet proximity | `nil` | control with locked bet | `addBetWithAnimation` adds odds; bet slides left |

**Two add methods = two semantics:**
- `addBetWithAnimation` → new money (deduct balance, haptic, bounce)
- `addBet` → transfer (no balance change)

---

## Hit Testing

- Uses **ghost chip center**, not finger position (chip is offset 40pt above finger).
- Each target provides `frameInView(_:)` — converts its bounds to the container view's coordinate space.
- First matching target in the registered array wins.

```swift
let newTarget = dropTargets.first { target in
    let targetFrame = target.frameInView(containerView)
    return targetFrame.contains(chipPosition)
}
```

---

## Visual Feedback

| Event | Effect |
|-------|--------|
| Enter drop target | `highlightAsDropTarget()` — blue border on controls, scale on ChipSelector |
| Leave drop target | `unhighlightAsDropTarget()` — restore original border |
| Near locked bet (within 60pt) | `animateBetViewSlideLeftForOdds()` — bet chip slides left to show odds slot |
| Successful drop | Ghost animates to `getBetViewPosition`, scales down, fades; target chip bounces |
| Failed drop | Ghost springs back to source position; source chip alpha restored |

---

## Ghost Chip Details

On `startDragging`:
1. Create `SmallBetChip`, set `translatesAutoresizingMaskIntoConstraints = true`
2. Add to root VC view (not the control's superview)
3. Set frame centered on touch point (offset above finger)
4. Scale up slightly (1.2 → 1.3) for lift effect
5. Hide source chip if moving existing bet

On completion: remove from superview, nil out manager state in `cleanup()`.

---

## Touch Routing (Nested Chips)

Controls with `OddsBetStack` override `hitTest` and `point(inside:)` so nested chips receive pan gestures without the parent control intercepting:

```swift
override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    if let stack = oddsBetStack, stack.isUserInteractionEnabled {
        let stackPoint = convert(point, to: stack)
        let expanded = stack.bounds.insetBy(dx: -20, dy: -20)
        if expanded.contains(stackPoint) {
            return stack.hitTest(stackPoint, with: event) ?? stack
        }
    }
    return super.hitTest(point, with: event)
}
```

---

## Control Hierarchy

```
ChipSelector
  └── ProgrammaticChipView (pan → new bet, source = nil)
        ↓ drag
PlainControl / ComeBetControl / PointControl / TriZoneBetControl
  ├── implements BetDropTarget + BetDragSource
  ├── betView (pan → move bet)
  └── OddsBetStack (optional)
        ├── betChip (pan → move bet, delegates to odds if locked)
        └── oddsChip (pan → move odds, setOddsSource)
        ↓ drop back
ChipSelector (onBetReturned → refund balance)
```

---

## Guard Rails

- `canRemoveBet` closure on sources — blocks drag start and triggers failure haptic + snap-back if bet is locked.
- `removeBetSilently` / `removeOddsSilently` — used for moves so balance callbacks don't fire.
- Delayed alpha restoration (0.5s fallback) in pan handlers in case `endDrag` completion doesn't restore visibility.
- `isDraggingOdds` flag in `OddsBetStack` prevents bet amount from being mutated mid-drag.

---

## Minimal Recipe for a New Project

1. **Define protocols** — `DropTarget` (geometry + add/remove + highlight) and `DragSource` (amount + silent remove + position).
2. **Build a singleton `DragManager`** with `startDragging`, `updateDrag`, `endDrag`, `cancelDrag`, and a registered targets array.
3. **On pan `.began`** — create floating view in root VC, hide source.
4. **On pan `.changed`** — move ghost, hit-test center against targets, highlight/unhighlight.
5. **On pan `.ended`** — branch on source presence + target type; animate; mutate model; cleanup.
6. **Register targets** in control init, unregister in deinit.
7. **Separate "new" vs "transfer"** add methods to avoid double balance charges.
8. **Use `tap.require(toFail: pan)`** so taps and drags coexist.

Game-specific complexity (odds, lay bets, zone moves) lives in `endDrag`'s decision tree and can be trimmed for simpler use cases.

---

## What NOT to Copy

- The full `endDrag` decision tree if you don't need odds/lay/zone semantics — start with three cases: new bet, move, cancel.
- Locked-bet proximity animation unless you have a similar "drop near existing item for sub-action" UX.
- Multiple source tracking (`oddsSourceControl`, `layBetSource`) unless you have multiple chip types per control.

---

## Testing Notes

- UI tests use accessibility identifiers on chips (`chipDrag.{value}`) and bet values on controls.
- Drag tests rely on the ghost chip being in the root view — coordinate space is always the VC's root view.
