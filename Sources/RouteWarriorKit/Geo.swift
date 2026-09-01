import Foundation

/// A WGS-84 coordinate. The kit's own type — CLLocation never crosses into
/// the kit (D-009); the app converts at the boundary.
public struct Coordinate: Sendable, Equatable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Spherical-earth geometry. Haversine on the IUGG mean radius is accurate to
/// well under 0.5% at driving scale, which is far inside GPS noise.
public enum Geo {
    public static let earthRadiusMeters = 6_371_008.8

    public static func distanceMeters(from a: Coordinate, to b: Coordinate) -> Double {
        let phi1 = a.latitude * .pi / 180
        let phi2 = b.latitude * .pi / 180
        let dPhi = (b.latitude - a.latitude) * .pi / 180
        let dLambda = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b` in degrees, 0..<360, 0 = north.
    public static func bearingDegrees(from a: Coordinate, to b: Coordinate) -> Double {
        let phi1 = a.latitude * .pi / 180
        let phi2 = b.latitude * .pi / 180
        let dLambda = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
        let theta = atan2(y, x) * 180 / .pi
        return (theta + 360).truncatingRemainder(dividingBy: 360)
    }
}
