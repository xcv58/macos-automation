import Foundation

/// Owns app-activation callbacks independently of any SwiftUI window lifetime.
@MainActor
public final class ApplicationLifecycleCoordinator {
    public static let shared = ApplicationLifecycleCoordinator()

    private var didBecomeActiveHandler: (() -> Void)?
    private var mainWindowWillPresentHandler: (() -> Void)?
    private var mainWindowDidAppearHandler: (() -> Void)?

    public init() {}

    public func install(
        didBecomeActive: @escaping () -> Void,
        mainWindowWillPresent: @escaping () -> Void,
        mainWindowDidAppear: @escaping () -> Void
    ) {
        didBecomeActiveHandler = didBecomeActive
        mainWindowWillPresentHandler = mainWindowWillPresent
        mainWindowDidAppearHandler = mainWindowDidAppear
    }

    public func applicationDidBecomeActive() {
        didBecomeActiveHandler?()
    }

    public func mainWindowWillPresent() {
        mainWindowWillPresentHandler?()
    }

    public func mainWindowDidAppear() {
        mainWindowDidAppearHandler?()
    }
}
