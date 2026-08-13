import Foundation

public struct PhotoPairSummary: Equatable, Sendable {
    public let rawJPEGPairCount: Int
    public let rawOnlyCount: Int
    public let jpegOnlyCount: Int

    public init(rawJPEGPairCount: Int, rawOnlyCount: Int, jpegOnlyCount: Int) {
        self.rawJPEGPairCount = rawJPEGPairCount
        self.rawOnlyCount = rawOnlyCount
        self.jpegOnlyCount = jpegOnlyCount
    }
}

public struct PhotoPairGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let rawFiles: [JobFileRecord]
    public let jpegFiles: [JobFileRecord]

    public init(id: String, rawFiles: [JobFileRecord], jpegFiles: [JobFileRecord]) {
        self.id = id
        self.rawFiles = rawFiles
        self.jpegFiles = jpegFiles
    }

    public var isPair: Bool {
        !rawFiles.isEmpty && !jpegFiles.isEmpty
    }
}

public struct PhotoPairDetector: Sendable {
    private let rawExtensions: Set<String> = [
        ".arw",
        ".cr2",
        ".dng",
        ".nef",
        ".raf",
        ".raw"
    ]
    private let jpegExtensions: Set<String> = [
        ".jpg",
        ".jpeg"
    ]

    public init() {}

    public func summarize(files: [JobFileRecord]) -> PhotoPairSummary {
        var pairCount = 0
        var rawOnlyCount = 0
        var jpegOnlyCount = 0

        for group in groups(files: files) {
            let pairs = min(group.rawFiles.count, group.jpegFiles.count)
            pairCount += pairs
            rawOnlyCount += max(0, group.rawFiles.count - pairs)
            jpegOnlyCount += max(0, group.jpegFiles.count - pairs)
        }

        return PhotoPairSummary(
            rawJPEGPairCount: pairCount,
            rawOnlyCount: rawOnlyCount,
            jpegOnlyCount: jpegOnlyCount
        )
    }

    public func groups(files: [JobFileRecord]) -> [PhotoPairGroup] {
        struct Group {
            var rawFiles: [JobFileRecord] = []
            var jpegFiles: [JobFileRecord] = []
        }

        var grouped: [String: Group] = [:]
        for file in files where file.mediaKind == .photo {
            let ext = file.ext.lowercased()
            guard rawExtensions.contains(ext) || jpegExtensions.contains(ext) else {
                continue
            }

            let key = pairKey(for: file)
            var group = grouped[key, default: Group()]
            if rawExtensions.contains(ext) {
                group.rawFiles.append(file)
            } else {
                group.jpegFiles.append(file)
            }
            grouped[key] = group
        }

        return grouped.map { key, group in
            PhotoPairGroup(
                id: key,
                rawFiles: group.rawFiles.sorted(by: Self.fileOrder),
                jpegFiles: group.jpegFiles.sorted(by: Self.fileOrder)
            )
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private func pairKey(for file: JobFileRecord) -> String {
        let relativePath = (file.relativePath ?? file.filename)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        let url = URL(fileURLWithPath: relativePath)
        let directory = url.deletingLastPathComponent().path
        let stem = url.deletingPathExtension().lastPathComponent
        return "\(directory)/\(stem)"
    }

    private static func fileOrder(_ lhs: JobFileRecord, _ rhs: JobFileRecord) -> Bool {
        lhs.sourcePath.localizedStandardCompare(rhs.sourcePath) == .orderedAscending
    }
}
