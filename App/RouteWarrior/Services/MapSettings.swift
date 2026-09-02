import Foundation
import RouteWarriorKit

/// The user's map-and-routes preference (FR-19) and the drive-view
/// options (automatic reroute, D-022 Q6). UserDefaults-backed: a device
/// choice, not trip data, so it stays out of the CloudKit store.
@MainActor
@Observable
final class MapSettings {
    /// Flips to true when the Google map surface ships (M8). Until then
    /// Google stays the comparison engine and never the map.
    static let googleSurfaceAvailable = false

    private(set) var provider: MapProvider
    private(set) var autoReroute: Bool
    let availableProviders: [MapProvider]

    private let defaults: UserDefaults
    private static let providerKey = "mapProvider"
    private static let autoRerouteKey = "autoReroute"

    init(defaults: UserDefaults = .standard, googleAvailable: Bool) {
        self.defaults = defaults
        availableProviders = googleAvailable ? [.apple, .google] : [.apple]
        let stored = defaults.string(forKey: MapSettings.providerKey)
            .flatMap(MapProvider.init(rawValue:)) ?? MapProvider.default
        provider = availableProviders.contains(stored) ? stored : MapProvider.default
        autoReroute = defaults.bool(forKey: MapSettings.autoRerouteKey)
    }

    func select(_ provider: MapProvider) {
        guard availableProviders.contains(provider) else { return }
        self.provider = provider
        defaults.set(provider.rawValue, forKey: Self.providerKey)
    }

    func setAutoReroute(_ on: Bool) {
        autoReroute = on
        defaults.set(on, forKey: Self.autoRerouteKey)
    }

    /// Google mode needs both a key and the Google map surface.
    static func googleAvailable(hasKey: Bool) -> Bool {
        hasKey && googleSurfaceAvailable
    }
}
