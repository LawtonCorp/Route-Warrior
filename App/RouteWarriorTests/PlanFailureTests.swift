import Foundation
import RouteWarriorKit
import XCTest

@testable import RouteWarrior

/// Google's plan was drawn with a 12-metre dash, which is sub-pixel on any
/// camera that fits a whole drive — the line was there and looked like an
/// empty map. And when a provider returned nothing at all, the `try?`
/// swallowed the reason. Both are covered here (D-031).
final class PlanFailureTests: XCTestCase {
    // MARK: The dash that reads as a line

    func testShortDrivesGetTheFloorNotAHairline() {
        let dash = GoogleMapSurface.dashMeters(for: 300)
        XCTAssertEqual(dash.on + dash.off, 40, accuracy: 0.001)
        XCTAssertGreaterThan(dash.on, dash.off, "the mark must be longer than the gap")
    }

    func testTheDashGrowsWithTheDrive() {
        let short = GoogleMapSurface.dashMeters(for: 5_000)
        let long = GoogleMapSurface.dashMeters(for: 60_000)
        XCTAssertGreaterThan(long.on, short.on)
        // Roughly forty dashes either way, so the pattern stays legible
        // whether the drive is a few miles or an afternoon.
        XCTAssertEqual(5_000 / (short.on + short.off), 40, accuracy: 0.5)
        XCTAssertEqual(60_000 / (long.on + long.off), 40, accuracy: 0.5)
    }

    func testEveryDashIsVisibleAtAnyLength() {
        for length in [0.0, 1, 100, 2_000, 250_000] {
            let dash = GoogleMapSurface.dashMeters(for: length)
            XCTAssertGreaterThan(dash.on, 0, "length \(length) produced an invisible dash")
            XCTAssertGreaterThan(dash.off, 0, "length \(length) produced no gap")
        }
    }

    // MARK: Why a plan is missing

    func testAnHTTPStatusSurvivesIntoTheRecorderLog() {
        // 403 is the one that matters: a key restricted to iOS apps is
        // refused by the Routes web service, which is exactly how the
        // route goes missing while the map SDK keeps working.
        XCTAssertEqual(RecordingPipeline.describe(RoutesClientError.badResponse(403)), "HTTP 403")
        XCTAssertEqual(RecordingPipeline.describe(RoutesClientError.badResponse(429)), "HTTP 429")
    }

    func testTheOtherRefusalsReadPlainly() {
        XCTAssertEqual(RecordingPipeline.describe(RoutesClientError.noAPIKey), "no API key")
        XCTAssertEqual(
            RecordingPipeline.describe(RoutesClientError.noRoutes),
            "no route between those points"
        )
    }

    func testAnUnknownFailureStillSaysSomething() {
        let network = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertFalse(RecordingPipeline.describe(network).isEmpty)
    }
}
