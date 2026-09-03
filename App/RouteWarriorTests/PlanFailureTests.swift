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

    /// A casing that is not wider than its line is not a casing — the
    /// plan would go back to disappearing into Google's traffic ribbons.
    func testThePlanRidesOnACasingWiderThanItself() {
        XCTAssertGreaterThan(GoogleMapSurface.planCasingWidth, GoogleMapSurface.planLineWidth)
        XCTAssertGreaterThan(AppleMapSurface.planCasingWidth, AppleMapSurface.planLineWidth)
    }

    /// Both maps draw the same drive; the same drive should not look
    /// heavier on one of them.
    func testBothSurfacesDrawTheSameWeights() {
        XCTAssertEqual(GoogleMapSurface.planLineWidth, AppleMapSurface.planLineWidth)
        XCTAssertEqual(GoogleMapSurface.planCasingWidth, AppleMapSurface.planCasingWidth)
        XCTAssertEqual(GoogleMapSurface.trailWidth, AppleMapSurface.trailWidth)
    }

    /// The trail is what the driver actually did; it must not be thinner
    /// than the plan it is being judged against.
    func testTheTrailIsNeverThinnerThanThePlan() {
        XCTAssertGreaterThanOrEqual(GoogleMapSurface.trailWidth, GoogleMapSurface.planLineWidth)
    }

    // MARK: Why a plan is missing

    func testAnHTTPStatusSurvivesIntoTheRecorderLog() {
        // 403 is the one that matters: a key that renders Google's map can
        // still be refused a route, and the status alone said nothing
        // about which restriction did it.
        XCTAssertEqual(
            RecordingPipeline.describe(RoutesClientError.badResponse(403, detail: "")),
            "HTTP 403"
        )
        XCTAssertEqual(
            RecordingPipeline.describe(RoutesClientError.badResponse(429, detail: "")),
            "HTTP 429"
        )
    }

    func testGooglesOwnReasonReachesTheLog() {
        let described = RecordingPipeline.describe(RoutesClientError.badResponse(
            403, detail: "Requests to this API routes.googleapis.com are blocked."
        ))
        XCTAssertTrue(described.hasPrefix("HTTP 403 — "))
        XCTAssertTrue(described.contains("blocked"))
    }

    // MARK: Reading Google's refusal

    func testTheReasonIsLiftedOutOfGooglesErrorBody() {
        let body = Data(#"{"error":{"code":403,"message":"Method blocked.","status":"PERMISSION_DENIED"}}"#.utf8)
        XCTAssertEqual(GoogleRoutesClient.reason(in: body), "Method blocked.")
    }

    func testAnUnreadableBodyYieldsNoReasonRatherThanNoise() {
        XCTAssertEqual(GoogleRoutesClient.reason(in: Data("<html>502</html>".utf8)), "")
        XCTAssertEqual(GoogleRoutesClient.reason(in: Data()), "")
    }

    /// The log is persisted and gets screenshotted; a key must never
    /// survive into it, whatever Google echoes back.
    func testAnyKeyInTheMessageIsRedacted() {
        let key = "AIza" + String(repeating: "x", count: 35)
        let body = Data(#"{"error":{"message":"API key \#(key) is not valid"}}"#.utf8)
        let reason = GoogleRoutesClient.reason(in: body)
        XCTAssertFalse(reason.contains(key))
        XCTAssertFalse(reason.contains("AIza"))
        XCTAssertTrue(reason.contains("«key»"))
    }

    func testRedactionLeavesOrdinaryTextAlone() {
        let plain = "Requests to this API are blocked."
        XCTAssertEqual(GoogleRoutesClient.redactingKeys(in: plain), plain)
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
