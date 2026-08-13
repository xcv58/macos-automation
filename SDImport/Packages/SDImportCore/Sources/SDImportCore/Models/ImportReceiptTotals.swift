import Foundation

public struct ImportReceiptTotals: Equatable, Sendable {
    public let copiedFiles: Int
    public let copiedBytes: Int64
    public let skippedFiles: Int
    public let failedFiles: Int

    public init(files: [JobFileRecord]) {
        copiedFiles = files.filter { $0.copyStatus == .copied }.count
        copiedBytes = files.reduce(Int64(0)) { total, file in
            file.copyStatus == .copied ? total + file.size : total
        }
        skippedFiles = files.filter { $0.copyStatus == .skipped }.count
        failedFiles = files.filter { $0.copyStatus == .failed }.count
    }
}
