import Foundation

public enum BackgroundPromptRetryPolicy {
    public static func remainingDelay(
        lastAttemptAt: Date?,
        now: Date = Date(),
        interval: TimeInterval = BackgroundPromptRegistrationPolicy.notFoundRepairRetryInterval
    ) -> TimeInterval {
        guard let lastAttemptAt else {
            return 0
        }
        return max(0, interval - now.timeIntervalSince(lastAttemptAt))
    }
}

public enum BackgroundPromptScheduledRepairPolicy {
    public static func canContinueRegistration(
        desiredEnabled: Bool,
        hasCompletedOnboarding: Bool,
        currentApplicationIsAuthoritative: Bool
    ) -> Bool {
        desiredEnabled && hasCompletedOnboarding && currentApplicationIsAuthoritative
    }

    public static func shouldRunMissingHelperRepair(
        desiredEnabled: Bool,
        hasCompletedOnboarding: Bool,
        canConfigure: Bool,
        serviceStatus: BackgroundPromptServiceStatus,
        ownsRegistration: Bool
    ) -> Bool {
        desiredEnabled
            && hasCompletedOnboarding
            && canConfigure
            && serviceStatus == .enabled
            && !ownsRegistration
    }
}

@MainActor
public final class BackgroundPromptRetryScheduler {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private let sleep: Sleep
    private var task: Task<Void, Never>?

    public init(
        sleep: @escaping Sleep = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.sleep = sleep
    }

    public func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        cancel()
        let sleep = sleep
        task = Task {
            do {
                if delay > 0 {
                    try await sleep(.seconds(delay))
                }
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await operation()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}
