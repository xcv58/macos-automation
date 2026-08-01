import Foundation

public enum KnownFileSource: String, Codable, Hashable, Sendable {
    case localLedger = "local_ledger"
    case portableLedger = "portable_ledger"
    case destination = "destination"
}
