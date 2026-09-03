import RouteWarriorKit
import SwiftUI
import UIKit

/// The app's colour vocabulary (D-018). Every colour here means something
/// the trip map already taught the user: blue is the route you drove,
/// orange is Google's plan, green is winning. Colour carries state or
/// meaning — never decoration — which is what keeps the app calm rather
/// than flashy. Nothing outside this file picks a raw colour.
enum Theme {
    /// Your route — the solid blue line on the trip map and the app icon.
    static let route = Color(red: 0.20, green: 0.47, blue: 0.85)
    /// Google's plan — the dashed orange line.
    static let google = Color(red: 0.93, green: 0.55, blue: 0.18)
    /// Ahead, faster, a win.
    static let win = Color(red: 0.22, green: 0.64, blue: 0.42)
    /// Route Warrior Pro.
    static let pro = Color(red: 0.48, green: 0.40, blue: 0.85)
    /// Armed — motion looks like a drive, not yet confirmed.
    static let armed = Color(red: 0.92, green: 0.70, blue: 0.20)
    /// Recording.
    static let recording = Color(red: 0.88, green: 0.30, blue: 0.28)

    /// Strokes for the driver's own routes when several are drawn on one
    /// map. Ordered so the fastest wears the win colour and the rest stay
    /// distinguishable — meaning first, decoration never.
    static let routePalette: [Color] = [win, route, google, pro, armed, recording]

    /// The stroke for the route ranked `rank` (0 = fastest).
    static func routeColor(rank: Int) -> Color {
        routePalette[abs(rank) % routePalette.count]
    }

    /// Tint for the Home status card, by recorder state.
    static func statusTint(for state: TripRecorder.State) -> Color {
        switch state {
        case .idle: route
        case .armed: armed
        case .recording: recording
        }
    }

    /// Glyph for the Home status card, by recorder state.
    static func statusSymbol(for state: TripRecorder.State) -> String {
        switch state {
        case .idle: "car.fill"
        case .armed: "car.side.fill"
        case .recording: "record.circle"
        }
    }
}

/// How a trip row is coloured: a win against Google's ETA, a loss, no
/// comparison, or excluded from stats. Pure so the mapping is testable.
enum TripTone: Equatable {
    case faster
    case slower
    case noComparison
    case excluded

    /// `deltaSeconds` is actual duration minus Google's traffic-aware ETA
    /// (negative = you were faster), nil when the trip has no comparison.
    static func forTrip(deltaSeconds: Double?, excluded: Bool) -> TripTone {
        if excluded { return .excluded }
        guard let deltaSeconds else { return .noComparison }
        return deltaSeconds <= 0 ? .faster : .slower
    }

    var color: Color {
        switch self {
        case .faster: Theme.win
        case .slower: Theme.google
        case .noComparison, .excluded: Color.secondary
        }
    }

    var symbol: String {
        switch self {
        case .faster: "hare.fill"
        case .slower: "tortoise.fill"
        case .noComparison: "car.fill"
        case .excluded: "person.2.fill"
        }
    }
}

extension Place.Kind {
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case .school: "graduationcap.fill"
        case .custom: "mappin"
        }
    }

    var color: Color {
        switch self {
        case .home: Theme.win
        case .work: Theme.route
        case .school: Theme.google
        case .custom: Theme.pro
        }
    }
}

/// A rounded-square glyph in the style of the system Settings app.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28
    var pulsing = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .symbolEffect(.pulse, isActive: pulsing)
            .frame(width: size, height: size)
            .background(
                color.gradient,
                in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            )
    }
}

extension View {
    /// A soft wash of `color` behind a list row — for the one card per
    /// screen that carries state (recording status, a verdict). Layered
    /// over the grouped cell background so the wash reads as a tint, not
    /// as a hole in the list, in light and dark mode alike.
    func tintedRow(_ color: Color) -> some View {
        listRowBackground(
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                LinearGradient(
                    colors: [color.opacity(0.22), color.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
    }
}
