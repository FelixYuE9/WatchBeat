import Foundation

public enum ECGQualityLevel: String, Codable, CaseIterable, Sendable {
    case good
    case usableWithCaution
    case poor
}

public struct ECGQualityReport: Codable, Equatable, Sendable {
    public let level: ECGQualityLevel
    public let reasonCodes: [String]

    public init(level: ECGQualityLevel, reasonCodes: [String]) {
        self.level = level
        self.reasonCodes = reasonCodes
    }
}
