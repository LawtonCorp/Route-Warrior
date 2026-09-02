import RouteWarriorKit
import RouteWarriorStore
import SwiftData
import XCTest

@testable import RouteWarrior

/// D-021 wiring: the address typed in the New Place form must survive the
/// kit → store → kit trip, or the Places list shows nothing for it.
@MainActor
final class PlaceAddressWiringTests: XCTestCase {
    func testAddressPersistsThroughTheStore() throws {
        let container = try RouteWarriorStoreFactory.inMemoryContainer()
        let context = ModelContext(container)
        let place = Place(
            name: "Office",
            coordinate: Coordinate(latitude: 41.8789, longitude: -87.6359),
            kind: .work,
            address: "233 S Wacker Dr, Chicago, IL 60606"
        )
        context.insert(PlaceRecord(place))
        try context.save()

        let records = try context.fetch(FetchDescriptor<PlaceRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].address, place.address)
        let back = records[0].place()
        XCTAssertEqual(back.address, place.address)
        XCTAssertEqual(back.name, place.name)
        XCTAssertEqual(back.kind, .work)
        XCTAssertEqual(back.coordinate, place.coordinate)
    }

    func testAPinDroppedByHandHasNoAddress() throws {
        let record = PlaceRecord(Place(name: "Cabin", coordinate: Coordinate(latitude: 45, longitude: -90)))
        XCTAssertEqual(record.address, "")
        XCTAssertEqual(record.place().address, "")
    }

    func testSuggestionQueryJoinsTitleAndSubtitle() {
        let full = AddressSuggestion(title: "233 S Wacker Dr", subtitle: "Chicago, IL")
        XCTAssertEqual(full.query, "233 S Wacker Dr, Chicago, IL")
        let bare = AddressSuggestion(title: "Willis Tower", subtitle: "")
        XCTAssertEqual(bare.query, "Willis Tower")
    }
}
