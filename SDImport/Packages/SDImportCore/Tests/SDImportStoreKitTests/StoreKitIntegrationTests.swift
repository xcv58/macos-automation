import Foundation
import StoreKit
import StoreKitTest
import XCTest
@testable import SDImportForMac

@MainActor
final class StoreKitIntegrationTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "SDImport")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session.clearTransactions()
        session = nil
    }

    func testLocalConfigurationDefinesLifetimeProduct() async throws {
        let product = try await requireRuntimeProduct()

        XCTAssertEqual(product.id, "media.jenny.sdimport.unlimited")
        XCTAssertEqual(product.type, .nonConsumable)
        XCTAssertEqual(product.displayName, "SD Import Unlimited")
        XCTAssertFalse(product.isFamilyShareable)
    }

    func testPurchaseRestoreAndRefundLifecycle() async throws {
        let purchased = makeManager(label: "purchase")
        await purchased.refreshStoreState()
        XCTAssertNotNil(purchased.productDisplayPrice)

        await purchased.purchase()
        XCTAssertTrue(purchased.hasLifetimeUnlock)
        XCTAssertEqual(purchased.purchaseStatus, .purchased)

        let transaction = try XCTUnwrap(session.allTransactions().last)
        try session.refundTransaction(identifier: transaction.identifier)
        let refunded = await waitForState(
            purchased,
            matching: { !$0.hasLifetimeUnlock }
        )
        XCTAssertNotNil(refunded)

        session.clearTransactions()
        let restorablePurchase = makeManager(label: "restorable-purchase")
        await restorablePurchase.refreshStoreState()
        await restorablePurchase.purchase()
        XCTAssertTrue(restorablePurchase.hasLifetimeUnlock)

        let restored = makeManager(label: "restore")
        await restored.restorePurchases()
        XCTAssertTrue(restored.hasLifetimeUnlock)
        XCTAssertEqual(restored.purchaseStatus, .purchased)
    }

    func testPendingPurchaseNeverUnlocks() async throws {
        session.askToBuyEnabled = true
        let pending = makeManager(label: "pending")
        await pending.refreshStoreState()
        await pending.purchase()
        XCTAssertFalse(pending.hasLifetimeUnlock)
        XCTAssertEqual(pending.purchaseStatus, .pending)
    }

    func testVerificationFailureNeverUnlocks() async throws {
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        try await session.setSimulatedError(
            .verification(.invalidSignature),
            forAPI: .verification
        )
        let unverified = makeManager(label: "verification")
        await unverified.refreshStoreState()
        await unverified.purchase()
        XCTAssertFalse(unverified.hasLifetimeUnlock)
        XCTAssertEqual(unverified.purchaseStatus, .verificationFailed)
    }

    private func requireRuntimeProduct() async throws -> Product {
        let products = try await Product.products(
            for: [StoreKitTestPurchaseDriver.lifetimeProductIdentifier]
        )
        return try XCTUnwrap(products.first)
    }

    private func makeManager(label: String) -> StoreKitTestPurchaseDriver {
        let suiteName = "StoreKitIntegrationTests.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return StoreKitTestPurchaseDriver(defaults: defaults)
    }

    private func waitForState(
        _ manager: StoreKitTestPurchaseDriver,
        matching predicate: (StoreKitTestPurchaseDriver) -> Bool,
        attempts: Int = 50
    ) async -> StoreKitTestPurchaseDriver? {
        for _ in 0..<attempts {
            await manager.refreshStoreState()
            if predicate(manager) {
                return manager
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

}
