import RouteWarriorStore
import StoreKit
import SwiftData
import SwiftUI

/// The Pro paywall (FR-17, D-050): what Pro adds, what is already
/// recorded and waiting behind the gate, counted, and the two plans with
/// their trials spelled out.
struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var trips: [TripRecord]
    @Query(sort: \PlaceRecord.createdAt) private var places: [PlaceRecord]

    private var locked: LockedDataSummary {
        LockedDataSummary.compute(
            trips: trips.map { LockedDataSummary.TripFacts($0) },
            placeIDs: places.map(\.id),
            policy: store.policy
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            IconTile(symbol: "star.fill", color: Theme.pro, size: 40)
                            Text("Route Rebel Pro")
                                .font(.title2.bold())
                        }
                        featureRow("g.circle.fill", Theme.google, "Google's plan on the scoreboard — beat both")
                        featureRow("infinity", Theme.route, "Every drive you have ever recorded")
                        featureRow("mappin.and.ellipse", Theme.win, "Analytics on every destination")
                        featureRow("chart.bar.xaxis", Theme.google, "Heatmaps, trends, and your routes raced")
                        featureRow("octagon.fill", Theme.recording, "Every stop and turn on every drive")
                        featureRow("flag.checkered", Theme.pro, "The ghost race, live drive view, reroute")
                        Text("Recording is always free — your history keeps building either way.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .tintedRow(Theme.pro)
                }

                let lines = PaywallText.lockedLines(locked, historyDays: store.policy.limits.historyDays)
                if !lines.isEmpty {
                    Section {
                        ForEach(lines, id: \.self) { line in
                            Label {
                                Text(line)
                            } icon: {
                                Image(systemName: "lock.open.fill")
                                    .foregroundStyle(Theme.pro)
                            }
                        }
                    } header: {
                        Text("Already recorded, waiting in Pro")
                    }
                }

                Section {
                    if store.products.isEmpty {
                        Text("Loading plans…")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.products, id: \.id) { product in
                        Button {
                            Task {
                                await store.purchase(product)
                                if store.tier == .pro { dismiss() }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(product.displayName)
                                    Text(priceLine(product))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(product.displayPrice)
                                    .bold()
                                    .foregroundStyle(Theme.pro)
                            }
                        }
                        .tint(.primary)
                    }
                } footer: {
                    if let error = store.lastError {
                        Text(error).foregroundStyle(Theme.recording)
                    } else {
                        Text("Cancel any time in Settings. A trial converts to the plan unless cancelled before it ends.")
                    }
                }

                Section {
                    Button("Restore purchases") {
                        Task {
                            await store.restore()
                            if store.tier == .pro { dismiss() }
                        }
                    }
                    Link("Terms of Use", destination: Legal.termsURL)
                    Link("Privacy Policy", destination: Legal.privacyURL)
                }
            }
            .navigationTitle("Go Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    /// "7 days free, then $24.99 per year", from StoreKit's parts.
    private func priceLine(_ product: Product) -> String {
        let period: String
        switch product.subscription?.subscriptionPeriod.unit {
        case .year?: period = "year"
        case .month?: period = "month"
        case .week?: period = "week"
        case .day?: period = "day"
        default: period = "period"
        }
        var trialDays: Int?
        if let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            let unitDays: Int
            switch offer.period.unit {
            case .week: unitDays = 7
            case .month: unitDays = 30
            case .year: unitDays = 365
            default: unitDays = 1
            }
            trialDays = offer.period.value * unitDays
        }
        return PaywallText.priceLine(displayPrice: product.displayPrice, period: period, trialDays: trialDays)
    }

    private func featureRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text)
        }
        .font(.subheadline)
    }
}
