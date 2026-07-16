import Foundation

enum Platform: String, Codable, Sendable {
    case iPhone
    case iPad
    case mac
}

enum DeviceClass: String, Codable, Hashable, Sendable {
    case iPhone16e
    case iPhone17ProMax
    case iPadProM4
    case macBookProM4
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
