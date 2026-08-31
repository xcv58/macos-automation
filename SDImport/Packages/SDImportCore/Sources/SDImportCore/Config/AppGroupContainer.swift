import Foundation

public enum AppGroupContainer {
    public static func sharedSupportDirectory(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) throws -> URL {
        try sharedSupportDirectory(
            fileManager: fileManager,
            bundle: bundle,
            distribution: .current
        )
    }

    static func sharedSupportDirectory(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        distribution: AppDistribution,
        appGroupIdentifier: String? = nil,
        containerURLProvider: ((String) -> URL?)? = nil
    ) throws -> URL {
        guard distribution.usesSharedAppGroupContainer else {
            return try DatabasePoolFactory.defaultApplicationSupportDirectory(fileManager: fileManager)
        }
        let identifier = appGroupIdentifier
            ?? bundle.object(forInfoDictionaryKey: "SDImportAppGroupIdentifier") as? String
            ?? AppDistribution.appGroupIdentifier
        let containerURL: URL?
        if let containerURLProvider {
            containerURL = containerURLProvider(identifier)
        } else {
            containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            )
        }
        guard let containerURL else {
            throw SDImportError.missingApplicationGroupContainer(identifier)
        }
        return containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("SD Import Shared", isDirectory: true)
    }
}
