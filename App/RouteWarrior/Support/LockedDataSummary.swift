import Foundation
import RouteWarriorKit
import RouteWarriorStore

/// What is already on the phone that the free tier cannot open (D-050).
/// The paywall shows these as counts: "47 drives older than 30 days"
/// says more than "unlimited history" ever will. Pure, so it is tested.
struct LockedDataSummary: Equatable {
    /// The facts the summary needs from a trip, so records need not be
    /// fully decoded (the points blob is the expensive part).
    struct TripFacts: Equatable {
        var startedAt: Date
        var destinationPlaceID: UUID?
        var stopCount: Int

        init(startedAt: Date, destinationPlaceID: UUID? = nil, stopCount: Int = 0) {
            self.startedAt = startedAt
            self.destinationPlaceID = destinationPlaceID
            self.stopCount = stopCount
        }

        init(_ record: TripRecord) {
            startedAt = record.startedAt
            destinationPlaceID = record.destinationPlaceID
            stopCount = (try? JSONDecoder().decode([StopEvent].self, from: record.stopEventsBlob))?.count ?? 0
        }
    }

    /// Trips outside the free history window.
    var olderTrips: Int
    /// Saved places past the free analytics limit that have at least one
    /// drive — a locked destination with nothing in it is not a loss.
    var lockedDestinations: Int
    /// Every stop on every drive: the free tier sees the count per trip,
    /// never the list.
    var stops: Int

    var isEmpty: Bool { olderTrips == 0 && lockedDestinations == 0 && stops == 0 }

    static func compute(
        trips: [TripFacts],
        placeIDs: [UUID],
        policy: TierPolicy = TierPolicy(),
        now: Date = .now
    ) -> LockedDataSummary {
        let older = trips.filter { !policy.canViewTrip(startedAt: $0.startedAt, now: now, tier: .free) }.count
        let visited = Set(trips.compactMap(\.destinationPlaceID))
        let locked = placeIDs.enumerated().filter { rank, id in
            !policy.canAnalyzeDestination(atRank: rank, tier: .free) && visited.contains(id)
        }.count
        let stops = trips.reduce(0) { $0 + $1.stopCount }
        return LockedDataSummary(olderTrips: older, lockedDestinations: locked, stops: stops)
    }
}
