/// Persistence layer for Route Warrior: SwiftData records mirroring the
/// kit's value types, mapping in `Mapping.swift`, containers in
/// `StoreFactory.swift`.
public enum RouteWarriorStore {
    /// Bumped whenever the persisted schema changes shape.
    public static let schemaVersion = 1
}
