import Foundation

enum Platform: String, Codable, Sendable {
    case iPhone
    case iPad
    case mac
}

struct DeviceClass: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let iPhone16e = Self(rawValue: "iPhone16e")
    static let iPhone17ProMax = Self(rawValue: "iPhone17ProMax")
    static let iPadProM4 = Self(rawValue: "iPadProM4")
    static let macBookProM4 = Self(rawValue: "macBookProM4")

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct DeviceFacts: Equatable, Sendable {
    let platform: Platform
    let deviceClass: DeviceClass
    let physicalMemoryBytes: Int
    let freeStorageBytes: Int
}

enum QualificationReason: Equatable, Sendable {
    case ternaryProhibitedOnIPhone
    case deviceNotMeasured
    case insufficientMemory
    case insufficientStorage
}

enum DeviceQualification: Equatable, Sendable {
    case qualified(Set<ModelCapability>)
    case unverified(QualificationReason)
    case unsupported(QualificationReason)
}

typealias QualificationEvidence = [ModelID: [DeviceClass: Set<ModelCapability>]]
