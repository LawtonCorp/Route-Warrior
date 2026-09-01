import Foundation

/// A saved destination or origin: home, work, the school, the coffee shop.
public struct Place: Sendable, Equatable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case home
        case work
        case school
        case custom
    }

    public var id: UUID
    public var name: String
    public var coordinate: Coordinate
    /// Arrival/departure geofence radius in meters.
    public var radiusM: Double
    public var kind: Kind
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        coordinate: Coordinate,
        radiusM: Double = 75,
        kind: Kind = .custom,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.radiusM = radiusM
        self.kind = kind
        self.createdAt = createdAt
    }

    /// Whether a coordinate falls inside this place's geofence.
    public func contains(_ point: Coordinate) -> Bool {
        Geo.distanceMeters(from: coordinate, to: point) <= radiusM
    }
}
