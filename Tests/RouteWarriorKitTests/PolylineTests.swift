import Testing
@testable import RouteWarriorKit

/// The encoding fixture is Google's own documentation example for the
/// encoded-polyline format — an expected value the implementation cannot
/// have produced. Geometry fixtures sit on the equator, where arc lengths
/// and offsets reduce to hand-computable degree-to-meter products.
struct PolylineTests {
    private func approx(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
        abs(a - b) <= tolerance
    }

    private let metersPerDegree = 111_195.08

    // Google's documented example: (38.5,-120.2) (40.7,-120.95) (43.252,-126.453).
    private let googleDocEncoded = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
    private let googleDocPoints = [
        Coordinate(latitude: 38.5, longitude: -120.2),
        Coordinate(latitude: 40.7, longitude: -120.95),
        Coordinate(latitude: 43.252, longitude: -126.453),
    ]

    @Test func decodesGoogleDocumentationExample() {
        let line = Polyline.decode(googleDocEncoded)
        #expect(line?.coordinates == googleDocPoints)
    }

    @Test func encodesGoogleDocumentationExample() {
        #expect(Polyline(coordinates: googleDocPoints).encoded() == googleDocEncoded)
    }

    @Test func encodeDecodeRoundTripsE5Coordinates() {
        let original = Polyline(coordinates: [
            Coordinate(latitude: 37.77493, longitude: -122.41942),
            Coordinate(latitude: 37.80837, longitude: -122.36512),
            Coordinate(latitude: -33.86882, longitude: 151.20930),
        ])
        #expect(Polyline.decode(original.encoded()) == original)
    }

    @Test func decodeRejectsMalformedInput() {
        #expect(Polyline.decode("_p~iF") == nil) // dangling latitude
        #expect(Polyline.decode("_p~iF~ps|U_ulL") == nil) // truncated pair
        #expect(Polyline.decode(" ") == nil) // byte below the format's floor
        #expect(Polyline.decode("") == Polyline(coordinates: []))
    }

    @Test func lengthAlongEquator() {
        let line = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 1),
            Coordinate(latitude: 0, longitude: 3),
        ])
        #expect(approx(line.lengthMeters, 3 * metersPerDegree, within: 3))
        #expect(Polyline(coordinates: []).lengthMeters == 0)
        #expect(Polyline(coordinates: [Coordinate(latitude: 5, longitude: 5)]).lengthMeters == 0)
    }

    @Test func cumulativeDistancesStartAtZeroAndEndAtLength() {
        let line = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 1),
            Coordinate(latitude: 0, longitude: 3),
        ])
        let cumulative = line.cumulativeDistances
        #expect(cumulative.count == 3)
        #expect(cumulative[0] == 0)
        #expect(approx(cumulative[2], line.lengthMeters, within: 0.001))
        #expect(Polyline(coordinates: []).cumulativeDistances.isEmpty)
    }

    @Test func resamplesEvenlyByArcLength() {
        let line = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 1),
            Coordinate(latitude: 0, longitude: 3),
        ])
        let resampled = line.resampled(to: 4)
        #expect(resampled.coordinates.count == 4)
        for (i, expectedLon) in [0.0, 1.0, 2.0, 3.0].enumerated() {
            #expect(approx(resampled.coordinates[i].longitude, expectedLon, within: 0.0001))
            #expect(approx(resampled.coordinates[i].latitude, 0, within: 0.0001))
        }
    }

    @Test func resampleDegenerateInputs() {
        let single = Polyline(coordinates: [Coordinate(latitude: 1, longitude: 1)])
        #expect(single.resampled(to: 5) == single)

        let line = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 1),
        ])
        #expect(line.resampled(to: 1) == line)

        let zeroLength = Polyline(coordinates: [
            Coordinate(latitude: 2, longitude: 2),
            Coordinate(latitude: 2, longitude: 2),
        ])
        let resampled = zeroLength.resampled(to: 3)
        #expect(resampled.coordinates == Array(repeating: Coordinate(latitude: 2, longitude: 2), count: 3))
    }

    @Test func nearestPointProjectsOntoSegment() {
        let line = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 1),
        ])
        let hit = line.nearestPoint(to: Coordinate(latitude: 0.1, longitude: 0.5))
        #expect(hit != nil)
        // 0.1° of latitude off the line; halfway along ~111.2 km of route.
        #expect(approx(hit!.distanceMeters, 0.1 * metersPerDegree, within: 5))
        #expect(approx(hit!.alongMeters, 0.5 * metersPerDegree, within: 25))
    }

    @Test func nearestPointClampsToEndpoints() {
        let line = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 1),
        ])
        let before = line.nearestPoint(to: Coordinate(latitude: 0, longitude: -0.5))
        #expect(approx(before!.alongMeters, 0, within: 0.001))
        let after = line.nearestPoint(to: Coordinate(latitude: 0, longitude: 1.5))
        #expect(approx(after!.alongMeters, line.lengthMeters, within: 0.001))
        #expect(Polyline(coordinates: [Coordinate(latitude: 0, longitude: 0)])
            .nearestPoint(to: Coordinate(latitude: 0, longitude: 0)) == nil)
    }

    @Test func identicalPolylinesHaveNearZeroDeviation() {
        let line = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0.2, longitude: 0.7),
            Coordinate(latitude: 0.1, longitude: 1.4),
        ])
        let deviation = line.symmetricMeanDeviation(to: line)
        #expect(deviation != nil && deviation! < 1)
    }

    @Test func parallelOffsetLinesMeasureTheirSeparation() {
        let a = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 1),
        ])
        let b = Polyline(coordinates: [
            Coordinate(latitude: 0.001, longitude: 0),
            Coordinate(latitude: 0.001, longitude: 1),
        ])
        let deviation = a.symmetricMeanDeviation(to: b)
        // 0.001° of latitude ≈ 111.2 m everywhere along the pair.
        #expect(deviation != nil)
        #expect(approx(deviation!, 0.001 * metersPerDegree, within: 2))
    }

    @Test func deviationRequiresTwoRealLines() {
        let point = Polyline(coordinates: [Coordinate(latitude: 0, longitude: 0)])
        let line = Polyline(coordinates: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 1),
        ])
        #expect(point.symmetricMeanDeviation(to: line) == nil)
        #expect(line.symmetricMeanDeviation(to: point) == nil)
    }
}
