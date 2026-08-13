import Foundation

public struct MediaSidecarGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let video: JobFileRecord
    public let sidecars: [JobFileRecord]

    public init(id: String, video: JobFileRecord, sidecars: [JobFileRecord]) {
        self.id = id
        self.video = video
        self.sidecars = sidecars
    }
}

public struct SidecarAssociationResult: Equatable, Sendable {
    public let groups: [MediaSidecarGroup]
    public let unassociated: [JobFileRecord]

    public init(groups: [MediaSidecarGroup], unassociated: [JobFileRecord]) {
        self.groups = groups
        self.unassociated = unassociated
    }
}

public struct SidecarAssociator: Sendable {
    public init() {}

    public func associate(files: [JobFileRecord]) -> SidecarAssociationResult {
        let videos = files.filter { $0.mediaKind == .video }
        let candidates = files.filter {
            $0.mediaKind == .unsupported || MediaFileHeuristics.isLikelyVideoPreviewJPEG($0)
        }
        let videosByStem = Dictionary(grouping: videos, by: associationStem)
        var sidecarsByVideo: [String: [JobFileRecord]] = [:]
        var unassociated: [JobFileRecord] = []

        for candidate in candidates {
            let matchingVideos = videosByStem[associationStem(candidate)] ?? []
            let video: JobFileRecord?
            if matchingVideos.count == 1 {
                video = matchingVideos[0]
            } else {
                let directory = normalizedDirectory(candidate)
                let sameDirectoryVideos = matchingVideos.filter { normalizedDirectory($0) == directory }
                video = sameDirectoryVideos.count == 1 ? sameDirectoryVideos[0] : nil
            }
            guard let video else {
                unassociated.append(candidate)
                continue
            }
            sidecarsByVideo[video.sourcePath, default: []].append(candidate)
        }

        let groups = videos.compactMap { video -> MediaSidecarGroup? in
            guard let sidecars = sidecarsByVideo[video.sourcePath], !sidecars.isEmpty else {
                return nil
            }
            return MediaSidecarGroup(
                id: video.sourcePath,
                video: video,
                sidecars: sidecars.sorted(by: Self.fileOrder)
            )
        }
        .sorted { Self.fileOrder($0.video, $1.video) }

        return SidecarAssociationResult(
            groups: groups,
            unassociated: unassociated.sorted(by: Self.fileOrder)
        )
    }

    private func associationStem(_ file: JobFileRecord) -> String {
        let relativePath = (file.relativePath ?? file.filename)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        let url = URL(fileURLWithPath: relativePath)
        return url.deletingPathExtension().lastPathComponent
    }

    private func normalizedDirectory(_ file: JobFileRecord) -> String {
        let relativePath = (file.relativePath ?? file.filename)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        return URL(fileURLWithPath: relativePath).deletingLastPathComponent().path
    }

    private static func fileOrder(_ lhs: JobFileRecord, _ rhs: JobFileRecord) -> Bool {
        lhs.sourcePath.localizedStandardCompare(rhs.sourcePath) == .orderedAscending
    }
}
