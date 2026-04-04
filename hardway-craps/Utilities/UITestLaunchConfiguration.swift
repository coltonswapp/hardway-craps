import Foundation

/// Launch arguments used when the app is driven by `XCUITest` (`XCUIApplication.launchArguments`).
enum UITestLaunchConfiguration {
    /// When set, gameplay sessions are not written to `SessionPersistenceManager` and craps session-start
    /// analytics are skipped — use for UI tests so runs are not recorded as real sessions.
    static var suppressGameplaySessionRecording: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestDisableSessionRecording")
    }
}
