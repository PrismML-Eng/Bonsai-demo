import Foundation

enum DeviceQualifier {
    private static let gibibyte = 1_073_741_824

    static func qualify(
        model: ModelDescriptor,
        facts: DeviceFacts,
        evidence: QualificationEvidence
    ) -> DeviceQualification {
        if model.id == .ternary27B, facts.platform == .iPhone {
            return .unsupported(.ternaryProhibitedOnIPhone)
        }

        guard
            let measuredCapabilities = evidence[model.id]?[facts.deviceClass],
            measuredCapabilities.contains(.textGeneration)
        else {
            return .unverified(.deviceNotMeasured)
        }

        let modelSpecificMemoryFloor = switch model.id {
        case .oneBit27B: 8 * gibibyte
        case .ternary27B: 16 * gibibyte
        }
        let requiredMemoryBytes = max(
            model.minimumPhysicalMemoryBytes,
            modelSpecificMemoryFloor
        )
        guard facts.physicalMemoryBytes >= requiredMemoryBytes else {
            return .unsupported(.insufficientMemory)
        }

        let (requiredStorageBytes, overflow) = model.manifest.requiredInstalledBytes
            .addingReportingOverflow(model.storageSafetyMarginBytes)
        guard !overflow, facts.freeStorageBytes >= requiredStorageBytes else {
            return .unsupported(.insufficientStorage)
        }

        return .qualified(model.capabilities.intersection(measuredCapabilities))
    }
}
