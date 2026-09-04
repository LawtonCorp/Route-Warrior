import Foundation
import Testing
@testable import RouteWarriorKit

struct PlaceTests {
    private let home = Place(
        name: "Home",
        coordinate: Coordinate(latitude: 41.8781, longitude: -87.6298),
        address: "233 S Wacker Dr, Chicago, IL"
    )

    @Test func addressRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(home)
        let decoded = try JSONDecoder().decode(Place.self, from: data)
        #expect(decoded == home)
        #expect(decoded.address == "233 S Wacker Dr, Chicago, IL")
    }

    @Test func placesSavedBeforeAddressesExistedStillDecode() throws {
        // D-021: a record written by v1 has no "address" key at all.
        let data = try JSONEncoder().encode(home)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "address")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Place.self, from: legacy)
        #expect(decoded.address == "")
        #expect(decoded.name == "Home")
        #expect(decoded.coordinate == home.coordinate)
    }

    @Test func addressIsDisplayOnlyAndNeverMovesTheGeofence() {
        var moved = home
        moved.address = "somewhere else entirely"
        #expect(moved.contains(home.coordinate))
        #expect(!moved.contains(Coordinate(latitude: 0, longitude: 0)))
    }

    /// D-039: `church` became `faith`. A place saved under the old name
    /// keeps its kind; an unknown name still falls back to custom.
    @Test func aStoredChurchIsNowFaith() {
        #expect(Place.Kind(stored: "church") == .faith)
        #expect(Place.Kind(stored: "faith") == .faith)
        #expect(Place.Kind(stored: "home") == .home)
        #expect(Place.Kind(stored: "cathedral") == .custom)
        #expect(Place.Kind(rawValue: "church") == nil, "the old raw value must not survive as a case")
    }
}
