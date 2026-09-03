import Foundation

/// Where a trip's destination sits among the saved places. The Places tab
/// ranks places by when they were saved and the free tier analyzes only
/// the first few (`TierPolicy.canAnalyzeDestination`); anything offering a
/// way into those analytics has to rank the place the same way.
enum DestinationAnalytics {
    /// The place's position in the saved-place order, or nil when the
    /// trip ended somewhere that was never saved.
    static func rank(of placeID: UUID?, in placeIDs: [UUID]) -> Int? {
        guard let placeID else { return nil }
        return placeIDs.firstIndex(of: placeID)
    }
}
