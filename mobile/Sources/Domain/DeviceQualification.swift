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

    static func evidenceClass(hardwareIdentifier: String) -> Self {
        Self(rawValue: hardwareIdentifier)
    }

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
    let osBuild: String
    let appBuild: String
    let appCommit: String
    let runtimeFingerprint: String
    let thermalState: ResourceThermalState
    let isSimulator: Bool

    init(
        platform: Platform,
        deviceClass: DeviceClass,
        physicalMemoryBytes: Int,
        freeStorageBytes: Int,
        osBuild: String = "",
        appBuild: String = "",
        appCommit: String = "",
        runtimeFingerprint: String = "",
        thermalState: ResourceThermalState = .nominal,
        isSimulator: Bool = false
    ) {
        self.platform = platform
        self.deviceClass = deviceClass
        self.physicalMemoryBytes = physicalMemoryBytes
        self.freeStorageBytes = freeStorageBytes
        self.osBuild = osBuild
        self.appBuild = appBuild
        self.appCommit = appCommit
        self.runtimeFingerprint = runtimeFingerprint
        self.thermalState = thermalState
        self.isSimulator = isSimulator
    }
}

enum QualificationReason: Equatable, Sendable {
    case ternaryProhibitedOnIPhone
    case deviceNotMeasured
    case insufficientMemory
    case insufficientStorage
    case incompatibleRuntime
    case simulatorNotSupported
    case criticalThermalState
}

enum DeviceQualification: Equatable, Sendable {
    case qualified(Set<ModelCapability>)
    case unverified(QualificationReason)
    case unsupported(QualificationReason)

    /// Download/import may proceed without release evidence so physical lanes can be measured.
    /// Unsupported hardware and resource floors still block acquisition.
    var allowsAcquisition: Bool {
        switch self {
        case .qualified, .unverified: true
        case .unsupported: false
        }
    }

    /// Loading into the inference runtime requires a validated support-policy match in Release.
    /// Debug builds may load `.deviceNotMeasured` installs so physical development and evidence
    /// capture can proceed before a support row exists. Simulator and incompatible-runtime
    /// unverified states stay blocked even in Debug.
    var allowsLoad: Bool {
        switch self {
        case .qualified:
            return true
        case .unverified(let reason):
            #if DEBUG
            return reason == .deviceNotMeasured
            #else
            return false
            #endif
        case .unsupported:
            return false
        }
    }
}

typealias QualificationEvidence = [ModelID: [DeviceClass: Set<ModelCapability>]]
