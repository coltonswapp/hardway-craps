//
//  CrapsAutoplayer.swift
//  hardway-craps
//

import Foundation

/// UI-driven craps autoplayer: issues `CrapsTableCommand`s through `CrapsAutoplayContext`.
final class CrapsAutoplayer {

  /// Table-style minimum for **main** bets (pass, field, odds, place-across totals).
  /// Props (horn, hardways, ATS, C&E, etc.) may use smaller stakes.
  private static let mainBetMinimum = 10

  /// Autoplayer never exceeds this on the pass line (field / place-across may still size separately).
  private static let passLineMaximum = 20

  /// Field stays modest — uses its own bankroll slice (not `maxBankrollFractionSingleMainCommit`).
  private static let fieldBetMaximum = 20

  /// Largest fraction of bankroll for one **field** bet (in addition to `fieldBetMaximum`).
  private static let maxBankrollFractionField: Double = 0.10

  /// Largest fraction of bankroll spent on one **main** wager (pass / field / odds / place-across whole spread).
  private static let maxBankrollFractionSingleMainCommit: Double = 0.22

  /// Largest fraction of bankroll for a full place-across spread (many numbers).
  private static let maxBankrollFractionPlaceAcross: Double = 0.38

  private weak var context: CrapsAutoplayContext?
  private var profile: CrapsAutoplayerProfile
  private var workItem: DispatchWorkItem?
  private var lastSnapshot: CrapsTableSnapshot?

  private(set) var isRunning: Bool = false
  /// Suppresses main `tick()` while staggered place bets are dispatching (avoids overlapping actions).
  private(set) var isSequentialCommandRunActive: Bool = false

  init(profile: CrapsAutoplayerProfile = .random()) {
    self.profile = profile
  }

  func attach(context: CrapsAutoplayContext) {
    self.context = context
  }

  func markSequentialBetCommandsStarted() {
    isSequentialCommandRunActive = true
  }

  func markSequentialBetCommandsFinished() {
    isSequentialCommandRunActive = false
  }

  func abortSequentialBetCommandsIfNeeded() {
    isSequentialCommandRunActive = false
  }

  func updateProfile(_ profile: CrapsAutoplayerProfile) {
    self.profile = profile
  }

  func start() {
    guard !isRunning else { return }
    context?.cancelAutoplayQueuedCommands()
    isRunning = true
    lastSnapshot = nil
    scheduleTick(after: Double.random(in: 0.8...2.2))
  }

  func stop() {
    context?.cancelAutoplayQueuedCommands()
    abortSequentialBetCommandsIfNeeded()
    isRunning = false
    workItem?.cancel()
    workItem = nil
    lastSnapshot = nil
  }

  /// Call after physical dice animation completes (same time `handleRollResult` runs).
  /// When `hitPassLinePoint` is true (shooter repeated the point / pass won), wait longer before the next autoplay action so the roll does not feel instant.
  /// When `passLineLost` is true (seven-out or come-out craps on pass), pause ~1s before the next tick so rebetting does not feel instant.
  func notifyRollResolved(hitPassLinePoint: Bool = false, passLineLost: Bool = false) {
    guard isRunning else { return }
    let delay: TimeInterval
    if hitPassLinePoint {
      delay = Double.random(in: 1.15...2.45)
    } else if passLineLost {
      delay = Double.random(in: 0.95...1.35)
    } else {
      delay = Double.random(in: 0.25...0.85)
    }
    scheduleTick(after: delay)
  }

  func cancelDueToUserInteraction() {
    guard isRunning else { return }
    stop()
    NotificationCenter.default.post(name: .crapsAutoplayDidStopFromUserInteraction, object: nil)
  }

  // MARK: - Tick

  private func scheduleTick(after delay: TimeInterval) {
    workItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.tick()
    }
    workItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
  }

  private func tick() {
    guard isRunning, let context else {
      stop()
      return
    }

    if isSequentialCommandRunActive {
      scheduleTick(after: 0.12)
      return
    }

    let snap = context.snapshot()

    if snap.balance < Self.mainBetMinimum {
      stop()
      NotificationCenter.default.post(name: .crapsAutoplayDidStopBankrupt, object: nil)
      return
    }

    guard snap.allowsAutoplayBetPlacement else {
      scheduleTick(after: 0.22)
      return
    }

    if handleSevenOutCollectIfNeeded(previous: lastSnapshot, current: snap, context: context) {
      lastSnapshot = snap
      scheduleTick(after: Double.random(in: 0.45...1.1))
      return
    }

    lastSnapshot = snap

    pickChipSometimes(snap: snap, context: context)

    let refreshed = context.snapshot()

    if refreshed.isComeOut && refreshed.passLineBet == 0 {
      let wager = passLineRoundedStake(for: refreshed)
      guard wager <= refreshed.balance else {
        scheduleTick(after: 0.5)
        return
      }
      context.execute(.placePassLine(wager))
      scheduleTick(after: Double.random(in: 0.35...1.1))
      return
    }

    let s1 = context.snapshot()
    guard s1.betsAreOn else {
      tryRollOrWait(s1, context: context)
      return
    }

    // Take pass odds **before** place-across so bankroll is not consumed by props first.
    // Always **≥ 1×** pass line when locked with sufficient balance.
    if !s1.isComeOut,
      s1.passLineBet > 0,
      s1.passLineOdds == 0,
      s1.balance >= s1.passLineBet
    {
      let target = passLineOddsStakeAmount(for: s1)
      guard target >= s1.passLineBet, target <= s1.balance else {
        tryRollOrWait(s1, context: context)
        return
      }
      context.execute(.placeOdds(target))
      scheduleTick(after: Double.random(in: 0.35...1.15))
      return
    }

    if s1.isComeOut && s1.fieldBet == 0 && Double.random(in: 0...1) < profile.fieldLean * 0.82 {
      let wager = fieldStakeAmount(for: s1)
      guard wager <= s1.balance else {
        tryRollOrWait(s1, context: context)
        return
      }
      context.execute(.placeField(wager))
      scheduleTick(after: Double.random(in: 0.3...1.0))
      return
    }

    let s2 = context.snapshot()
    // Place bets only after point is established (not on come-out).
    if !s2.isComeOut,
      Double.random(in: 0...1) < profile.placeAcrossProbability,
      let allocation = pickPlaceAcrossAllocation(
        balance: s2.balance, variant: s2.variant, skipBox: s2.pointNumber)
    {
      let cmds = PlaceAcrossAutoplayCommands.staggeredPlaceBets(
        allocation: allocation,
        skipBox: s2.pointNumber)
      guard !cmds.isEmpty else {
        tryRollOrWait(s2, context: context)
        return
      }
      let chipCost = allocation.chipCostSkipping(pointNumber: s2.pointNumber)
      guard chipCost <= s2.balance else {
        tryRollOrWait(s2, context: context)
        return
      }
      context.enqueueAutoplayCommands(cmds, delayBetweenSteps: Self.betweenBetDelaySeconds) {
        [weak self] in
        self?.scheduleTick(after: Double.random(in: 0.35...1.15))
      }
      return
    }

    let s3 = context.snapshot()
    if s3.hardwaysEnabled && Double.random(in: 0...1) < profile.hardwaySprinkleProbability {
      let w = min(propStakeAmount(for: s3), s3.balance)
      if w >= 1 {
        context.execute(.placeRandomHardway(w))
        scheduleTick(after: Double.random(in: 0.28...0.85))
        return
      }
    }

    let s4 = context.snapshot()
    if s4.hornEnabled && Double.random(in: 0...1) < profile.hornSprinkleProbability {
      let w = min(propStakeAmount(for: s4), s4.balance)
      if w >= 1 {
        context.execute(.placeRandomHorn(w))
        scheduleTick(after: Double.random(in: 0.28...0.85))
        return
      }
    }

    tryRollOrWait(context.snapshot(), context: context)
  }

  private func tryRollOrWait(_ snap: CrapsTableSnapshot, context: CrapsAutoplayContext) {
    if snap.canRoll && Double.random(in: 0...1) > 0.15 {
      context.execute(.rollDice)
      scheduleTick(after: Double.random(in: 0.35...1.05))
    } else {
      scheduleTick(after: Double.random(in: 0.25...0.75))
    }
  }

  private func handleSevenOutCollectIfNeeded(
    previous: CrapsTableSnapshot?,
    current: CrapsTableSnapshot,
    context: CrapsAutoplayContext
  ) -> Bool {
    guard let previous else { return false }
    if case .point = previous.phase,
      current.isComeOut,
      previous.passLineBet > 0,
      current.passLineBet == 0,
      Double.random(in: 0...1) < profile.collectAfterSevenOutProbability
    {
      context.execute(.collectBets)
      return true
    }
    return false
  }

  /// Pass line uses nearest **$5** increment (i.e. valid **$5 / $10** table chips), minimum `mainBetMinimum`.
  private func passLineRoundedStake(for snap: CrapsTableSnapshot) -> Int {
    let raw = mainStakeAmount(for: snap)
    let nearestFive = ((raw + 2) / 5) * 5
    var wager = min(
      nearestFive, snap.balance, mainBetCap(balance: snap.balance), Self.passLineMaximum)
    wager = (wager / 5) * 5
    return max(Self.mainBetMinimum, wager)
  }

  /// Field: **≥ $10**, capped lower than generic `mainStakeAmount` so large chip / bankroll does not produce huge fields.
  private func fieldStakeAmount(for snap: CrapsTableSnapshot) -> Int {
    let softCap = max(Self.mainBetMinimum, Int(Double(snap.balance) * Self.maxBankrollFractionField))
    let ceiling = min(softCap, Self.fieldBetMaximum, snap.balance)
    let chip = min(snap.selectedChipValue, Self.fieldBetMaximum)
    let imperfect =
      (Double.random(in: 0...1) < 0.08 && Self.mainBetMinimum + 5 <= ceiling)
      ? -5 : 0
    let desired = max(Self.mainBetMinimum, min(chip, ceiling) + imperfect)
    let clamped = min(max(Self.mainBetMinimum, desired), ceiling)
    return clamped
  }

  /// Pass / single-shot sizing (not field): **≥ $10**, never most of the bankroll on one bet.
  private func mainStakeAmount(for snap: CrapsTableSnapshot) -> Int {
    let cap = mainBetCap(balance: snap.balance)
    let chip = snap.selectedChipValue
    let imperfect =
      (Double.random(in: 0...1) < 0.1 && Self.mainBetMinimum + 5 <= cap)
      ? -5 : 0
    let desired = max(Self.mainBetMinimum, min(chip, cap) + imperfect)
    let clamped = min(max(Self.mainBetMinimum, desired), cap, snap.balance)
    return clamped
  }

  /// Horn / hardway sprinkles — **below** main $10 minimum (table-style props).
  private func propStakeAmount(for snap: CrapsTableSnapshot) -> Int {
    let cap = max(1, min(5, snap.balance / 25))
    let chip = min(snap.selectedChipValue, cap)
    let amount = max(1, chip)
    return min(amount, snap.balance)
  }

  /// Odds: **always ≥ 1×** pass line (`amount >= passLineBet`), up to 5× within balance.
  private func passLineOddsStakeAmount(for snap: CrapsTableSnapshot) -> Int {
    let line = snap.passLineBet
    guard line > 0 else { return 0 }

    let maxMultipleRules = 5
    let maxTotalByRules = line * maxMultipleRules
    let affordableCeiling = min(snap.balance, maxTotalByRules)

    // Keep odds exposure in line with **main bet** bankroll cap (avoid pass@cap + 5× odds ≈ entire roll).
    let capMultipleFromSizing = max(1, mainBetCap(balance: snap.balance) / max(1, line))

    let maxMultiple = min(maxMultipleRules, affordableCeiling / line, capMultipleFromSizing)

    let desiredMultiple: Int = {
      if maxMultiple <= 1 { return 1 }
      let r = Double.random(in: 0...1)
      let p = profile.oddsTakeProbability
      let hi = maxMultiple
      if r < p * 0.35 {
        return Int.random(in: 1...min(2, hi))
      }
      if r < p {
        return Int.random(in: 1...min(3, hi))
      }
      return Int.random(in: 1...hi)
    }()

    let target = line * desiredMultiple
    return min(max(line, target), affordableCeiling, snap.balance)
  }

  /// Soft cap for one main wager from current bankroll (pass / field / odds).
  private func mainBetCap(balance: Int) -> Int {
    let frac = max(Self.mainBetMinimum, Int(Double(balance) * Self.maxBankrollFractionSingleMainCommit))
    return min(balance, frac)
  }

  private func pickChipSometimes(snap: CrapsTableSnapshot, context: CrapsAutoplayContext) {
    guard Double.random(in: 0...1) < 0.32 else { return }
    let targets: [Int] = [1, 5, 25, 50, 100]
    guard let ceiling = targets.last(where: { $0 <= snap.balance }) else { return }
    let choice = targets.filter { $0 <= ceiling }.randomElement() ?? ceiling
    context.execute(.setChip(choice))
  }

  /// Delay between staggered place bets (place-across boxes).
  private static let betweenBetDelaySeconds: TimeInterval = 0.3

  private func pickPlaceAcrossAllocation(balance: Int, variant: CrapsVariant, skipBox: Int?) -> PlaceAcrossAllocation? {
    let minTotal = PlaceAcrossAllocator.minimumSpreadTotal(for: variant)
    let spendCap = max(
      minTotal,
      min(balance, Int(Double(balance) * Self.maxBankrollFractionPlaceAcross)))
    guard balance >= minTotal else { return nil }

    let rows = PlaceAcrossAllocator.presets(balance: balance, variant: variant, chipStepPreferred: nil, maxOptions: 8)
    func cost(_ a: PlaceAcrossAllocation) -> Int {
      a.chipCostSkipping(pointNumber: skipBox)
    }
    let affordable = rows.filter {
      let c = cost($0)
      return c <= spendCap && c <= balance
    }
    guard let pick = affordable.randomElement()
      ?? rows.filter({ cost($0) <= balance }).min(by: { cost($0) < cost($1) })
    else {
      return nil
    }
    return pick
  }
}

extension Notification.Name {
  static let crapsAutoplayDidStopFromUserInteraction = Notification.Name("crapsAutoplayDidStopFromUserInteraction")
  static let crapsAutoplayDidStopBankrupt = Notification.Name("crapsAutoplayDidStopBankrupt")
}
