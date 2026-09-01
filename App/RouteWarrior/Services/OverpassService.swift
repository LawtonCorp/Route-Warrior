import Foundation
import RouteWarriorKit
import RouteWarriorStore
import SwiftData

/// Fetches a variant's stop-sign/signal inventory from Overpass, on demand
/// and once (FR-10). Query building, parsing, corridor counting, and the
/// coverage grade all live in the kit; this is HTTP plus persistence.
/// Failures leave the inventory absent — the UI shows "pending" and the
/// next appearance retries (SPEC §2.6).
@MainActor
final class OverpassService {
    private let session: URLSession
    private var inFlight: Set<UUID> = []

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Public Overpass instance; a self-hosted mirror is the scale
    /// escape hatch (SPEC §2.4).
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    func fetchInventoryIfMissing(for record: VariantRecord, context: ModelContext) async {
        guard record.inventoryFetchedAt == nil, !inFlight.contains(record.id) else { return }
        guard let variant = try? record.variant(),
              let query = Overpass.query(forCorridorOf: variant.representativePolyline)
        else { return }
        inFlight.insert(record.id)
        defer { inFlight.remove(record.id) }

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
            request.httpBody = Data("data=\(encoded)".utf8)
            request.timeoutInterval = 30

            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let nodes = try Overpass.nodes(fromResponseData: data)
            let inventory = Overpass.inventory(
                nodes: nodes,
                along: variant.representativePolyline,
                fetchedAt: .now
            )
            record.signalCount = inventory.signalCount
            record.stopSignCount = inventory.stopSignCount
            record.coverageRaw = inventory.coverageConfidence.rawValue
            record.inventoryFetchedAt = inventory.fetchedAt
            try context.save()
        } catch {
            // Rate limit or outage: stay pending, retry on next appearance.
        }
    }
}
