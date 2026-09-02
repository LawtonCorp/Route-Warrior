import Foundation
import Testing
@testable import RouteWarriorKit

/// Equator geometry: 0.001° of latitude ≈ 111 m, so offsets are known to
/// the metre without the detector grading itself.
struct OffPlanDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let plan = Polyline(coordinates: [
        Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 0.02),
    ])

    private func at(_ seconds: Double, offsetDegrees: Double) -> (Coordinate, Date) {
        (Coordinate(latitude: offsetDegrees, longitude: 0.01), t0.addingTimeInterval(seconds))
    }

    @Test func drivingOnThePlanStaysOnPlan() {
        var detector = OffPlanDetector(plan: plan)
        for s in 0..<60 {
            let (p, t) = at(Double(s), offsetDegrees: 0.0003) // ~33 m, a wide lane
            #expect(detector.ingest(position: p, at: t) == .onPlan)
        }
    }

    @Test func aBriefExcursionUnderTheConfirmWindowNeverCounts() {
        var detector = OffPlanDetector(plan: plan)
        for s in 0..<15 {
            let (p, t) = at(Double(s), offsetDegrees: 0.002) // ~222 m off
            detector.ingest(position: p, at: t)
        }
        let (back, t) = at(15, offsetDegrees: 0)
        #expect(detector.ingest(position: back, at: t) == .onPlan)
        #expect(detector.state == .onPlan)
    }

    @Test func sustainedDistanceConfirmsOffPlanFromTheFirstFarSample() {
        var detector = OffPlanDetector(plan: plan)
        var last: OffPlanDetector.State = .onPlan
        for s in 0..<25 {
            let (p, t) = at(Double(s), offsetDegrees: 0.002)
            last = detector.ingest(position: p, at: t)
        }
        #expect(last == .offPlan(since: t0))
    }

    @Test func returningNeedsToComeWellBackInside() {
        var detector = OffPlanDetector(plan: plan)
        for s in 0..<25 {
            let (p, t) = at(Double(s), offsetDegrees: 0.002)
            detector.ingest(position: p, at: t)
        }
        // ~100 m: inside the 120 m leave line but outside the 60 m return line.
        let (near, t1) = at(25, offsetDegrees: 0.0009)
        #expect(detector.ingest(position: near, at: t1) == .offPlan(since: t0))
        let (inside, t2) = at(26, offsetDegrees: 0.0004) // ~44 m
        #expect(detector.ingest(position: inside, at: t2) == .onPlan)
    }
}
