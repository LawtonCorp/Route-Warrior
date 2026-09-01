import Foundation

/// Placeholder logic proving the kit → app wiring. Replace with the real
/// app's core the moment there is one; the shape to preserve is that logic
/// lives here, UI-free and testable with plain `swift test`, and the app
/// target only renders it.
public enum Greeting {
    public static func message(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Hello." : "Hello, \(trimmed)."
    }
}
