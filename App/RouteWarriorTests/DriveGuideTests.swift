import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import UIKit
import XCTest
@testable import RouteWarrior

/// D-052 wiring: the guide feeds the kit's engine, hands callouts to the
/// voice unless silenced, follows a reroute when one lands, and through
/// all of it the departure plan held by the pipeline — the one the
/// verdict is against — never changes (D-010).
@MainActor
final class DriveGuideTests: XCTestCase {
    private let metersPerDegree = 111_195.08
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private final class SpySpeaker: GuidanceSpeaking {
        private(set) var spoken: [String] = []
        func speak(_ text: String) { spoken.append(text) }
    }

    private func at(east x: Double, north y: Double = 0) -> Coordinate {
        Coordinate(latitude: y / metersPerDegree, longitude: x / metersPerDegree)
    }

    /// East 1200 m, left, north 900 m.
    private var plan: PlanSnapshot {
        PlanSnapshot(
            provider: .appleMaps,
            requestedAt: t0,
            polyline: Polyline(coordinates: [at(east: 0), at(east: 1_200), at(east: 1_200, north: 900)]),
            distanceM: 2_100, staticDuration: 180, trafficDuration: 180,
            steps: [
                PlanStep(instruction: "Proceed to A St", polyline: Polyline(coordinates: [at(east: 0), at(east: 1_200)]), distanceM: 1_200),
                PlanStep(instruction: "Turn left onto B St", polyline: Polyline(coordinates: [at(east: 1_200), at(east: 1_200, north: 900)]), distanceM: 900),
                PlanStep(instruction: "Arrive at your destination", polyline: Polyline(coordinates: [at(east: 1_200, north: 900)]), distanceM: 0),
            ]
        )
    }

    func testTheGuideSpeaksTheKitsCalloutsUnlessSilenced() {
        let speaker = SpySpeaker()
        let guide = DriveGuide(plan: plan, units: .imperial, voice: speaker)
        XCTAssertTrue(guide.hasSteps)
        guide.ingest(position: at(east: 0))
        XCTAssertEqual(guide.guidance?.instruction, "Turn left onto B St")
        XCTAssertEqual(guide.distanceText, "0.7 mi")
        XCTAssertTrue(speaker.spoken.isEmpty)

        guide.ingest(position: at(east: 1_100))
        XCTAssertEqual(speaker.spoken, ["In 500 feet, turn left onto B St."])
        XCTAssertEqual(guide.distanceText, "350 ft")

        guide.voiceEnabled = false
        guide.ingest(position: at(east: 1_180))
        XCTAssertEqual(speaker.spoken.count, 1, "silenced: no new speech")
        XCTAssertEqual(guide.announcements.last?.text, "Turn left onto B St.", "but the callout is still recorded")
    }

    func testARerouteIsFollowedAndTheDeparturePlanIsUntouched() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let pipeline = RecordingPipeline(context: ModelContext(container))
        let departure = plan
        pipeline.startPlannedDrive(with: [departure])

        let guide = DriveGuide(plan: departure, units: .imperial, voice: nil)
        guide.ingest(position: at(east: 600))
        XCTAssertEqual(guide.guidance?.stepIndex, 0)

        // The driver went north early; the reroute from there is one leg.
        let reroute = PlanSnapshot(
            provider: .appleMaps, requestedAt: t0.addingTimeInterval(60),
            polyline: Polyline(coordinates: [at(east: 600, north: 300), at(east: 600, north: 1_200)]),
            distanceM: 900, staticDuration: 90, trafficDuration: 90,
            steps: [
                PlanStep(instruction: "Head north on C St", polyline: Polyline(coordinates: [at(east: 600, north: 300), at(east: 600, north: 1_200)]), distanceM: 900),
                PlanStep(instruction: "Arrive at your destination", polyline: Polyline(coordinates: [at(east: 600, north: 1_200)]), distanceM: 0),
            ]
        )
        guide.follow(reroute)
        XCTAssertEqual(guide.following.id, reroute.id)
        XCTAssertNil(guide.guidance, "a new line starts with no placement")
        guide.ingest(position: at(east: 600, north: 400))
        XCTAssertEqual(guide.guidance?.instruction, "Arrive at your destination")
        XCTAssertEqual(guide.guidance?.metersToManeuver ?? 0, 800, accuracy: 1)

        // D-010: the pipeline's plan for this drive is still the departure's.
        XCTAssertEqual(pipeline.plansForCurrentDrive.map(\.id), [departure.id])
        XCTAssertEqual(pipeline.plansForCurrentDrive.first?.steps, departure.steps)
        XCTAssertEqual(pipeline.plansForCurrentDrive.first?.polyline, departure.polyline)

        guide.follow(reroute)
        XCTAssertNotNil(guide.guidance, "following the same line again is a no-op")
    }

    func testUnitsFollowTheLocaleAndEverySymbolExists() {
        XCTAssertEqual(DriveGuide.localUnits(locale: Locale(identifier: "en_US")), .imperial)
        XCTAssertEqual(DriveGuide.localUnits(locale: Locale(identifier: "fr_FR")), .metric)
        for maneuver in Maneuver.allCases {
            XCTAssertNotNil(UIImage(systemName: ManeuverSymbol.name(for: maneuver)), "\(maneuver)")
        }
    }
}
