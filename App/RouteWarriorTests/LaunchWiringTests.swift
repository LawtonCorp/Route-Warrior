import XCTest
@testable import RouteWarrior

/// D-078: auto-recording starts at launch, and iOS launches this app two
/// ways. The background relaunch — no window, no root view, no `.task` —
/// is the one that carries a drive taken after iOS reclaimed the app, and
/// it was the one nothing ran on.
@MainActor
final class LaunchWiringTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Why the process started

    func testALocationKeyInTheLaunchOptionsIsABackgroundWake() {
        XCTAssertEqual(LaunchReason.from(hasLocationKey: true), .locationWake)
        XCTAssertEqual(LaunchReason.from(hasLocationKey: false), .foreground)
    }

    /// The log line is the whole point of telling them apart.
    func testTheTwoLaunchesReadDifferentlyInTheLog() {
        XCTAssertNotEqual(LaunchReason.foreground.logLabel, LaunchReason.locationWake.logLabel)
        XCTAssertTrue(LaunchReason.locationWake.logLabel.contains("woken"))
    }

    // MARK: The handoff runs exactly once, in either order

    func testTheLaunchRunsTheHandlerWhenTheDelegateReportsItFirst() {
        let coordinator = LaunchCoordinator()
        var seen: [LaunchReason] = []
        coordinator.began(.locationWake)
        coordinator.onLaunch { seen.append($0) }
        XCTAssertEqual(seen, [.locationWake])
    }

    /// The order SwiftUI builds the `App` in relative to UIKit's launch
    /// callback is not documented and has changed between releases. A
    /// hook that works in only one order is the wiring that passes its
    /// test and does nothing on a phone.
    func testTheLaunchRunsTheHandlerWhenTheAppRegistersFirst() {
        let coordinator = LaunchCoordinator()
        var seen: [LaunchReason] = []
        coordinator.onLaunch { seen.append($0) }
        XCTAssertEqual(seen, [], "nothing to run yet — the process has not reported its launch")
        coordinator.began(.foreground)
        XCTAssertEqual(seen, [.foreground])
    }

    /// Both callers may fire more than once across a process; starting
    /// the services twice is harmless but a second "App launched" line in
    /// the recorder log is a lie about a second launch.
    func testTheHandlerRunsOnceNoMatterHowOftenEitherSideSpeaks() {
        let coordinator = LaunchCoordinator()
        var count = 0
        coordinator.began(.locationWake)
        coordinator.began(.locationWake)
        coordinator.onLaunch { _ in count += 1 }
        coordinator.onLaunch { _ in count += 1 }
        XCTAssertEqual(count, 1)
    }

    // MARK: Silence is no longer ambiguous

    func testTheFirstIdleUpdateIsAlwaysWorthALine() {
        XCTAssertTrue(WakeLog.shouldLog(at: t0, lastLoggedAt: nil))
    }

    func testIdleUpdatesAreLoggedAtMostOncePerWindow() {
        XCTAssertFalse(WakeLog.shouldLog(at: t0.addingTimeInterval(599), lastLoggedAt: t0))
        XCTAssertTrue(WakeLog.shouldLog(at: t0.addingTimeInterval(600), lastLoggedAt: t0))
        XCTAssertTrue(WakeLog.shouldLog(at: t0.addingTimeInterval(3_600), lastLoggedAt: t0))
    }

    /// Location samples can arrive out of order; an older one must not
    /// look like a fresh window.
    func testASampleOlderThanTheLastLineIsNotANewWindow() {
        XCTAssertFalse(WakeLog.shouldLog(at: t0.addingTimeInterval(-600), lastLoggedAt: t0))
    }
}
