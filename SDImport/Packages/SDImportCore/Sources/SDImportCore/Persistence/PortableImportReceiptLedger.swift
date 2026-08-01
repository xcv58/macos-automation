import CryptoKit
import Darwin
import Foundation

public struct PortableFileIdentity: Hashable, Sendable {
    public let size: Int64
    public let modificationTimeEpochSeconds: Int64
    public let relativePath: String

    public init(size: Int64, modificationDate: Date, relativePath: String) {
        self.init(
            size: size,
            modificationTimeEpochSeconds: Int64(floor(modificationDate.timeIntervalSince1970)),
            relativePath: relativePath
        )
    }

    public init(size: Int64, modificationTimeEpochSeconds: Int64, relativePath: String) {
        self.size = size
        self.modificationTimeEpochSeconds = modificationTimeEpochSeconds
        self.relativePath = relativePath
    }
}

public struct PortableImportReceiptSnapshot: Sendable {
    public let fingerprints: Set<String>
    public let invalidRecordCount: Int

    public init(fingerprints: Set<String>, invalidRecordCount: Int) {
        self.fingerprints = fingerprints
        self.invalidRecordCount = invalidRecordCount
    }

    public var warning: String? {
        guard invalidRecordCount > 0 else {
            return nil
        }
        let noun = invalidRecordCount == 1 ? "record" : "records"
        return "Ignored \(invalidRecordCount) invalid or corrupted portable import \(noun)"
    }
}

public enum PortableImportReceiptLedgerError: LocalizedError, Sendable {
    case sourceUnavailable(String)
    case sourceNotDirectory(String)
    case ledgerTooLarge(Int64)
    case recordTooLarge(Int)
    case ledgerIsNotAFile(String)
    case unsafeLedgerPath(String)

    public var errorDescription: String? {
        switch self {
        case .sourceUnavailable(let path):
            return "The source is no longer available at \(path)"
        case .sourceNotDirectory(let path):
            return "The source is not a directory at \(path)"
        case .ledgerTooLarge(let size):
            return "The portable import ledger is too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))"
        case .recordTooLarge(let size):
            return "The portable import receipt is too large (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))"
        case .ledgerIsNotAFile(let path):
            return "The portable import ledger is not a regular file at \(path)"
        case .unsafeLedgerPath(let path):
            return "The portable import ledger path is unsafe at \(path)"
        }
    }
}

public struct PortableImportReceiptLedger: Sendable {
    public static let directoryName = ".sd-import"
    public static let fileName = "imported-v1.jsonl"

    private static let schemaVersion = 1
    private static let fingerprintAlgorithm = "sdimport-portable-v1"
    private static let maximumLedgerBytes: Int64 = 64 * 1_024 * 1_024
    private static let maximumRecordBytes = 16 * 1_024
    private static let maximumRelativePathLength = 4_096
    private static let readBufferSize = 64 * 1_024
    private static let processLock = NSLock()

    public let sourceRootURL: URL

    public init(sourceRootURL: URL) {
        self.sourceRootURL = sourceRootURL.standardizedFileURL
    }

    public var ledgerURL: URL {
        sourceRootURL
            .appendingPathComponent(Self.directoryName, isDirectory: true)
            .appendingPathComponent(Self.fileName, isDirectory: false)
    }

    public static func portableFingerprint(for identity: PortableFileIdentity) -> String {
        portableFingerprint(
            size: identity.size,
            modificationTimeEpochSeconds: identity.modificationTimeEpochSeconds,
            relativePath: identity.relativePath
        )
    }

    public func load() throws -> PortableImportReceiptSnapshot {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }

        let sourceDescriptor = try openSourceDirectory()
        defer { Darwin.close(sourceDescriptor) }

        guard let ledgerDescriptor = try openLedgerForReading(sourceDescriptor: sourceDescriptor) else {
            return PortableImportReceiptSnapshot(fingerprints: [], invalidRecordCount: 0)
        }
        defer { Darwin.close(ledgerDescriptor) }

        try lock(ledgerDescriptor, type: F_RDLCK)
        defer { unlock(ledgerDescriptor) }

        let size = try regularFileSize(descriptor: ledgerDescriptor)
        guard size <= Self.maximumLedgerBytes else {
            throw PortableImportReceiptLedgerError.ledgerTooLarge(size)
        }
        let data = try readAll(descriptor: ledgerDescriptor, expectedSize: size)

        let decoder = JSONDecoder()
        var fingerprints: Set<String> = []
        var invalidRecordCount = 0

        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let lineData = Data(line)
            guard lineData.count <= Self.maximumRecordBytes else {
                invalidRecordCount += 1
                continue
            }
            guard
                let receipt = try? decoder.decode(Receipt.self, from: lineData),
                Self.isValid(receipt)
            else {
                invalidRecordCount += 1
                continue
            }
            fingerprints.insert(receipt.fingerprint)
        }

        return PortableImportReceiptSnapshot(
            fingerprints: fingerprints,
            invalidRecordCount: invalidRecordCount
        )
    }

    public func append(
        identity: PortableFileIdentity,
        importedAt: Date = Date()
    ) throws {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }

        let importedAtString = DateCoding.string(from: importedAt)
        var receipt = Receipt(
            schemaVersion: Self.schemaVersion,
            fingerprintAlgorithm: Self.fingerprintAlgorithm,
            fingerprint: Self.portableFingerprint(for: identity),
            size: identity.size,
            modificationTimeEpochSeconds: identity.modificationTimeEpochSeconds,
            relativePath: identity.relativePath,
            importedAt: importedAtString,
            checksum: ""
        )
        receipt.checksum = try Self.checksum(for: receipt)
        guard Self.isValid(receipt) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var recordData = try encoder.encode(receipt)
        recordData.append(0x0A)
        guard recordData.count <= Self.maximumRecordBytes else {
            throw PortableImportReceiptLedgerError.recordTooLarge(recordData.count)
        }

        let sourceDescriptor = try openSourceDirectory()
        defer { Darwin.close(sourceDescriptor) }
        let directoryDescriptor = try openOrCreateLedgerDirectory(sourceDescriptor: sourceDescriptor)
        defer { Darwin.close(directoryDescriptor) }
        let ledgerDescriptor = try openLedgerForAppending(directoryDescriptor: directoryDescriptor)
        defer { Darwin.close(ledgerDescriptor) }

        try lock(ledgerDescriptor, type: F_WRLCK)
        defer { unlock(ledgerDescriptor) }

        let currentSize = try regularFileSize(descriptor: ledgerDescriptor)
        guard currentSize <= Self.maximumLedgerBytes else {
            throw PortableImportReceiptLedgerError.ledgerTooLarge(currentSize)
        }

        var appendData = Data()
        if currentSize > 0, try lastByte(descriptor: ledgerDescriptor, size: currentSize) != 0x0A {
            appendData.append(0x0A)
        }
        appendData.append(recordData)

        let finalSize = currentSize + Int64(appendData.count)
        guard finalSize <= Self.maximumLedgerBytes else {
            throw PortableImportReceiptLedgerError.ledgerTooLarge(finalSize)
        }
        try writeAll(appendData, descriptor: ledgerDescriptor)
        guard Darwin.fsync(ledgerDescriptor) == 0 else {
            throw Self.posixError(path: ledgerURL.path)
        }
    }

    private func openSourceDirectory() throws -> Int32 {
        let descriptor = Darwin.open(
            sourceRootURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            let code = errno
            switch code {
            case ENOENT:
                throw PortableImportReceiptLedgerError.sourceUnavailable(sourceRootURL.path)
            case ENOTDIR:
                throw PortableImportReceiptLedgerError.sourceNotDirectory(sourceRootURL.path)
            case ELOOP:
                throw PortableImportReceiptLedgerError.unsafeLedgerPath(sourceRootURL.path)
            default:
                throw Self.posixError(code: code, path: sourceRootURL.path)
            }
        }
        return descriptor
    }

    private func openLedgerForReading(sourceDescriptor: Int32) throws -> Int32? {
        let directoryDescriptor = Darwin.openat(
            sourceDescriptor,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directoryDescriptor >= 0 else {
            let code = errno
            if code == ENOENT {
                return nil
            }
            if code == ELOOP || code == ENOTDIR {
                throw PortableImportReceiptLedgerError.unsafeLedgerPath(
                    ledgerURL.deletingLastPathComponent().path
                )
            }
            throw Self.posixError(code: code, path: ledgerURL.deletingLastPathComponent().path)
        }
        defer { Darwin.close(directoryDescriptor) }

        let descriptor = Darwin.openat(
            directoryDescriptor,
            Self.fileName,
            O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            let code = errno
            if code == ENOENT {
                return nil
            }
            if code == ELOOP {
                throw PortableImportReceiptLedgerError.unsafeLedgerPath(ledgerURL.path)
            }
            throw Self.posixError(code: code, path: ledgerURL.path)
        }
        do {
            _ = try regularFileSize(descriptor: descriptor)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func openOrCreateLedgerDirectory(sourceDescriptor: Int32) throws -> Int32 {
        if Darwin.mkdirat(sourceDescriptor, Self.directoryName, 0o700) != 0, errno != EEXIST {
            throw Self.posixError(path: ledgerURL.deletingLastPathComponent().path)
        }
        let descriptor = Darwin.openat(
            sourceDescriptor,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            let code = errno
            if code == ELOOP || code == ENOTDIR {
                throw PortableImportReceiptLedgerError.unsafeLedgerPath(
                    ledgerURL.deletingLastPathComponent().path
                )
            }
            throw Self.posixError(code: code, path: ledgerURL.deletingLastPathComponent().path)
        }
        return descriptor
    }

    private func openLedgerForAppending(directoryDescriptor: Int32) throws -> Int32 {
        let descriptor = Darwin.openat(
            directoryDescriptor,
            Self.fileName,
            O_RDWR | O_APPEND | O_CREAT | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0 else {
            let code = errno
            if code == ELOOP {
                throw PortableImportReceiptLedgerError.unsafeLedgerPath(ledgerURL.path)
            }
            if code == EISDIR {
                throw PortableImportReceiptLedgerError.ledgerIsNotAFile(ledgerURL.path)
            }
            throw Self.posixError(code: code, path: ledgerURL.path)
        }
        do {
            _ = try regularFileSize(descriptor: descriptor)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func regularFileSize(descriptor: Int32) throws -> Int64 {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            throw Self.posixError(path: ledgerURL.path)
        }
        guard status.st_mode & S_IFMT == S_IFREG else {
            throw PortableImportReceiptLedgerError.ledgerIsNotAFile(ledgerURL.path)
        }
        return Int64(status.st_size)
    }

    private func lock(_ descriptor: Int32, type: Int32) throws {
        var fileLock = Darwin.flock()
        fileLock.l_type = Int16(type)
        fileLock.l_whence = Int16(SEEK_SET)
        while Darwin.fcntl(descriptor, F_SETLKW, &fileLock) != 0 {
            guard errno == EINTR else {
                throw Self.posixError(path: ledgerURL.path)
            }
        }
    }

    private func unlock(_ descriptor: Int32) {
        var fileLock = Darwin.flock()
        fileLock.l_type = Int16(F_UNLCK)
        fileLock.l_whence = Int16(SEEK_SET)
        _ = Darwin.fcntl(descriptor, F_SETLK, &fileLock)
    }

    private func readAll(descriptor: Int32, expectedSize: Int64) throws -> Data {
        var data = Data()
        data.reserveCapacity(Int(expectedSize))
        var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 {
                return data
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw Self.posixError(path: ledgerURL.path)
            }
            data.append(buffer, count: count)
            guard data.count <= Self.maximumLedgerBytes else {
                throw PortableImportReceiptLedgerError.ledgerTooLarge(Int64(data.count))
            }
        }
    }

    private func lastByte(descriptor: Int32, size: Int64) throws -> UInt8 {
        var byte: UInt8 = 0
        while true {
            let count = Darwin.pread(descriptor, &byte, 1, off_t(size - 1))
            if count == 1 {
                return byte
            }
            if count < 0, errno == EINTR {
                continue
            }
            throw Self.posixError(path: ledgerURL.path)
        }
    }

    private func writeAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    bytes.count - written
                )
                if count < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw Self.posixError(path: ledgerURL.path)
                }
                guard count > 0 else {
                    throw Self.posixError(code: EIO, path: ledgerURL.path)
                }
                written += count
            }
        }
    }

    private static func posixError(code: Int32 = errno, path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSFilePathErrorKey: path]
        )
    }

    private static func isValid(_ receipt: Receipt) -> Bool {
        guard
            receipt.schemaVersion == schemaVersion,
            receipt.fingerprintAlgorithm == fingerprintAlgorithm,
            receipt.size >= 0,
            isValidRelativePath(receipt.relativePath),
            DateCoding.date(from: receipt.importedAt) != nil,
            receipt.checksum.count == 64,
            receipt.checksum.allSatisfy({ $0.isHexDigit }),
            (try? checksum(for: receipt)) == receipt.checksum
        else {
            return false
        }

        let expected = portableFingerprint(
            size: receipt.size,
            modificationTimeEpochSeconds: receipt.modificationTimeEpochSeconds,
            relativePath: receipt.relativePath
        )
        return receipt.fingerprint == expected
    }

    private static func isValidRelativePath(_ path: String) -> Bool {
        guard
            !path.isEmpty,
            path.count <= maximumRelativePathLength,
            !path.hasPrefix("/"),
            !path.hasPrefix("\\")
        else {
            return false
        }

        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    private static func portableFingerprint(
        size: Int64,
        modificationTimeEpochSeconds: Int64,
        relativePath: String
    ) -> String {
        let payload = "p1|\(relativePath)|\(size)|\(modificationTimeEpochSeconds)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return "p1:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func checksum(for receipt: Receipt) throws -> String {
        let payload = ReceiptPayload(
            schemaVersion: receipt.schemaVersion,
            fingerprintAlgorithm: receipt.fingerprintAlgorithm,
            fingerprint: receipt.fingerprint,
            size: receipt.size,
            modificationTimeEpochSeconds: receipt.modificationTimeEpochSeconds,
            relativePath: receipt.relativePath,
            importedAt: receipt.importedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct Receipt: Codable {
    let schemaVersion: Int
    let fingerprintAlgorithm: String
    let fingerprint: String
    let size: Int64
    let modificationTimeEpochSeconds: Int64
    let relativePath: String
    let importedAt: String
    var checksum: String
}

private struct ReceiptPayload: Encodable {
    let schemaVersion: Int
    let fingerprintAlgorithm: String
    let fingerprint: String
    let size: Int64
    let modificationTimeEpochSeconds: Int64
    let relativePath: String
    let importedAt: String
}
