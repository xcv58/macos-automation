import Foundation

public enum KnownFileSource: String, Codable, Hashable, Sendable {
    case localLedger = "local_ledger"
    case portableLedger = "portable_ledger"
    case destination = "destination"

    public var skippedStatusTitle: String {
        switch self {
        case .portableLedger:
            return "Other Mac"
        case .localLedger:
            return "Known"
        case .destination:
            return "Already Exists"
        }
    }
}
