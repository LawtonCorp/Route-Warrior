import Foundation

/// Where the drive stands right now: against the plan the driver left
/// with, and against their own history when a ghost race is running.
/// Pure, so the phone's banner and the car screen render the same
/// numbers instead of each computing their own (D-035).
public struct DriveScoreboard: Sendable, Equatable {
    /// Positive = ahead of the provider's pace by this many seconds. Nil
    /// when there is no plan, or the driver cannot be placed on it.
    public var aheadOfPlanSeconds: Double?
    /// Positive = ahead of your own reference, when a ghost race is on.
    public var aheadOfGhostSeconds: Double?
    public var elapsed: TimeInterval
    /// How far along the plan, 0...1. Zero when there is no plan.
    public var progress: Double
    public var offPlan: Bool

    public init(
        aheadOfPlanSeconds: Double? = nil,
        aheadOfGhostSeconds: Double? = nil,
        elapsed: TimeInterval = 0,
        progress: Double = 0,
        offPlan: Bool = false
    ) {
        self.aheadOfPlanSeconds = aheadOfPlanSeconds
        self.aheadOfGhostSeconds = aheadOfGhostSeconds
        self.elapsed = elapsed
        self.progress = progress
        self.offPlan = offPlan
    }

    /// True when there is something to say about the plan at all.
    public var racesThePlan: Bool { aheadOfPlanSeconds != nil }
}

public extension DriveScoreboard {
    /// The pace that arrives exactly at the provider's ETA: a straight
    /// line from the start of the route to its end. Deliberately crude —
    /// a provider gives one number for the whole trip, not a curve — and
    /// enough to answer "am I beating it right now?".
    static func planPace(for plan: PlanSnapshot) -> GhostRace.ReferenceProfile? {
        let length = plan.polyline.lengthMeters
        guard length > 0, plan.trafficDuration > 0 else { return nil }
        return GhostRace.ReferenceProfile(samples: [
            GhostRace.ReferenceProfile.Sample(alongMeters: 0, elapsed: 0),
            GhostRace.ReferenceProfile.Sample(alongMeters: length, elapsed: plan.trafficDuration),
        ])
    }

    static func board(
        elapsed: TimeInterval,
        position: Coordinate,
        plan: PlanSnapshot?,
        ghost: GhostRace.Status? = nil,
        offPlan: Bool = false
    ) -> DriveScoreboard {
        var aheadOfPlan: Double?
        var progress = 0.0
        if let plan,
           let pace = planPace(for: plan),
           let standing = GhostRace.status(
               myElapsed: elapsed, position: position, along: plan.polyline, reference: pace
           ) {
            aheadOfPlan = standing.aheadSeconds
            if standing.routeLengthM > 0 {
                progress = min(1, max(0, standing.distanceAlongM / standing.routeLengthM))
            }
        }
        return DriveScoreboard(
            aheadOfPlanSeconds: aheadOfPlan,
            aheadOfGhostSeconds: ghost?.aheadSeconds,
            elapsed: elapsed,
            progress: progress,
            offPlan: offPlan
        )
    }
}
