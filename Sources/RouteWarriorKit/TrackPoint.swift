import Foundation

/// One GPS sample of a drive, in the kit's own terms (see D-009: CLLocation
/// never enters the kit; the app converts at the boundary).
public struct TrackPoint: Sendable, Equatable, Codable {
    public var coordinate: Coordinate
    public var timestamp: Date
    /// Meters per second; negative means unknown (mirrors Core Location).
    public var speedMps: Double
    /// Degrees clockwise from north, 0..<360; negative means unknown.
    public var courseDegrees: Double
    /// Radius of the 68%-confidence circle in meters; negative means invalid.
    public var horizontalAccuracyM: Double

    public init(
        coordinate: Coordinate,
        timestamp: Date,
        speedMps: Double = -1,
        courseDegrees: Double = -1,
        horizontalAccuracyM: Double = -1
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.speedMps = speedMps
        self.courseDegrees = courseDegrees
        self.horizontalAccuracyM = horizontalAccuracyM
    }
}
