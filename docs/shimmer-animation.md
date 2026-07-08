# Shimmer Animation — Agent Handoff

This document describes how **hardway-craps** implements shimmer animations. It is intended for another agent building a similar effect in a different project.

## Summary

Shimmer is implemented with **`CAGradientLayer` + `CABasicAnimation` on the `locations` key path** — not SwiftUI, Lottie, or third-party libraries. There are **two patterns**:

1. **Persistent label shimmer** — looping overlay masked to label text (`LabelShimmerView` + `UILabel` extensions)
2. **One-shot view/chip shimmer** — single sweep across any `UIView`, layer removed on completion

Both use the same gradient recipe and sweep direction (~10° angle).

---

## Key Files

| File | Purpose |
|------|---------|
| `hardway-craps/LabelShimmerView.swift` | Core implementation: label overlay, UILabel/UIView extensions |
| `hardway-craps/Controls/PlainControl.swift` | `shimmerTitleLabel()` / `stopTitleShimmer()` wrappers on bet controls |
| `hardway-craps/Games/Craps/FlipDiceContainer.swift` | CTA label: shimmer on `enableRolling()`, remove on `disableRolling()` |
| `hardway-craps/Games/Blackjack/BlackjackGameplayViewController.swift` | State-driven shimmer via `updateBetShimmer()` |
| `hardway-craps/Controls/ChipSelector.swift` | One-shot shimmer when a new chip denomination unlocks |
| `hardway-craps/Controls/MPSmallBetChip.swift` | `playChipShimmer()` for multiplayer bet chips |
| `hardway-craps/Utilities/BetResultContainer.swift` | Quick shimmer when win/loss amount finishes counting up |

---

## Core Technique

### Gradient setup

Four color stops: transparent → white (40% opacity) → white → transparent.

```swift
shimmer.colors = [
    UIColor.clear.cgColor,
    UIColor.white.withAlphaComponent(0.4).cgColor,
    UIColor.white.withAlphaComponent(0.4).cgColor,
    UIColor.clear.cgColor
]
shimmer.locations = [0, 0.3, 0.7, 1]
```

### Sweep angle (~10°)

Convert angle to gradient start/end points in unit coordinate space:

```swift
let angle = 10 * CGFloat.pi / 180
shimmer.startPoint = CGPoint(x: 0.5 - cos(angle) * 0.5, y: 0.5 - sin(angle) * 0.5)
shimmer.endPoint   = CGPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)
```

### Animation

Animate `locations` so the bright band sweeps across:

```swift
let animation = CABasicAnimation(keyPath: "locations")
animation.fromValue = [-0.8, -0.6, -0.4, -0.2]   // off-screen left
animation.toValue   = [1.2, 1.4, 1.6, 1.8]       // off-screen right
animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
```

Negative/above-1 location values are intentional — they start/end the band fully outside the visible bounds.

---

## Pattern 1: Persistent Label Shimmer

Used for **call-to-action text** that should shimmer continuously until dismissed (e.g. "Tap to Roll", "Place Bet").

### Architecture

```
UILabel
  └── (associated object) LabelShimmerView overlay
        ├── CAGradientLayer (shimmer band)
        └── CALayer mask
              └── CATextLayer (matches label text/font/alignment)
```

`LabelShimmerView` is a clear, non-interactive overlay pinned to the label's frame. The gradient is **masked to the text glyphs** via a `CATextLayer` recreated in `layoutSubviews`.

### UILabel API (via associated object)

| Method | Behavior |
|--------|----------|
| `addShimmerEffect()` | Create overlay, pin to label, start **1.8s infinite** loop |
| `addQuickShimmerEffect()` | Same overlay, **0.75s infinite** loop |
| `removeShimmerEffect()` | Stop animation, remove overlay, clear association |
| `startShimmer()` / `stopShimmer()` | Pause/resume existing overlay without removing it |

**Guard:** `addShimmerEffect()` is a no-op if a shimmer overlay already exists or the label has no superview.

### Associated object storage

The overlay is retained on the label via `objc_setAssociatedObject` — no subclassing required:

```swift
private static var shimmerViewAssociationKey: UInt8 = 0

private var shimmerView: LabelShimmerView? {
    get { objc_getAssociatedObject(self, &UILabel.shimmerViewAssociationKey) as? LabelShimmerView }
    set { objc_setAssociatedObject(self, &UILabel.shimmerViewAssociationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
}
```

### Mask updates

On `layoutSubviews`, the mask's `CATextLayer` is rebuilt from the target label's current `text`, `font`, `textAlignment`, and `bounds`. Call `layoutIfNeeded()` on the label before starting shimmer if text was just set.

### Control-level wrappers

`PlainControl` exposes convenience methods that shimmer the title label:

```swift
func shimmerTitleLabel() {
    titleLabel.addShimmerEffect()
}

func stopTitleShimmer() {
    titleLabel.removeShimmerEffect()
}
```

`BlackJackBetControl` overrides these to shimmer a custom `betLabel` instead.

---

## Pattern 2: One-Shot View/Chip Shimmer

Used for **momentary feedback** — chip unlocked, remote bet updated, win celebration. No persistent overlay; layer is added, animates once, then removed.

### UIView.playShimmer()

```swift
extension UIView {
    func playShimmer() {
        let shimmer = CAGradientLayer()
        // ... gradient setup ...
        shimmer.frame = bounds
        shimmer.cornerRadius = layer.cornerRadius
        shimmer.masksToBounds = true
        layer.addSublayer(shimmer)

        let animation = CABasicAnimation(keyPath: "locations")
        animation.duration = 0.75
        animation.repeatCount = 1
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { shimmer.removeFromSuperlayer() }
        shimmer.add(animation, forKey: "shimmer")
        CATransaction.commit()
    }
}
```

**Important:** Call `layoutIfNeeded()` on the view first so `bounds` is correct.

### MPSmallBetChip.playChipShimmer()

Same technique, **0.3s duration** (faster for small chips). Used in multiplayer controls when bets update remotely.

---

## Timing Reference

| API | Duration | Repeat | Use case |
|-----|----------|--------|----------|
| `startShimmerAnimation()` | 1.8s | ∞ | Persistent CTA labels |
| `startQuickShimmerAnimation()` | 0.75s | ∞ | Faster persistent (win amount display) |
| `UIView.playShimmer()` | 0.75s | 1 | Chip unlock, general feedback |
| `MPSmallBetChip.playChipShimmer()` | 0.3s | 1 | Small bet chips, multiplayer updates |

---

## Usage Patterns in the App

### 1. Enable/disable CTA (FlipDiceContainer)

Shimmer starts when rolling becomes available; stops when rolling is disabled:

```swift
func enableRolling() {
    // ... fade in "Tap to Roll" label ...
    tapToRollLabel.addShimmerEffect()
}

func disableRolling() {
    tapToRollLabel.removeShimmerEffect()
    // ... fade out label ...
}
```

### 2. State-driven bet control shimmer (Blackjack)

Central method toggles shimmer based on game phase:

```swift
private func updateBetShimmer() {
    let betAmount = playerHandView.betControl.betAmount
    if gamePhase == .waitingForBet && betAmount == 0 {
        playerHandView.betControl.shimmerTitleLabel()
    } else {
        playerHandView.betControl.stopTitleShimmer()
    }
}
```

Called from phase transitions and after bet placement. **Always pair start with a clear stop condition** to avoid orphaned overlays.

### 3. Stop shimmer on user action (Craps pass line)

`addedBetCompletionHandler` on bet controls fires after a bet is placed (including drag-drop). Craps uses it to stop shimmer:

```swift
passLineControl.addedBetCompletionHandler = { [weak self] in
    self?.passLineControl.stopTitleShimmer()
    self?.dontPassControl?.stopTitleShimmer()
}
```

### 4. Win amount celebration (BetResultContainer)

When a counting animation completes, trigger a quick shimmer on the final value:

```swift
if progress >= 1.0 {
    label.text = "\(prefix)$\(targetValue)"
    stopAnimation()
    label.addQuickShimmerEffect()
}
```

### 5. New chip unlocked (ChipSelector)

When balance crosses a threshold and a new denomination appears:

```swift
if let newValue = newChipValue,
   let chip = chipControls.first(where: { $0.value == newValue }) {
    chip.layoutIfNeeded()
    chip.playShimmer()
}
```

### 6. Multiplayer bet updates

Remote bet changes trigger scale + shimmer on the affected chip:

```swift
chip.playChipShimmer()  // or existing.chip.playChipShimmer()
```

Used in `MPBonusBetControl`, `MPInsuranceControl`, `PassLineTwoPlayerControl`, `MPChipAnimationHelper`.

---

## Lifecycle Diagram

### Persistent label shimmer

```
addShimmerEffect()
  → Create LabelShimmerView, pin to label frame
  → Build CATextLayer mask from label properties
  → Start infinite locations animation

removeShimmerEffect()
  → stopShimmerAnimation() (remove CA animation)
  → removeFromSuperview()
  → shimmerView = nil
```

### One-shot view shimmer

```
playShimmer() / playChipShimmer()
  → Add CAGradientLayer sublayer (frame = bounds)
  → Animate locations once
  → CATransaction completion → removeFromSuperlayer()
```

---

## Design Decisions Worth Copying

1. **Animate `locations`, not `transform` or `position`** — Keeps the gradient band shape consistent; only the stop positions move.

2. **Text masking for labels** — Shimmer appears only on glyph shapes, not the full label bounding box. Recreate mask on layout so dynamic text stays correct.

3. **Associated objects on UILabel** — Any label can shimmer without subclassing. Overlay lives in the label's superview (same z-order as the label).

4. **Separate persistent vs one-shot APIs** — Looping CTAs use overlay + remove; feedback flashes use ephemeral sublayers.

5. **`isUserInteractionEnabled = false` on overlay** — Shimmer never blocks taps on the underlying control.

6. **Always call `layoutIfNeeded()` before one-shot shimmer** — Gradient `frame = bounds` must reflect final layout.

7. **Pair start/stop explicitly** — Use game-state methods (`updateBetShimmer`) or completion handlers (`addedBetCompletionHandler`) so shimmer doesn't run forever after the CTA is satisfied.

---

## Minimal Recipe for a New Project

### Persistent label shimmer

1. Create a `LabelShimmerView` overlay with `CAGradientLayer` + text mask.
2. Add `UILabel` extensions with associated-object storage.
3. Pin overlay to label edges in the label's superview.
4. Expose `addShimmerEffect()` / `removeShimmerEffect()`.
5. Start on "needs attention" state; stop on user action or state change.

### One-shot view shimmer

1. Add `playShimmer()` to `UIView`.
2. Create gradient sublayer, animate `locations` once.
3. Remove layer in `CATransaction.setCompletionBlock`.
4. Call after layout when you want a brief highlight.

### Copy-paste constants

```swift
// Gradient
colors: [clear, white@0.4, white@0.4, clear]
locations: [0, 0.3, 0.7, 1]
angle: 10°

// Animation keyframes
fromValue: [-0.8, -0.6, -0.4, -0.2]
toValue:   [1.2, 1.4, 1.6, 1.8]
timing: easeInEaseOut
```

---

## What NOT to Copy

- **Infinite quick shimmer on win labels** unless you also wire up removal — `addQuickShimmerEffect()` loops forever until `removeShimmerEffect()` is called.
- **CATextLayer mask** if you only need a rectangular shimmer (buttons, chips) — use the simpler one-shot sublayer approach.
- **Duplicate gradient setup** in three places — consider extracting a shared `ShimmerGradientLayer` factory if maintaining across projects.

---

## Gotchas

| Issue | Cause | Fix |
|-------|-------|-----|
| Shimmer not visible | Label has no superview when `addShimmerEffect()` called | Ensure label is in hierarchy first |
| Shimmer wrong shape | Text changed after mask created | `layoutSubviews` rebuilds mask; call `layoutIfNeeded()` |
| One-shot shimmer at wrong size | `bounds` zero | `layoutIfNeeded()` before `playShimmer()` |
| Shimmer blocks taps | Overlay intercepts touches | Set `isUserInteractionEnabled = false` on overlay |
| Double shimmer | `addShimmerEffect()` called twice | Guard checks `shimmerView == nil` |
| Shimmer never stops | No `removeShimmerEffect()` on state change | Wire stop to bet placed, phase change, or disable |

---

## Testing Notes

- Shimmer is visual-only; no accessibility identifiers specific to shimmer state.
- UI tests should assert on underlying control state (bet placed, rolling enabled), not shimmer presence.
- Autoplay gates on `FlipDiceContainer.isRollingEnabled` which correlates with tap-to-roll shimmer being active.
