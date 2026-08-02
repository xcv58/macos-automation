import AppKit
import Testing

@testable import SDImportCore

@Suite("Main window presenter")
@MainActor
struct MainWindowPresenterTests {
    @Test("restores a minimized main window before presenting it")
    func restoresMinimizedWindow() {
        let window = WindowSpy(isMiniaturized: true)

        MainWindowPresenter.restoreAndPresent(window)

        #expect(window.deminiaturizeCount == 1)
        #expect(window.makeKeyAndOrderFrontCount == 1)
    }

    @Test("presents a visible main window without redundant restoration")
    func presentsVisibleWindow() {
        let window = WindowSpy(isMiniaturized: false)

        MainWindowPresenter.restoreAndPresent(window)

        #expect(window.deminiaturizeCount == 0)
        #expect(window.makeKeyAndOrderFrontCount == 1)
    }
}

@MainActor
private final class WindowSpy: NSWindow {
    private let reportsMiniaturized: Bool
    private(set) var deminiaturizeCount = 0
    private(set) var makeKeyAndOrderFrontCount = 0

    init(isMiniaturized: Bool) {
        reportsMiniaturized = isMiniaturized
        super.init(
            contentRect: .zero,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
    }

    override var isMiniaturized: Bool {
        reportsMiniaturized
    }

    override func deminiaturize(_ sender: Any?) {
        deminiaturizeCount += 1
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCount += 1
    }
}
