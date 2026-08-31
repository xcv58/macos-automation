import Foundation

#if DEBUG
public enum BackgroundPromptRuntimeQA {
    public static let prepareApplicationArgument = "--sdimport-helper-runtime-qa-prepare"
    public static let consumeHandoffArgument = "--sdimport-helper-runtime-qa-consume-handoff"
    public static let unregisterHelperArgument = "--sdimport-helper-runtime-qa-unregister"
    public static let injectedMountArgument = "--sdimport-helper-runtime-qa-mount"

    public static func preparesApplication(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        distribution: AppDistribution = .current
    ) -> Bool {
        distribution == .macAppStore && arguments.contains(prepareApplicationArgument)
    }

    public static func unregistersHelper(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        distribution: AppDistribution = .current
    ) -> Bool {
        distribution == .macAppStore && arguments.contains(unregisterHelperArgument)
    }

    public static func consumesInjectedHandoff(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        distribution: AppDistribution = .current
    ) -> Bool {
        distribution == .macAppStore && arguments.contains(consumeHandoffArgument)
    }

    public static func injectedMountURL(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        distribution: AppDistribution = .current
    ) -> URL? {
        guard distribution == .macAppStore else {
            return nil
        }
        guard
            let argumentIndex = arguments.firstIndex(of: injectedMountArgument),
            arguments.indices.contains(argumentIndex + 1)
        else {
            return nil
        }
        let url = URL(
            fileURLWithPath: arguments[argumentIndex + 1],
            isDirectory: true
        ).standardizedFileURL
        guard url.path.hasPrefix("/Volumes/") else {
            return nil
        }
        return url
    }

    public static func injectedPostDetectionVolume(at mountURL: URL) -> MountedVolume {
        let url = mountURL.standardizedFileURL
        return MountedVolume(
            id: "runtime-qa:\(url.path)",
            name: url.lastPathComponent,
            mountURL: url,
            volumeUUID: nil,
            isRemovable: true,
            isInternal: false,
            isDiskImage: false,
            totalCapacityBytes: nil,
            availableCapacityBytes: nil
        )
    }
}
#endif
