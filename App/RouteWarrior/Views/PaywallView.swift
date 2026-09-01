import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Route Warrior Pro")
                            .font(.title2.bold())
                        featureRow("infinity", "Unlimited trip history")
                        featureRow("mappin.and.ellipse", "Analytics on every destination")
                        featureRow("flag.checkered", "The ghost race — beat your best, live")
                        featureRow("chart.bar.xaxis", "Full verdicts, heatmaps, and trends")
                        Text("Recording is always free — your history keeps building either way.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
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
                                VStack(alignment: .leading) {
                                    Text(product.displayName)
                                    Text(product.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(product.displayPrice)
                                    .bold()
                            }
                        }
                    }
                } footer: {
                    if let error = store.lastError {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Restore purchases") {
                        Task {
                            await store.restore()
                            if store.tier == .pro { dismiss() }
                        }
                    }
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

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
        }
        .font(.subheadline)
    }
}
