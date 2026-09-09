import Foundation
@testable import RouteWarriorKit

/// Draws test tracks the way a car draws them: straight legs and arcs of
/// a known radius, in a flat metre frame on the equator where one degree
/// is 111,195.08 m both ways. The geometry is by construction — the turn
/// counter has no hand in the expected values.
struct TurtleTrack {
    static let metersPerDegree = 111_195.08

    private(set) var x = 0.0
    private(set) var y = 0.0
    /// Degrees clockwise from north.
    private(set) var heading: Double
    private(set) var points: [(x: Double, y: Double)] = []
    private let spacing: Double

    init(heading: Double = 0, spacing: Double = 2) {
        self.heading = heading
        self.spacing = spacing
        points.append((0, 0))
    }

    private mutating func step(_ meters: Double) {
        let radians = heading * .pi / 180
        x += meters * sin(radians)
        y += meters * cos(radians)
        points.append((x, y))
    }

    mutating func straight(_ meters: Double) {
        var remaining = meters
        while remaining > 0 {
            let piece = min(spacing, remaining)
            step(piece)
            remaining -= piece
        }
    }

    /// Turns through `degrees` (clockwise positive) on a circle of the
    /// given radius, laid down as short chords.
    mutating func curve(radius: Double, degrees: Double) {
        let arc = radius * abs(degrees) * .pi / 180
        let pieces = max(1, Int((arc / spacing).rounded(.up)))
        let turnPerPiece = degrees / Double(pieces)
        let chord = 2 * radius * sin(abs(turnPerPiece) * .pi / 360)
        for _ in 0..<pieces {
            heading += turnPerPiece / 2
            step(chord)
            heading += turnPerPiece / 2
        }
    }

    var polyline: Polyline {
        Polyline(coordinates: points.map { coordinate(x: $0.x, y: $0.y) })
    }

    var current: Coordinate { coordinate(x: x, y: y) }

    func coordinate(x: Double, y: Double) -> Coordinate {
        Coordinate(latitude: y / Self.metersPerDegree, longitude: x / Self.metersPerDegree)
    }

    /// The same shape as GPS samples at `speed`, one per point, timestamps
    /// spaced by the point spacing.
    func trackPoints(from start: Date, speedMps: Double, accuracy: Double = 5) -> [TrackPoint] {
        points.enumerated().map { index, point in
            TrackPoint(
                coordinate: coordinate(x: point.x, y: point.y),
                timestamp: start.addingTimeInterval(Double(index) * spacing / speedMps),
                speedMps: speedMps,
                courseDegrees: -1,
                horizontalAccuracyM: accuracy
            )
        }
    }
}
