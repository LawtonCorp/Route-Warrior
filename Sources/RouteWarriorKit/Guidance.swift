import Foundation

/// One leg of a provider's plan (D-052): the instruction carried out at
/// its start and the line driven after it. Apple's `MKRoute.Step` and
/// Google's `legs.steps` both work this way — step 0 is the departure,
/// and the maneuver ahead while driving step i is step i+1's
/// instruction, reached at the end of step i's line.
public struct PlanStep: Sendable, Equatable, Codable {
    public var instruction: String
    public var polyline: Polyline
    public var distanceM: Double
    /// The provider's own maneuver class when it gives one (Google
    /// does). Nil means read it from the words (Apple gives words only).
    public var maneuver: Maneuver?

    public init(instruction: String, polyline: Polyline, distanceM: Double, maneuver: Maneuver? = nil) {
        self.instruction = instruction
        self.polyline = polyline
        self.distanceM = distanceM
        self.maneuver = maneuver
    }

    /// The maneuver to draw: the provider's when it gave one, otherwise
    /// inferred from the instruction.
    public var resolvedManeuver: Maneuver {
        maneuver ?? Maneuver.inferred(from: instruction)
    }
}

/// The shape of a maneuver, for the banner's arrow. Coarse on purpose:
/// what the driver needs at a glance is which way, not which lane.
public enum Maneuver: String, Sendable, Codable, CaseIterable {
    case depart
    case straight
    case left
    case right
    case slightLeft
    case slightRight
    case sharpLeft
    case sharpRight
    case keepLeft
    case keepRight
    case uTurn
    case merge
    case exit
    case roundabout
    case arrive
    case unknown

    /// Google's `Maneuver` enum names (Routes API v2).
    public init(googleName: String) {
        switch googleName {
        case "DEPART": self = .depart
        case "STRAIGHT", "NAME_CHANGE": self = .straight
        case "TURN_LEFT": self = .left
        case "TURN_RIGHT": self = .right
        case "TURN_SLIGHT_LEFT", "RAMP_LEFT": self = .slightLeft
        case "TURN_SLIGHT_RIGHT", "RAMP_RIGHT": self = .slightRight
        case "TURN_SHARP_LEFT": self = .sharpLeft
        case "TURN_SHARP_RIGHT": self = .sharpRight
        case "FORK_LEFT": self = .keepLeft
        case "FORK_RIGHT": self = .keepRight
        case "UTURN_LEFT", "UTURN_RIGHT": self = .uTurn
        case "MERGE": self = .merge
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT": self = .roundabout
        default: self = .unknown
        }
    }

    /// Reads Apple's instruction text ("Turn right onto Broadway", "At
    /// the end of the road, turn left onto Pearl St", "Take exit 205",
    /// "Arrive at the destination"). The road name is cut off first so a
    /// street called Left Hand Canyon Drive does not read as a left.
    public static func inferred(from instruction: String) -> Maneuver {
        var text = instruction.lowercased()
        for cut in [" onto ", " toward", " towards", " to ", " on "] {
            if let range = text.range(of: cut) {
                text = String(text[..<range.lowerBound])
            }
        }
        func has(_ phrases: String...) -> Bool {
            phrases.contains { text.contains($0) }
        }
        if has("u-turn", "u turn", "uturn") { return .uTurn }
        if has("arrive", "destination", "you have arrived") { return .arrive }
        if has("roundabout", "rotary", "traffic circle") { return .roundabout }
        if has("take exit", "take the exit", "exit ") || text.hasSuffix("exit") { return .exit }
        if has("merge") { return .merge }
        if has("keep left", "stay left", "stay in the left") { return .keepLeft }
        if has("keep right", "stay right", "stay in the right") { return .keepRight }
        if has("slight left", "slightly left", "bear left") { return .slightLeft }
        if has("slight right", "slightly right", "bear right") { return .slightRight }
        if has("sharp left") { return .sharpLeft }
        if has("sharp right") { return .sharpRight }
        if has("left") { return .left }
        if has("right") { return .right }
        if has("proceed", "head ", "start ", "depart") { return .depart }
        if has("continue", "straight", "go through") { return .straight }
        return .unknown
    }
}

/// Where the driver is on a plan's steps, and what to say about it
/// (D-052). Pure and position-driven, like the off-plan detector: the
/// drive view feeds it every sample and renders what comes back.
///
/// The engine follows whichever line it was given — the departure plan
/// or, after a reroute, the new plan. It never touches the snapshot the
/// drive is judged against; that is `DriveScoreboard`'s, and it reads the
/// departure plan (D-010).
public struct GuidanceEngine: Sendable {
    public enum Units: Sendable, Equatable {
        case imperial
        case metric
    }

    public struct Config: Sendable {
        public var units: Units = .imperial
        /// Farther than this from the line, the sample is not placed on
        /// it and the guidance is left as it was. Off-plan detection
        /// proper is `OffPlanDetector`'s, with its own hysteresis.
        public var maxOffLineM: Double = 80
        /// Within this of the end of the last step, the drive has arrived.
        public var arrivalRadiusM: Double = 30
        /// A distance callout ("in half a mile") is made only on a step at
        /// least this many times longer than the callout's distance, so
        /// "in half a mile" is never said on a step that is 0.4 mi long.
        public var calloutHeadroom: Double = 1.15

        public init() {}
    }

    /// The maneuver ahead and how far it is.
    public struct Guidance: Sendable, Equatable {
        /// The step being driven.
        public var stepIndex: Int
        /// The maneuver at the end of this step; nil past the last
        /// maneuver, which reads as arrival.
        public var next: PlanStep?
        /// The one after, for the "then" line.
        public var then: PlanStep?
        public var metersToManeuver: Double
        public var remainingM: Double
        public var arrived: Bool

        public var instruction: String { next?.instruction ?? "Arrive at your destination" }
        public var maneuver: Maneuver { next?.resolvedManeuver ?? .arrive }
    }

    /// One spoken line. `tier` is which callout it was; tests read it,
    /// the voice reads `text`.
    public struct Announcement: Sendable, Equatable {
        public enum Tier: Int, Sendable, Comparable {
            case far = 0
            case mid
            case quarter
            case near
            case now

            public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        public var tier: Tier
        public var text: String
    }

    public let steps: [PlanStep]
    public private(set) var guidance: Guidance?

    private let config: Config
    private let line: Polyline
    /// Arc length along `line` at the end of each step.
    private let stepEnds: [Double]
    private var announced: [Int: Set<Announcement.Tier>] = [:]
    private var furthestAlongM = 0.0

    public init(steps: [PlanStep], config: Config = Config()) {
        self.steps = steps
        self.config = config
        var coordinates: [Coordinate] = []
        var lastIndices: [Int] = []
        for step in steps {
            for coordinate in step.polyline.coordinates {
                // Steps share their joints; a duplicated joint is a
                // zero-length segment the projection handles, but it is
                // cleaner not to make one.
                if coordinates.last != coordinate { coordinates.append(coordinate) }
            }
            lastIndices.append(max(0, coordinates.count - 1))
        }
        let line = Polyline(coordinates: coordinates)
        let cumulative = line.cumulativeDistances
        self.line = line
        self.stepEnds = lastIndices.map { cumulative.isEmpty ? 0 : cumulative[min($0, cumulative.count - 1)] }
    }

    /// True when there is anything to guide along.
    public var hasSteps: Bool { steps.count >= 2 && line.coordinates.count >= 2 }

    public var lengthMeters: Double { line.lengthMeters }

    /// Places the sample on the line and returns the callout it is time
    /// for, if any. A sample too far from the line changes nothing.
    @discardableResult
    public mutating func ingest(position: Coordinate) -> Announcement? {
        guard hasSteps, let hit = line.nearestPoint(to: position),
              hit.distanceMeters <= config.maxOffLineM
        else { return nil }
        // Progress is monotonic: a sample that projects onto an earlier
        // pass of an out-and-back route teaches nothing.
        let along = max(hit.alongMeters, furthestAlongM)
        furthestAlongM = along

        let index = stepEnds.firstIndex { $0 > along } ?? (steps.count - 1)
        let total = stepEnds.last ?? 0
        let toManeuver = max(0, stepEnds[index] - along)
        let isLast = index == steps.count - 1
        let next = isLast ? nil : steps[index + 1]
        // A trailing arrival step with no line of its own is the maneuver
        // at the end of the step before it, and is never "driven".
        let then = index + 2 < steps.count ? steps[index + 2] : nil
        guidance = Guidance(
            stepIndex: index,
            next: next,
            then: then,
            metersToManeuver: toManeuver,
            remainingM: max(0, total - along),
            arrived: isLast && toManeuver <= config.arrivalRadiusM
        )
        return announcement(for: index, toManeuver: toManeuver, next: next)
    }

    // MARK: Callouts

    private var tiers: [(Announcement.Tier, Double, String)] {
        switch config.units {
        case .imperial:
            [
                (.far, 1_609, "In one mile"),
                (.mid, 805, "In half a mile"),
                (.quarter, 402, "In a quarter mile"),
                (.near, 152, "In 500 feet"),
                (.now, 45, ""),
            ]
        case .metric:
            [
                (.far, 2_000, "In two kilometres"),
                (.mid, 1_000, "In one kilometre"),
                (.quarter, 500, "In 500 metres"),
                (.near, 200, "In 200 metres"),
                (.now, 50, ""),
            ]
        }
    }

    private mutating func announcement(for index: Int, toManeuver: Double, next: PlanStep?) -> Announcement? {
        let stepLength = stepEnds[index] - (index > 0 ? stepEnds[index - 1] : 0)
        var done = announced[index] ?? []
        var chosen: (Announcement.Tier, String)?
        for (tier, meters, phrase) in tiers where toManeuver <= meters && !done.contains(tier) {
            done.insert(tier)
            let eligible = tier == .now || stepLength >= meters * config.calloutHeadroom
            // The nearest due callout wins; the farther ones it skipped
            // past are spent, so a GPS gap never plays three in a row.
            if eligible { chosen = (tier, phrase) }
        }
        announced[index] = done
        guard let (tier, phrase) = chosen else { return nil }
        let instruction = next?.instruction ?? "arrive at your destination"
        let text = phrase.isEmpty
            ? Self.sentence(instruction)
            : phrase + ", " + Self.lowercasedFirst(instruction) + "."
        return Announcement(tier: tier, text: text)
    }

    private static func lowercasedFirst(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") { trimmed.removeLast() }
        guard let first = trimmed.first else { return trimmed }
        return first.lowercased() + trimmed.dropFirst()
    }

    private static func sentence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(".") { trimmed.removeLast() }
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst() + "."
    }
}

public extension GuidanceEngine {
    /// "450 ft", "0.4 mi", "12 mi" — or "450 m", "1.2 km": the distance
    /// to the maneuver as a banner reads it, in the units the callouts
    /// use, so the words and the number never disagree.
    static func distanceText(_ meters: Double, units: Units) -> String {
        switch units {
        case .imperial:
            let feet = meters * 3.28084
            if feet < 1_000 {
                let rounded = max(50, (feet / 50).rounded() * 50)
                return "\(Int(rounded)) ft"
            }
            let miles = meters / 1_609.344
            return miles >= 10 ? "\(Int(miles.rounded())) mi" : String(format: "%.1f mi", miles)
        case .metric:
            if meters < 1_000 {
                let unit = meters < 100 ? 10.0 : 50.0
                let rounded = max(unit, (meters / unit).rounded() * unit)
                return "\(Int(rounded)) m"
            }
            let km = meters / 1_000
            return km >= 10 ? "\(Int(km.rounded())) km" : String(format: "%.1f km", km)
        }
    }
}
