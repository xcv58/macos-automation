import AppKit
import Foundation

enum FilePanelPresenter {
    @MainActor
    static func chooseDirectoryURL(
        title: String,
        initialPath: String? = nil,
        prompt: String? = nil,
        message: String? = nil
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        if let prompt {
            panel.prompt = prompt
        }
        if let message {
            panel.message = message
        }
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let initialPath, !initialPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (initialPath as NSString).expandingTildeInPath)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseSaveURL(title: String, suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
