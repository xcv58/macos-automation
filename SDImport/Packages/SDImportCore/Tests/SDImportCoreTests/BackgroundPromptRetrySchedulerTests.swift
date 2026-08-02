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
    func scheduledRetryWaitsForDelay() async throws {
        let sleeper = ControlledRetrySleeper()
        let scheduler = BackgroundPromptRetryScheduler { duration in
            try await sleeper.sleep(duration)
        }
        let operationCompleted = AsyncTestSignal()
        var operationCount = 0

        scheduler.schedule(after: 300) {
            operationCount += 1
            operationCompleted.signal()
        }
        try await waitWithinTimeout {
            await sleeper.waitUntilPending()
        }
        #expect(operationCount == 0)

        await sleeper.resume()
        try await waitWithinTimeout {
            await operationCompleted.wait()
        }
        #expect(operationCount == 1)
    }

    @Test("a replacement retry cancels the previous schedule")
    func replacementCancelsPreviousRetry() async throws {
        let scheduler = BackgroundPromptRetryScheduler { _ in
            try await Task.sleep(for: .seconds(60))
        }
        let operationCompleted = AsyncTestSignal()
        var operationCount = 0

        scheduler.schedule(after: 60) {
            operationCount += 1
        }
        scheduler.schedule(after: 0) {
            operationCount += 10
            operationCompleted.signal()
        }
        try await waitWithinTimeout {
            await operationCompleted.wait()
        }

        #expect(operationCount == 10)
    }
}

private actor ControlledRetrySleeper {
    private var continuation: CheckedContinuation<Void, any Error>?
    private let sleepStarted = AsyncTestSignal()

    func sleep(_ duration: Duration) async throws {
        sleepStarted.signal()
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilPending() async {
        await sleepStarted.wait()
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private final class AsyncTestSignal: @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        let pair = AsyncStream<Void>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func signal() {
        continuation.yield()
        continuation.finish()
    }

    func wait() async {
        for await _ in stream {
            return
        }
    }
}

private enum AsyncTestTimeout: Error {
    case expired
}

private func waitWithinTimeout(
    _ operation: @escaping @Sendable () async -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(2))
            throw AsyncTestTimeout.expired
        }
        _ = try await group.next()
        group.cancelAll()
    }
}
