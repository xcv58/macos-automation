import AppKit
import SwiftUI

@MainActor
public enum MainWindowPresenter {
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("SDImport.main")

    public static func present() {
        let existingWindow = NSApp.windows.first { $0.identifier == windowIdentifier }
        MainWindowPresentationCoordinator.shared.present(
            existingWindow: existingWindow.map { window in
                {
                    restoreAndPresent(window)
                }
            }
        )
        NSApp.activate()
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
