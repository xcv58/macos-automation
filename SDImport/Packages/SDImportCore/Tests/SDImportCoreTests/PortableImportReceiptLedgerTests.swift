import CryptoKit
import Darwin
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

    @Test("reloads only when the ledger revision changes")
    func reloadsChangedLedgerRevisions() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        let missingSnapshot = try ledger.load()

        #expect(missingSnapshot.revision == .missing)
        #expect(try ledger.load(ifChangedSince: missingSnapshot.revision) == nil)

        let firstIdentity = PortableFileIdentity(
            size: 17,
            modificationTimeEpochSeconds: 1_700_000_000,
            relativePath: "DCIM/IMG_FIRST.JPG"
        )
        let firstAppend = try ledger.appendReturningRevision(identity: firstIdentity)
        #expect(try ledger.load(ifChangedSince: firstAppend.revision) == nil)

        let secondIdentity = PortableFileIdentity(
            size: 18,
            modificationTimeEpochSeconds: 1_700_000_100,
            relativePath: "DCIM/IMG_SECOND.JPG"
        )
        try ledger.append(identity: secondIdentity)

        let changedSnapshot = try ledger.load(ifChangedSince: firstAppend.revision)
        let updatedSnapshot = try #require(changedSnapshot)
        #expect(updatedSnapshot.fingerprints.count == 2)
        #expect(updatedSnapshot.revision != firstAppend.revision)
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

        let traversalIdentity = PortableFileIdentity(
            size: 17,
            modificationTimeEpochSeconds: 1_700_000_000,
            relativePath: "../IMG_0001.JPG"
        )
        let traversalRecord = try encodedTestReceipt(identity: traversalIdentity)
        let invalidLines = "\(traversalRecord)\n{not-json}\n"
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

    @Test("normalizes Unicode path forms in portable fingerprints")
    func fingerprintsNormalizeUnicodePaths() {
        let decomposedPath = "DCIM/Cafe\u{301}.JPG"
        let composedPath = decomposedPath.precomposedStringWithCanonicalMapping
        #expect(Array(decomposedPath.utf8) != Array(composedPath.utf8))

        let decomposed = PortableImportReceiptLedger.portableFingerprint(
            for: PortableFileIdentity(
                size: 17,
                modificationTimeEpochSeconds: 1_700_000_000,
                relativePath: decomposedPath
            )
        )
        let composed = PortableImportReceiptLedger.portableFingerprint(
            for: PortableFileIdentity(
                size: 17,
                modificationTimeEpochSeconds: 1_700_000_000,
                relativePath: composedPath
            )
        )

        #expect(decomposed == composed)
        #expect(decomposed.hasPrefix("p2:"))
    }

    @Test("rejects invalid identities with a ledger-specific error")
    func rejectsInvalidIdentity() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        let identity = PortableFileIdentity(
            size: 17,
            modificationTimeEpochSeconds: 1_700_000_000,
            relativePath: "../IMG_INVALID.JPG"
        )

        do {
            try ledger.append(identity: identity)
            Issue.record("invalid identity should not be appended")
        } catch let error as PortableImportReceiptLedgerError {
            guard case .invalidReceipt = error else {
                Issue.record("unexpected ledger error: \(error)")
                return
            }
        }
    }

    @Test("rejects a validly formatted but incorrect checksum")
    func rejectsChecksumMismatch() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        let identity = PortableFileIdentity(
            size: 17,
            modificationTimeEpochSeconds: 1_700_000_000,
            relativePath: "DCIM/IMG_CHECKSUM.JPG"
        )
        let record = try encodedTestReceipt(
            identity: identity,
            checksumOverride: String(repeating: "0", count: 64)
        )
        try FileManager.default.createDirectory(
            at: ledger.ledgerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("\(record)\n".utf8).write(to: ledger.ledgerURL)

        let snapshot = try ledger.load()
        #expect(snapshot.fingerprints.isEmpty)
        #expect(snapshot.invalidRecordCount == 1)
    }

    @Test("rejects ledgers larger than the configured limit")
    func rejectsOversizedLedger() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        try FileManager.default.createDirectory(
            at: ledger.ledgerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #expect(FileManager.default.createFile(atPath: ledger.ledgerURL.path, contents: nil))
        let handle = try FileHandle(forWritingTo: ledger.ledgerURL)
        try handle.truncate(atOffset: UInt64(64 * 1_024 * 1_024 + 1))
        try handle.close()

        do {
            _ = try ledger.load()
            Issue.record("oversized ledger should not load")
        } catch let error as PortableImportReceiptLedgerError {
            guard case .ledgerTooLarge(let size) = error else {
                Issue.record("unexpected ledger error: \(error)")
                return
            }
            #expect(size == 64 * 1_024 * 1_024 + 1)
        }
    }

    @Test("rejects encoded records larger than the configured limit")
    func rejectsOversizedRecord() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        let identity = PortableFileIdentity(
            size: 17,
            modificationTimeEpochSeconds: 1_700_000_000,
            relativePath: String(repeating: "\u{0001}", count: 4_096)
        )

        do {
            try ledger.append(identity: identity)
            Issue.record("oversized record should not be appended")
        } catch let error as PortableImportReceiptLedgerError {
            guard case .recordTooLarge(let size) = error else {
                Issue.record("unexpected ledger error: \(error)")
                return
            }
            #expect(size > 16 * 1_024)
        }
    }

    @Test(
        "reports an unwritable source",
        .enabled(if: geteuid() != 0, "root bypasses POSIX write permissions")
    )
    func rejectsReadOnlySourceAppend() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sourceURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sourceURL.path)
        }

        do {
            try ledger.append(
                identity: PortableFileIdentity(
                    size: 17,
                    modificationTimeEpochSeconds: 1_700_000_000,
                    relativePath: "DCIM/IMG_READ_ONLY.JPG"
                )
            )
            Issue.record("read-only source should reject the ledger append")
        } catch let error as NSError {
            #expect(error.domain == NSPOSIXErrorDomain)
            #expect(error.code == Int(EACCES) || error.code == Int(EROFS))
        }
    }

    @Test("batch append writes every identity")
    func appendsIdentityBatch() throws {
        let sourceURL = try temporaryDirectory()
        let ledger = PortableImportReceiptLedger(sourceRootURL: sourceURL)
        let identities = (0..<3).map { index in
            PortableFileIdentity(
                size: Int64(index + 1),
                modificationTimeEpochSeconds: 1_700_000_000 + Int64(index),
                relativePath: "DCIM/IMG_BATCH_\(index).JPG"
            )
        }

        try ledger.append(identities: identities)

        let snapshot = try ledger.load()
        #expect(snapshot.fingerprints.count == identities.count)
        #expect(
            snapshot.fingerprints
                == Set(identities.map(PortableImportReceiptLedger.portableFingerprint(for:)))
        )
    }

    @Test("continues with a warning when advisory locks are unsupported")
    func toleratesUnsupportedAdvisoryLocks() throws {
        let sourceURL = try temporaryDirectory()
        let firstIdentity = PortableFileIdentity(
            size: 17,
            modificationTimeEpochSeconds: 1_700_000_000,
            relativePath: "DCIM/IMG_LOCK_FIRST.JPG"
        )
        try PortableImportReceiptLedger(sourceRootURL: sourceURL).append(identity: firstIdentity)
        let ledger = PortableImportReceiptLedger(
            sourceRootURL: sourceURL,
            fileLockOperation: { _, _, _ in
                errno = ENOTSUP
                return -1
            }
        )

        let snapshot = try ledger.load()
        #expect(snapshot.fingerprints.count == 1)
        #expect(snapshot.warning?.contains("does not support file locking") == true)

        let appendResult = try ledger.appendReturningRevision(
            identity: PortableFileIdentity(
                size: 18,
                modificationTimeEpochSeconds: 1_700_000_001,
                relativePath: "DCIM/IMG_LOCK_SECOND.JPG"
            )
        )
        #expect(appendResult.advisoryLockUnavailable)
        #expect(appendResult.warning?.contains("does not support file locking") == true)
        #expect(try PortableImportReceiptLedger(sourceRootURL: sourceURL).load().fingerprints.count == 2)
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
    func serializesConcurrentAppends() throws {
        let sourceURL = try temporaryDirectory()
        let receiptCount = 32
        let errors = TestErrorCollector()

        DispatchQueue.concurrentPerform(iterations: receiptCount) { index in
            do {
                let relativePath = "DCIM/IMG_\(index).JPG"
                let identity = PortableFileIdentity(
                    size: Int64(index + 1),
                    modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
                    relativePath: relativePath
                )
                try PortableImportReceiptLedger(sourceRootURL: sourceURL).append(
                    identity: identity
                )
            } catch {
                errors.record(error)
            }
        }
        if let error = errors.first {
            throw error
        }

        let snapshot = try PortableImportReceiptLedger(sourceRootURL: sourceURL).load()
        #expect(snapshot.fingerprints.count == receiptCount)
        #expect(snapshot.invalidRecordCount == 0)
    }
}

private func encodedTestReceipt(
    identity: PortableFileIdentity,
    checksumOverride: String? = nil
) throws -> String {
    let importedAt = DateCoding.string(from: Date(timeIntervalSince1970: 1_700_000_000))
    let fingerprint = PortableImportReceiptLedger.portableFingerprint(for: identity)
    let payload = TestReceiptPayload(
        schemaVersion: 1,
        fingerprintAlgorithm: "sdimport-portable-v2",
        fingerprint: fingerprint,
        size: identity.size,
        modificationTimeEpochSeconds: identity.modificationTimeEpochSeconds,
        relativePath: identity.relativePath,
        importedAt: importedAt
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let checksum = SHA256.hash(data: try encoder.encode(payload))
        .map { String(format: "%02x", $0) }
        .joined()
    let receipt = TestReceipt(
        schemaVersion: payload.schemaVersion,
        fingerprintAlgorithm: payload.fingerprintAlgorithm,
        fingerprint: payload.fingerprint,
        size: payload.size,
        modificationTimeEpochSeconds: payload.modificationTimeEpochSeconds,
        relativePath: payload.relativePath,
        importedAt: payload.importedAt,
        checksum: checksumOverride ?? checksum
    )
    return try #require(String(data: encoder.encode(receipt), encoding: .utf8))
}

private struct TestReceipt: Encodable {
    let schemaVersion: Int
    let fingerprintAlgorithm: String
    let fingerprint: String
    let size: Int64
    let modificationTimeEpochSeconds: Int64
    let relativePath: String
    let importedAt: String
    let checksum: String
}

private struct TestReceiptPayload: Encodable {
    let schemaVersion: Int
    let fingerprintAlgorithm: String
    let fingerprint: String
    let size: Int64
    let modificationTimeEpochSeconds: Int64
    let relativePath: String
    let importedAt: String
}

private final class TestErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []

    func record(_ error: Error) {
        lock.lock()
        errors.append(error)
        lock.unlock()
    }

    var first: Error? {
        lock.lock()
        defer { lock.unlock() }
        return errors.first
    }
}
