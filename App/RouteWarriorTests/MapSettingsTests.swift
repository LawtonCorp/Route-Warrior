import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// FR-19 wiring: the preference persists, never names a provider the
/// build cannot show, and Google mode waits for the Google map (M8).
@MainActor
final class MapSettingsTests: XCTestCase {
    private func freshDefaults() throws -> (UserDefaults, () -> Void) {
        let name = "MapSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    func testWithoutTheGoogleSurfaceOnlyAppleIsOffered() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        defaults.set("google", forKey: "mapProvider") // a stale choice
        let settings = MapSettings(defaults: defaults, googleAvailable: false)
        XCTAssertEqual(settings.availableProviders, [.apple])
        XCTAssertEqual(settings.provider, .apple)
        settings.select(.google)
        XCTAssertEqual(settings.provider, .apple)
    }

    func testSelectionAndAutoReroutePersist() throws {
        let (defaults, cleanup) = try freshDefaults()
        defer { cleanup() }
        let settings = MapSettings(defaults: defaults, googleAvailable: true)
        XCTAssertEqual(settings.provider, .apple, "Apple is the default (D-022 Q4)")
        settings.select(.google)
        settings.setAutoReroute(true)
        let again = MapSettings(defaults: defaults, googleAvailable: true)
        XCTAssertEqual(again.provider, .google)
        XCTAssertTrue(again.autoReroute)
    }

    func testGoogleModeNeedsAKeyAndTheGoogleMap() {
        XCTAssertFalse(MapSettings.googleAvailable(hasKey: false))
        // Until M8 ships the Google surface, a key alone is not enough.
        XCTAssertEqual(MapSettings.googleAvailable(hasKey: true), MapSettings.googleSurfaceAvailable)
    }
}
