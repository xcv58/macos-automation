import Foundation

@MainActor
public final class MainWindowPresentationCoordinator {
    public static let shared = MainWindowPresentationCoordinator()

    private var windowOpener: (() -> Void)?
    private var isOpeningWindow = false

    public init() {}

    public func installWindowOpener(_ opener: @escaping () -> Void) {
        windowOpener = opener
    }

    @discardableResult
    public func present(existingWindow: (() -> Void)? = nil) -> PresentationResult {
        if let existingWindow {
            isOpeningWindow = false
            existingWindow()
            return .presentedExistingWindow
        }
        guard !isOpeningWindow else {
            return .openingInProgress
        }
        guard let windowOpener else {
            return .unavailable
        }
        isOpeningWindow = true
        windowOpener()
        return .openedNewWindow
    }

    public func windowDidBecomeAvailable() {
        isOpeningWindow = false
    }

    public enum PresentationResult: Equatable, Sendable {
        case presentedExistingWindow
        case openedNewWindow
        case openingInProgress
        case unavailable
    }
}
