import Foundation

public enum MountHandoff {
    public static let notificationName = "com.xcv58.SDImport.mountedVolume"
    public static let eventIDKey = "eventID"
    public static let pathKey = "path"
    public static let nameKey = "name"
    public static let targetApplicationPathKey = "targetApplicationPath"

    public static func containingApplicationURL(for agentBundleURL: URL) -> URL? {
        var candidate = agentBundleURL.deletingLastPathComponent()

        while candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else {
                return nil
            }
            candidate = parent
        }

        return nil
    }
}
