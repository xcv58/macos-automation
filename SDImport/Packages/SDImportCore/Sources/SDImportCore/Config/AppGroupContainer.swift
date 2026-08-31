import Foundation

public enum AppGroupContainer {
    public static func sharedSupportDirectory(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) throws -> URL {
        guard AppDistribution.current.usesSharedAppGroupContainer else {
            return try DatabasePoolFactory.defaultApplicationSupportDirectory(fileManager: fileManager)
        }
        let identifier = bundle.object(forInfoDictionaryKey: "SDImportAppGroupIdentifier") as? String
            ?? AppDistribution.appGroupIdentifier
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            throw SDImportError.missingApplicationGroupContainer(identifier)
        }
        return containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("SD Import Shared", isDirectory: true)
    }
}
