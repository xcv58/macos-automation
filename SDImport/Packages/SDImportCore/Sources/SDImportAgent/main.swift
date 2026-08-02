import AppKit
import Foundation
import OSLog
import SDImportCore

private let agentLogger = Logger(subsystem: "com.xcv58.SDImport", category: "BackgroundPrompt")

@main
@MainActor
struct SDImportAgent {
    private static var delegate: AgentDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AgentDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
private final class AgentDelegate: NSObject, NSApplicationDelegate {
    private static let mainBundleIdentifier = "com.xcv58.SDImport"

    private let detector = VolumeDetector()
    private var token: NSObjectProtocol?

    private var agentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    private var agentBundlePath: String {
        Bundle.main.bundleURL.standardizedFileURL.path
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try BackgroundPromptAgentStateStore.defaultStore().recordLaunch(
                agentBuild: agentBuild,
                agentBundlePath: agentBundlePath
            )
        } catch {
            agentLogger.error("Could not record background helper launch")
        }

        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let mountURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
                return
            }
            Task { @MainActor in
                self?.handleMountURL(mountURL)
            }
        }
    }

    private func handleMountURL(_ mountURL: URL) {
        let volume = detector.mountedVolume(from: mountURL)
        guard detector.isLikelyImportVolume(volume) else {
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            guard VolumeDetector().containsImportableMedia(at: mountURL) else {
                return
            }
            await MainActor.run {
                self?.handleImportableVolume(volume)
            }
        }
    }

    private func handleImportableVolume(_ volume: MountedVolume) {
        guard let appURL = containingMainApplicationURL else {
            try? BackgroundPromptAgentStateStore.defaultStore().recordError(
                agentBuild: agentBuild,
                agentBundlePath: agentBundlePath,
                message: "Could not locate the containing SD Import application"
            )
            agentLogger.error("Could not locate the containing SD Import application")
            return
        }

        guard
            let stateStore = try? BackgroundPromptAgentStateStore.defaultStore(),
            let eventSequence = try? stateStore.issueEventSequence(
                agentBuild: agentBuild,
                agentBundlePath: agentBundlePath
            )
        else {
            agentLogger.error("Ignoring mount event from a stale or unavailable background helper")
            return
        }
        let event: MountHandoffEvent?
        do {
            event = try MountHandoffOccurrenceRecorder(
                store: MountHandoffStore.defaultStore()
            ).persistBackgroundAgentOccurrence(
                volume: volume,
                agentBuild: agentBuild,
                agentSequence: eventSequence,
                targetApplicationPath: appURL.path
            )
        } catch {
            event = nil
            try? BackgroundPromptAgentStateStore.defaultStore().recordError(
                agentBuild: agentBuild,
                agentBundlePath: agentBundlePath,
                message: "Could not persist a mounted-card event",
                eventSequence: eventSequence
            )
            agentLogger.error("Could not persist mounted-card handoff")
        }
        if event != nil {
            do {
                try BackgroundPromptAgentStateStore.defaultStore().recordHandoff(
                    agentBuild: agentBuild,
                    agentBundlePath: agentBundlePath,
                    eventSequence: eventSequence
                )
            } catch {
                agentLogger.error("Could not record background helper activity")
            }
        }

        activateOrLaunchMainApp(at: appURL, eventSequence: eventSequence)
        post(volume, eventID: event?.id, targetApplicationPath: appURL.path)
    }

    private func activateOrLaunchMainApp(at appURL: URL, eventSequence: UInt64) {
        let currentAgentBuild = agentBuild
        let currentAgentBundlePath = agentBundlePath
        let standardizedAppURL = appURL.standardizedFileURL
        let runningApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.mainBundleIdentifier
        )
        let runningApp = runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL == standardizedAppURL
        })
        if let runningApp {
            runningApp.activate(options: [.activateAllWindows])
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = !runningApplications.isEmpty
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if error != nil {
                try? BackgroundPromptAgentStateStore.defaultStore().recordError(
                    agentBuild: currentAgentBuild,
                    agentBundlePath: currentAgentBundlePath,
                    message: "Could not launch the containing SD Import application",
                    eventSequence: eventSequence
                )
                agentLogger.error("Could not launch the containing SD Import application")
            }
        }
    }

    private func post(
        _ volume: MountedVolume,
        eventID: UUID?,
        targetApplicationPath: String
    ) {
        var userInfo: [String: Any] = [
            MountHandoff.pathKey: volume.mountURL.path,
            MountHandoff.nameKey: volume.name,
            MountHandoff.targetApplicationPathKey: targetApplicationPath
        ]
        if let eventID {
            userInfo[MountHandoff.eventIDKey] = eventID.uuidString
        }

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(MountHandoff.notificationName),
            object: targetApplicationPath,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    private var containingMainApplicationURL: URL? {
        guard
            let appURL = MountHandoff.containingApplicationURL(for: Bundle.main.bundleURL),
            Bundle(url: appURL)?.bundleIdentifier == Self.mainBundleIdentifier
        else {
            return nil
        }
        return appURL.standardizedFileURL
    }
}
