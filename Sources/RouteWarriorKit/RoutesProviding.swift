import Foundation

/// The seam between the app and any routing provider (FR-5). The production
/// implementation calls the Google Routes API from the app layer; tests and
/// keyless builds substitute stubs. The kit defines the contract and the
/// response parsing so both are CI-testable without a network.
public protocol RoutesProviding: Sendable {
    /// Snapshot the provider's plan for a departure happening now.
    /// Throwing means "no comparison for this trip" — recording never
    /// depends on it (FR-3/FR-6).
    func computeSnapshot(
        from origin: Coordinate,
        to destination: Coordinate,
        destinationPlaceID: UUID?
    ) async throws -> PlanSnapshot
}

/// Parsing for Google Routes API `computeRoutes` v2 responses.
public enum GoogleRoutes {
    public enum ParseError: Error, Equatable {
        case noRoutes
        case missingPolyline
        case malformedDuration(String)
    }

    /// Field mask the client requests — parsing expects exactly these.
    public static let fieldMask =
        "routes.distanceMeters,routes.duration,routes.staticDuration,routes.polyline.encodedPolyline"

    public static func snapshot(
        fromResponseData data: Data,
        requestedAt: Date,
        destinationPlaceID: UUID? = nil
    ) throws -> PlanSnapshot {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let routes = response.routes, let primary = routes.first else {
            throw ParseError.noRoutes
        }
        guard let encoded = primary.polyline?.encodedPolyline,
              let polyline = Polyline.decode(encoded)
        else {
            throw ParseError.missingPolyline
        }
        let traffic = try seconds(primary.duration ?? "")
        let stat = primary.staticDuration.map { try? seconds($0) }.flatMap { $0 } ?? traffic

        var alternates: [PlanSnapshot.AltRoute] = []
        for route in routes.dropFirst() {
            guard let altEncoded = route.polyline?.encodedPolyline,
                  let altPolyline = Polyline.decode(altEncoded),
                  let altTraffic = try? seconds(route.duration ?? "")
            else { continue }
            let altStatic = route.staticDuration.map { try? seconds($0) }.flatMap { $0 } ?? altTraffic
            alternates.append(.init(
                polyline: altPolyline,
                staticDuration: altStatic,
                trafficDuration: altTraffic
            ))
        }

        return PlanSnapshot(
            requestedAt: requestedAt,
            destinationPlaceID: destinationPlaceID,
            polyline: polyline,
            distanceM: primary.distanceMeters ?? polyline.lengthMeters,
            staticDuration: stat,
            trafficDuration: traffic,
            alternates: alternates
        )
    }

    /// Google encodes durations as decimal seconds with an "s" suffix
    /// ("723s", "723.5s").
    static func seconds(_ value: String) throws -> TimeInterval {
        guard value.hasSuffix("s"), let seconds = Double(value.dropLast()) else {
            throw ParseError.malformedDuration(value)
        }
        return seconds
    }

    private struct Response: Decodable {
        var routes: [Route]?
    }

    private struct Route: Decodable {
        var distanceMeters: Double?
        var duration: String?
        var staticDuration: String?
        var polyline: EncodedPolyline?
    }

    private struct EncodedPolyline: Decodable {
        var encodedPolyline: String?
    }
}
