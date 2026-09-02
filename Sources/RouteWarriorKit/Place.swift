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
    /// The street address the user searched for, when the place was made
    /// from a search rather than a dropped pin (D-021). Display only — the
    /// geofence is the coordinate.
    public var address: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        coordinate: Coordinate,
        radiusM: Double = 75,
        kind: Kind = .custom,
        address: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.radiusM = radiusM
        self.kind = kind
        self.address = address
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, coordinate, radiusM, kind, address, createdAt
    }

    /// Places encoded before D-021 carry no address; they decode as "".
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        coordinate = try container.decode(Coordinate.self, forKey: .coordinate)
        radiusM = try container.decode(Double.self, forKey: .radiusM)
        kind = try container.decode(Kind.self, forKey: .kind)
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    /// Whether a coordinate falls inside this place's geofence.
    public func contains(_ point: Coordinate) -> Bool {
        Geo.distanceMeters(from: coordinate, to: point) <= radiusM
    }
}
