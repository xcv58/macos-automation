import Foundation

public enum AppDistribution: String, Codable, Sendable {
    case direct
    case macAppStore = "app-store"

    public static let appStoreBundleIdentifier = "media.jenny.sdimport"
    public static let appStoreAgentBundleIdentifier = "media.jenny.sdimport.agent"
    public static let appGroupIdentifier = "group.media.jenny.sdimport"
    public static let lifetimeProductIdentifier = "media.jenny.sdimport.unlimited"

    public static var current: AppDistribution {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "SDImportDistribution") as? String,
            let distribution = AppDistribution(rawValue: value)
        else {
            return .direct
        }
        return distribution
    }

    public var requiresConsentBeforeMediaProbe: Bool {
        self == .macAppStore
    }

    public var usesSharedAppGroupContainer: Bool {
        self == .macAppStore
    }

    public var importsUnsandboxedLegacyState: Bool {
        self == .direct
    }

    public var canBrowseSystemCrashReports: Bool {
        self == .direct
    }

    public var supportsSourceEjection: Bool {
        self == .direct
    }
}
