import Testing
@testable import RouteWarriorKit

/// Expected values are external: the worked example published in Movable
/// Type's "Calculating distance between two points" reference (Veness), and
/// hand geometry on the equator where 1° of longitude is 2πR/360 meters.
/// Nothing here was produced by the code under test.
struct GeoTests {
    private func approx(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
        abs(a - b) <= tolerance
    }

    // Veness's worked example: 50°03′59″N 5°42′53″W to 58°38′38″N 3°04′12″W.
    private let veness1 = Coordinate(latitude: 50.06639, longitude: -5.71472)
    private let veness2 = Coordinate(latitude: 58.64389, longitude: -3.07000)

    @Test func haversineMatchesPublishedExample() {
        let d = Geo.distanceMeters(from: veness1, to: veness2)
        // Published answer: 968.9 km.
        #expect(approx(d, 968_900, within: 1_000))
    }

    @Test func bearingMatchesPublishedExample() {
        let b = Geo.bearingDegrees(from: veness1, to: veness2)
        // Published answer: 009°07′11″ ≈ 9.1197°.
        #expect(approx(b, 9.1197, within: 0.05))
    }

    @Test func oneDegreeOfLongitudeAtEquator() {
        let d = Geo.distanceMeters(
            from: Coordinate(latitude: 0, longitude: 0),
            to: Coordinate(latitude: 0, longitude: 1)
        )
        // 2π × 6371008.8 m / 360 = 111195.08 m.
        #expect(approx(d, 111_195.08, within: 1))
    }

    @Test func zeroDistanceForIdenticalPoints() {
        let p = Coordinate(latitude: 41.2, longitude: -87.5)
        #expect(Geo.distanceMeters(from: p, to: p) == 0)
    }

    @Test func cardinalBearings() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        #expect(approx(Geo.bearingDegrees(from: origin, to: Coordinate(latitude: 1, longitude: 0)), 0, within: 0.001))
        #expect(approx(Geo.bearingDegrees(from: origin, to: Coordinate(latitude: 0, longitude: 1)), 90, within: 0.001))
        #expect(approx(Geo.bearingDegrees(from: origin, to: Coordinate(latitude: -1, longitude: 0)), 180, within: 0.001))
        #expect(approx(Geo.bearingDegrees(from: origin, to: Coordinate(latitude: 0, longitude: -1)), 270, within: 0.001))
    }
}
