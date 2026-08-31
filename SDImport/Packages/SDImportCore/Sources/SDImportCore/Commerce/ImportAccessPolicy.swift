import Foundation

public enum ImportPurchaseStatus: Equatable, Sendable {
    case idle
    case loading
    case available
    case purchasing
    case pending
    case purchased
    case cancelled
    case verificationFailed
    case unavailable
    case failed(String)
}

public enum ImportPurchaseOutcome: Equatable, Sendable {
    case productAvailable
    case productUnavailable
    case purchased
    case restored
    case pending
    case cancelled
    case verificationFailed
    case revoked
    case failed(String)
}

public struct ImportAccessState: Equatable, Sendable {
    public private(set) var hasLifetimeUnlock: Bool
    public private(set) var completedFreeImports: Int
    public private(set) var purchaseStatus: ImportPurchaseStatus

    public init(
        hasLifetimeUnlock: Bool = false,
        completedFreeImports: Int = 0,
        purchaseStatus: ImportPurchaseStatus = .idle
    ) {
        self.hasLifetimeUnlock = hasLifetimeUnlock
        self.completedFreeImports = max(0, completedFreeImports)
        self.purchaseStatus = purchaseStatus
    }

    public func canStartImport(distribution: AppDistribution) -> Bool {
        distribution == .direct || hasLifetimeUnlock || completedFreeImports == 0
    }

    public func remainingFreeImports(distribution: AppDistribution) -> Int? {
        distribution == .direct ? nil : max(0, 1 - completedFreeImports)
    }

    public mutating func beginLoading() {
        purchaseStatus = .loading
    }

    public mutating func beginPurchase() {
        purchaseStatus = .purchasing
    }

    public mutating func apply(_ outcome: ImportPurchaseOutcome) {
        switch outcome {
        case .productAvailable:
            purchaseStatus = hasLifetimeUnlock ? .purchased : .available
        case .productUnavailable:
            purchaseStatus = .unavailable
        case .purchased, .restored:
            hasLifetimeUnlock = true
            purchaseStatus = .purchased
        case .pending:
            purchaseStatus = .pending
        case .cancelled:
            purchaseStatus = .cancelled
        case .verificationFailed:
            purchaseStatus = .verificationFailed
        case .revoked:
            hasLifetimeUnlock = false
            purchaseStatus = .available
        case .failed(let message):
            purchaseStatus = .failed(message)
        }
    }

    @discardableResult
    public mutating func recordSuccessfulImport(_ result: ImportResult) -> Bool {
        guard result.importedFiles > 0, result.failedFiles == 0 else {
            return false
        }
        completedFreeImports = max(1, completedFreeImports)
        return true
    }
}
