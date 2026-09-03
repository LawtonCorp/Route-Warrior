import Foundation
import RouteWarriorKit

/// Where the maps were last looking. A map that opens on the whole
/// country while it waits for a fix is the first thing a driver sees, and
/// it looks broken; the previous centre is a better guess than the middle
/// of Kansas and costs two doubles (D-036).
enum LastMapCenter {
    private static let latitudeKey = "lastMapCenterLatitude"
    private static let longitudeKey = "lastMapCenterLongitude"

    static func load(from defaults: UserDefaults = .standard) -> Coordinate? {
        guard defaults.object(forKey: latitudeKey) != nil,
              defaults.object(forKey: longitudeKey) != nil
        else { return nil }
        return valid(Coordinate(
            latitude: defaults.double(forKey: latitudeKey),
            longitude: defaults.double(forKey: longitudeKey)
        ))
    }

    static func save(_ coordinate: Coordinate, to defaults: UserDefaults = .standard) {
        guard let coordinate = valid(coordinate) else { return }
        defaults.set(coordinate.latitude, forKey: latitudeKey)
        defaults.set(coordinate.longitude, forKey: longitudeKey)
    }

    /// Null Island is what an unset pair of doubles looks like, and a
    /// coordinate off the globe is corruption. Neither is somewhere the
    /// driver has been.
    static func valid(_ coordinate: Coordinate) -> Coordinate? {
        guard abs(coordinate.latitude) <= 90, abs(coordinate.longitude) <= 180 else { return nil }
        guard abs(coordinate.latitude) > 0.0001 || abs(coordinate.longitude) > 0.0001 else { return nil }
        return coordinate
    }
}
