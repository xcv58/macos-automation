import Foundation
import Testing

@testable import SDImportCore

@Suite("PortableImportReceiptLedger")
struct PortableImportReceiptLedgerTests {
    @Test("round trips a validated receipt")
    func roundTripsReceipt() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let identity = PortableFileIdentity(
            size: 17,
            modificationDate: modificationDate,
            relativePath: "DCIM/IMG_0001.JPG"
        )

        try ledger.append(
            identity: identity,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let snapshot = try ledger.load()
        #expect(
            snapshot.fingerprints == [
                PortableImportReceiptLedger.portableFingerprint(for: identity)
            ]
        )
        #expect(snapshot.invalidRecordCount == 0)
        #expect(snapshot.warning == nil)
        #expect(FileManager.default.fileExists(atPath: ledger.ledgerURL.path))
    }

    @Test("ignores corrupted and path-traversing records")
    func ignoresInvalidRecords() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let identity = PortableFileIdentity(
            size: 17,
            modificationDate: modificationDate,
            relativePath: "DCIM/IMG_0001.JPG"
        )
        try ledger.append(
            identity: identity,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let invalidLines = """
        {"schemaVersion":1,"fingerprintAlgorithm":"sdimport-v2","fingerprint":"invalid","size":17,"modificationDate":"2023-11-14T22:13:20","relativePath":"../IMG_0001.JPG","importedAt":"2023-11-14T22:13:20Z","checksum":"deadbeef"}
        {not-json}

        """
        let handle = try FileHandle(forWritingTo: ledger.ledgerURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(invalidLines.utf8))

        let snapshot = try ledger.load()
        #expect(
            snapshot.fingerprints == [
                PortableImportReceiptLedger.portableFingerprint(for: identity)
            ]
        )
        #expect(snapshot.invalidRecordCount == 2)
        #expect(snapshot.warning?.contains("2 invalid or corrupted portable import records") == true)
    }

    @Test("rejects a ledger directory masquerading as the ledger file")
    func rejectsNonFileLedger() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        try FileManager.default.createDirectory(
            at: ledger.ledgerURL,
            withIntermediateDirectories: true
        )

        #expect(throws: PortableImportReceiptLedgerError.self) {
            try ledger.load()
        }
    }

    @Test("portable fingerprints are stable across Mac time zones")
    func fingerprintsIgnoreTimeZoneFormatting() throws {
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let newYorkFingerprint = FileFingerprint.compute(
            size: 17,
            modificationDate: modificationDate,
            timeZone: newYork,
            identityHint: "DCIM/IMG_0001.JPG"
        )
        let tokyoFingerprint = FileFingerprint.compute(
            size: 17,
            modificationDate: modificationDate,
            timeZone: tokyo,
            identityHint: "DCIM/IMG_0001.JPG"
        )

        #expect(newYorkFingerprint.value != tokyoFingerprint.value)
        let newYorkIdentity = PortableFileIdentity(
            size: newYorkFingerprint.size,
            modificationDate: newYorkFingerprint.modificationDate,
            relativePath: "DCIM/IMG_0001.JPG"
        )
        let tokyoIdentity = PortableFileIdentity(
            size: tokyoFingerprint.size,
            modificationDate: tokyoFingerprint.modificationDate,
            relativePath: "DCIM/IMG_0001.JPG"
        )
        #expect(
            PortableImportReceiptLedger.portableFingerprint(for: newYorkIdentity)
                == PortableImportReceiptLedger.portableFingerprint(for: tokyoIdentity)
        )
    }

    @Test("portable identity distinguishes both sides of a DST fallback hour")
    func fingerprintsPreserveAmbiguousDSTEpochs() {
        let firstOccurrence = PortableFileIdentity(
            size: 17,
            modificationTimeEpochSeconds: 1_730_611_800,
            relativePath: "DCIM/IMG_DST.JPG"
        )
        let secondOccurrence = PortableFileIdentity(
            size: 17,
            modificationTimeEpochSeconds: 1_730_615_400,
            relativePath: "DCIM/IMG_DST.JPG"
        )

        #expect(firstOccurrence.modificationTimeEpochSeconds + 3_600 == secondOccurrence.modificationTimeEpochSeconds)
        #expect(
            PortableImportReceiptLedger.portableFingerprint(for: firstOccurrence)
                != PortableImportReceiptLedger.portableFingerprint(for: secondOccurrence)
        )
    }

    @Test("rejects a symlinked ledger directory without writing outside the source")
    func rejectsSymlinkedLedgerDirectory() throws {
        let sourceURL = try temporaryDirectory()
        let outsideURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        try FileManager.default.createSymbolicLink(
            at: ledger.ledgerURL.deletingLastPathComponent(),
            withDestinationURL: outsideURL
        )
        let identity = PortableFileIdentity(
            size: 17,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            relativePath: "DCIM/IMG_ESCAPE.JPG"
        )

        #expect(throws: PortableImportReceiptLedgerError.self) {
            try ledger.load()
        }
        #expect(throws: PortableImportReceiptLedgerError.self) {
            try ledger.append(identity: identity)
        }
        #expect(
            FileManager.default.fileExists(
                atPath: outsideURL.appendingPathComponent(PortableImportReceiptLedger.fileName).path
            ) == false
        )
    }

    @Test("preserves exact case and whitespace in portable fingerprint paths")
    func fingerprintsPreserveExactPathIdentity() {
        let upper = PortableImportReceiptLedger.portableFingerprint(
            for: PortableFileIdentity(
                size: 17,
                modificationTimeEpochSeconds: 1_700_000_000,
                relativePath: "DCIM/IMG.JPG"
            )
        )
        let lower = PortableImportReceiptLedger.portableFingerprint(
            for: PortableFileIdentity(
                size: 17,
                modificationTimeEpochSeconds: 1_700_000_000,
                relativePath: "DCIM/img.jpg"
            )
        )
        let spaced = PortableImportReceiptLedger.portableFingerprint(
            for: PortableFileIdentity(
                size: 17,
                modificationTimeEpochSeconds: 1_700_000_000,
                relativePath: "DCIM/IMG.JPG "
            )
        )

        #expect(upper != lower)
        #expect(upper != spaced)
    }

    @Test("separates a truncated tail before appending the next receipt")
    func recoversFromTruncatedTail() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        try FileManager.default.createDirectory(
            at: ledger.ledgerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"truncated\":".utf8).write(to: ledger.ledgerURL)
        let identity = PortableFileIdentity(
            size: 17,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            relativePath: "DCIM/IMG_RECOVER.JPG"
        )

        try ledger.append(identity: identity)

        let snapshot = try ledger.load()
        #expect(snapshot.invalidRecordCount == 1)
        #expect(
            snapshot.fingerprints.contains(
                PortableImportReceiptLedger.portableFingerprint(for: identity)
            )
        )
    }

    @Test("keeps valid receipts when a multibyte UTF-8 tail is truncated")
    func isolatesTruncatedMultibyteTail() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        let firstIdentity = PortableFileIdentity(
            size: 17,
            modificationTimeEpochSeconds: 1_700_000_000,
            relativePath: "DCIM/IMG_VALID.JPG"
        )
        try ledger.append(identity: firstIdentity)

        do {
            let handle = try FileHandle(forWritingTo: ledger.ledgerURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data([0x7B, 0x22, 0xC3]))
        }

        var snapshot = try ledger.load()
        #expect(snapshot.invalidRecordCount == 1)
        #expect(
            snapshot.fingerprints == [
                PortableImportReceiptLedger.portableFingerprint(for: firstIdentity)
            ]
        )

        let secondIdentity = PortableFileIdentity(
            size: 18,
            modificationTimeEpochSeconds: 1_700_000_100,
            relativePath: "DCIM/IMG_AFTER_TRUNCATION.JPG"
        )
        try ledger.append(identity: secondIdentity)

        snapshot = try ledger.load()
        #expect(snapshot.invalidRecordCount == 1)
        #expect(snapshot.fingerprints.count == 2)
        #expect(
            snapshot.fingerprints.contains(
                PortableImportReceiptLedger.portableFingerprint(for: secondIdentity)
            )
        )
    }

    @Test("serializes concurrent receipt appends")
    func serializesConcurrentAppends() async throws {
        let sourceURL = try temporaryDirectory()
        let receiptCount = 32

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<receiptCount {
                group.addTask {
                    let relativePath = "DCIM/IMG_\(index).JPG"
                    let identity = PortableFileIdentity(
                        size: Int64(index + 1),
                        modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
                        relativePath: relativePath
                    )
                    try PortableImportReceiptLedger(sourceRootURL: sourceURL).append(
                        identity: identity
                    )
                }
            }
            try await group.waitForAll()
        }

        let snapshot = try PortableImportReceiptLedger(sourceRootURL: sourceURL).load()
        #expect(snapshot.fingerprints.count == receiptCount)
        #expect(snapshot.invalidRecordCount == 0)
    }
}
