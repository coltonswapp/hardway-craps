//
//  CrapsGameplayViewController+Autoplay.swift
//  hardway-craps
//

import UIKit

extension CrapsGameplayViewController: CrapsAutoplayContext {

  func snapshot() -> CrapsTableSnapshot {
    let phase: CrapsAutoplayPhase
    switch game.currentPhase {
    case .comeOut:
      phase = .comeOut
    case .point(let n):
      phase = .point(n)
    }

    let gateOpen = flipDiceContainer.allowsProgrammaticRoll
    let anyBet = hasAnyBetPlaced()
    let canRollNow = gateOpen && (game.isPointPhase || anyBet)

    let settings = settingsManager.currentSettings
    return CrapsTableSnapshot(
      phase: phase,
      balance: balance,
      betsAreOn: betsAreOn,
      selectedChipValue: selectedChipValue,
      passLineBet: passLineControl.betAmount,
      passLineOdds: passLineControl.oddsAmount,
      fieldBet: fieldControl.betAmount,
      hardwaysEnabled: settings.hardwaysEnabled,
      makeEmEnabled: settings.makeEmEnabled,
      hornEnabled: settings.hornEnabled,
      variant: variant,
      rollingGateOpen: gateOpen,
      isDiceRolling: flipDiceContainer.isRolling,
      canRoll: canRollNow
    )
  }

  func enqueueAutoplayCommands(
    _ commands: [CrapsTableCommand],
    delayBetweenSteps: TimeInterval,
    completion: (() -> Void)?
  ) {
    cancelAutoplayQueuedCommands()

    guard !commands.isEmpty else {
      DispatchQueue.main.async {
        completion?()
      }
      return
    }

    crapsAutoplayer?.markSequentialBetCommandsStarted()

    for (idx, cmd) in commands.enumerated() {
      let work = DispatchWorkItem { [weak self] in
        guard let self else { return }
        guard self.crapsAutoplayer?.isRunning == true else { return }
        self.execute(cmd)
      }
      crapsAutoplayQueuedWorkItems.append(work)
      DispatchQueue.main.asyncAfter(deadline: .now() + delayBetweenSteps * Double(idx), execute: work)
    }

    let doneWork = DispatchWorkItem { [weak self] in
      self?.crapsAutoplayer?.markSequentialBetCommandsFinished()
      guard self?.crapsAutoplayer?.isRunning == true else { return }
      completion?()
    }
    crapsAutoplayQueuedWorkItems.append(doneWork)
    let completionDelay = delayBetweenSteps * Double(max(0, commands.count - 1)) + 0.02
    DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay, execute: doneWork)
  }

  func cancelAutoplayQueuedCommands() {
    crapsAutoplayer?.abortSequentialBetCommandsIfNeeded()
    for item in crapsAutoplayQueuedWorkItems {
      item.cancel()
    }
    crapsAutoplayQueuedWorkItems.removeAll()
  }

  func execute(_ command: CrapsTableCommand) {
    switch command {
    case .setChip(let value):
      chipSelector.selectChip(withValue: value, animated: true)

    case .placePassLine(let amount):
      guard amount > 0, amount <= balance else { return }
      passLineControl.addBetWithAnimation(amount)

    case .placeField(let amount):
      guard amount > 0, amount <= balance, betsAreOn else { return }
      fieldControl.addBetWithAnimation(amount)

    case .placeAcross(let allocation):
      applyPlaceAcross(allocation)

    case .placeBetOnBox(let number, let amount):
      guard betsAreOn, amount > 0, amount <= balance else { return }
      // Never buy the box that is currently the pass-line point.
      if game.isPointPhase, game.currentPoint == number {
        return
      }
      guard let pc = pointStack?.getPointControl(for: number) else { return }
      pc.addBetWithAnimation(amount)

    case .placeOdds(let amount):
      guard amount > 0, amount <= balance else { return }
      guard game.isPointPhase, passLineControl.betAmount > 0 else { return }
      guard let stack = passLineControl.oddsBetStack, stack.hasLockedBet() else { return }
      stack.addOddsWithAnimation(amount)

    case .placeRandomHardway(let amount):
      guard amount > 0, amount <= balance, betsAreOn else { return }
      guard let control = randomHardwayPlainControlForAutoplay() else { return }
      control.addBetWithAnimation(amount)

    case .placeRandomHorn(let amount):
      guard amount > 0, amount <= balance, betsAreOn else { return }
      guard let control = randomHornPlainControlForAutoplay() else { return }
      control.addBetWithAnimation(amount)

    case .toggleBetsOnOff:
      toggleBetsTapped()

    case .collectBets:
      collectBetsTapped()

    case .rollDice:
      flipDiceContainer.roll()
    }
  }

  func refreshAutoplayNavigationChrome() {
    let base: String
    switch variant {
    case .standard:
      base = "Craps"
    case .crapless:
      base = "Crapless"
    }
    title = crapsAutoplayer?.isRunning == true ? "\(base) · Auto" : base
  }

  func stopCrapsAutoplaySilently() {
    cancelAutoplayQueuedCommands()
    crapsAutoplayer?.stop()
    refreshAutoplayNavigationChrome()
  }

  func handleCrapsAutoplaySettingChanged(enabled: Bool) {
    if enabled {
      cancelAutoplayQueuedCommands()
      if crapsAutoplayer == nil {
        crapsAutoplayer = CrapsAutoplayer(profile: .random())
      }
      crapsAutoplayer?.attach(context: self)
      crapsAutoplayer?.start()
    } else {
      cancelAutoplayQueuedCommands()
      crapsAutoplayer?.stop()
    }
    refreshAutoplayNavigationChrome()
  }

  // MARK: - Random proposition helpers

  fileprivate func randomHardwayPlainControlForAutoplay() -> PlainControl? {
    guard let hardwayView = hardwayView else { return nil }
    var pool: [PlainControl] = []
    for arrangedSubview in hardwayView.betStack.arrangedSubviews {
      guard let columnStack = arrangedSubview as? UIStackView else { continue }
      for columnSubview in columnStack.arrangedSubviews {
        if let pc = columnSubview as? PlainControl {
          pool.append(pc)
        }
      }
    }
    return pool.randomElement()
  }

  fileprivate func randomHornPlainControlForAutoplay() -> PlainControl? {
    guard let hornView = hornView else { return nil }
    var pool: [PlainControl] = []
    for arrangedSubview in hornView.betStack.arrangedSubviews {
      guard let columnStack = arrangedSubview as? UIStackView else { continue }
      for columnSubview in columnStack.arrangedSubviews {
        if let pc = columnSubview as? PlainControl {
          pool.append(pc)
        }
      }
    }
    return pool.randomElement()
  }
}
