import Foundation
import Testing

@testable import SDImportCore

@Suite("Background prompt retry scheduler")
@MainActor
struct BackgroundPromptRetrySchedulerTests {
    @Test("scheduled health repair revalidates enabled ownership state")
    func scheduledHealthRepairRevalidatesState() {
        #expect(
            BackgroundPromptScheduledRepairPolicy.canContinueRegistration(
                desiredEnabled: true,
                hasCompletedOnboarding: true,
                currentApplicationIsAuthoritative: true
            )
        )
        #expect(
            !BackgroundPromptScheduledRepairPolicy.canContinueRegistration(
                desiredEnabled: true,
                hasCompletedOnboarding: true,
                currentApplicationIsAuthoritative: false
            )
        )
        #expect(
            !BackgroundPromptScheduledRepairPolicy.canContinueRegistration(
                desiredEnabled: false,
                hasCompletedOnboarding: true,
                currentApplicationIsAuthoritative: true
            )
        )
        #expect(
            BackgroundPromptScheduledRepairPolicy.shouldRunMissingHelperRepair(
                desiredEnabled: true,
                hasCompletedOnboarding: true,
                canConfigure: true,
                serviceStatus: .enabled,
                ownsRegistration: false
            )
        )
        #expect(
            !BackgroundPromptScheduledRepairPolicy.shouldRunMissingHelperRepair(
                desiredEnabled: false,
                hasCompletedOnboarding: true,
                canConfigure: true,
                serviceStatus: .enabled,
                ownsRegistration: false
            )
        )
        #expect(
            !BackgroundPromptScheduledRepairPolicy.shouldRunMissingHelperRepair(
                desiredEnabled: true,
                hasCompletedOnboarding: true,
                canConfigure: false,
                serviceStatus: .enabled,
                ownsRegistration: false
            )
        )
        #expect(
            !BackgroundPromptScheduledRepairPolicy.shouldRunMissingHelperRepair(
                desiredEnabled: true,
                hasCompletedOnboarding: true,
                canConfigure: true,
                serviceStatus: .enabled,
                ownsRegistration: true
            )
        )
        #expect(
            !BackgroundPromptScheduledRepairPolicy.shouldRunMissingHelperRepair(
                desiredEnabled: true,
                hasCompletedOnboarding: true,
                canConfigure: true,
                serviceStatus: .notRegistered,
                ownsRegistration: false
            )
        )
    }

    @Test("scheduled retry runs only after its delay completes")
    func scheduledRetryWaitsForDelay() async {
        let sleeper = ControlledRetrySleeper()
        let scheduler = BackgroundPromptRetryScheduler { duration in
            try await sleeper.sleep(duration)
        }
        var operationCount = 0

        scheduler.schedule(after: 300) {
            operationCount += 1
        }
        while await !sleeper.hasPendingSleep {
            await Task.yield()
        }
        #expect(operationCount == 0)

        await sleeper.resume()
        for _ in 0..<10 where operationCount == 0 {
            await Task.yield()
        }
        #expect(operationCount == 1)
    }

    @Test("a replacement retry cancels the previous schedule")
    func replacementCancelsPreviousRetry() async {
        let scheduler = BackgroundPromptRetryScheduler { _ in
            try await Task.sleep(for: .seconds(60))
        }
        var operationCount = 0

        scheduler.schedule(after: 60) {
            operationCount += 1
        }
        scheduler.schedule(after: 0) {
            operationCount += 10
        }
        for _ in 0..<10 where operationCount == 0 {
            await Task.yield()
        }

        #expect(operationCount == 10)
    }
}

private actor ControlledRetrySleeper {
    private var continuation: CheckedContinuation<Void, any Error>?
    private(set) var hasPendingSleep = false

    func sleep(_ duration: Duration) async throws {
        hasPendingSleep = true
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
        hasPendingSleep = false
    }
}
