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

    /// Owner-build Pro override (D-017). scripts/device-build.sh can inject
    /// `RouteWarriorForcePro` into Info.plist exactly the way it injects the
    /// Google key; the value is empty in CI and in any build made without
    /// the setting, so store builds are unaffected. The override only ever
    /// raises the tier to .pro — a real entitlement is never masked.
    nonisolated static func forcesPro(infoValue: Any?) -> Bool {
        guard let value = infoValue as? String else { return false }
        return value.trimmingCharacters(in: .whitespaces) == "1"
    }

    private nonisolated static var isForcedPro: Bool {
        forcesPro(infoValue: Bundle.main.object(forInfoDictionaryKey: "RouteWarriorForcePro"))
    }

    private(set) var tier: TierPolicy.Tier = StoreService.isForcedPro ? .pro : .free
    private(set) var products: [Product] = []
    private(set) var lastError: String?
    let policy = TierPolicy()

    // Created once at app launch and alive for the process's lifetime, so
    // the updates task never needs cancellation (a nonisolated deinit
    // could not touch this actor-isolated property anyway).
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
        tier = (pro || Self.isForcedPro) ? .pro : .free
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
