import Foundation
import SwiftData

/// Container creation for every context the store runs in. The app uses the
/// CloudKit private database (NFR-1: the user's own iCloud, nobody else's
/// server); tests use in-memory; local-only is the fallback when iCloud is
/// unavailable (NFR-5 — sync resumes when the account comes back).
public enum RouteWarriorStoreFactory {
    /// Must match project.yml's iCloud container for app and widget targets.
    public static let cloudKitContainerID = "iCloud.com.lawtoncorp.routewarrior"

    public static var schema: Schema {
        Schema([TripRecord.self, PlaceRecord.self, VariantRecord.self, SnapshotRecord.self])
    }

    public static func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    public static func localContainer() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)]
        )
    }

    /// The production container. Requires the iCloud entitlement, so only
    /// the app/widget targets can call this successfully — never tests.
    public static func cloudContainer() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudKitContainerID)),
            ]
        )
    }
}
