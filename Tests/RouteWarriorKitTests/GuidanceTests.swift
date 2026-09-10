import Foundation
import Testing
@testable import RouteWarriorKit

/// D-052: the guidance engine places the car on the plan's steps, names
/// the maneuver ahead with its distance, and makes each callout once, at
/// the right distance, only on a step long enough to deserve it. The
/// expected values are geometry by construction on a flat metre frame at
/// the equator — the engine has no hand in them.
struct GuidanceTests {
    private static let metersPerDegree = 111_195.08

    private func at(east x: Double, north y: Double = 0) -> Coordinate {
        Coordinate(latitude: y / Self.metersPerDegree, longitude: x / Self.metersPerDegree)
    }

    /// East 1200 m on A St, left, north 900 m on B St, arrive.
    private var steps: [PlanStep] {
        [
            PlanStep(
                instruction: "Proceed to A St",
                polyline: Polyline(coordinates: [at(east: 0), at(east: 600), at(east: 1_200)]),
                distanceM: 1_200
            ),
            PlanStep(
                instruction: "Turn left onto B St",
                polyline: Polyline(coordinates: [at(east: 1_200), at(east: 1_200, north: 900)]),
                distanceM: 900
            ),
            PlanStep(
                instruction: "Arrive at your destination",
                polyline: Polyline(coordinates: [at(east: 1_200, north: 900)]),
                distanceM: 0
            ),
        ]
    }

    @Test func placesTheCarAndNamesTheManeuverAhead() throws {
        var engine = GuidanceEngine(steps: steps)
        #expect(engine.hasSteps)
        #expect(abs(engine.lengthMeters - 2_100) < 1)

        engine.ingest(position: at(east: 0))
        let start = try #require(engine.guidance)
        #expect(start.stepIndex == 0)
        #expect(start.instruction == "Turn left onto B St")
        #expect(start.maneuver == .left)
        #expect(abs(start.metersToManeuver - 1_200) < 1)
        #expect(abs(start.remainingM - 2_100) < 1)
        #expect(start.then?.instruction == "Arrive at your destination")
        #expect(!start.arrived)

        engine.ingest(position: at(east: 1_200, north: 100))
        let onB = try #require(engine.guidance)
        #expect(onB.stepIndex == 1)
        #expect(onB.instruction == "Arrive at your destination")
        #expect(onB.maneuver == .arrive)
        #expect(abs(onB.metersToManeuver - 800) < 1)
        #expect(onB.then == nil)

        engine.ingest(position: at(east: 1_200, north: 900))
        let end = try #require(engine.guidance)
        #expect(end.arrived)
        #expect(end.next == nil)
        #expect(end.instruction == "Arrive at your destination")
    }

    @Test func calloutsComeOnceEachAtTheirDistances() {
        var engine = GuidanceEngine(steps: steps)
        var spoken: [GuidanceEngine.Announcement] = []
        for x in stride(from: 0.0, through: 1_200, by: 20) {
            if let a = engine.ingest(position: at(east: x)) { spoken.append(a) }
        }
        // A St is 1200 m: "in one mile" cannot be said on it, the rest can.
        #expect(spoken.map(\.tier) == [.mid, .quarter, .near, .now])
        #expect(spoken.map(\.text) == [
            "In half a mile, turn left onto B St.",
            "In a quarter mile, turn left onto B St.",
            "In 500 feet, turn left onto B St.",
            "Turn left onto B St.",
        ])

        spoken.removeAll()
        for y in stride(from: 20.0, through: 900, by: 20) {
            if let a = engine.ingest(position: at(east: 1_200, north: y)) { spoken.append(a) }
        }
        // B St is 900 m: "in half a mile" needs 926, so it is skipped.
        #expect(spoken.map(\.tier) == [.quarter, .near, .now])
        #expect(spoken.first?.text == "In a quarter mile, arrive at your destination.")
        #expect(spoken.last?.text == "Arrive at your destination.")
    }

    @Test func aGapPlaysOnlyTheNearestDueCallout() {
        var engine = GuidanceEngine(steps: steps)
        #expect(engine.ingest(position: at(east: 0)) == nil)
        let a = engine.ingest(position: at(east: 1_100))
        #expect(a?.tier == .near)
        // The ones it skipped past are spent, not queued.
        #expect(engine.ingest(position: at(east: 1_120)) == nil)
        #expect(engine.ingest(position: at(east: 1_180))?.tier == .now)
    }

    @Test func offTheLineChangesNothingAndProgressNeverGoesBackwards() {
        var engine = GuidanceEngine(steps: steps)
        engine.ingest(position: at(east: 1_000))
        let before = engine.guidance
        #expect(engine.ingest(position: at(east: 600, north: 300)) == nil)
        #expect(engine.guidance == before)
        engine.ingest(position: at(east: 700))
        #expect(abs((engine.guidance?.metersToManeuver ?? 0) - 200) < 1, "a sample that projects behind keeps the furthest point")
    }

    @Test func metricCalloutsAndNoStepsMeanNoGuidance() {
        var config = GuidanceEngine.Config()
        config.units = .metric
        var engine = GuidanceEngine(steps: steps, config: config)
        var spoken: [String] = []
        for x in stride(from: 0.0, through: 1_200, by: 20) {
            if let a = engine.ingest(position: at(east: x)) { spoken.append(a.text) }
        }
        // 1200 m: "in one kilometre" needs 1150, so it is said; "in two" is not.
        #expect(spoken.first == "In one kilometre, turn left onto B St.")
        #expect(spoken.contains("In 200 metres, turn left onto B St."))

        var empty = GuidanceEngine(steps: [])
        #expect(!empty.hasSteps)
        #expect(empty.ingest(position: at(east: 0)) == nil)
        #expect(empty.guidance == nil)
        var single = GuidanceEngine(steps: [steps[0]])
        #expect(!single.hasSteps)
        #expect(single.ingest(position: at(east: 0)) == nil)
    }

    @Test func distanceTextReadsLikeASign() {
        #expect(GuidanceEngine.distanceText(30, units: .imperial) == "100 ft")
        #expect(GuidanceEngine.distanceText(140, units: .imperial) == "450 ft")
        #expect(GuidanceEngine.distanceText(1_609.344, units: .imperial) == "1.0 mi")
        #expect(GuidanceEngine.distanceText(20_000, units: .imperial) == "12 mi")
        #expect(GuidanceEngine.distanceText(34, units: .metric) == "30 m")
        #expect(GuidanceEngine.distanceText(460, units: .metric) == "450 m")
        #expect(GuidanceEngine.distanceText(1_500, units: .metric) == "1.5 km")
        #expect(GuidanceEngine.distanceText(20_400, units: .metric) == "20 km")
    }

    @Test func maneuversAreReadFromAppleWordsAndGoogleNames() {
        let cases: [(String, Maneuver)] = [
            ("Turn right onto Left Hand Canyon Dr", .right),
            ("At the end of the road, turn left onto Pearl St", .left),
            ("Keep left onto I-25 N", .keepLeft),
            ("Bear right onto the ramp toward Denver", .slightRight),
            ("Slight left onto Broadway", .slightLeft),
            ("Make a U-turn at Main St", .uTurn),
            ("Take exit 205 toward Colfax Ave", .exit),
            ("Merge onto I-70 W", .merge),
            ("At the roundabout, take the 2nd exit onto Ring Rd", .roundabout),
            ("Arrive at the destination", .arrive),
            ("The destination is on your right", .arrive),
            ("Continue straight onto Lincoln St", .straight),
            ("Proceed to Main St", .depart),
            ("Sharp right onto Old Mill Rd", .sharpRight),
            ("Take the ferry", .unknown),
        ]
        for (words, expected) in cases {
            #expect(Maneuver.inferred(from: words) == expected, "\(words)")
        }
        #expect(Maneuver(googleName: "TURN_SLIGHT_LEFT") == .slightLeft)
        #expect(Maneuver(googleName: "RAMP_RIGHT") == .slightRight)
        #expect(Maneuver(googleName: "FORK_LEFT") == .keepLeft)
        #expect(Maneuver(googleName: "UTURN_RIGHT") == .uTurn)
        #expect(Maneuver(googleName: "ROUNDABOUT_LEFT") == .roundabout)
        #expect(Maneuver(googleName: "NAME_CHANGE") == .straight)
        #expect(Maneuver(googleName: "DEPART") == .depart)
        #expect(Maneuver(googleName: "FERRY") == .unknown)
        let given = PlanStep(instruction: "Turn left", polyline: Polyline(coordinates: []), distanceM: 0, maneuver: .right)
        #expect(given.resolvedManeuver == .right, "the provider's class beats the words")
    }

    @Test func snapshotsKeepStepsInMemoryAndReadOldJSONWithoutThem() throws {
        let plan = PlanSnapshot(
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            polyline: Polyline(coordinates: [at(east: 0), at(east: 1_200)]),
            distanceM: 1_200, staticDuration: 100, trafficDuration: 100,
            alternates: [.init(
                polyline: Polyline(coordinates: [at(east: 0), at(east: 1_300)]),
                staticDuration: 110, trafficDuration: 110, steps: [steps[1]]
            )],
            steps: steps
        )
        let promoted = plan.promotingAlternate(at: 0)
        #expect(promoted.steps == [steps[1]])
        #expect(promoted.alternates[0].steps == steps)

        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(PlanSnapshot.self, from: data) == plan)

        var stripped = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        stripped["steps"] = nil
        var alternates = try #require(stripped["alternates"] as? [[String: Any]])
        alternates[0]["steps"] = nil
        stripped["alternates"] = alternates
        let old = try JSONDecoder().decode(PlanSnapshot.self, from: JSONSerialization.data(withJSONObject: stripped))
        #expect(old.steps.isEmpty)
        #expect(old.alternates[0].steps.isEmpty)
        #expect(old.id == plan.id)
    }
}
