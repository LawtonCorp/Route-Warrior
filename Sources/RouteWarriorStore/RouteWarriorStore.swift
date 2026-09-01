import RouteWarriorKit

/// Persistence layer for Route Warrior. The SwiftData models that mirror the
/// kit's value types arrive with milestone M2; this target exists from M0 so
/// the package layout, project generation, and CI wiring are proven before
/// any schema lands.
public enum RouteWarriorStore {
    /// Bumped whenever the persisted schema changes shape.
    public static let schemaVersion = 0
}
