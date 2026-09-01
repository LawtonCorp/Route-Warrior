import Foundation
import Testing
@testable import RouteWarriorKit

/// The fixture is hand-written to Google's published computeRoutes v2
/// response schema (field names and the "<seconds>s" duration encoding are
/// Google's documented contract), and the embedded polyline is Google's own
/// documentation example — external expected values, not parser output.
struct GoogleRoutesTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let docPolyline = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
    private let docCoordinates = [
        Coordinate(latitude: 38.5, longitude: -120.2),
        Coordinate(latitude: 40.7, longitude: -120.95),
        Coordinate(latitude: 43.252, longitude: -126.453),
    ]

    private var fixture: Data {
        Data("""
        {
          "routes": [
            {
              "distanceMeters": 9214,
              "duration": "723s",
              "staticDuration": "674s",
              "polyline": { "encodedPolyline": "\(docPolyline)" }
            },
            {
              "distanceMeters": 9950,
              "duration": "800.5s",
              "polyline": { "encodedPolyline": "\(docPolyline)" }
            }
          ]
        }
        """.utf8)
    }

    @Test func parsesPrimaryRouteAndAlternate() throws {
        let destination = UUID()
        let snapshot = try GoogleRoutes.snapshot(
            fromResponseData: fixture,
            requestedAt: t0,
            destinationPlaceID: destination
        )
        #expect(snapshot.requestedAt == t0)
        #expect(snapshot.destinationPlaceID == destination)
        #expect(snapshot.distanceM == 9214)
        #expect(snapshot.trafficDuration == 723)
        #expect(snapshot.staticDuration == 674)
        #expect(snapshot.polyline.coordinates == docCoordinates)
        #expect(abs(snapshot.trafficFactor - 723.0 / 674.0) < 0.0001)

        #expect(snapshot.alternates.count == 1)
        // No staticDuration on the alternate: falls back to traffic.
        #expect(snapshot.alternates[0].trafficDuration == 800.5)
        #expect(snapshot.alternates[0].staticDuration == 800.5)
    }

    @Test func rejectsResponsesWithoutRoutes() {
        #expect(throws: GoogleRoutes.ParseError.noRoutes) {
            try GoogleRoutes.snapshot(fromResponseData: Data("{}".utf8), requestedAt: t0)
        }
        #expect(throws: GoogleRoutes.ParseError.noRoutes) {
            try GoogleRoutes.snapshot(fromResponseData: Data(#"{"routes":[]}"#.utf8), requestedAt: t0)
        }
    }

    @Test func rejectsPrimaryWithoutPolyline() {
        let data = Data(#"{"routes":[{"duration":"600s"}]}"#.utf8)
        #expect(throws: GoogleRoutes.ParseError.missingPolyline) {
            try GoogleRoutes.snapshot(fromResponseData: data, requestedAt: t0)
        }
    }

    @Test func rejectsMalformedDurations() {
        let data = Data("""
        {"routes":[{"duration":"xyz","polyline":{"encodedPolyline":"\(docPolyline)"}}]}
        """.utf8)
        #expect(throws: GoogleRoutes.ParseError.malformedDuration("xyz")) {
            try GoogleRoutes.snapshot(fromResponseData: data, requestedAt: t0)
        }
    }

    @Test func durationStringParsing() throws {
        #expect(try GoogleRoutes.seconds("723s") == 723)
        #expect(try GoogleRoutes.seconds("723.5s") == 723.5)
        #expect(throws: GoogleRoutes.ParseError.self) { try GoogleRoutes.seconds("723") }
        #expect(throws: GoogleRoutes.ParseError.self) { try GoogleRoutes.seconds("s") }
    }
}
