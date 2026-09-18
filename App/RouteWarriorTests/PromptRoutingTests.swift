import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import UserNotifications
import XCTest
@testable import RouteWarrior

/// D-082: the destination handler ended in `if let placeID =
/// UUID(uuidString: action)`, and a tap on the notification itself sends
/// `UNNotificationDefaultActionIdentifier`, which is not a UUID. The tap
/// fell off the end of the `if` and did nothing — no picker, no log
/// line, nothing to tell it from a tap that worked. Every response is
/// named now, so one can no longer be dropped by omission.
@MainActor
final class PromptRoutingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let metersPerDegree = 111_195.08

    private func route(_ category: String, _ action: String) -> PromptResponse {
        PromptResponse.route(category: category, action: action)
    }

    // MARK: The destination notification

    func testAPlaceButtonIsAPick() {
        let id = UUID()
        XCTAssertEqual(
            route(PromptService.destinationCategoryID, id.uuidString), .pick(id)
        )
    }

    /// The case that did nothing.
    func testTappingTheNotificationOpensThePicker() {
        XCTAssertEqual(
            route(PromptService.destinationCategoryID, UNNotificationDefaultActionIdentifier),
            .openPicker
        )
    }

    func testSwipingItAwayIsNotAnAnswer() {
        XCTAssertEqual(
            route(PromptService.destinationCategoryID, UNNotificationDismissActionIdentifier),
            .ignore
        )
    }

    // MARK: The pause question

    func testThePauseActionsStillRoute() {
        XCTAssertEqual(
            route(PromptService.pauseCategoryID, PromptService.stillHereAction), .stillHere
        )
        XCTAssertEqual(
            route(PromptService.pauseCategoryID, PromptService.endDriveAction), .endDrive
        )
    }

    /// Tapping the pause question opens the app, where the same question
    /// is already waiting as an alert (D-072) — it must not be answered
    /// twice, and must not open the destination picker either.
    func testTappingThePauseQuestionAnswersNothing() {
        XCTAssertEqual(
            route(PromptService.pauseCategoryID, UNNotificationDefaultActionIdentifier), .ignore
        )
    }

    func testAnUnknownCategoryIsIgnored() {
        XCTAssertEqual(route("SOMETHING_ELSE", UUID().uuidString), .ignore)
        XCTAssertEqual(route(PromptService.destinationCategoryID, "not-a-uuid"), .ignore)
    }

    // MARK: What the picker request does to the pipeline

    private func makePipeline() throws -> RecordingPipeline {
        let context = ModelContext(try RouteWarriorStoreFactory.inMemoryContainer())
        return RecordingPipeline(context: context, timezoneID: "America/Chicago")
    }

    private func point(east: Double, at time: Date) -> TrackPoint {
        TrackPoint(
            coordinate: Coordinate(latitude: 0, longitude: east / metersPerDegree),
            timestamp: time, speedMps: 10, courseDegrees: 90, horizontalAccuracyM: 5
        )
    }

    func testThePickerIsAskedForOnlyWhileADriveIsOn() throws {
        let pipeline = try makePipeline()
        pipeline.requestDestinationPicker()
        XCTAssertFalse(pipeline.destinationPickerRequested,
                       "a finished drive has no destination left to name")

        pipeline.startManualRecording()
        pipeline.ingest(location: point(east: 0, at: t0))
        pipeline.requestDestinationPicker()
        XCTAssertTrue(pipeline.destinationPickerRequested)
    }

    /// A paused drive is still a drive: the driver reading the
    /// notification at the kerb is exactly who this is for.
    func testAPausedDriveStillOpensThePicker() throws {
        let pipeline = try makePipeline()
        pipeline.startManualRecording()
        pipeline.ingest(location: point(east: 0, at: t0))
        pipeline.pauseRecording(at: t0.addingTimeInterval(10))
        pipeline.requestDestinationPicker()
        XCTAssertTrue(pipeline.destinationPickerRequested)
    }

    func testAnsweringClosesTheRequest() throws {
        let pipeline = try makePipeline()
        pipeline.startManualRecording()
        pipeline.ingest(location: point(east: 0, at: t0))
        pipeline.requestDestinationPicker()

        pipeline.requestSnapshot(to: UUID())
        XCTAssertFalse(pipeline.destinationPickerRequested)
    }

    func testDismissingClosesTheRequest() throws {
        let pipeline = try makePipeline()
        pipeline.startManualRecording()
        pipeline.ingest(location: point(east: 0, at: t0))
        pipeline.requestDestinationPicker()

        pipeline.dismissDestinationPicker()
        XCTAssertFalse(pipeline.destinationPickerRequested)
    }
}
