import Foundation
import Testing
@testable import RouteWarriorKit

struct MapProviderTests {
    @Test func rawValuesArePersistedNamesAndMustNotDrift() {
        // These strings live in every stored snapshot and in UserDefaults.
        #expect(PlanSnapshot.Provider.googleRoutes.rawValue == "googleRoutes")
        #expect(PlanSnapshot.Provider.appleMaps.rawValue == "appleMaps")
        #expect(MapProvider.apple.rawValue == "apple")
        #expect(MapProvider.google.rawValue == "google")
    }

    @Test func preferenceAndSnapshotProviderRoundTrip() {
        for provider in MapProvider.allCases {
            #expect(provider.snapshotProvider.mapProvider == provider)
        }
        #expect(MapProvider.default == .apple)
    }

    @Test func tierGatesForTheDriveView() {
        let policy = TierPolicy()
        #expect(policy.driveViewAvailable(for: .pro))
        #expect(!policy.driveViewAvailable(for: .free))
        #expect(policy.rerouteAvailable(for: .pro))
        #expect(!policy.rerouteAvailable(for: .free))
    }

    @Test func routeMatcherLabelsBothPlans() {
        let straight = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.02),
        ])
        let detour = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0.01, longitude: 0.01),
            Coordinate(latitude: 0, longitude: 0.02),
        ])
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0...20).map { i in
            TrackPoint(coordinate: Coordinate(latitude: 0, longitude: Double(i) * 0.001), timestamp: t0.addingTimeInterval(Double(i) * 60), speedMps: 15, horizontalAccuracyM: 5)
        }
        let trip = Trip(startedAt: t0, endedAt: t0.addingTimeInterval(1200), timezoneID: "UTC", points: points)
        let primary = PlanSnapshot(provider: .appleMaps, requestedAt: t0, polyline: straight, distanceM: 2_224, staticDuration: 600, trafficDuration: 600)
        let alt = PlanSnapshot(provider: .googleRoutes, requestedAt: t0, polyline: detour, distanceM: 3_000, staticDuration: 700, trafficDuration: 700)
        let result = RouteMatcher.assign(trip: trip, places: [], variants: [], snapshot: primary, altSnapshot: alt)
        #expect(result.trip.followedPlan == true)
        #expect(result.trip.followedAltPlan == false)
    }
}
