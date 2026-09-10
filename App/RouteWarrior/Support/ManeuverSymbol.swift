import RouteWarriorKit

/// The SF Symbol for each maneuver on the guidance banner (D-052).
enum ManeuverSymbol {
    static func name(for maneuver: Maneuver) -> String {
        switch maneuver {
        case .depart: "location.north.line.fill"
        case .straight: "arrow.up"
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .slightLeft: "arrow.up.left"
        case .slightRight: "arrow.up.right"
        case .sharpLeft: "arrow.turn.down.left"
        case .sharpRight: "arrow.turn.down.right"
        case .keepLeft: "arrow.up.left"
        case .keepRight: "arrow.up.right"
        case .uTurn: "arrow.uturn.down"
        case .merge: "arrow.triangle.merge"
        case .exit: "arrow.up.right"
        case .roundabout: "arrow.triangle.2.circlepath"
        case .arrive: "flag.checkered"
        case .unknown: "arrow.up"
        }
    }
}
