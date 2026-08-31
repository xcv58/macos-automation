#if DEBUG
import Foundation
import SDImportCommerce
import SDImportCore

/// Keeps hosted StoreKit tests linked through the app under test. Linking the
/// package products into both the host app and its XCTest bundle would load two
/// copies of their static types in the same process.
@MainActor
final class StoreKitTestPurchaseDriver {
    static let lifetimeProductIdentifier = AppDistribution.lifetimeProductIdentifier

    private let manager: PurchaseManager

    init(defaults: UserDefaults) {
        manager = PurchaseManager(
            defaults: defaults,
            distribution: .macAppStore,
            startsStoreTask: false
        )
        manager.startObservingTransactions()
    }

    var productDisplayPrice: String? {
        manager.productDisplayPrice
    }

    var hasLifetimeUnlock: Bool {
        manager.hasLifetimeUnlock
    }

    var purchaseStatus: ImportPurchaseStatus {
        manager.accessState.purchaseStatus
    }

    func refreshStoreState() async {
        await manager.refreshStoreState()
    }

    func purchase() async {
        await manager.purchase()
    }

    func restorePurchases() async {
        await manager.restorePurchases()
    }
}
#endif
