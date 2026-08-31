import Foundation
import Testing

@testable import SDImportCore

@Suite("App Store distribution boundaries")
struct AppStoreDistributionTests {
    @Test("identifiers and mount privacy behavior remain edition-specific")
    func distributionIdentityAndMountPrivacyPolicy() {
        #expect(AppDistribution.appStoreBundleIdentifier == "media.jenny.sdimport")
        #expect(AppDistribution.appStoreAgentBundleIdentifier == "media.jenny.sdimport.agent")
        #expect(AppDistribution.appGroupIdentifier == "group.media.jenny.sdimport")
        #expect(AppDistribution.lifetimeProductIdentifier == "media.jenny.sdimport.unlimited")

        #expect(
            AppDistribution.direct.mountPrivacyPolicy
                == MountPrivacyPolicy(
                    includesCapacityBeforeConsent: true,
                    probesMediaBeforeConsent: true,
                    usesDistributedNotificationHandoff: true
                )
        )
        #expect(
            AppDistribution.macAppStore.mountPrivacyPolicy
                == MountPrivacyPolicy(
                    includesCapacityBeforeConsent: false,
                    probesMediaBeforeConsent: false,
                    usesDistributedNotificationHandoff: false
                )
        )
        #expect(AppDistribution.macAppStore.requiresConsentBeforeMediaProbe)
        #expect(!AppDistribution.direct.requiresConsentBeforeMediaProbe)
        #expect(AppDistribution.macAppStore.usesSharedAppGroupContainer)
        #expect(!AppDistribution.direct.usesSharedAppGroupContainer)
        #expect(!AppDistribution.macAppStore.importsUnsandboxedLegacyState)
        #expect(AppDistribution.direct.importsUnsandboxedLegacyState)
        #expect(!AppDistribution.macAppStore.canBrowseSystemCrashReports)
        #expect(AppDistribution.direct.canBrowseSystemCrashReports)
        #expect(!AppDistribution.macAppStore.supportsSourceEjection)
        #expect(AppDistribution.direct.supportsSourceEjection)
        #expect(AppDistribution.macAppStore.staleBookmarkHandling == .requireNewSelection)
        #expect(AppDistribution.direct.staleBookmarkHandling == .refresh)
    }

    @Test("the App Store edition rejects stale bookmarks until the user selects again")
    func staleBookmarkPolicy() {
        #expect(
            BookmarkStore.accessDecision(
                isStale: false,
                staleBookmarkHandling: .requireNewSelection
            ) == .beginAccess(refreshBookmark: false)
        )
        #expect(
            BookmarkStore.accessDecision(
                isStale: true,
                staleBookmarkHandling: AppDistribution.macAppStore.staleBookmarkHandling
            ) == .requireNewSelection
        )
        #expect(
            BookmarkStore.accessDecision(
                isStale: true,
                staleBookmarkHandling: AppDistribution.direct.staleBookmarkHandling
            ) == .beginAccess(refreshBookmark: true)
        )
    }

    @Test("security-scoped access stops exactly once only after a successful start")
    func securityScopedAccessBalancesLifetime() {
        let activeCounter = AccessCounter()
        var active: SecurityScopedResourceAccess? = SecurityScopedResourceAccess(
            url: URL(fileURLWithPath: "/Volumes/Test Card", isDirectory: true),
            startAccess: { _ in
                activeCounter.starts += 1
                return true
            },
            stopAccess: { _ in
                activeCounter.stops += 1
            }
        )
        #expect(active?.isActive == true)
        #expect(activeCounter.starts == 1)
        #expect(activeCounter.stops == 0)
        active = nil
        #expect(activeCounter.stops == 1)

        let inactiveCounter = AccessCounter()
        var inactive: SecurityScopedResourceAccess? = SecurityScopedResourceAccess(
            url: URL(fileURLWithPath: "/Volumes/Denied Card", isDirectory: true),
            startAccess: { _ in
                inactiveCounter.starts += 1
                return false
            },
            stopAccess: { _ in
                inactiveCounter.stops += 1
            }
        )
        #expect(inactive?.isActive == false)
        inactive = nil
        #expect(inactiveCounter.starts == 1)
        #expect(inactiveCounter.stops == 0)
    }

    @Test("App Store state resolves inside the exact shared group container")
    func appGroupSupportDirectory() throws {
        let container = try temporaryDirectory()
        var requestedIdentifier: String?
        let supportDirectory = try AppGroupContainer.sharedSupportDirectory(
            distribution: .macAppStore,
            appGroupIdentifier: AppDistribution.appGroupIdentifier,
            containerURLProvider: { identifier in
                requestedIdentifier = identifier
                return container
            }
        )

        #expect(requestedIdentifier == "group.media.jenny.sdimport")
        #expect(
            supportDirectory.standardizedFileURL.path
                == container
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("SD Import Shared", isDirectory: true)
                    .standardizedFileURL.path
        )
    }

    @Test("the direct edition keeps its native support directory")
    func directSupportDirectoryDoesNotUseAppGroup() throws {
        var requestedAppGroup = false
        let supportDirectory = try AppGroupContainer.sharedSupportDirectory(
            distribution: .direct,
            containerURLProvider: { _ in
                requestedAppGroup = true
                return nil
            }
        )

        #expect(!requestedAppGroup)
        #expect(supportDirectory.lastPathComponent == "SD Import")
    }

    @Test("a missing App Group container fails closed")
    func missingAppGroupContainerFailsClosed() {
        #expect(throws: SDImportError.missingApplicationGroupContainer("group.media.jenny.sdimport")) {
            try AppGroupContainer.sharedSupportDirectory(
                distribution: .macAppStore,
                appGroupIdentifier: AppDistribution.appGroupIdentifier,
                containerURLProvider: { _ in nil }
            )
        }
    }
}

private final class AccessCounter: @unchecked Sendable {
    var starts = 0
    var stops = 0
}
