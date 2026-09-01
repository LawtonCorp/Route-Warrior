import Foundation

/// Small display formatters. US-first (NFR-6); the units setting arrives
/// with Settings polish in M5.
enum Format {
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: .miles)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    /// "+0:42" / "−1:05" for the ghost race and plan deltas.
    static func signedDelta(_ seconds: Double) -> String {
        let sign = seconds < 0 ? "−" : "+"
        return sign + duration(abs(seconds))
    }
}
