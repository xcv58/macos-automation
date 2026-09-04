import Foundation
import SDImportCore
import XCTest
@testable import SDImportCommerce

@MainActor
final class PurchaseManagerOrchestrationTests: XCTestCase {
    func testRefreshUnlocksBeforeSlowProductMetadataReturns() async {
        let manager = makeManager(storefront: PurchaseStorefront(
            loadProduct: { _ in
                try await Task.sleep(for: .seconds(1))
                return nil
            },
            currentEntitlement: { _ in .entitled },
            latestEntitlement: { _ in .notEntitled },
            sync: {},
            entitlementLookupTimeout: .milliseconds(50),
            productLoadTimeout: .milliseconds(100),
            restoreSyncTimeout: .milliseconds(100)
        ))

        let refresh = Task { @MainActor in
            await manager.refreshStoreState()
        }
        for _ in 0..<20 where !manager.hasLifetimeUnlock {
            try? await Task.sleep(for: .milliseconds(2))
        }

        XCTAssertTrue(manager.hasLifetimeUnlock)
        await refresh.value
        XCTAssertTrue(manager.hasLifetimeUnlock)
        XCTAssertEqual(manager.accessState.purchaseStatus, .purchased)
    }

    func testRefreshFallsBackToLatestTransactionBeforeLoadingProduct() async {
        let manager = makeManager(storefront: PurchaseStorefront(
            loadProduct: { _ in
                StoreProductSnapshot(
                    product: nil,
                    displayName: "SD Import Unlimited",
                    displayPrice: "$9.99",
                    isFamilyShareable: true
                )
            },
            currentEntitlement: { _ in .notEntitled },
            latestEntitlement: { _ in .entitled },
            sync: {},
            entitlementLookupTimeout: .milliseconds(50),
            productLoadTimeout: .milliseconds(50),
            restoreSyncTimeout: .milliseconds(50)
        ))

        await manager.refreshStoreState()

        XCTAssertTrue(manager.hasLifetimeUnlock)
        XCTAssertEqual(manager.accessState.purchaseStatus, .purchased)
        XCTAssertEqual(manager.productDisplayPrice, "$9.99")
        XCTAssertTrue(manager.isFamilyShareable)
    }

    func testRefreshDoesNotRegrantRevokedEntitlementFromStaleLatestTransaction() async {
        let recorder = StorefrontCallRecorder()
        let manager = makeManager(storefront: PurchaseStorefront(
            loadProduct: { _ in
                StoreProductSnapshot(
                    product: nil,
                    displayName: "SD Import Unlimited",
                    displayPrice: "$9.99",
                    isFamilyShareable: true
                )
            },
            currentEntitlement: { _ in
                recorder.currentEntitlementCalls += 1
                return recorder.currentEntitlementCalls == 1 ? .entitled : .notEntitled
            },
            latestEntitlement: { _ in
                recorder.latestEntitlementCalls += 1
                return .entitled
            },
            sync: {},
            entitlementLookupTimeout: .milliseconds(50),
            productLoadTimeout: .milliseconds(50),
            restoreSyncTimeout: .milliseconds(50)
        ))

        await manager.refreshStoreState()
        XCTAssertTrue(manager.hasLifetimeUnlock)

        await manager.refreshStoreState()

        XCTAssertFalse(manager.hasLifetimeUnlock)
        XCTAssertEqual(manager.accessState.purchaseStatus, .available)
        XCTAssertEqual(recorder.latestEntitlementCalls, 0)
    }

    func testRestoreUsesExistingEntitlementWithoutAuthenticatedSync() async {
        let recorder = StorefrontCallRecorder()
        let manager = makeManager(storefront: PurchaseStorefront(
            loadProduct: { _ in nil },
            currentEntitlement: { _ in .entitled },
            latestEntitlement: { _ in .notEntitled },
            sync: {
                recorder.syncCalls += 1
            },
            entitlementLookupTimeout: .milliseconds(50),
            productLoadTimeout: .milliseconds(50),
            restoreSyncTimeout: .milliseconds(50)
        ))

        await manager.restorePurchases()

        XCTAssertTrue(manager.hasLifetimeUnlock)
        XCTAssertEqual(manager.accessState.purchaseStatus, .purchased)
        XCTAssertEqual(recorder.syncCalls, 0)
    }

    func testRestoreSyncTimeoutReturnsControlWithRetryMessage() async {
        let manager = makeManager(storefront: PurchaseStorefront(
            loadProduct: { _ in nil },
            currentEntitlement: { _ in .notEntitled },
            latestEntitlement: { _ in .notEntitled },
            sync: {
                try await Task.sleep(for: .seconds(10))
            },
            entitlementLookupTimeout: .milliseconds(50),
            productLoadTimeout: .milliseconds(50),
            restoreSyncTimeout: .milliseconds(20)
        ))

        await manager.restorePurchases()

        XCTAssertFalse(manager.hasLifetimeUnlock)
        XCTAssertEqual(
            manager.accessState.purchaseStatus,
            .failed("The App Store did not finish restoring purchases. Your purchase is safe; try again.")
        )
        XCTAssertFalse(manager.isPerformingStoreOperation)
    }

    func testRestoreVerificationFailureNeverUnlocksOrStartsSync() async {
        let recorder = StorefrontCallRecorder()
        let manager = makeManager(storefront: PurchaseStorefront(
            loadProduct: { _ in nil },
            currentEntitlement: { _ in .verificationFailed },
            latestEntitlement: { _ in .entitled },
            sync: {
                recorder.syncCalls += 1
            },
            entitlementLookupTimeout: .milliseconds(50),
            productLoadTimeout: .milliseconds(50),
            restoreSyncTimeout: .milliseconds(50)
        ))

        await manager.restorePurchases()

        XCTAssertFalse(manager.hasLifetimeUnlock)
        XCTAssertEqual(manager.accessState.purchaseStatus, .verificationFailed)
        XCTAssertEqual(recorder.syncCalls, 0)
    }

    func testProductTimeoutDoesNotLeavePurchaseLoadingForever() async {
        let manager = makeManager(storefront: PurchaseStorefront(
            loadProduct: { _ in
                try await Task.sleep(for: .seconds(10))
                return nil
            },
            currentEntitlement: { _ in .notEntitled },
            latestEntitlement: { _ in .notEntitled },
            sync: {},
            entitlementLookupTimeout: .milliseconds(50),
            productLoadTimeout: .milliseconds(20),
            restoreSyncTimeout: .milliseconds(50)
        ))

        await manager.refreshStoreState()

        XCTAssertFalse(manager.hasLifetimeUnlock)
        XCTAssertEqual(
            manager.accessState.purchaseStatus,
            .failed("Purchase information is taking longer than expected. Try again.")
        )
        XCTAssertFalse(manager.isPerformingStoreOperation)
    }

    private func makeManager(storefront: PurchaseStorefront) -> PurchaseManager {
        let suiteName = "PurchaseManagerOrchestrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return PurchaseManager(
            defaults: defaults,
            distribution: .macAppStore,
            startsStoreTask: false,
            storefront: storefront
        )
    }
}

@MainActor
private final class StorefrontCallRecorder {
    var syncCalls = 0
    var currentEntitlementCalls = 0
    var latestEntitlementCalls = 0
}
