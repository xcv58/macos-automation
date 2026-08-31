import AppKit
import ApplicationServices
import Darwin
import Foundation

private enum RuntimeQAError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            message
        }
    }
}

private struct SyntheticFixture {
    let root: URL
    let source: URL
    let destination: URL
}

private struct AXQuery {
    var role: String?
    var identifier: String?
    var title: String?
    var description: String?
    var value: String?

    func matches(_ element: AXUIElement) -> Bool {
        if let role, AXDriver.stringAttribute(element, kAXRoleAttribute as CFString) != role {
            return false
        }
        if let identifier, AXDriver.stringAttribute(element, kAXIdentifierAttribute as CFString) != identifier {
            return false
        }
        if let title, AXDriver.stringAttribute(element, kAXTitleAttribute as CFString) != title {
            return false
        }
        if let description, AXDriver.stringAttribute(element, kAXDescriptionAttribute as CFString) != description {
            return false
        }
        if let value, AXDriver.stringAttribute(element, kAXValueAttribute as CFString) != value {
            return false
        }
        return true
    }
}

private final class AXDriver {
    private(set) var runningApplication: NSRunningApplication
    private(set) var application: AXUIElement

    init(runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        application = AXUIElementCreateApplication(runningApplication.processIdentifier)
    }

    func replaceRunningApplication(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        application = AXUIElementCreateApplication(runningApplication.processIdentifier)
    }

    func activate() {
        _ = runningApplication.activate(options: [])
    }

    func element(
        _ query: AXQuery,
        timeout: TimeInterval,
        failure: String
    ) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let match = firstDescendant(of: application, matching: query.matches) {
                return match
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw RuntimeQAError.failed(failure)
    }

    func optionalElement(_ query: AXQuery, timeout: TimeInterval) -> AXUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let match = firstDescendant(of: application, matching: query.matches) {
                return match
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return nil
    }

    func waitForNoElement(
        _ query: AXQuery,
        timeout: TimeInterval,
        failure: String
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if firstDescendant(of: application, matching: query.matches) == nil {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw RuntimeQAError.failed(failure)
    }

    func press(_ element: AXUIElement) throws {
        try performAction(kAXPressAction as CFString, on: element)
    }

    private func performAction(_ action: CFString, on element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, action)
        guard error == .success || error == .cannotComplete else {
            throw RuntimeQAError.failed("Accessibility action failed with error \(error.rawValue)")
        }
    }

    func setValue(_ value: String, for element: AXUIElement) throws {
        let error = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            value as CFTypeRef
        )
        guard error == .success else {
            throw RuntimeQAError.failed("Accessibility value update failed with error \(error.rawValue)")
        }
    }

    func focus(_ element: AXUIElement) throws {
        let error = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        guard error == .success else {
            throw RuntimeQAError.failed("Accessibility focus update failed with error \(error.rawValue)")
        }
    }

    func isEnabled(_ element: AXUIElement) -> Bool {
        guard let value = Self.attribute(element, kAXEnabledAttribute as CFString) else {
            return false
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return false
    }

    func waitUntilEnabled(
        _ query: AXQuery,
        timeout: TimeInterval,
        failure: String
    ) throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if
                let match = firstDescendant(of: application, matching: query.matches),
                isEnabled(match)
            {
                return match
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw RuntimeQAError.failed(failure)
    }

    func diagnosticSnapshot() -> String {
        var lines: [String] = []
        appendDiagnosticLines(from: application, depth: 0, to: &lines)
        return lines.isEmpty ? "<no accessible UI>" : lines.joined(separator: "\n")
    }

    static func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value
    }

    static func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
        attribute(element, name) as? String
    }

    private func firstDescendant(
        of element: AXUIElement,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        if predicate(element) {
            return element
        }
        let role = Self.stringAttribute(element, kAXRoleAttribute as CFString)
        if role == (kAXMenuBarRole as String) {
            return nil
        }
        let children = Self.attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
        for child in children {
            if let match = firstDescendant(of: child, matching: predicate) {
                return match
            }
        }
        return nil
    }

    private func appendDiagnosticLines(
        from element: AXUIElement,
        depth: Int,
        to lines: inout [String]
    ) {
        guard depth < 12 else {
            return
        }
        let role = Self.stringAttribute(element, kAXRoleAttribute as CFString) ?? ""
        let noteworthyRoles = [
            kAXButtonRole as String,
            kAXStaticTextRole as String,
            kAXTextFieldRole as String,
        ]
        if noteworthyRoles.contains(role) {
            let identifier = Self.stringAttribute(element, kAXIdentifierAttribute as CFString) ?? ""
            let title = Self.stringAttribute(element, kAXTitleAttribute as CFString) ?? ""
            let description = Self.stringAttribute(element, kAXDescriptionAttribute as CFString) ?? ""
            let value = Self.stringAttribute(element, kAXValueAttribute as CFString) ?? ""
            lines.append(
                "\(role) id=\(identifier.debugDescription) title=\(title.debugDescription) "
                    + "description=\(description.debugDescription) value=\(value.debugDescription)"
            )
        }
        let children = Self.attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
        for child in children {
            appendDiagnosticLines(from: child, depth: depth + 1, to: &lines)
        }
    }
}

@main
private struct MacAppStoreRuntimeQA {
    private static let bundleIdentifier = "media.jenny.sdimport"
    private static let helperBundleIdentifier = "media.jenny.sdimport.agent"
    private static let helperPrepareArgument = "--sdimport-helper-runtime-qa-prepare"
    private static let helperUnregisterArgument = "--sdimport-helper-runtime-qa-unregister"
    private static let helperInjectedMountArgument = "--sdimport-helper-runtime-qa-mount"
    private static let launchArguments = [
        "-ApplePersistenceIgnoreState", "YES",
        "-SDImport.purchase.completedFreeImports", "0",
    ]

    static func main() async {
        do {
            try await run()
        } catch {
            fputs("MAS runtime QA failed: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        guard AXIsProcessTrusted() else {
            throw RuntimeQAError.failed(
                "Accessibility permission is required for the terminal or automation host running this QA script"
            )
        }

        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count == 1 {
            try await runManualImport(
                appURL: URL(fileURLWithPath: arguments[0], isDirectory: true).standardizedFileURL
            )
        } else if arguments.count == 3, arguments[0] == "helper" {
            try await runHelperConsent(
                appURL: URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL,
                mountURL: URL(fileURLWithPath: arguments[2], isDirectory: true).standardizedFileURL
            )
        } else {
            throw RuntimeQAError.failed(
                "usage: mas_runtime_qa.swift <app-bundle-path>\n"
                    + "   or: mas_runtime_qa.swift helper <installed-app-bundle-path> <mounted-volume-path>"
            )
        }
    }

    private static func runManualImport(appURL: URL) async throws {
        let appURL = appURL
            .standardizedFileURL
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        defer { terminateRunningCopies(of: appURL) }

        terminateRunningCopies(of: appURL)
        var running = try await launchApplication(at: appURL)
        let driver = AXDriver(runningApplication: running)
        driver.activate()

        if let useDefaults = driver.optionalElement(
            AXQuery(role: kAXButtonRole as String, title: "Use Defaults"),
            timeout: 3
        ) {
            try driver.press(useDefaults)
        }
        _ = try driver.element(
            AXQuery(identifier: "import.phase.source.heading", value: "Choose a source"),
            timeout: 10,
            failure: "The import source page did not appear"
        )

        print("QA: authorizing synthetic source through NSOpenPanel")
        try chooseDirectory(
            fixture.source,
            chooser: AXQuery(
                role: kAXButtonRole as String,
                description: "Choose source folder"
            ),
            driver: driver
        )
        guard let sourceField = driver.optionalElement(
            AXQuery(role: kAXTextFieldRole as String),
            timeout: 5
        ) else {
            throw RuntimeQAError.failed(
                "The selected synthetic source path was not retained. Accessible UI:\n"
                    + driver.diagnosticSnapshot()
            )
        }
        guard
            let selectedSourcePath = AXDriver.stringAttribute(
                sourceField,
                kAXValueAttribute as CFString
            ),
            equivalentPaths(selectedSourcePath, fixture.source.path)
        else {
            throw RuntimeQAError.failed("The source field did not match the authorized synthetic card")
        }

        let scanButton = try driver.waitUntilEnabled(
            AXQuery(identifier: "import.scan"),
            timeout: 5,
            failure: "The authorized source did not enable Scan Card"
        )
        try driver.press(scanButton)
        _ = try driver.element(
            AXQuery(identifier: "import.phase.review.heading", value: "Review import"),
            timeout: 30,
            failure: "The independently signed sandbox app did not finish scanning the synthetic card"
        )
        _ = try driver.element(
            AXQuery(role: kAXStaticTextRole as String, value: "1 file ready"),
            timeout: 5,
            failure: "The synthetic JPEG was not present in the scan review"
        )

        print("QA: authorizing synthetic destination through NSOpenPanel")
        try chooseDirectory(
            fixture.destination,
            chooser: AXQuery(
                role: kAXButtonRole as String,
                description: "Choose photos folder"
            ),
            driver: driver
        )
        let copyButton = try driver.waitUntilEnabled(
            AXQuery(identifier: "import.review.copy"),
            timeout: 5,
            failure: "The authorized destination did not enable Import 1 File"
        )
        try driver.press(copyButton)
        _ = try driver.element(
            AXQuery(identifier: "import.phase.completed.heading", value: "Import complete"),
            timeout: 30,
            failure: "The independently signed sandbox import did not complete"
        )
        guard try containsImportedFixture(in: fixture.destination) else {
            throw RuntimeQAError.failed("The completed import did not copy IMG_0001.JPG")
        }

        print("QA: relaunching and resolving the persisted source bookmark")
        running.terminate()
        try await waitForTermination(running)
        running = try await launchApplication(at: appURL)
        driver.replaceRunningApplication(running)
        driver.activate()

        _ = try driver.element(
            AXQuery(identifier: "import.phase.source.heading", value: "Choose a source"),
            timeout: 10,
            failure: "The source page did not reappear after relaunch"
        )
        if let rejectMount = driver.optionalElement(
            AXQuery(role: kAXButtonRole as String, title: "Don't Scan"),
            timeout: 2
        ) {
            try driver.press(rejectMount)
        }
        guard
            let relaunchedSourceField = driver.optionalElement(
                AXQuery(role: kAXTextFieldRole as String),
                timeout: 5
            ),
            let relaunchedSourcePath = AXDriver.stringAttribute(
                relaunchedSourceField,
                kAXValueAttribute as CFString
            ),
            equivalentPaths(relaunchedSourcePath, fixture.source.path)
        else {
            throw RuntimeQAError.failed(
                "The persisted source bookmark did not restore the synthetic card path"
            )
        }
        try driver.waitForNoElement(
            AXQuery(identifier: "open-panel"),
            timeout: 1,
            failure: "Relaunch unexpectedly requested folder access for the saved source"
        )
        let relaunchedScanButton = try driver.waitUntilEnabled(
            AXQuery(identifier: "import.scan"),
            timeout: 5,
            failure: "The persisted source bookmark did not re-enable Scan Card"
        )
        try driver.press(relaunchedScanButton)
        _ = try driver.element(
            AXQuery(identifier: "import.phase.review.heading", value: "Review import"),
            timeout: 30,
            failure: "The persisted source bookmark did not authorize a relaunch scan"
        )

        terminateRunningCopies(of: appURL)
        print("Verified independently signed sandbox import, copied output, and bookmark-backed relaunch scan")
    }

    private static func runHelperConsent(appURL: URL, mountURL: URL) async throws {
        guard appURL.path.hasPrefix("/Applications/") else {
            throw RuntimeQAError.failed("The helper QA app must be installed below /Applications")
        }
        let helperURL = appURL
            .appendingPathComponent("Contents/Library/LoginItems/SDImportAgent.app", isDirectory: true)
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            throw RuntimeQAError.failed("The installed app does not contain SDImportAgent.app")
        }
        guard try isMountedVolumeRoot(mountURL) else {
            throw RuntimeQAError.failed("The helper QA mount path is not an actual mounted-volume root")
        }

        var helperRegistrationWasRequested = false
        do {
            terminateRunningCopies(of: appURL)
            terminateRunningCopies(bundleIdentifier: helperBundleIdentifier, at: helperURL)

            print("QA: registering and launching the real embedded login-item helper")
            _ = try await launchApplication(
                at: appURL,
                arguments: [helperPrepareArgument] + launchArguments,
                createsNewInstance: true
            )
            helperRegistrationWasRequested = true
            _ = try await waitForRunningApplication(
                bundleIdentifier: helperBundleIdentifier,
                at: helperURL,
                timeout: 15,
                failure: "The registered embedded helper did not launch; check Login Items approval"
            )
            terminateRunningCopies(of: appURL)
            try await waitForNoRunningApplication(
                bundleIdentifier: bundleIdentifier,
                at: appURL,
                timeout: 5,
                failure: "The exact temporary app copy could not be terminated"
            )

            print("QA: injecting one post-detection event into a new instance of the signed helper")
            _ = try await launchApplication(
                at: helperURL,
                arguments: [helperInjectedMountArgument, mountURL.path],
                createsNewInstance: true
            )
            let launchedApp = try await waitForRunningApplication(
                bundleIdentifier: bundleIdentifier,
                at: appURL,
                timeout: 15,
                failure: "The helper did not launch its containing app through the App Group handoff"
            )
            let driver = AXDriver(runningApplication: launchedApp)
            driver.activate()

            let consentMessage =
                "SD Import detected this removable volume but has not scanned its contents. "
                + "Allow a scan now to preview what would be copied?"
            _ = try driver.element(
                AXQuery(role: kAXStaticTextRole as String, value: consentMessage),
                timeout: 15,
                failure: "The helper handoff did not present the explicit no-scan consent message. "
                    + "Accessible UI:\n" + driver.diagnosticSnapshot()
            )
            let declineButton = try driver.element(
                AXQuery(role: kAXButtonRole as String, title: "Don't Scan"),
                timeout: 3,
                failure: "The helper consent sheet did not offer Don't Scan"
            )
            _ = try driver.element(
                AXQuery(role: kAXButtonRole as String, title: "Allow Scan"),
                timeout: 3,
                failure: "The helper consent sheet did not offer Allow Scan"
            )
            try assertNoScanUI(driver, context: "before consent")

            print("QA: declining consent and confirming that no scan or access panel starts")
            try driver.press(declineButton)
            try driver.waitForNoElement(
                AXQuery(role: kAXButtonRole as String, title: "Allow Scan"),
                timeout: 5,
                failure: "The consent sheet did not dismiss after Don't Scan"
            )
            _ = try driver.element(
                AXQuery(identifier: "import.phase.source.heading", value: "Choose a source"),
                timeout: 5,
                failure: "Declining helper consent did not leave the app on the source page"
            )
            try assertNoScanUI(driver, context: "after declining consent")

            try await unregisterHelper(appURL: appURL, helperURL: helperURL)
            helperRegistrationWasRequested = false
            print("Verified signed helper registration, App Group handoff, explicit consent, and no-scan decline")
        } catch {
            if helperRegistrationWasRequested {
                try? await unregisterHelper(appURL: appURL, helperURL: helperURL)
            }
            terminateRunningCopies(of: appURL)
            terminateRunningCopies(bundleIdentifier: helperBundleIdentifier, at: helperURL)
            throw error
        }
    }

    private static func assertNoScanUI(_ driver: AXDriver, context: String) throws {
        let forbiddenQueries = [
            AXQuery(identifier: "open-panel"),
            AXQuery(identifier: "import.phase.review.heading", value: "Review import"),
            AXQuery(role: kAXStaticTextRole as String, value: "1 file ready"),
        ]
        for query in forbiddenQueries where driver.optionalElement(query, timeout: 0.5) != nil {
            throw RuntimeQAError.failed(
                "Unexpected scan or authorization UI appeared \(context). Accessible UI:\n"
                    + driver.diagnosticSnapshot()
            )
        }
    }

    private static func unregisterHelper(appURL: URL, helperURL: URL) async throws {
        terminateRunningCopies(of: appURL)
        let unregisteringApp = try await launchApplication(
            at: appURL,
            arguments: [helperUnregisterArgument] + launchArguments,
            createsNewInstance: true
        )
        try await waitForTermination(unregisteringApp)
        terminateRunningCopies(bundleIdentifier: helperBundleIdentifier, at: helperURL)
        try await waitForNoRunningApplication(
            bundleIdentifier: helperBundleIdentifier,
            at: helperURL,
            timeout: 5,
            failure: "The temporary embedded helper remained running after unregistration"
        )
        terminateRunningCopies(of: appURL)
    }

    private static func isMountedVolumeRoot(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .volumeURLKey])
        return values.isDirectory == true
            && values.volume?.standardizedFileURL == url.standardizedFileURL
    }

    private static func chooseDirectory(
        _ directory: URL,
        chooser: AXQuery,
        driver: AXDriver
    ) throws {
        driver.activate()
        let chooserElement = try driver.element(
            chooser,
            timeout: 5,
            failure: "The folder chooser was not available"
        )
        try driver.press(chooserElement)
        _ = try driver.element(
            AXQuery(identifier: "open-panel"),
            timeout: 5,
            failure: "The macOS folder panel did not appear"
        )

        postKey(virtualKey: 5, flags: [.maskCommand, .maskShift])
        let pathField = try driver.element(
            AXQuery(role: kAXTextFieldRole as String, identifier: "PathTextField"),
            timeout: 5,
            failure: "Go to Folder did not present its path field"
        )
        try driver.focus(pathField)
        try driver.setValue(directory.path, for: pathField)
        postKey(virtualKey: 36)
        try driver.waitForNoElement(
            AXQuery(identifier: "GoToWindow"),
            timeout: 5,
            failure: "Go to Folder did not navigate to the requested directory"
        )

        let confirmation = try driver.element(
            AXQuery(role: kAXButtonRole as String, identifier: "OKButton"),
            timeout: 5,
            failure: "The folder panel confirmation button was not available"
        )
        try driver.press(confirmation)
        try driver.waitForNoElement(
            AXQuery(identifier: "open-panel"),
            timeout: 5,
            failure: "The folder panel did not accept the selected directory"
        )
    }

    private static func postKey(
        virtualKey: CGKeyCode,
        flags: CGEventFlags = []
    ) {
        let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: virtualKey,
            keyDown: true
        )!
        keyDown.flags = flags
        keyDown.post(tap: .cghidEventTap)

        let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: virtualKey,
            keyDown: false
        )!
        keyUp.flags = flags
        keyUp.post(tap: .cghidEventTap)
    }

    private static func launchApplication(
        at applicationURL: URL,
        arguments: [String] = launchArguments,
        createsNewInstance: Bool = false
    ) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = createsNewInstance
        let running = try await NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
        let deadline = Date().addingTimeInterval(10)
        while running.isTerminated, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !running.isTerminated else {
            throw RuntimeQAError.failed("The independently signed app did not launch")
        }
        return running
    }

    private static func terminateRunningCopies(of applicationURL: URL) {
        terminateRunningCopies(bundleIdentifier: bundleIdentifier, at: applicationURL)
    }

    private static func terminateRunningCopies(bundleIdentifier: String, at applicationURL: URL) {
        let matchingApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).filter {
            $0.bundleURL?.standardizedFileURL == applicationURL
        }
        for running in matchingApplications {
            running.terminate()
        }
        let deadline = Date().addingTimeInterval(5)
        while matchingApplications.contains(where: { !$0.isTerminated }), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        for running in matchingApplications where !running.isTerminated {
            running.forceTerminate()
        }
        let forceDeadline = Date().addingTimeInterval(5)
        while matchingApplications.contains(where: { !$0.isTerminated }), Date() < forceDeadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private static func waitForRunningApplication(
        bundleIdentifier: String,
        at applicationURL: URL,
        timeout: TimeInterval,
        failure: String
    ) async throws -> NSRunningApplication {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let running = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first(where: {
                !$0.isTerminated && $0.bundleURL?.standardizedFileURL == applicationURL
            }) {
                return running
            }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        throw RuntimeQAError.failed(failure)
    }

    private static func waitForNoRunningApplication(
        bundleIdentifier: String,
        at applicationURL: URL,
        timeout: TimeInterval,
        failure: String
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let isRunning = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).contains(where: {
                !$0.isTerminated && $0.bundleURL?.standardizedFileURL == applicationURL
            })
            if !isRunning {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        throw RuntimeQAError.failed(failure)
    }

    private static func waitForTermination(_ running: NSRunningApplication) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !running.isTerminated, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard running.isTerminated else {
            throw RuntimeQAError.failed("The temporary app did not terminate for the relaunch check")
        }
    }

    private static func makeFixture() throws -> SyntheticFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SDImportMASRuntimeQA-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("SYNTHETIC-CARD", isDirectory: true)
        let destination = root.appendingPathComponent("IMPORTED", isDirectory: true)
        let mediaDirectory = source.appendingPathComponent("DCIM/100MEDIA", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 32, height: 32)).fill()
        image.unlockFocus()
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let jpeg = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.9]
            )
        else {
            throw RuntimeQAError.failed("Could not create the synthetic JPEG fixture")
        }
        try jpeg.write(
            to: mediaDirectory.appendingPathComponent("IMG_0001.JPG"),
            options: .atomic
        )
        return SyntheticFixture(
            root: root.resolvingSymlinksInPath(),
            source: source.resolvingSymlinksInPath(),
            destination: destination.resolvingSymlinksInPath()
        )
    }

    private static func containsImportedFixture(in destination: URL) throws -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: destination,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return enumerator.compactMap { $0 as? URL }.contains {
            $0.lastPathComponent == "IMG_0001.JPG"
        }
    }

    private static func equivalentPaths(_ lhs: String, _ rhs: String) -> Bool {
        canonicalPath(lhs) == canonicalPath(rhs)
    }

    private static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
