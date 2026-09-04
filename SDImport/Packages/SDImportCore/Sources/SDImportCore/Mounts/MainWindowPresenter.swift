import AppKit
import SwiftUI

@MainActor
public enum MainWindowPresenter {
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("SDImport.main")

    public static func present() {
        let application: NSApplication? = NSApp
        present(
            application: application,
            coordinator: MainWindowPresentationCoordinator.shared
        )
    }

    @discardableResult
    static func present(
        application: NSApplication?,
        coordinator: MainWindowPresentationCoordinator
    ) -> MainWindowPresentationCoordinator.PresentationResult {
        let existingWindow = application?.windows.first { $0.identifier == windowIdentifier }
        let result = coordinator.present(
            existingWindow: existingWindow.map { window in
                {
                    restoreAndPresent(window)
                }
            }
        )
        application?.activate()
        return result
    }

    static func restoreAndPresent(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

public struct MainWindowIdentifierView: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        identifyWindow(containing: view)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        identifyWindow(containing: nsView)
    }

    private func identifyWindow(containing view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }
            window.identifier = MainWindowPresenter.windowIdentifier
            MainWindowPresentationCoordinator.shared.windowDidBecomeAvailable()
        }
    }
}
