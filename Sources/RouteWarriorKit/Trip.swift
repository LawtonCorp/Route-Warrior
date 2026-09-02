import Foundation

/// A detected halt during a drive, classified as well as the evidence allows.
public struct StopEvent: Sendable, Equatable, Codable {
    public enum Cause: String, Sendable, Codable {
        case stopSign
        case signal
        case trafficQueue
        case unknown
    }

    public var coordinate: Coordinate
    public var startedAt: Date
    public var duration: TimeInterval
    public var cause: Cause
    /// OSM node id when the halt matched a mapped stop sign or signal.
    public var matchedOSMNode: Int64?

    public init(
        coordinate: Coordinate,
        startedAt: Date,
        duration: TimeInterval,
        cause: Cause = .unknown,
        matchedOSMNode: Int64? = nil
    ) {
        self.coordinate = coordinate
        self.startedAt = startedAt
        self.duration = duration
        self.cause = cause
        self.matchedOSMNode = matchedOSMNode
    }
}

/// One recorded drive. Self-contained with a stable id (NFR-2) so future
/// opt-in sharing needs no migration.
public struct Trip: Sendable, Equatable, Codable, Identifiable {
    public enum Source: String, Sendable, Codable {
        case auto
        case manual
    }

    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    /// IANA timezone identifier where the trip happened; day/time analytics
    /// bucket in this zone, not the device's current one.
    public var timezoneID: String
    public var points: [TrackPoint]
    public var originPlaceID: UUID?
    public var destinationPlaceID: UUID?
    public var variantID: UUID?
    public var distanceM: Double
    public var movingTime: TimeInterval
    public var idleTime: TimeInterval
    public var stopEvents: [StopEvent]
    /// The plan the driver saw (the preferred provider's) at departure.
    public var snapshotID: UUID?
    /// True when the driven shape matched the snapshot's recommended route;
    /// nil when there was no snapshot to compare against.
    public var followedPlan: Bool?
    /// The other provider's plan for the same departure ("beat both",
    /// D-022), with its own followed label. Nil on v1 trips.
    public var altSnapshotID: UUID?
    public var followedAltPlan: Bool?
    public var source: Source
    public var excludedFromStats: Bool

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        timezoneID: String,
        points: [TrackPoint],
        originPlaceID: UUID? = nil,
        destinationPlaceID: UUID? = nil,
        variantID: UUID? = nil,
        distanceM: Double = 0,
        movingTime: TimeInterval = 0,
        idleTime: TimeInterval = 0,
        stopEvents: [StopEvent] = [],
        snapshotID: UUID? = nil,
        followedPlan: Bool? = nil,
        altSnapshotID: UUID? = nil,
        followedAltPlan: Bool? = nil,
        source: Source = .auto,
        excludedFromStats: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timezoneID = timezoneID
        self.points = points
        self.originPlaceID = originPlaceID
        self.destinationPlaceID = destinationPlaceID
        self.variantID = variantID
        self.distanceM = distanceM
        self.movingTime = movingTime
        self.idleTime = idleTime
        self.stopEvents = stopEvents
        self.snapshotID = snapshotID
        self.followedPlan = followedPlan
        self.altSnapshotID = altSnapshotID
        self.followedAltPlan = followedAltPlan
        self.source = source
        self.excludedFromStats = excludedFromStats
    }
}
