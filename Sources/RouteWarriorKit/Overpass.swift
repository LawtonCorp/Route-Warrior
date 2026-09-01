import Foundation

/// OpenStreetMap intersection data (FR-10/FR-11, D-005): query building,
/// response parsing, corridor counting, and the coverage-confidence
/// heuristic. The network call lives in the app; everything here is pure
/// and fixture-testable.
public enum Overpass {
    public struct Node: Sendable, Equatable {
        public enum Kind: String, Sendable {
            case stopSign
            case signal
        }

        public var id: Int64
        public var coordinate: Coordinate
        public var kind: Kind

        public init(id: Int64, coordinate: Coordinate, kind: Kind) {
            self.id = id
            self.coordinate = coordinate
            self.kind = kind
        }
    }

    public enum ParseError: Error, Equatable {
        case malformed
    }

    /// Overpass QL for stop signs and signals in the route's padded
    /// bounding box. The padding deliberately blurs the exact route —
    /// privacy means Overpass sees a box, not a polyline (NFR-1).
    public static func query(forCorridorOf polyline: Polyline, paddingM: Double = 400) -> String? {
        guard let box = boundingBox(of: polyline, paddingM: paddingM) else { return nil }
        return """
        [out:json][timeout:25];\
        node["highway"~"^(stop|traffic_signals)$"](\(box.south),\(box.west),\(box.north),\(box.east));\
        out;
        """
    }

    static func boundingBox(
        of polyline: Polyline,
        paddingM: Double
    ) -> (south: Double, west: Double, north: Double, east: Double)? {
        guard !polyline.coordinates.isEmpty else { return nil }
        let lats = polyline.coordinates.map(\.latitude)
        let lons = polyline.coordinates.map(\.longitude)
        let midLat = ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2
        let latPad = paddingM / 111_195.08
        let lonPad = paddingM / (111_195.08 * max(0.1, cos(midLat * .pi / 180)))
        return (
            south: lats.min()! - latPad,
            west: lons.min()! - lonPad,
            north: lats.max()! + latPad,
            east: lons.max()! + lonPad
        )
    }

    /// Parses an Overpass JSON response into nodes; elements that aren't
    /// stop/signal nodes are skipped, a body that isn't Overpass JSON throws.
    public static func nodes(fromResponseData data: Data) throws -> [Node] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let elements = response.elements
        else {
            throw ParseError.malformed
        }
        return elements.compactMap { element in
            guard element.type == "node",
                  let id = element.id, let lat = element.lat, let lon = element.lon
            else { return nil }
            let kind: Node.Kind? = switch element.tags?["highway"] {
            case "stop": .stopSign
            case "traffic_signals": .signal
            default: nil
            }
            guard let kind else { return nil }
            return Node(id: id, coordinate: Coordinate(latitude: lat, longitude: lon), kind: kind)
        }
    }

    /// Counts the nodes lying on the route itself (within `corridorM` of
    /// the polyline) and grades OSM coverage honestly: signals are usually
    /// mapped, stop signs often aren't (D-005).
    public static func inventory(
        nodes: [Node],
        along polyline: Polyline,
        corridorM: Double = 30,
        fetchedAt: Date
    ) -> IntersectionInventory {
        var signals = 0
        var stopSigns = 0
        for node in nodes {
            guard let hit = polyline.nearestPoint(to: node.coordinate),
                  hit.distanceMeters <= corridorM
            else { continue }
            switch node.kind {
            case .signal: signals += 1
            case .stopSign: stopSigns += 1
            }
        }
        let confidence: IntersectionInventory.CoverageConfidence
        if signals > 0 && stopSigns > 0 {
            confidence = .high
        } else if signals > 0 || stopSigns > 0 {
            confidence = .medium
        } else {
            confidence = .low
        }
        return IntersectionInventory(
            signalCount: signals,
            stopSignCount: stopSigns,
            coverageConfidence: confidence,
            fetchedAt: fetchedAt
        )
    }

    private struct Response: Decodable {
        var elements: [Element]?
    }

    private struct Element: Decodable {
        var type: String?
        var id: Int64?
        var lat: Double?
        var lon: Double?
        var tags: [String: String]?
    }
}

/// Upgrades duration-prior stop causes with map evidence: a halt within
/// `withinM` of a mapped stop sign or signal takes that cause and records
/// the node (FR-11). Halts with no nearby node keep their prior.
public enum StopClassifier {
    public static func classify(
        _ events: [StopEvent],
        near nodes: [Overpass.Node],
        withinM: Double = 30
    ) -> [StopEvent] {
        events.map { event in
            var nearest: (node: Overpass.Node, distance: Double)?
            for node in nodes {
                let distance = Geo.distanceMeters(from: event.coordinate, to: node.coordinate)
                guard distance <= withinM else { continue }
                if nearest == nil || distance < nearest!.distance {
                    nearest = (node, distance)
                }
            }
            guard let nearest else { return event }
            var updated = event
            updated.matchedOSMNode = nearest.node.id
            switch nearest.node.kind {
            case .stopSign: updated.cause = .stopSign
            case .signal: updated.cause = .signal
            }
            return updated
        }
    }
}
