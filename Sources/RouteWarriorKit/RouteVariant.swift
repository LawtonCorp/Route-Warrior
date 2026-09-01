import Foundation

/// Signals and stop signs known to lie along a variant, from OpenStreetMap.
/// Coverage varies by area — the confidence label is part of the honest
/// accuracy story (D-005).
public struct IntersectionInventory: Sendable, Equatable, Codable {
    public enum CoverageConfidence: String, Sendable, Codable {
        case high
        case medium
        case low
    }

    public var signalCount: Int
    public var stopSignCount: Int
    public var coverageConfidence: CoverageConfidence
    public var fetchedAt: Date

    public init(
        signalCount: Int,
        stopSignCount: Int,
        coverageConfidence: CoverageConfidence,
        fetchedAt: Date
    ) {
        self.signalCount = signalCount
        self.stopSignCount = stopSignCount
        self.coverageConfidence = coverageConfidence
        self.fetchedAt = fetchedAt
    }
}

/// A distinct way of driving one origin→destination pair. Trips cluster into
/// variants by shape similarity; stats and the ghost race run per variant.
public struct RouteVariant: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var originPlaceID: UUID
    public var destinationPlaceID: UUID
    /// The line the variant is recognized and raced against — the shape of
    /// the trip that founded the variant.
    public var representativePolyline: Polyline
    /// Auto-generated label, e.g. "via Maple Ave"; user-renamable.
    public var autoName: String
    public var tripCount: Int
    public var intersections: IntersectionInventory?

    public init(
        id: UUID = UUID(),
        originPlaceID: UUID,
        destinationPlaceID: UUID,
        representativePolyline: Polyline,
        autoName: String = "",
        tripCount: Int = 0,
        intersections: IntersectionInventory? = nil
    ) {
        self.id = id
        self.originPlaceID = originPlaceID
        self.destinationPlaceID = destinationPlaceID
        self.representativePolyline = representativePolyline
        self.autoName = autoName
        self.tripCount = tripCount
        self.intersections = intersections
    }
}
