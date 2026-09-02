import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// D-022 Q6 wiring: leaving the plan is detected through the kit, a
/// reroute happens on tap always and automatically only when the setting
/// is on, never more often than the throttle, and the baseline plan is
/// untouched by any of it.
@MainActor
final class DriveMonitorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let plan = PlanSnapshot(
        provider: .appleMaps,
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
        polyline: Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.02),
        ]),
        distanceM: 2_224, staticDuration: 300, trafficDuration: 300
    )

    private final class Counter {
        var calls = 0
    }

    private func makeMonitor(counter: Counter) -> DriveMonitor {
        DriveMonitor(plan: plan) { [plan] position in
            counter.calls += 1
            return PlanSnapshot(
                provider: .appleMaps, requestedAt: .now,
                polyline: Polyline(coordinates: [position, Coordinate(latitude: 0, longitude: 0.02)]),
                distanceM: 1, staticDuration: 100, trafficDuration: 100,
                alternates: plan.alternates
            )
        }
    }

    /// Points ~222 m north of the plan, one per second from `start`.
    private func offPlanTrack(seconds: Int, from start: Date) -> [TrackPoint] {
        (0..<seconds).map { s in
            TrackPoint(
                coordinate: Coordinate(latitude: 0.002, longitude: 0.01),
                timestamp: start.addingTimeInterval(Double(s)),
                speedMps: 10, horizontalAccuracyM: 5
            )
        }
    }

    func testAutomaticRerouteFiresOnceAfterConfirmationAndRespectsTheThrottle() async {
        let counter = Counter()
        let monitor = makeMonitor(counter: counter)
        var track: [TrackPoint] = []
        for point in offPlanTrack(seconds: 40, from: t0) {
            track.append(point)
            monitor.ingest(track: track, autoReroute: true)
            await monitor.pendingReroute?.value
        }
        XCTAssertEqual(monitor.offPlan, .offPlan(since: t0))
        XCTAssertEqual(counter.calls, 1, "one reroute after the 20 s confirmation, then throttled")
        XCTAssertNotNil(monitor.reroute)
        XCTAssertEqual(monitor.plan.polyline, plan.polyline, "the baseline never changes")

        for point in offPlanTrack(seconds: 45, from: t0.addingTimeInterval(40)) {
            track.append(point)
            monitor.ingest(track: track, autoReroute: true)
            await monitor.pendingReroute?.value
        }
        // 85 s in: the throttle (60 s after the first reroute at t0+20) has passed once, at t0+80.
        XCTAssertEqual(counter.calls, 2)
    }

    func testWithAutomaticRerouteOffOnlyTheButtonReroutes() async {
        let counter = Counter()
        let monitor = makeMonitor(counter: counter)
        var track: [TrackPoint] = []
        for point in offPlanTrack(seconds: 40, from: t0) {
            track.append(point)
            monitor.ingest(track: track, autoReroute: false)
        }
        XCTAssertEqual(monitor.offPlan, .offPlan(since: t0))
        XCTAssertEqual(counter.calls, 0)
        await monitor.requestReroute(from: track.last!.coordinate, at: track.last!.timestamp)
        XCTAssertEqual(counter.calls, 1)
        XCTAssertNotNil(monitor.reroute)
    }

    func testOnPlanDrivingNeverReroutes() async {
        let counter = Counter()
        let monitor = makeMonitor(counter: counter)
        var track: [TrackPoint] = []
        for s in 0..<60 {
            track.append(TrackPoint(
                coordinate: Coordinate(latitude: 0, longitude: Double(s) * 0.0002),
                timestamp: t0.addingTimeInterval(Double(s)), speedMps: 15, horizontalAccuracyM: 5
            ))
            monitor.ingest(track: track, autoReroute: true)
            await monitor.pendingReroute?.value
        }
        XCTAssertEqual(monitor.offPlan, .onPlan)
        XCTAssertEqual(counter.calls, 0)
    }
}
