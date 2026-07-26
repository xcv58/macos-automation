import Foundation

public struct MountDebouncer: Sendable {
    private let interval: TimeInterval
    private var lastSeenBySource: [String: Date] = [:]

    public init(interval: TimeInterval = 5) {
        self.interval = interval
    }

    public mutating func shouldAccept(_ volume: MountedVolume, now: Date = Date()) -> Bool {
        let key: String
        if let deviceIdentifier = volume.deviceGroupIdentifier, !deviceIdentifier.isEmpty {
            key = "device:\(deviceIdentifier)"
        } else if let wholeDiskIdentifier = volume.wholeDiskIdentifier, !wholeDiskIdentifier.isEmpty {
            key = "disk:\(wholeDiskIdentifier)"
        } else {
            key = "volume:\(volume.mountURL.standardizedFileURL.path)"
        }

        if let lastSeen = lastSeenBySource[key], now.timeIntervalSince(lastSeen) < interval {
            return false
        }

        lastSeenBySource[key] = now
        return true
    }
}
