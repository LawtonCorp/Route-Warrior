import Foundation
import RouteWarriorKit
import StoreKit

/// StoreKit 2 subscription state (FR-16/FR-17). The only authority on the
/// user's tier; TierPolicy (kit) decides what that tier may do. Enforced
/// on-device — no server (NFR-1).
@MainActor
@Observable
final class StoreService {
    static let monthlyID = "com.lawtoncorp.routewarrior.pro.monthly"
    static let annualID = "com.lawtoncorp.routewarrior.pro.annual"

    private(set) var tier: TierPolicy.Tier = .free
    private(set) var products: [Product] = []
    private(set) var lastError: String?
    let policy = TierPolicy()

    private var updatesTask: Task<Void, Never>?

    func start() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.monthlyID, Self.annualID])
                .sorted { $0.price < $1.price }
        } catch {
            lastError = "Could not load products: \(error.localizedDescription)"
        }
    }

    func refreshEntitlement() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.monthlyID || transaction.productID == Self.annualID,
               transaction.revocationDate == nil {
                pro = true
            }
        }
        tier = pro ? .pro : .free
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
            }
            await refreshEntitlement()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }
}
