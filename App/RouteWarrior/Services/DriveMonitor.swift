import Foundation
import RouteWarriorKit

/// The drive view's brain (FR-21/FR-22, D-022 Q6): feeds the live track
/// to the kit's off-plan detector and applies the reroute policy —
/// on tap always, automatically when the setting is on and the throttle
/// allows. The plan it was given is the baseline and never changes; a
/// reroute is a second line the view may draw.
@MainActor
@Observable
final class DriveMonitor {
    /// Automatic reroutes are at least this far apart.
    static let autoRerouteInterval: TimeInterval = 60

    let plan: PlanSnapshot
    private(set) var offPlan: OffPlanDetector.State = .onPlan
    private(set) var reroute: PlanSnapshot?
    private(set) var rerouting = false
    private(set) var lastRerouteAt: Date?
    /// The in-flight automatic reroute; tests await it.
    private(set) var pendingReroute: Task<Void, Never>?

    private var detector: OffPlanDetector
    private let rerouter: @MainActor (Coordinate) async -> PlanSnapshot?

    init(plan: PlanSnapshot, rerouter: @escaping @MainActor (Coordinate) async -> PlanSnapshot?) {
        self.plan = plan
        self.detector = OffPlanDetector(plan: plan.polyline)
        self.rerouter = rerouter
    }

    /// Called with the live track after every sample.
    func ingest(track: [TrackPoint], autoReroute: Bool) {
        guard let last = track.last else { return }
        offPlan = detector.ingest(position: last.coordinate, at: last.timestamp)
        if case .offPlan = offPlan, autoReroute, canReroute(at: last.timestamp) {
            let position = last.coordinate
            let time = last.timestamp
            pendingReroute = Task { [weak self] in
                await self?.requestReroute(from: position, at: time)
            }
        }
    }

    /// The Reroute button, or the automatic policy. One at a time.
    func requestReroute(from position: Coordinate, at time: Date = .now) async {
        guard !rerouting else { return }
        rerouting = true
        lastRerouteAt = time
        defer { rerouting = false }
        reroute = await rerouter(position)
    }

    private func canReroute(at time: Date) -> Bool {
        guard !rerouting else { return false }
        guard let lastRerouteAt else { return true }
        return time.timeIntervalSince(lastRerouteAt) >= Self.autoRerouteInterval
    }
}
