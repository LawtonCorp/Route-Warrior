import Foundation
import Testing
@testable import RouteWarriorKit

/// The fixture is hand-written to the published Overpass JSON schema
/// (`elements` of typed nodes with `tags`). Corridor geometry sits on the
/// equator: 0.0001° of latitude ≈ 11 m, so in/out-of-corridor calls are
/// hand-checkable.
struct OverpassTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let route = Polyline(coordinates: [
        Coordinate(latitude: 0, longitude: 0),
        Coordinate(latitude: 0, longitude: 1),
    ])

    private var fixture: Data {
        Data("""
        {
          "elements": [
            {"type": "node", "id": 101, "lat": 0.0001, "lon": 0.5, "tags": {"highway": "stop"}},
            {"type": "node", "id": 102, "lat": 0.0, "lon": 0.2, "tags": {"highway": "traffic_signals"}},
            {"type": "node", "id": 103, "lat": 0.01, "lon": 0.5, "tags": {"highway": "traffic_signals"}},
            {"type": "node", "id": 104, "lat": 0.0, "lon": 0.7, "tags": {"highway": "crossing"}},
            {"type": "node", "id": 105, "lat": 0.0, "lon": 0.8},
            {"type": "way", "id": 106}
          ]
        }
        """.utf8)
    }

    @Test func parsesOnlyStopAndSignalNodes() throws {
        let nodes = try Overpass.nodes(fromResponseData: fixture)
        #expect(nodes.map(\.id) == [101, 102, 103])
        #expect(nodes[0].kind == .stopSign)
        #expect(nodes[1].kind == .signal)
    }

    @Test func malformedResponseThrows() {
        #expect(throws: Overpass.ParseError.malformed) {
            try Overpass.nodes(fromResponseData: Data("not json".utf8))
        }
    }

    @Test func inventoryCountsOnlyTheCorridor() throws {
        let nodes = try Overpass.nodes(fromResponseData: fixture)
        let inventory = Overpass.inventory(nodes: nodes, along: route, fetchedAt: t0)
        // Node 101 is ~11 m off the line (in), 102 is on it (in),
        // 103 is ~1.1 km off (out).
        #expect(inventory.stopSignCount == 1)
        #expect(inventory.signalCount == 1)
        #expect(inventory.coverageConfidence == .high)
        #expect(inventory.fetchedAt == t0)
    }

    @Test func coverageConfidenceGrades() {
        let signalOnly = [Overpass.Node(id: 1, coordinate: Coordinate(latitude: 0, longitude: 0.5), kind: .signal)]
        #expect(Overpass.inventory(nodes: signalOnly, along: route, fetchedAt: t0).coverageConfidence == .medium)
        #expect(Overpass.inventory(nodes: [], along: route, fetchedAt: t0).coverageConfidence == .low)
    }

    @Test func boundingBoxPadsInMeters() {
        let box = Overpass.boundingBox(of: route, paddingM: 400)
        #expect(box != nil)
        let pad = 400.0 / 111_195.08
        #expect(abs(box!.south - (-pad)) < 0.0001)
        #expect(abs(box!.north - pad) < 0.0001)
        #expect(abs(box!.west - (-pad)) < 0.0001)
        #expect(abs(box!.east - (1 + pad)) < 0.0001)
        #expect(Overpass.boundingBox(of: Polyline(coordinates: []), paddingM: 400) == nil)
    }

    @Test func queryTargetsStopsAndSignals() {
        let query = Overpass.query(forCorridorOf: route)
        #expect(query != nil)
        #expect(query!.contains("traffic_signals"))
        #expect(query!.contains("[out:json]"))
        #expect(Overpass.query(forCorridorOf: Polyline(coordinates: [])) == nil)
    }
}

struct StopClassifierTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(at coordinate: Coordinate, cause: StopEvent.Cause) -> StopEvent {
        StopEvent(coordinate: coordinate, startedAt: t0, duration: 20, cause: cause)
    }

    @Test func nearbyNodeOverridesTheDurationPrior() {
        // A 20 s halt reads as a signal by duration — but it sits ~10 m
        // from a mapped stop sign.
        let events = [event(at: Coordinate(latitude: 0, longitude: 0.5), cause: .signal)]
        let nodes = [
            Overpass.Node(id: 7, coordinate: Coordinate(latitude: 0.00009, longitude: 0.5), kind: .stopSign),
        ]
        let classified = StopClassifier.classify(events, near: nodes)
        #expect(classified[0].cause == .stopSign)
        #expect(classified[0].matchedOSMNode == 7)
    }

    @Test func distantNodesLeaveEventsUntouched() {
        let events = [event(at: Coordinate(latitude: 0, longitude: 0.5), cause: .signal)]
        let nodes = [
            Overpass.Node(id: 7, coordinate: Coordinate(latitude: 0.001, longitude: 0.5), kind: .stopSign),
        ]
        let classified = StopClassifier.classify(events, near: nodes)
        #expect(classified[0].cause == .signal)
        #expect(classified[0].matchedOSMNode == nil)
    }

    @Test func nearestOfSeveralNodesWins() {
        let events = [event(at: Coordinate(latitude: 0, longitude: 0.5), cause: .unknown)]
        let nodes = [
            Overpass.Node(id: 1, coordinate: Coordinate(latitude: 0.0002, longitude: 0.5), kind: .stopSign),
            Overpass.Node(id: 2, coordinate: Coordinate(latitude: 0.00005, longitude: 0.5), kind: .signal),
        ]
        let classified = StopClassifier.classify(events, near: nodes)
        #expect(classified[0].cause == .signal)
        #expect(classified[0].matchedOSMNode == 2)
    }
}
