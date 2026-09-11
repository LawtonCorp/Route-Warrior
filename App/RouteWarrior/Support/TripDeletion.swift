import Foundation
import RouteWarriorStore
import SwiftData

/// What deleting a trip takes with it (D-058). A trip owns rows no
/// other screen will ever clean up: the departure snapshots taken for
/// it, and one tick of its route's drive count. Pure, so the rule is
/// tested without a store; `apply` does the SwiftData work.
enum TripDeletion {
    /// The parts of a trip this decision reads.
    struct Facts: Equatable {
        var id: UUID
        var snapshotID: UUID?
        var altSnapshotID: UUID?
        var variantID: UUID?

        init(id: UUID, snapshotID: UUID? = nil, altSnapshotID: UUID? = nil, variantID: UUID? = nil) {
            self.id = id
            self.snapshotID = snapshotID
            self.altSnapshotID = altSnapshotID
            self.variantID = variantID
        }

        init(_ record: TripRecord) {
            self.init(
                id: record.id,
                snapshotID: record.snapshotID,
                altSnapshotID: record.altSnapshotID,
                variantID: record.variantID
            )
        }
    }

    struct Plan: Equatable {
        /// Snapshots no remaining trip refers to.
        var snapshotIDs: Set<UUID> = []
        /// The route whose drive count loses one.
        var variantID: UUID?
        /// True when this was the last drive on that route, so the
        /// route itself goes too.
        var removesVariant = false
    }

    /// `others` is every trip that will still exist afterwards.
    static func plan(deleting trip: Facts, others: [Facts]) -> Plan {
        var plan = Plan()
        let kept = others.filter { $0.id != trip.id }
        let stillReferenced = Set(kept.flatMap { [$0.snapshotID, $0.altSnapshotID].compactMap { $0 } })
        for id in [trip.snapshotID, trip.altSnapshotID].compactMap({ $0 }) where !stillReferenced.contains(id) {
            plan.snapshotIDs.insert(id)
        }
        if let variantID = trip.variantID {
            plan.variantID = variantID
            plan.removesVariant = !kept.contains { $0.variantID == variantID }
        }
        return plan
    }

    /// Deletes the trip and everything the plan names, and saves.
    @MainActor
    static func delete(_ record: TripRecord, in context: ModelContext) {
        let others = (try? context.fetch(FetchDescriptor<TripRecord>()))?.map(Facts.init) ?? []
        let plan = plan(deleting: Facts(record), others: others)

        if !plan.snapshotIDs.isEmpty,
           let snapshots = try? context.fetch(FetchDescriptor<SnapshotRecord>()) {
            for snapshot in snapshots where plan.snapshotIDs.contains(snapshot.id) {
                context.delete(snapshot)
            }
        }
        if let variantID = plan.variantID,
           let variants = try? context.fetch(FetchDescriptor<VariantRecord>()),
           let variant = variants.first(where: { $0.id == variantID }) {
            if plan.removesVariant {
                context.delete(variant)
            } else {
                variant.tripCount = max(0, variant.tripCount - 1)
            }
        }
        context.delete(record)
        try? context.save()
    }
}
