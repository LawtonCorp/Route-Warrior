import Foundation
import RouteWarriorStore
import SwiftData

/// The one order saved places are shown in (D-074): the driver's own
/// arrangement, then oldest first for places that have never been moved.
///
/// It is shared rather than repeated because the order is load-bearing,
/// not decorative. The free tier analyses the first few destinations *by
/// position*, so a list that disagreed with itself between the Places tab
/// and a trip's detail screen would put a place inside the allowance on
/// one screen and outside it on the other.
enum PlaceOrder {
    static let descriptors: [SortDescriptor<PlaceRecord>] = [
        SortDescriptor(\.sortIndex),
        SortDescriptor(\.createdAt),
    ]

    /// For the services that fetch places themselves — the destination
    /// picker offers the first few, and those should be the ones the
    /// driver put at the top.
    static var fetchDescriptor: FetchDescriptor<PlaceRecord> {
        FetchDescriptor<PlaceRecord>(sortBy: descriptors)
    }

    /// The ids in their new order after a drag. The caller writes each
    /// id's position back as its `sortIndex`, so every place carries its
    /// own row number and the stored order can never develop the ties
    /// that would let a later save land in the middle of the list.
    static func reordered(_ ids: [UUID], from source: IndexSet, to destination: Int) -> [UUID] {
        var ids = ids
        ids.move(fromOffsets: source, toOffset: destination)
        return ids
    }

    /// The index a newly saved place takes: after everything already
    /// there, so adding a place never reshuffles the list the driver
    /// arranged. Zero when there is nothing yet.
    static func nextIndex(after existing: [Int]) -> Int {
        guard let highest = existing.max() else { return 0 }
        return highest + 1
    }
}
