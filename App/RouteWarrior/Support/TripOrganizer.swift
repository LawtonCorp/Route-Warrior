import Foundation

/// How the Trips tab is ordered. Pure vocabulary — the ordering itself
/// lives in `TripOrganizer` so it can be tested without SwiftData.
enum TripSort: String, CaseIterable, Identifiable {
    case newest, oldest, longest, farthest, biggestWin

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .longest: "Longest drive"
        case .farthest: "Farthest"
        case .biggestWin: "Biggest win vs. ETA"
        }
    }

    var symbol: String {
        switch self {
        case .newest: "arrow.down"
        case .oldest: "arrow.up"
        case .longest: "clock"
        case .farthest: "ruler"
        case .biggestWin: "trophy"
        }
    }
}

/// Which trips the Trips tab shows.
enum TripOutcome: String, CaseIterable, Identifiable {
    case any, beat, lost, excluded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: "All trips"
        case .beat: "Beat the ETA"
        case .lost: "Lost to the ETA"
        case .excluded: "Excluded from stats"
        }
    }
}

/// What the organizer needs of a trip. `TripRecord` satisfies it as it
/// stands, and a test can satisfy it with a struct.
protocol TripSortable {
    var id: UUID { get }
    var startedAt: Date { get }
    var endedAt: Date { get }
    var distanceM: Double { get }
    var destinationPlaceID: UUID? { get }
    var excludedFromStats: Bool { get }
}

/// Filters, sorts, and splits today off the top of the trip list. Pure,
/// so the Trips tab's behaviour is checkable without a store or a screen.
struct TripOrganizer {
    var sort: TripSort = .newest
    var destination: UUID?
    var outcome: TripOutcome = .any

    /// `delta` is the trip's actual duration minus the ETA it was judged
    /// against — negative means the driver won — and nil when the trip has
    /// no comparison.
    func arrange<T: TripSortable>(
        _ trips: [T],
        delta: (T) -> Double?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (today: [T], earlier: [T]) {
        let kept = trips.filter { keep($0, delta: delta($0)) }
        let ordered = kept.sorted { order($0, $1, delta: delta) }
        var today: [T] = []
        var earlier: [T] = []
        for trip in ordered {
            if calendar.isDate(trip.startedAt, inSameDayAs: now) {
                today.append(trip)
            } else {
                earlier.append(trip)
            }
        }
        return (today, earlier)
    }

    private func keep<T: TripSortable>(_ trip: T, delta: Double?) -> Bool {
        if let destination, trip.destinationPlaceID != destination { return false }
        switch outcome {
        case .any: return true
        case .beat: return (delta ?? 1) <= 0
        case .lost: return (delta ?? -1) > 0
        case .excluded: return trip.excludedFromStats
        }
    }

    private func order<T: TripSortable>(_ a: T, _ b: T, delta: (T) -> Double?) -> Bool {
        switch sort {
        case .newest:
            return tieBreak(a, b, a.startedAt > b.startedAt, a.startedAt == b.startedAt)
        case .oldest:
            return tieBreak(a, b, a.startedAt < b.startedAt, a.startedAt == b.startedAt)
        case .longest:
            let left = a.endedAt.timeIntervalSince(a.startedAt)
            let right = b.endedAt.timeIntervalSince(b.startedAt)
            return tieBreak(a, b, left > right, left == right)
        case .farthest:
            return tieBreak(a, b, a.distanceM > b.distanceM, a.distanceM == b.distanceM)
        case .biggestWin:
            // A trip with no comparison has no win to rank, so it sinks
            // below every trip that does.
            switch (delta(a), delta(b)) {
            case let (left?, right?): return tieBreak(a, b, left < right, left == right)
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return tieBreak(a, b, false, true)
            }
        }
    }

    /// Equal keys fall back to newest, then to the id, so the list never
    /// reshuffles itself between redraws.
    private func tieBreak<T: TripSortable>(_ a: T, _ b: T, _ less: Bool, _ equal: Bool) -> Bool {
        guard equal else { return less }
        if a.startedAt != b.startedAt { return a.startedAt > b.startedAt }
        return a.id.uuidString < b.id.uuidString
    }
}
