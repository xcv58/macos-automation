import Testing

@testable import SDImportCore

@Suite("Sidecar associator")
struct SidecarAssociatorTests {
    @Test("groups an unambiguous video with same-stem metadata and preview files")
    func groupsVideoSidecarsAcrossCameraFolders() throws {
        let video = jobFile(
            id: 1,
            relativePath: "PRIVATE/M4ROOT/CLIP/C0001.MP4",
            mediaKind: .video
        )
        let xml = jobFile(
            id: 2,
            relativePath: "PRIVATE/M4ROOT/CLIP/C0001.XML",
            mediaKind: .unsupported
        )
        let preview = jobFile(
            id: 3,
            relativePath: "PRIVATE/M4ROOT/THMBNL/C0001.JPG",
            mediaKind: .photo,
            size: 100_000
        )

        let result = SidecarAssociator().associate(files: [preview, video, xml])
        let group = try #require(result.groups.first)

        #expect(result.groups.count == 1)
        #expect(group.video.id == video.id)
        #expect(group.sidecars.map(\.id) == [xml.id, preview.id])
        #expect(result.unassociated.isEmpty)
    }

    @Test("does not guess when duplicate video stems make a cross-folder sidecar ambiguous")
    func leavesAmbiguousSidecarUngrouped() {
        let files = [
            jobFile(id: 1, relativePath: "DAY1/C0001.MP4", mediaKind: .video),
            jobFile(id: 2, relativePath: "DAY2/C0001.MP4", mediaKind: .video),
            jobFile(id: 3, relativePath: "META/C0001.XML", mediaKind: .unsupported)
        ]

        let result = SidecarAssociator().associate(files: files)

        #expect(result.groups.isEmpty)
        #expect(result.unassociated.map(\.id) == [3])
    }
}

private func jobFile(
    id: Int64,
    relativePath: String,
    mediaKind: MediaKind,
    size: Int64 = 10
) -> JobFileRecord {
    let filename = String(relativePath.split(separator: "/").last ?? "")
    return JobFileRecord(
        id: id,
        jobID: "job-1",
        sourcePath: "/Volumes/CARD/\(relativePath)",
        relativePath: relativePath,
        filename: filename,
        ext: ".\(filename.split(separator: ".").last?.lowercased() ?? "")",
        size: size,
        modificationDateString: "2026-04-29T12:00:00Z",
        mediaKind: mediaKind,
        fingerprint: nil,
        captureDate: "2026-04-29",
        decision: .new,
        destinationDirectory: nil,
        plannedDestinationPath: nil,
        copyStatus: .pending
    )
}
