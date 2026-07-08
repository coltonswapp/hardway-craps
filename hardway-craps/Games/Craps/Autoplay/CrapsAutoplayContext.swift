//
//  CrapsAutoplayContext.swift
//  hardway-craps
//

import Foundation

/// Execution surface for craps autoplay — implemented by the gameplay view controller.
protocol CrapsAutoplayContext: AnyObject {
  func snapshot() -> CrapsTableSnapshot
  func execute(_ command: CrapsTableCommand)

  /// Runs commands on the main queue with `delayBetweenSteps` spacing (e.g. place each box separately).
  func enqueueAutoplayCommands(_ commands: [CrapsTableCommand], delayBetweenSteps: TimeInterval, completion: (() -> Void)?)

  func cancelAutoplayQueuedCommands()
}
