import Testing
@testable import SDImportCore

@Suite("Import access policy")
struct ImportAccessPolicyTests {
    @Test("direct builds remain unlimited")
    func directBuildIsUnlimited() {
        let state = ImportAccessState(completedFreeImports: 99)
        #expect(state.canStartImport(distribution: .direct))
        #expect(state.remainingFreeImports(distribution: .direct) == nil)
    }

    @Test("App Store builds allow exactly one successful free import")
    func freeImportAllowance() {
        var state = ImportAccessState()
        #expect(state.canStartImport(distribution: .macAppStore))
        #expect(state.remainingFreeImports(distribution: .macAppStore) == 1)

        let consumed = state.recordSuccessfulImport(
            ImportResult(
                jobID: "success",
                importedFiles: 3,
                skippedFiles: 0,
                failedFiles: 0,
                progressPath: nil
            )
        )

        #expect(consumed)
        #expect(!state.canStartImport(distribution: .macAppStore))
        #expect(state.remainingFreeImports(distribution: .macAppStore) == 0)
    }

    @Test("empty and failed imports do not consume the allowance", arguments: [
        ImportResult(jobID: "empty", importedFiles: 0, skippedFiles: 2, failedFiles: 0, progressPath: nil),
        ImportResult(jobID: "partial", importedFiles: 2, skippedFiles: 0, failedFiles: 1, progressPath: nil)
    ])
    func unsuccessfulImportDoesNotConsumeAllowance(result: ImportResult) {
        var state = ImportAccessState()
        let consumed = state.recordSuccessfulImport(result)
        #expect(!consumed)
        #expect(state.canStartImport(distribution: .macAppStore))
    }

    @Test("verified purchase and restore unlock while revocation removes entitlement")
    func entitlementLifecycle() {
        var state = ImportAccessState(completedFreeImports: 1)
        state.apply(.purchased)
        #expect(state.canStartImport(distribution: .macAppStore))
        #expect(state.purchaseStatus == .purchased)

        state.apply(.revoked)
        #expect(!state.canStartImport(distribution: .macAppStore))

        state.apply(.restored)
        #expect(state.canStartImport(distribution: .macAppStore))
    }

    @Test("pending cancellation and verification failures never unlock")
    func nonSuccessOutcomesDoNotUnlock() {
        for outcome in [
            ImportPurchaseOutcome.pending,
            .cancelled,
            .verificationFailed,
            .failed("Store unavailable")
        ] {
            var state = ImportAccessState(completedFreeImports: 1)
            state.apply(outcome)
            #expect(!state.hasLifetimeUnlock)
            #expect(!state.canStartImport(distribution: .macAppStore))
        }
    }
}
