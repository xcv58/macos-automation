public struct ImportPreviewGroupDispositionSummary: Equatable, Sendable {
    public let copyCount: Int
    public let skippedCount: Int

    public init(copyCount: Int, skippedCount: Int) {
        self.copyCount = copyCount
        self.skippedCount = skippedCount
    }

    public var mixedStatusTitle: String? {
        guard copyCount > 0, skippedCount > 0 else {
            return nil
        }
        let copiedTitle = copyCount == 1 ? "1 copy" : "\(copyCount) copies"
        return "\(copiedTitle) · \(skippedCount) skipped"
    }
}
