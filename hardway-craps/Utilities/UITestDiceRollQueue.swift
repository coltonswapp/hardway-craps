import Foundation

/// Dequeues fixed dice totals when the app is launched with UI-test launch arguments.
///
/// Combine with session suppression so UI runs are not saved as real gameplay (see `UITestLaunchConfiguration`).
///
/// From `XCUITest`, before `launch()`:
/// ```swift
/// app.launchArguments = ["-UITestDisableSessionRecording", "-UITestFixedDiceTotals", "8,6,7"]
/// ```
/// Each physical tap on the dice consumes the next value (must be 2...12). After the list is
/// exhausted, `FlipDiceContainer` falls back to normal random rolls.
enum UITestDiceRollQueue {
    private static let totals: [Int]? = {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-UITestFixedDiceTotals"),
              idx + 1 < args.count else { return nil }
        let csv = args[idx + 1]
        let parsed = csv.split(separator: ",").compactMap { raw -> Int? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let v = Int(trimmed), (2...12).contains(v) else { return nil }
            return v
        }
        return parsed.isEmpty ? nil : parsed
    }()

    private static var nextIndex = 0

    static func dequeueNextTotalIfAvailable() -> Int? {
        guard let totals, nextIndex < totals.count else { return nil }
        defer { nextIndex += 1 }
        return totals[nextIndex]
    }
}
