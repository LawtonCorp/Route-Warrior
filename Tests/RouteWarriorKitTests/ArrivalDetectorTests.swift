import Foundation
import XCTest

@testable import RouteWarriorKit

/// Recording stops itself on arrival (D-038). The failure that would
/// matter is a false arrival — a trip cut short while driving past — so
/// most of these are about *not* arriving.
final class ArrivalDetectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let school = Coordinate(latitude: 39.70, longitude: -104.90)

    /// A point `metres` due east of the school, at `speed`, `seconds` in.
    private func point(metres: Double, speed: Double, seconds: TimeInterval) -> TrackPoint {
        // ~85 km per degree of longitude at this latitude.
        let degreesPerMetre = 1 / (111_320 * cos(school.latitude * .pi / 180))
        return TrackPoint(
            coordinate: Coordinate(latitude: school.latitude, longitude: school.longitude + metres * degreesPerMetre),
            timestamp: t0.addingTimeInterval(seconds),
            speedMps: speed,
            courseDegrees: 90,
            horizontalAccuracyM: 10
        )
    }

    func testParkingAtTheDestinationIsAnArrival() {
        var detector = ArrivalDetector()
        detector.ingest(point(metres: 40, speed: 1, seconds: 0), destination: school)
        XCTAssertEqual(detector.ingest(point(metres: 30, speed: 0, seconds: 10), destination: school), .settling(since: t0))
        XCTAssertEqual(detector.ingest(point(metres: 30, speed: 0, seconds: 20), destination: school), .arrived)
    }

    func testDrivingPastAtRoadSpeedIsNotAnArrival() {
        var detector = ArrivalDetector()
        for seconds in stride(from: 0.0, through: 60, by: 5) {
            // Through the radius and out the other side at 15 m/s.
            let metres = -300 + seconds * 15
            XCTAssertNotEqual(
                detector.ingest(point(metres: metres, speed: 15, seconds: seconds), destination: school),
                .arrived, "arrived at t=\(seconds)"
            )
        }
    }

    /// Stopped at a light beside the destination, then away again.
    func testABriefStopNearbyDoesNotCount() {
        var detector = ArrivalDetector()
        detector.ingest(point(metres: 100, speed: 0, seconds: 0), destination: school)
        detector.ingest(point(metres: 100, speed: 0, seconds: 12), destination: school)
        let state = detector.ingest(point(metres: 400, speed: 14, seconds: 20), destination: school)
        XCTAssertEqual(state, .travelling)
    }

    func testLeavingTheRadiusRestartsTheClock() {
        var detector = ArrivalDetector()
        detector.ingest(point(metres: 50, speed: 0, seconds: 0), destination: school)
        detector.ingest(point(metres: 500, speed: 10, seconds: 15), destination: school)
        // Back inside: the earlier 15 seconds do not carry over.
        XCTAssertEqual(detector.ingest(point(metres: 50, speed: 0, seconds: 30), destination: school),
                       .settling(since: t0.addingTimeInterval(30)))
        XCTAssertNotEqual(detector.ingest(point(metres: 50, speed: 0, seconds: 40), destination: school), .arrived)
        XCTAssertEqual(detector.ingest(point(metres: 50, speed: 0, seconds: 50), destination: school), .arrived)
    }

    func testAnUnknownSpeedAtTheKerbIsSlowNotFast() {
        var detector = ArrivalDetector()
        detector.ingest(point(metres: 20, speed: -1, seconds: 0), destination: school)
        XCTAssertEqual(detector.ingest(point(metres: 20, speed: -1, seconds: 25), destination: school), .arrived)
    }

    func testOnceArrivedItStaysArrivedUntilReset() {
        var detector = ArrivalDetector()
        detector.ingest(point(metres: 20, speed: 0, seconds: 0), destination: school)
        detector.ingest(point(metres: 20, speed: 0, seconds: 25), destination: school)
        XCTAssertEqual(detector.ingest(point(metres: 900, speed: 20, seconds: 30), destination: school), .arrived)
        detector.reset()
        XCTAssertEqual(detector.state, .travelling)
    }

    func testJustOutsideTheRadiusIsStillTravelling() {
        var detector = ArrivalDetector()
        let config = ArrivalDetector.Config()
        detector.ingest(point(metres: config.radiusM + 5, speed: 0, seconds: 0), destination: school)
        XCTAssertEqual(detector.ingest(point(metres: config.radiusM + 5, speed: 0, seconds: 30), destination: school), .travelling)
    }
}
