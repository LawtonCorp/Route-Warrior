import Foundation

/// Whose map and whose routes the user wants inside the app (FR-19, D-022).
/// Distinct from `PlanSnapshot.Provider`, which names where a snapshot
/// came from: a preference is a choice, a snapshot is a fact.
public enum MapProvider: String, Sendable, Codable, CaseIterable {
    case apple
    case google

    /// Apple: free, keyless, and no change to the privacy label (D-022 Q4).
    public static let `default`: MapProvider = .apple

    public var snapshotProvider: PlanSnapshot.Provider {
        switch self {
        case .apple: .appleMaps
        case .google: .googleRoutes
        }
    }

    public var displayName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }
}

public extension PlanSnapshot.Provider {
    var displayName: String {
        switch self {
        case .appleMaps: "Apple"
        case .googleRoutes: "Google"
        }
    }

    var mapProvider: MapProvider {
        switch self {
        case .appleMaps: .apple
        case .googleRoutes: .google
        }
    }
}
