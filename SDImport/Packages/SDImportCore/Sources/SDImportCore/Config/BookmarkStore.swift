import Foundation
import GRDB

public enum BookmarkPurpose: String, Codable, CaseIterable, Hashable, Sendable {
    case source
    case photos
    case videos
}

public enum StaleBookmarkHandling: Equatable, Sendable {
    case refresh
    case requireNewSelection
}

enum BookmarkAccessDecision: Equatable, Sendable {
    case beginAccess(refreshBookmark: Bool)
    case requireNewSelection
}

public final class SecurityScopedResourceAccess: @unchecked Sendable {
    public let url: URL
    private let didStartAccess: Bool
    private let stopAccess: (URL) -> Void

    public var isActive: Bool {
        didStartAccess
    }

    public convenience init(url: URL) {
        self.init(
            url: url,
            startAccess: { $0.startAccessingSecurityScopedResource() },
            stopAccess: { $0.stopAccessingSecurityScopedResource() }
        )
    }

    init(
        url: URL,
        startAccess: (URL) -> Bool,
        stopAccess: @escaping (URL) -> Void
    ) {
        self.url = url
        didStartAccess = startAccess(url)
        self.stopAccess = stopAccess
    }

    deinit {
        if didStartAccess {
            stopAccess(url)
        }
    }
}

public struct ResolvedBookmark: Hashable, Sendable {
    public let purpose: BookmarkPurpose
    public let url: URL
    public let isStale: Bool

    public init(purpose: BookmarkPurpose, url: URL, isStale: Bool) {
        self.purpose = purpose
        self.url = url
        self.isStale = isStale
    }
}

public struct BookmarkStore {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func saveBookmark(
        purpose: BookmarkPurpose,
        url: URL,
        updatedAt: Date = Date()
    ) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        try pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO bookmarks (id, purpose, bookmark_data, url, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    purpose = excluded.purpose,
                    bookmark_data = excluded.bookmark_data,
                    url = excluded.url,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    purpose.rawValue,
                    purpose.rawValue,
                    data,
                    url.path,
                    DateCoding.string(from: updatedAt)
                ]
            )
        }
    }

    public func resolveBookmark(purpose: BookmarkPurpose) throws -> ResolvedBookmark? {
        try pool.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT bookmark_data FROM bookmarks WHERE id = ?",
                arguments: [purpose.rawValue]
            ) else {
                return nil
            }

            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return ResolvedBookmark(purpose: purpose, url: url, isStale: isStale)
        }
    }

    public func beginAccess(
        purpose: BookmarkPurpose,
        staleBookmarkHandling: StaleBookmarkHandling = .refresh
    ) throws -> SecurityScopedResourceAccess? {
        guard let resolved = try resolveBookmark(purpose: purpose) else {
            return nil
        }

        switch Self.accessDecision(
            isStale: resolved.isStale,
            staleBookmarkHandling: staleBookmarkHandling
        ) {
        case .requireNewSelection:
            return nil
        case .beginAccess(let refreshBookmark):
            let access = SecurityScopedResourceAccess(url: resolved.url)
            if refreshBookmark {
                try saveBookmark(purpose: purpose, url: resolved.url)
            }
            return access
        }
    }

    static func accessDecision(
        isStale: Bool,
        staleBookmarkHandling: StaleBookmarkHandling
    ) -> BookmarkAccessDecision {
        guard isStale else {
            return .beginAccess(refreshBookmark: false)
        }

        switch staleBookmarkHandling {
        case .refresh:
            return .beginAccess(refreshBookmark: true)
        case .requireNewSelection:
            return .requireNewSelection
        }
    }

    public func resolvedPath(purpose: BookmarkPurpose, fallback: String) -> String {
        do {
            return try resolveBookmark(purpose: purpose)?.url.path ?? fallback
        } catch {
            return fallback
        }
    }

    public func storedPath(purpose: BookmarkPurpose) throws -> String? {
        try pool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT url FROM bookmarks WHERE id = ?",
                arguments: [purpose.rawValue]
            )
        }
    }
}
