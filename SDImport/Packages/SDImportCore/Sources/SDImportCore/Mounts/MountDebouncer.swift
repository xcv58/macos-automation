import Foundation

public struct MountDebouncer: Sendable {
    private let interval: TimeInterval
    private var lastSeenBySource: [String: Date] = [:]

    public init(interval: TimeInterval = 5) {
        self.interval = interval
    }

    public mutating func shouldAccept(_ volume: MountedVolume, now: Date = Date()) -> Bool {
        guard !hasRecentlyAccepted(volume, now: now) else {
            return false
        }

        recordAccepted(volume, now: now)
        return true
    }

    public func hasRecentlyAccepted(_ volume: MountedVolume, now: Date = Date()) -> Bool {
        let key = sourceKey(for: volume)
        guard let lastSeen = lastSeenBySource[key] else {
            return false
        }
        return now.timeIntervalSince(lastSeen) < interval
    }

    public mutating func recordAccepted(_ volume: MountedVolume, now: Date = Date()) {
        lastSeenBySource[sourceKey(for: volume)] = now
    }

    private func sourceKey(for volume: MountedVolume) -> String {
        if let deviceIdentifier = volume.deviceGroupIdentifier, !deviceIdentifier.isEmpty {
            return "device:\(deviceIdentifier)"
        } else if let wholeDiskIdentifier = volume.wholeDiskIdentifier, !wholeDiskIdentifier.isEmpty {
            return "disk:\(wholeDiskIdentifier)"
        } else {
            return "volume:\(volume.mountURL.standardizedFileURL.path)"
        }
    }
}
