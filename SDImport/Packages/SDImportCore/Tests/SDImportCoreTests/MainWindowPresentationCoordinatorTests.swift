import Testing

@testable import SDImportCore

@Suite("Main window presentation")
@MainActor
struct MainWindowPresentationCoordinatorTests {
    @Test("process lifecycle callbacks remain available without a window")
    func processLifecycleCallbacksAreIndependentOfWindow() {
        let coordinator = ApplicationLifecycleCoordinator()
        var activationCount = 0
        var willPresentCount = 0
        var didAppearCount = 0
        coordinator.install(
            didBecomeActive: { activationCount += 1 },
            mainWindowWillPresent: { willPresentCount += 1 },
            mainWindowDidAppear: { didAppearCount += 1 }
        )

        coordinator.applicationDidBecomeActive()
        coordinator.mainWindowWillPresent()
        coordinator.mainWindowDidAppear()

        #expect(activationCount == 1)
        #expect(willPresentCount == 1)
        #expect(didAppearCount == 1)
    }

    @Test("opens a new main window when no existing window is available")
    func opensNewWindow() {
        let coordinator = MainWindowPresentationCoordinator()
        var openCount = 0
        coordinator.installWindowOpener { openCount += 1 }

        let result = coordinator.present()

        #expect(result == .openedNewWindow)
        #expect(openCount == 1)
    }

    @Test("coalesces repeated requests while a new main window is opening")
    func coalescesWindowOpenRequests() {
        let coordinator = MainWindowPresentationCoordinator()
        var openCount = 0
        coordinator.installWindowOpener { openCount += 1 }

        #expect(coordinator.present() == .openedNewWindow)
        #expect(coordinator.present() == .openingInProgress)
        #expect(openCount == 1)

        coordinator.windowDidBecomeAvailable()
        #expect(coordinator.present() == .openedNewWindow)
        #expect(openCount == 2)
    }

    @Test("reuses an existing main window without creating a duplicate")
    func reusesExistingWindow() {
        let coordinator = MainWindowPresentationCoordinator()
        var openCount = 0
        var presentCount = 0
        coordinator.installWindowOpener { openCount += 1 }

        let result = coordinator.present(existingWindow: { presentCount += 1 })

        #expect(result == .presentedExistingWindow)
        #expect(presentCount == 1)
        #expect(openCount == 0)
    }
}
