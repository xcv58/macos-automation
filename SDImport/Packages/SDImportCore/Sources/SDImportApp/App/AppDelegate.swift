import AppKit
import SDImportCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        ApplicationLifecycleCoordinator.shared.applicationDidBecomeActive()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ApplicationLifecycleCoordinator.shared.mainWindowWillPresent()
        MainWindowPresenter.present()
        return true
    }
}
