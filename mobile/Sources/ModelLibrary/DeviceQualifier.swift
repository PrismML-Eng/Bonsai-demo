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

        guard !facts.isSimulator else { return .unverified(.simulatorNotSupported) }
        guard facts.runtimeFingerprint.isEmpty
            || facts.runtimeFingerprint == BonsaiRuntimeFingerprint.current else {
            return .unverified(.incompatibleRuntime)
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

        guard facts.thermalState != .critical else {
            return .unsupported(.criticalThermalState)
        }

        return .qualified(model.capabilities.intersection(measuredCapabilities))
    }

    static func qualify(
        model: ModelDescriptor,
        facts: DeviceFacts,
        manifest: ReleaseSupportManifest,
        artifactLoader: (String) throws -> Data
    ) -> DeviceQualification {
        guard manifest.evidence
            .filter({ $0.modelID == model.id })
            .allSatisfy({
                $0.modelRevision == model.manifest.revision
                    && (facts.osBuild.isEmpty || $0.osBuild == facts.osBuild)
                    && (facts.appBuild.isEmpty || $0.appBuild == facts.appBuild)
                    && (facts.appCommit.isEmpty || $0.appCommit == facts.appCommit)
                    && (facts.runtimeFingerprint.isEmpty
                        || $0.runtimeFingerprint == facts.runtimeFingerprint)
            }) else {
            return .unverified(.deviceNotMeasured)
        }
        guard let evidence = try? manifest.qualificationEvidence(artifactLoader: artifactLoader) else {
            return .unverified(.deviceNotMeasured)
        }
        return qualify(model: model, facts: facts, evidence: evidence)
    }
}
