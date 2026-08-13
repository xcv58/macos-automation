import Foundation
import Testing

@testable import SDImportCore

@Suite("ImportPlanBuilder")
struct ImportPlanBuilderTests {
    @Test("typed dispositions define stable labels and attention levels")
    func typedDispositionPresentation() {
        #expect(ImportPlanDisposition.copy.title == "Will copy")
        #expect(ImportPlanDisposition.copy.attention == .normal)
        #expect(ImportPlanDisposition.known(.localLedger).attention == .informational)
        #expect(ImportPlanDisposition.known(.portableLedger).title == "Other Mac")
        #expect(ImportPlanDisposition.known(.portableLedger).attention == .attention)
        #expect(ImportPlanDisposition.noDestination.attention == .blocking)
        #expect(
            ImportPlanDisposition.rename(
                originalPath: "/a.mov",
                destinationPath: "/a-copy-1.mov",
                reason: "exists"
            ).attention == .attention
        )
    }

    @Test("mixed visual groups report both copied and skipped members")
    func mixedVisualGroupStatus() {
        let summary = ImportPreviewGroupDispositionSummary(copyCount: 1, skippedCount: 1)

        #expect(summary.mixedStatusTitle == "1 copy · 1 skipped")
        #expect(
            ImportPreviewGroupDispositionSummary(copyCount: 2, skippedCount: 0)
                .mixedStatusTitle == nil
        )
    }

    @Test("receipt totals include skipped and failed job files")
    func receiptTotalsUseFinalJobFileStatuses() {
        let files = [
            jobFile(
                id: 1,
                filename: "COPIED.JPG",
                relativePath: "COPIED.JPG",
                mediaKind: .photo,
                captureDate: "2026-05-06",
                copyStatus: .copied
            ),
            jobFile(
                id: 2,
                filename: "SKIPPED.JPG",
                relativePath: "SKIPPED.JPG",
                mediaKind: .photo,
                captureDate: "2026-05-06",
                copyStatus: .skipped
            ),
            jobFile(
                id: 3,
                filename: "FAILED.JPG",
                relativePath: "FAILED.JPG",
                mediaKind: .photo,
                captureDate: "2026-05-06",
                copyStatus: .failed
            )
        ]

        let totals = ImportReceiptTotals(files: files)

        #expect(totals.copiedFiles == 1)
        #expect(totals.copiedBytes == 1024)
        #expect(totals.skippedFiles == 1)
        #expect(totals.failedFiles == 1)
    }

    @Test("copied files are not rewritten during replanning")
    func copiedFilesDoNotProducePlanUpdates() {
        let originalDestination = "/Original/Photos/IMG_0001.JPG"
        let file = JobFileRecord(
            id: 42,
            jobID: "job-copied",
            sourcePath: "/Volumes/CARD/DCIM/IMG_0001.JPG",
            relativePath: "DCIM/IMG_0001.JPG",
            filename: "IMG_0001.JPG",
            ext: ".jpg",
            size: 1024,
            modificationDateString: "2024-07-15T10:00:00",
            mediaKind: .photo,
            fingerprint: "v2:fingerprint",
            captureDate: "2024-07-15",
            decision: .new,
            destinationDirectory: "/Original/Photos",
            plannedDestinationPath: originalDestination,
            finalDestinationPath: originalDestination,
            copyStatus: .copied,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let builder = ImportPlanBuilder(
            sessions: [
                ImportPlanSession(
                    date: "2024-07-15",
                    label: "Changed Session",
                    photoCount: 1,
                    videoCount: 0,
                    unsupportedCount: 0,
                    includePhotos: true,
                    includeVideos: false,
                    includeSidecars: false
                )
            ],
            organizationPreset: .shootSessionsByDate,
            roots: DestinationRoots(
                photosURL: URL(fileURLWithPath: "/Changed/Photos", isDirectory: true),
                videosURL: URL(fileURLWithPath: "/Changed/Videos", isDirectory: true)
            ),
            fallbackLocation: "Changed Location",
            volumeName: "CARD"
        )

        let plan = builder.plan(file: file)

        #expect(plan.update == nil)
        #expect(plan.willCopy == false)
        #expect(plan.status == "Copied")
        #expect(plan.destinationPath == originalDestination)
        #expect(builder.updates(files: [file]).isEmpty)
    }

    @Test("one shoot folder uses a date range and flat destinations")
    func oneShootFolderUsesDateRangeAndFlatDestinations() throws {
        let files = [
            jobFile(
                id: 1,
                filename: "IMG_0001.JPG",
                relativePath: "DCIM/100/IMG_0001.JPG",
                mediaKind: .photo,
                captureDate: "2026-05-02"
            ),
            jobFile(
                id: 2,
                filename: "C0001.MP4",
                relativePath: "PRIVATE/M4ROOT/CLIP/C0001.MP4",
                mediaKind: .video,
                captureDate: "2026-05-04"
            )
        ]
        let builder = ImportPlanBuilder(
            sessions: [
                session(date: "2026-05-02", photoCount: 1, videoCount: 0),
                session(date: "2026-05-04", photoCount: 0, videoCount: 1)
            ],
            organizationPreset: .shootSessionsByDate,
            folderGrouping: .oneShootFolder,
            roots: DestinationRoots(
                photosURL: URL(fileURLWithPath: "/Library", isDirectory: true),
                videosURL: URL(fileURLWithPath: "/Footage", isDirectory: true)
            ),
            fallbackLocation: "Launch Weekend",
            volumeName: "CARD"
        )

        let plans = builder.plans(files: files)

        #expect(plans.map(\.destinationPath) == [
            "/Library/2026-05-02 to 2026-05-04 Launch Weekend/IMG_0001.JPG",
            "/Library/2026-05-02 to 2026-05-04 Launch Weekend/C0001.MP4"
        ])
    }

    @Test("one shoot folder renames duplicate filenames within the same import")
    func oneShootFolderRenamesDuplicateFilenamesInBatch() throws {
        let files = [
            jobFile(
                id: 1,
                filename: "C0001.MP4",
                relativePath: "DAY1/C0001.MP4",
                mediaKind: .video,
                captureDate: "2026-05-02"
            ),
            jobFile(
                id: 2,
                filename: "C0001.MP4",
                relativePath: "DAY2/C0001.MP4",
                mediaKind: .video,
                captureDate: "2026-05-03"
            )
        ]
        let builder = ImportPlanBuilder(
            sessions: [
                session(date: "2026-05-02", photoCount: 0, videoCount: 1),
                session(date: "2026-05-03", photoCount: 0, videoCount: 1)
            ],
            organizationPreset: .footageBackup,
            folderGrouping: .oneShootFolder,
            roots: DestinationRoots(
                photosURL: URL(fileURLWithPath: "/Library", isDirectory: true),
                videosURL: URL(fileURLWithPath: "/Footage", isDirectory: true)
            ),
            fallbackLocation: "Race Weekend",
            volumeName: "CARD"
        )

        let plans = builder.plans(files: files)

        #expect(plans.map(\.destinationPath) == [
            "/Footage/2026-05-02 to 2026-05-03 Race Weekend/C0001.MP4",
            "/Footage/2026-05-02 to 2026-05-03 Race Weekend/C0001-copy-1.MP4"
        ])
        #expect(plans[1].status == "Rename")
        #expect(
            plans[1].disposition
                == .rename(
                    originalPath: "/Footage/2026-05-02 to 2026-05-03 Race Weekend/C0001.MP4",
                    destinationPath: "/Footage/2026-05-02 to 2026-05-03 Race Weekend/C0001-copy-1.MP4",
                    reason: "destination file name repeats in this import"
                )
        )
        #expect(plans[1].disposition.attention == .attention)
        #expect(plans[1].update?.error == "destination file name repeats in this import")
    }

    @Test("footage backup renames duplicate filenames in flat day folder")
    func footageBackupRenamesDuplicateFilenamesInFlatDayFolder() throws {
        let files = [
            jobFile(
                id: 1,
                filename: "C0001.MP4",
                relativePath: "PRIVATE/M4ROOT/CLIP/C0001.MP4",
                mediaKind: .video,
                captureDate: "2026-05-06"
            ),
            jobFile(
                id: 2,
                filename: "C0001.MP4",
                relativePath: "PRIVATE/M4ROOT/CLIP2/C0001.MP4",
                mediaKind: .video,
                captureDate: "2026-05-06"
            )
        ]
        let builder = ImportPlanBuilder(
            sessions: [
                session(date: "2026-05-06", label: "XXX", photoCount: 0, videoCount: 2)
            ],
            organizationPreset: .footageBackup,
            roots: DestinationRoots(
                photosURL: URL(fileURLWithPath: "/Library", isDirectory: true),
                videosURL: URL(fileURLWithPath: "/Footage", isDirectory: true)
            ),
            fallbackLocation: "XXX",
            volumeName: "CARD"
        )

        let plans = builder.plans(files: files)

        #expect(plans.map(\.destinationPath) == [
            "/Footage/2026-05-06 XXX/C0001.MP4",
            "/Footage/2026-05-06 XXX/C0001-copy-1.MP4"
        ])
        #expect(plans[1].status == "Rename")
        #expect(plans[1].update?.error == "destination file name repeats in this import")
    }

    @Test("footage backup sidecars are opt-in")
    func footageBackupSidecarsAreOptIn() throws {
        let file = jobFile(
            id: 1,
            filename: "C0001.XML",
            relativePath: "PRIVATE/M4ROOT/CLIP/C0001.XML",
            mediaKind: .unsupported,
            captureDate: "2026-05-06"
        )

        let defaultBuilder = ImportPlanBuilder(
            sessions: [
                session(
                    date: "2026-05-06",
                    label: "Singapore Trip",
                    photoCount: 0,
                    videoCount: 0,
                    unsupportedCount: 1,
                    includeSidecars: false
                )
            ],
            organizationPreset: .footageBackup,
            roots: DestinationRoots(
                photosURL: URL(fileURLWithPath: "/Library", isDirectory: true),
                videosURL: URL(fileURLWithPath: "/Footage", isDirectory: true)
            ),
            fallbackLocation: "Singapore Trip",
            volumeName: "CARD"
        )

        let optInBuilder = ImportPlanBuilder(
            sessions: [
                session(
                    date: "2026-05-06",
                    label: "Singapore Trip",
                    photoCount: 0,
                    videoCount: 0,
                    unsupportedCount: 1,
                    includeSidecars: true
                )
            ],
            organizationPreset: .footageBackup,
            roots: DestinationRoots(
                photosURL: URL(fileURLWithPath: "/Library", isDirectory: true),
                videosURL: URL(fileURLWithPath: "/Footage", isDirectory: true)
            ),
            fallbackLocation: "Singapore Trip",
            volumeName: "CARD"
        )

        let defaultPlan = defaultBuilder.plan(file: file)
        let optInPlan = optInBuilder.plan(file: file)

        #expect(defaultPlan.willCopy == false)
        #expect(defaultPlan.status == "Unsupported")
        #expect(optInPlan.willCopy)
        #expect(optInPlan.destinationPath == "/Footage/2026-05-06 Singapore Trip/C0001.XML")
    }

    @Test("tiny JPEG previews in footage backup are opt-in sidecars")
    func tinyJPEGPreviewsInFootageBackupAreOptInSidecars() throws {
        let file = jobFile(
            id: 1,
            filename: "C0001.JPG",
            relativePath: "PRIVATE/M4ROOT/THMBNL/C0001.JPG",
            mediaKind: .photo,
            captureDate: "2026-05-06"
        )

        let defaultBuilder = ImportPlanBuilder(
            sessions: [
                session(
                    date: "2026-05-06",
                    label: "Singapore Trip",
                    photoCount: 0,
                    videoCount: 1,
                    unsupportedCount: 1,
                    includeSidecars: false
                )
            ],
            organizationPreset: .footageBackup,
            roots: DestinationRoots(
                photosURL: URL(fileURLWithPath: "/Library", isDirectory: true),
                videosURL: URL(fileURLWithPath: "/Footage", isDirectory: true)
            ),
            fallbackLocation: "Singapore Trip",
            volumeName: "CARD"
        )

        let optInBuilder = ImportPlanBuilder(
            sessions: [
                session(
                    date: "2026-05-06",
                    label: "Singapore Trip",
                    photoCount: 0,
                    videoCount: 1,
                    unsupportedCount: 1,
                    includeSidecars: true
                )
            ],
            organizationPreset: .footageBackup,
            roots: DestinationRoots(
                photosURL: URL(fileURLWithPath: "/Library", isDirectory: true),
                videosURL: URL(fileURLWithPath: "/Footage", isDirectory: true)
            ),
            fallbackLocation: "Singapore Trip",
            volumeName: "CARD"
        )

        let defaultPlan = defaultBuilder.plan(file: file)
        let optInPlan = optInBuilder.plan(file: file)

        #expect(defaultPlan.willCopy == false)
        #expect(defaultPlan.status == "Unsupported")
        #expect(optInPlan.willCopy)
        #expect(optInPlan.disposition == .supportFile)
        #expect(optInPlan.status == "Support file")
        #expect(optInPlan.destinationPath == "/Footage/2026-05-06 Singapore Trip/C0001.JPG")
    }

    @Test("date customization cannot re-enable globally excluded photos")
    func globalVideoSelectionOverridesDatePhotoSelection() {
        let file = jobFile(
            id: 1,
            filename: "IMG_0100.ARW",
            relativePath: "DCIM/100/IMG_0100.ARW",
            mediaKind: .photo,
            captureDate: "2026-05-06"
        )
        let builder = ImportPlanBuilder(
            sessions: [session(date: "2026-05-06", photoCount: 1, videoCount: 0)],
            mediaSelection: .videosOnly,
            organizationPreset: .classicDatedFolders,
            roots: DestinationRoots(
                photosURL: URL(fileURLWithPath: "/Library", isDirectory: true),
                videosURL: URL(fileURLWithPath: "/Footage", isDirectory: true)
            ),
            fallbackLocation: "Singapore Trip",
            volumeName: "CARD"
        )

        let plan = builder.plan(file: file)

        #expect(plan.willCopy == false)
        #expect(plan.disposition == .excluded)
    }

    @Test("date customization cannot re-enable globally excluded videos")
    func globalPhotoSelectionOverridesDateVideoSelection() {
        let file = jobFile(
            id: 1,
            filename: "C0001.MP4",
            relativePath: "PRIVATE/M4ROOT/CLIP/C0001.MP4",
            mediaKind: .video,
            captureDate: "2026-05-06"
        )
        let builder = ImportPlanBuilder(
            sessions: [session(date: "2026-05-06", photoCount: 0, videoCount: 1)],
            mediaSelection: .photosOnly,
            organizationPreset: .classicDatedFolders,
            roots: DestinationRoots(
                photosURL: URL(fileURLWithPath: "/Library", isDirectory: true),
                videosURL: URL(fileURLWithPath: "/Footage", isDirectory: true)
            ),
            fallbackLocation: "Singapore Trip",
            volumeName: "CARD"
        )

        let plan = builder.plan(file: file)

        #expect(plan.willCopy == false)
        #expect(plan.disposition == .excluded)
    }

    private func session(
        date: String,
        label: String = "Ignored Per-Day Label",
        photoCount: Int,
        videoCount: Int,
        unsupportedCount: Int = 0,
        includeSidecars: Bool = false
    ) -> ImportPlanSession {
        ImportPlanSession(
            date: date,
            label: label,
            photoCount: photoCount,
            videoCount: videoCount,
            unsupportedCount: unsupportedCount,
            includePhotos: true,
            includeVideos: true,
            includeSidecars: includeSidecars
        )
    }

    private func jobFile(
        id: Int64,
        filename: String,
        relativePath: String,
        mediaKind: MediaKind,
        captureDate: String,
        copyStatus: CopyStatus = .pending
    ) -> JobFileRecord {
        JobFileRecord(
            id: id,
            jobID: "job-1",
            sourcePath: "/Volumes/CARD/\(relativePath)",
            relativePath: relativePath,
            filename: filename,
            ext: ".\(URL(fileURLWithPath: filename).pathExtension.lowercased())",
            size: 1024,
            modificationDateString: "\(captureDate)T10:00:00",
            mediaKind: mediaKind,
            fingerprint: "v2:\(id)",
            captureDate: captureDate,
            decision: .new,
            destinationDirectory: nil,
            plannedDestinationPath: nil,
            copyStatus: copyStatus
        )
    }
}
