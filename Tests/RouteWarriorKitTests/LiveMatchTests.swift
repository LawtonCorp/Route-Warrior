import Foundation
import Testing
@testable import RouteWarriorKit

/// Partial-drive recognition against the same hand-built equator routes as
/// RouteMatcherTests: Route A straight, Route B arcing ~1.1 km north.
struct LiveMatchTests {
    private let home = UUID()
    private let school = UUID()

    private func variant(via corners: [Coordinate], name: String) -> RouteVariant {
        RouteVariant(
            originPlaceID: home,
            destinationPlaceID: school,
            representativePolyline: Polyline(coordinates: corners).resampled(to: 64),
            autoName: name
        )
    }

    private var variantA: RouteVariant {
        variant(via: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 0.09),
        ], name: "Route A")
    }

    private var variantB: RouteVariant {
        variant(via: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0.01, longitude: 0.01),
            Coordinate(latitude: 0.01, longitude: 0.08),
            Coordinate(latitude: 0, longitude: 0.09),
        ], name: "Route B")
    }

    @Test func partialDriveMatchesItsVariant() {
        // Bind once: the computed properties mint a fresh id per access.
        let a = variantA
        let b = variantB
        // First 3 km of Route A (the full route is ~10 km).
        let partial = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 0.027),
        ])
        let match = RouteMatcher.liveMatch(partialTrack: partial, candidates: [a, b])
        #expect(match?.variantID == a.id)
        #expect((match?.deviationM ?? .infinity) < 50)
    }

    @Test func tooShortATrackRefusesToCommit() {
        let stub = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 0.005), // ~556 m < 800 m floor
        ])
        #expect(RouteMatcher.liveMatch(partialTrack: stub, candidates: [variantA]) == nil)
    }

    @Test func offRouteDriveMatchesNothing() {
        // Heading due south, away from both variants.
        let partial = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: -0.027, longitude: 0),
        ])
        #expect(RouteMatcher.liveMatch(partialTrack: partial, candidates: [variantA, variantB]) == nil)
    }

    @Test func oneWayDeviationIgnoresTheUndrivenRemainder() {
        let full = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 0.09),
        ])
        let partial = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 0.03),
        ])
        // One-way: the partial hugs the full line exactly.
        let oneWay = partial.meanDeviation(to: full)
        #expect(oneWay != nil && oneWay! < 1)
        // Symmetric: the undriven 6 km dominates — this is why liveMatch
        // must not use it.
        let symmetric = partial.symmetricMeanDeviation(to: full)
        #expect(symmetric != nil && symmetric! > 500)
    }
}
