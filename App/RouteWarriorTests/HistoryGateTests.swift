import RouteWarriorKit
import RouteWarriorStore
import XCTest
@testable import RouteWarrior

/// FR-16 wiring: the free tier's history window hides old trips (they are
/// never deleted) and Pro sees everything.
@MainActor
final class HistoryGateTests: XCTestCase {
    private func record(daysAgo: Int, now: Date) -> TripRecord {
        let record = TripRecord()
        record.startedAt = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        record.endedAt = record.startedAt.addingTimeInterval(600)
        return record
    }

    func testFreeTierHidesButNeverDeletesOldTrips() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            record(daysAgo: 1, now: now),
            record(daysAgo: 29, now: now),
            record(daysAgo: 31, now: now),
            record(daysAgo: 90, now: now),
        ]
        let free = HistoryGate.visible(records, tier: .free, now: now)
        XCTAssertEqual(free.visible.count, 2)
        XCTAssertEqual(free.hiddenCount, 2)

        let pro = HistoryGate.visible(records, tier: .pro, now: now)
        XCTAssertEqual(pro.visible.count, 4)
        XCTAssertEqual(pro.hiddenCount, 0)
    }
}
