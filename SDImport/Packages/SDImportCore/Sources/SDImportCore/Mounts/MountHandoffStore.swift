import Darwin
import Foundation

public enum MountHandoffOrigin: String, Codable, Equatable, Sendable {
    case backgroundAgent
    case foregroundApplication
}

public struct MountHandoffEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let mountPath: String
    public let volumeName: String
    public let agentBuild: String
    public let agentSequence: UInt64
    public let targetApplicationPath: String
    public let origin: MountHandoffOrigin
    public let mountedVolume: MountedVolume?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        mountPath: String,
        volumeName: String,
        agentBuild: String,
        agentSequence: UInt64 = 0,
        targetApplicationPath: String,
        origin: MountHandoffOrigin = .backgroundAgent,
        mountedVolume: MountedVolume? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mountPath = mountPath
        self.volumeName = volumeName
        self.agentBuild = agentBuild
        self.agentSequence = agentSequence
        self.targetApplicationPath = Self.normalizedPath(targetApplicationPath)
        self.origin = origin
        self.mountedVolume = mountedVolume
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case mountPath
        case volumeName
        case agentBuild
        case agentSequence
        case targetApplicationPath
        case origin
        case mountedVolume
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        mountPath = try container.decode(String.self, forKey: .mountPath)
        volumeName = try container.decode(String.self, forKey: .volumeName)
        agentBuild = try container.decode(String.self, forKey: .agentBuild)
        agentSequence = try container.decodeIfPresent(UInt64.self, forKey: .agentSequence) ?? 0
        targetApplicationPath = Self.normalizedPath(
            try container.decode(String.self, forKey: .targetApplicationPath)
        )
        origin = try container.decodeIfPresent(MountHandoffOrigin.self, forKey: .origin)
            ?? .backgroundAgent
        mountedVolume = try container.decodeIfPresent(MountedVolume.self, forKey: .mountedVolume)
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}

public final class MountHandoffClaim: @unchecked Sendable, Identifiable {
    public var id: UUID { event.id }
    public let event: MountHandoffEvent

    fileprivate let recordURL: URL
    fileprivate var descriptor: Int32

    fileprivate init(event: MountHandoffEvent, recordURL: URL, descriptor: Int32) {
        self.event = event
        self.recordURL = recordURL
        self.descriptor = descriptor
    }

    deinit {
        releaseLock()
    }

    fileprivate func releaseLock() {
        guard descriptor >= 0 else {
            return
        }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}

public struct MountHandoffStore {
    public let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public static func defaultStore(fileManager: FileManager = .default) throws -> MountHandoffStore {
        let supportURL = try DatabasePoolFactory.defaultApplicationSupportDirectory(fileManager: fileManager)
        return MountHandoffStore(
            directoryURL: supportURL.appendingPathComponent("Mount Handoffs", isDirectory: true),
            fileManager: fileManager
        )
    }

    @discardableResult
    public func enqueue(
        mountPath: String,
        volumeName: String,
        agentBuild: String,
        agentSequence: UInt64 = 0,
        targetApplicationPath: String,
        origin: MountHandoffOrigin = .backgroundAgent,
        mountedVolume: MountedVolume? = nil,
        now: Date = Date(),
        id: UUID = UUID()
    ) throws -> MountHandoffEvent {
        let event = MountHandoffEvent(
            id: id,
            createdAt: now,
            mountPath: mountPath,
            volumeName: volumeName,
            agentBuild: agentBuild,
            agentSequence: agentSequence,
            targetApplicationPath: targetApplicationPath,
            origin: origin,
            mountedVolume: mountedVolume
        )
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        try data.write(to: eventURL(id: id), options: [.atomic])
        return event
    }

    public func claimPendingEvents(
        targetApplicationPath: String,
        now: Date = Date(),
        maximumAge: TimeInterval? = nil
    ) throws -> [MountHandoffClaim] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let targetPath = normalizedPath(targetApplicationPath)
        let eventURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var claims: [MountHandoffClaim] = []

        for eventURL in eventURLs where eventURL.pathExtension == "json" {
            guard let claim = claim(
                eventURL: eventURL,
                targetApplicationPath: targetPath,
                now: now,
                maximumAge: maximumAge
            ) else {
                continue
            }
            claims.append(claim)
        }

        return claims.sorted {
            if $0.event.createdAt == $1.event.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.event.createdAt < $1.event.createdAt
        }
    }

    public func claimEvent(
        id: UUID,
        targetApplicationPath: String,
        now: Date = Date(),
        maximumAge: TimeInterval? = nil
    ) throws -> MountHandoffClaim? {
        claim(
            eventURL: eventURL(id: id),
            targetApplicationPath: normalizedPath(targetApplicationPath),
            now: now,
            maximumAge: maximumAge
        )
    }

    public func acknowledge(_ claim: MountHandoffClaim) throws {
        defer { claim.releaseLock() }
        guard recordMatchesDescriptor(at: claim.recordURL, descriptor: claim.descriptor) else {
            return
        }
        try fileManager.removeItem(at: claim.recordURL)
    }

    public func release(_ claim: MountHandoffClaim) {
        claim.releaseLock()
    }

    private func claim(
        eventURL: URL,
        targetApplicationPath: String,
        now: Date,
        maximumAge: TimeInterval?
    ) -> MountHandoffClaim? {
        let descriptor = open(eventURL.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            return nil
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }

        func discard(removeRecord: Bool) -> MountHandoffClaim? {
            if removeRecord {
                try? fileManager.removeItem(at: eventURL)
            }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            return nil
        }

        // Another consumer may have opened this inode before the winning consumer
        // removed its directory entry. Never deliver an already-acknowledged record.
        guard recordMatchesDescriptor(at: eventURL, descriptor: descriptor) else {
            return discard(removeRecord: false)
        }

        do {
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            try handle.seek(toOffset: 0)
            let data = try handle.readToEnd() ?? Data()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let event = try decoder.decode(
                MountHandoffEvent.self,
                from: data
            )
            guard eventURL.lastPathComponent == canonicalFilename(id: event.id) else {
                return discard(removeRecord: true)
            }
            if let maximumAge, now.timeIntervalSince(event.createdAt) > maximumAge {
                return discard(removeRecord: true)
            }
            guard normalizedPath(event.targetApplicationPath) == targetApplicationPath else {
                return discard(removeRecord: false)
            }
            return MountHandoffClaim(event: event, recordURL: eventURL, descriptor: descriptor)
        } catch {
            return discard(removeRecord: true)
        }
    }

    private func eventURL(id: UUID) -> URL {
        directoryURL.appendingPathComponent(canonicalFilename(id: id), isDirectory: false)
    }

    private func canonicalFilename(id: UUID) -> String {
        id.uuidString.lowercased() + ".json"
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private func recordMatchesDescriptor(at url: URL, descriptor: Int32) -> Bool {
        guard descriptor >= 0 else {
            return false
        }
        var descriptorInfo = stat()
        var pathInfo = stat()
        guard
            fstat(descriptor, &descriptorInfo) == 0,
            lstat(url.path, &pathInfo) == 0
        else {
            return false
        }
        return descriptorInfo.st_dev == pathInfo.st_dev
            && descriptorInfo.st_ino == pathInfo.st_ino
    }
}
