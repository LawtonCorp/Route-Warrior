import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest
@testable import RouteWarrior

/// D-066: the wiring from the store to the Plan tab's personal rows, and
/// from the Plan tab into the drive.
@MainActor
final class PersonalRouteFinderTests: XCTestCase {
    private let sunday = Date(timeIntervalSince1970: 1_699_747_200)

    private func line(_ east: Double) -> Polyline {
        Polyline(coordinates: [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: east)])
    }

    /// Home and School 5 km apart, two routes between them with five
    /// Tuesday-morning drives each, and one route to the Gym.
    private func seed(_ context: ModelContext) throws -> (home: Place, school: Place, maple: UUID, backWay: UUID) {
        let home = Place(name: "Home", coordinate: Coordinate(latitude: 0, longitude: 0))
        let school = Place(name: "School", coordinate: Coordinate(latitude: 0, longitude: 0.045))
        let gym = Place(name: "Gym", coordinate: Coordinate(latitude: 0.05, longitude: 0.02))
        for place in [home, school, gym] { context.insert(PlaceRecord(place)) }

        let maple = RouteVariant(originPlaceID: home.id, destinationPlaceID: school.id,
                                 representativePolyline: line(0.045), autoName: "via Maple Ave", tripCount: 5)
        let backWay = RouteVariant(originPlaceID: home.id, destinationPlaceID: school.id,
                                   representativePolyline: line(0.046), autoName: "the back way", tripCount: 5)
        let toGym = RouteVariant(originPlaceID: home.id, destinationPlaceID: gym.id,
                                 representativePolyline: line(0.02), autoName: "to the gym", tripCount: 1)
        for variant in [maple, backWay, toGym] { context.insert(VariantRecord(variant)) }

        func drive(_ variant: UUID, destination: UUID, week: Int, minutes: Double) throws -> TripRecord {
            let start = sunday.addingTimeInterval(Double(week) * 7 * 86_400 + 2 * 86_400 + 9 * 3_600)
            return try TripRecord(Trip(
                startedAt: start, endedAt: start.addingTimeInterval(minutes * 60), timezoneID: "UTC",
                points: [], originPlaceID: home.id, destinationPlaceID: destination, variantID: variant
            ))
        }
        for week in 0..<5 {
            context.insert(try drive(maple.id, destination: school.id, week: week, minutes: 18))
            context.insert(try drive(backWay.id, destination: school.id, week: week, minutes: 22))
        }
        context.insert(try drive(toGym.id, destination: gym.id, week: 0, minutes: 12))
        try context.save()
        return (home, school, maple.id, backWay.id)
    }

    func testRoutesFromWhereYouAreToWhereYouAreGoing() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let seeded = try seed(context)
        let tuesdayNine = sunday.addingTimeInterval(2 * 86_400 + 9 * 3_600)

        let rows = PersonalRouteFinder.rows(
            from: seeded.home.coordinate, to: seeded.school.id, in: context, now: tuesdayNine, timezoneID: "UTC"
        )
        XCTAssertEqual(rows.map(\.id), [seeded.maple, seeded.backWay], "fastest first; the gym route is not here")
        XCTAssertEqual(rows[0].claim, "usually fastest on Tuesday mornings")
        XCTAssertEqual(rows[0].usualDuration, 1_080)
    }

    func testNoRowsWithoutAnOriginPlaceOrForTheSamePlace() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let seeded = try seed(context)
        let nowhere = Coordinate(latitude: 1, longitude: 1)
        XCTAssertTrue(PersonalRouteFinder.rows(from: nowhere, to: seeded.school.id, in: context).isEmpty)
        XCTAssertTrue(PersonalRouteFinder.rows(from: seeded.home.coordinate, to: seeded.home.id, in: context).isEmpty)
    }

    /// The pipeline carries the pick for the drive view and clears it with
    /// the drive; the baseline plans travel untouched beside it.
    func testThePipelineCarriesTheChosenRouteForTheDriveAndClearsItAfter() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let pipeline = RecordingPipeline(context: context, timezoneID: "UTC")
        let chosen = RecordingPipeline.ChosenRoute(variantID: UUID(), polyline: line(0.045))
        let baseline = PlanSnapshot(
            provider: .googleRoutes, requestedAt: .now, polyline: line(0.05),
            distanceM: 5_560, staticDuration: 1_100, trafficDuration: 1_176
        )

        pipeline.startPlannedDrive(with: [baseline], choosingRoute: chosen)
        XCTAssertEqual(pipeline.chosenRouteForCurrentDrive, chosen)
        XCTAssertEqual(pipeline.plansForCurrentDrive.map(\.id), [baseline.id], "the provider's plan is still the baseline")

        pipeline.stopManualRecording()
        XCTAssertNil(pipeline.chosenRouteForCurrentDrive, "the pick belongs to the drive that ended")
    }
}
