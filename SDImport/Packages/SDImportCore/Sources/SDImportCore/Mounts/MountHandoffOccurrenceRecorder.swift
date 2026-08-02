import Foundation

/// Persists every helper-observed mount as its own durable occurrence.
/// Cross-origin correlation happens only when the app consumes the event.
public struct MountHandoffOccurrenceRecorder {
    private let store: MountHandoffStore

    public init(store: MountHandoffStore) {
        self.store = store
    }

    @discardableResult
    public func persistBackgroundAgentOccurrence(
        volume: MountedVolume,
        agentBuild: String,
        agentSequence: UInt64,
        targetApplicationPath: String,
        now: Date = Date(),
        id: UUID = UUID()
    ) throws -> MountHandoffEvent {
        try store.enqueue(
            mountPath: volume.mountURL.path,
            volumeName: volume.name,
            agentBuild: agentBuild,
            agentSequence: agentSequence,
            targetApplicationPath: targetApplicationPath,
            origin: .backgroundAgent,
            mountedVolume: volume,
            now: now,
            id: id
        )
    }
}
