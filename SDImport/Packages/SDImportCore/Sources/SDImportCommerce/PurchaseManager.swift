import Combine
import Foundation
import SDImportCore
import StoreKit

@MainActor
public final class PurchaseManager: ObservableObject {
    private enum DefaultsKey {
        static let completedFreeImports = "SDImport.purchase.completedFreeImports"
    }

    @Published public private(set) var accessState: ImportAccessState
    @Published public var isShowingPurchase = false
    @Published public private(set) var productDisplayName = "SD Import Unlimited"
    @Published public private(set) var productDisplayPrice: String?

    private let defaults: UserDefaults
    private let distribution: AppDistribution
    private var product: Product?
    private var updatesTask: Task<Void, Never>?
    private var initialStoreRefreshTask: Task<Void, Never>?
    private var entitlementRevision: UInt64 = 0

    public init(
        defaults: UserDefaults = .standard,
        distribution: AppDistribution = .current,
        startsStoreTask: Bool = true
    ) {
        self.defaults = defaults
        self.distribution = distribution
        accessState = ImportAccessState(
            completedFreeImports: defaults.integer(forKey: DefaultsKey.completedFreeImports)
        )
        let isHostedTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if distribution == .macAppStore, startsStoreTask, !isHostedTest {
            startObservingTransactions()
        }
    }

    deinit {
        updatesTask?.cancel()
        initialStoreRefreshTask?.cancel()
    }

    public var isMacAppStoreEdition: Bool {
        distribution == .macAppStore
    }

    public var canStartImport: Bool {
        accessState.canStartImport(distribution: distribution)
    }

    public var hasLifetimeUnlock: Bool {
        accessState.hasLifetimeUnlock
    }

    public var isPerformingStoreOperation: Bool {
        switch accessState.purchaseStatus {
        case .loading, .purchasing:
            true
        default:
            false
        }
    }

    public var allowanceSummary: String {
        if accessState.hasLifetimeUnlock {
            return "Lifetime access unlocked"
        }
        if accessState.remainingFreeImports(distribution: distribution) == 1 {
            return "Your first completed import is free"
        }
        return "The free import has been used"
    }

    public var statusMessage: String? {
        switch accessState.purchaseStatus {
        case .idle, .available, .purchased:
            return nil
        case .loading:
            return "Loading purchase information…"
        case .purchasing:
            return "Completing purchase…"
        case .pending:
            return "Purchase is pending approval."
        case .cancelled:
            return "Purchase cancelled."
        case .verificationFailed:
            return "The App Store transaction could not be verified."
        case .unavailable:
            return "Purchase information is temporarily unavailable."
        case .failed(let message):
            return message
        }
    }

    public func recordSuccessfulImport(_ result: ImportResult) {
        guard
            distribution == .macAppStore,
            !accessState.hasLifetimeUnlock,
            accessState.recordSuccessfulImport(result)
        else {
            return
        }
        defaults.set(
            accessState.completedFreeImports,
            forKey: DefaultsKey.completedFreeImports
        )
    }

    public func purchase() async {
        guard distribution == .macAppStore else {
            return
        }
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            accessState.apply(.productUnavailable)
            return
        }
        accessState.beginPurchase()
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    accessState.apply(.verificationFailed)
                    return
                }
                guard transaction.productID == AppDistribution.lifetimeProductIdentifier else {
                    accessState.apply(.verificationFailed)
                    return
                }
                applyVerifiedLifetimeEntitlement(restored: false)
                await transaction.finish()
            case .pending:
                accessState.apply(.pending)
            case .userCancelled:
                accessState.apply(.cancelled)
            @unknown default:
                accessState.apply(.failed("The App Store returned an unknown purchase result."))
            }
        } catch StoreKitError.userCancelled {
            accessState.apply(.cancelled)
        } catch {
            accessState.apply(.failed(error.localizedDescription))
        }
    }

    public func restorePurchases() async {
        guard distribution == .macAppStore else {
            return
        }
        accessState.beginLoading()
        do {
            try await AppStore.sync()
            if product == nil {
                await loadProduct()
            }
            for attempt in 0..<5 {
                let hasCurrentEntitlement = await refreshEntitlement(restored: true)
                let hasLatestTransaction: Bool
                if
                    hasCurrentEntitlement
                        || accessState.purchaseStatus == .verificationFailed
                {
                    hasLatestTransaction = false
                } else {
                    hasLatestTransaction = await refreshLatestLifetimeTransaction(restored: true)
                }
                if hasCurrentEntitlement || hasLatestTransaction {
                    return
                }
                guard
                    accessState.purchaseStatus != .verificationFailed,
                    attempt < 4
                else {
                    return
                }
                // AppStore.sync() can complete just before the restored
                // transaction becomes visible to currentEntitlements.
                try? await Task.sleep(for: .milliseconds(100))
            }
        } catch StoreKitError.userCancelled {
            accessState.apply(.cancelled)
        } catch {
            accessState.apply(.failed(error.localizedDescription))
        }
    }

    public func refreshStoreState() async {
        accessState.beginLoading()
        await loadProduct()
        await refreshEntitlement(restored: false)
    }

    public func startObservingTransactions() {
        guard distribution == .macAppStore, updatesTask == nil else {
            return
        }
        updatesTask = Task { [weak self] in
            for await verification in Transaction.updates {
                guard !Task.isCancelled else {
                    return
                }
                guard let self else {
                    return
                }
                guard case .verified(let transaction) = verification else {
                    accessState.apply(.verificationFailed)
                    continue
                }
                guard transaction.productID == AppDistribution.lifetimeProductIdentifier else {
                    continue
                }
                if transaction.revocationDate == nil {
                    // The verified update is already authoritative. Re-querying
                    // currentEntitlements here can briefly return the pre-update
                    // snapshot and incorrectly treat a new purchase as revoked.
                    applyVerifiedLifetimeEntitlement(restored: false)
                } else {
                    // A revocation can coexist with another valid transaction, so
                    // resolve the complete entitlement set before locking access.
                    await refreshEntitlement(restored: false)
                }
                await transaction.finish()
            }
        }
        initialStoreRefreshTask = Task { [weak self] in
            await self?.refreshStoreState()
        }
    }

    private func loadProduct() async {
        do {
            product = try await Product.products(
                for: [AppDistribution.lifetimeProductIdentifier]
            ).first
            if let product {
                productDisplayName = product.displayName
                productDisplayPrice = product.displayPrice
                accessState.apply(.productAvailable)
            } else {
                accessState.apply(.productUnavailable)
            }
        } catch {
            accessState.apply(.failed(error.localizedDescription))
        }
    }

    @discardableResult
    func refreshEntitlement(restored: Bool) async -> Bool {
        let startingEntitlementRevision = entitlementRevision
        var isEntitled = false
        var encounteredVerificationFailure = false
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else {
                encounteredVerificationFailure = true
                continue
            }
            if
                transaction.productID == AppDistribution.lifetimeProductIdentifier,
                transaction.revocationDate == nil
            {
                isEntitled = true
            }
        }
        if isEntitled {
            applyVerifiedLifetimeEntitlement(restored: restored)
            return true
        } else if encounteredVerificationFailure {
            accessState.apply(.verificationFailed)
        } else if
            accessState.hasLifetimeUnlock,
            entitlementRevision == startingEntitlementRevision
        {
            // A refresh can overlap a purchase while StoreKit still exposes
            // its earlier entitlement snapshot. Only revoke the state that
            // this refresh actually began checking.
            entitlementRevision &+= 1
            accessState.apply(.revoked)
        } else if product != nil {
            accessState.apply(.productAvailable)
        }
        return false
    }

    private func applyVerifiedLifetimeEntitlement(restored: Bool) {
        entitlementRevision &+= 1
        accessState.apply(restored ? .restored : .purchased)
    }

    private func refreshLatestLifetimeTransaction(restored: Bool) async -> Bool {
        guard
            let verification = await Transaction.latest(
                for: AppDistribution.lifetimeProductIdentifier
            )
        else {
            return false
        }
        guard case .verified(let transaction) = verification else {
            accessState.apply(.verificationFailed)
            return false
        }
        guard
            transaction.productID == AppDistribution.lifetimeProductIdentifier,
            transaction.revocationDate == nil
        else {
            return false
        }
        applyVerifiedLifetimeEntitlement(restored: restored)
        return true
    }
}
