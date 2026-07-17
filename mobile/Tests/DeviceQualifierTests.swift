import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Device qualification")
struct DeviceQualifierTests {
    private static let gibibyte = 1_073_741_824

    @Test
    func ternaryIsAlwaysBlockedOnIPhone() {
        let model = Self.descriptor(
            id: .ternary27B,
            minimumMemoryBytes: 16 * Self.gibibyte
        )
        let facts = DeviceFacts(
            platform: .iPhone,
            deviceClass: .iPhone16e,
            physicalMemoryBytes: 32 * Self.gibibyte,
            freeStorageBytes: 100 * Self.gibibyte
        )
        let evidence: QualificationEvidence = [
            .ternary27B: [.iPhone16e: [.textGeneration, .vision]]
        ]

        let result = DeviceQualifier.qualify(model: model, facts: facts, evidence: evidence)

        #expect(result == .unsupported(.ternaryProhibitedOnIPhone))
    }

    @Test
    func unverifiedDevicesMayAcquireAndDebugMayLoad() {
        let unverified = DeviceQualification.unverified(.deviceNotMeasured)
        #expect(unverified.allowsAcquisition)
        #if DEBUG
        #expect(unverified.allowsLoad)
        #else
        #expect(!unverified.allowsLoad)
        #endif

        let simulator = DeviceQualification.unverified(.simulatorNotSupported)
        #expect(simulator.allowsAcquisition)
        #expect(!simulator.allowsLoad)

        let unsupported = DeviceQualification.unsupported(.ternaryProhibitedOnIPhone)
        #expect(!unsupported.allowsAcquisition)
        #expect(!unsupported.allowsLoad)

        let qualified = DeviceQualification.qualified([.textGeneration])
        #expect(qualified.allowsAcquisition)
        #expect(qualified.allowsLoad)
    }

    @Test
    func oneBitNeedsEvidenceForTheExactDeviceClass() {
        let model = Self.descriptor(id: .oneBit27B)
        let facts = DeviceFacts(
            platform: .iPhone,
            deviceClass: .iPhone16e,
            physicalMemoryBytes: 8 * Self.gibibyte,
            freeStorageBytes: 20 * Self.gibibyte
        )
        let evidence: QualificationEvidence = [
            .oneBit27B: [.iPhone17ProMax: [.textGeneration]]
        ]

        let result = DeviceQualifier.qualify(model: model, facts: facts, evidence: evidence)

        #expect(result == .unverified(.deviceNotMeasured))
    }

    @Test
    func unknownHardwareIdentifierDecodesAndRemainsUnverified() throws {
        let unknown = try JSONDecoder().decode(
            DeviceClass.self,
            from: Data(#""iPhone99,9""#.utf8)
        )
        let facts = DeviceFacts(
            platform: .iPhone,
            deviceClass: unknown,
            physicalMemoryBytes: 32 * Self.gibibyte,
            freeStorageBytes: 100 * Self.gibibyte
        )

        let result = DeviceQualifier.qualify(
            model: Self.descriptor(id: .oneBit27B),
            facts: facts,
            evidence: [:]
        )

        #expect(unknown.rawValue == "iPhone99,9")
        #expect(result == .unverified(.deviceNotMeasured))
    }

    @Test
    func visionRequiresSeparateEvidence() {
        let model = Self.descriptor(id: .oneBit27B)
        let facts = Self.qualifiedFacts()
        let evidence: QualificationEvidence = [
            .oneBit27B: [.macBookProM4: [.textGeneration, .toolCalling, .thinking]]
        ]

        let result = DeviceQualifier.qualify(model: model, facts: facts, evidence: evidence)

        #expect(result == .qualified([.textGeneration, .toolCalling, .thinking]))
    }

    @Test
    func enforcesOneBitMemoryFloorAfterEvidence() {
        let model = Self.descriptor(id: .oneBit27B)
        let facts = DeviceFacts(
            platform: .mac,
            deviceClass: .macBookProM4,
            physicalMemoryBytes: (8 * Self.gibibyte) - 1,
            freeStorageBytes: 20 * Self.gibibyte
        )
        let evidence = Self.measuredEvidence(for: model.id)

        let result = DeviceQualifier.qualify(model: model, facts: facts, evidence: evidence)

        #expect(result == .unsupported(.insufficientMemory))
    }

    @Test
    func descriptorCannotLowerTheModelSpecificMemoryFloor() {
        let model = Self.descriptor(
            id: .oneBit27B,
            minimumMemoryBytes: 1
        )
        let facts = DeviceFacts(
            platform: .mac,
            deviceClass: .macBookProM4,
            physicalMemoryBytes: Self.gibibyte,
            freeStorageBytes: 20 * Self.gibibyte
        )

        let result = DeviceQualifier.qualify(
            model: model,
            facts: facts,
            evidence: Self.measuredEvidence(for: model.id)
        )

        #expect(result == .unsupported(.insufficientMemory))
    }

    @Test
    func measuredDeviceWithoutTextEvidenceRemainsUnverified() {
        let model = Self.descriptor(id: .oneBit27B)
        let evidence: QualificationEvidence = [
            .oneBit27B: [.macBookProM4: [.vision]]
        ]

        let result = DeviceQualifier.qualify(
            model: model,
            facts: Self.qualifiedFacts(),
            evidence: evidence
        )

        #expect(result == .unverified(.deviceNotMeasured))
    }

    @Test
    func enforcesTernaryMemoryFloorAfterEvidence() {
        let model = Self.descriptor(
            id: .ternary27B,
            minimumMemoryBytes: 16 * Self.gibibyte
        )
        let facts = DeviceFacts(
            platform: .iPad,
            deviceClass: .iPadProM4,
            physicalMemoryBytes: (16 * Self.gibibyte) - 1,
            freeStorageBytes: 20 * Self.gibibyte
        )
        let evidence: QualificationEvidence = [
            .ternary27B: [.iPadProM4: [.textGeneration]]
        ]

        let result = DeviceQualifier.qualify(model: model, facts: facts, evidence: evidence)

        #expect(result == .unsupported(.insufficientMemory))
    }

    @Test
    func requiresInstalledBytesPlusDescriptorSafetyMargin() {
        let installedBytes = 5 * Self.gibibyte
        let safetyMarginBytes = Self.gibibyte
        let model = Self.descriptor(
            id: .oneBit27B,
            requiredInstalledBytes: installedBytes,
            storageSafetyMarginBytes: safetyMarginBytes
        )
        let facts = DeviceFacts(
            platform: .mac,
            deviceClass: .macBookProM4,
            physicalMemoryBytes: 8 * Self.gibibyte,
            freeStorageBytes: installedBytes + safetyMarginBytes - 1
        )
        let evidence = Self.measuredEvidence(for: model.id)

        let result = DeviceQualifier.qualify(model: model, facts: facts, evidence: evidence)

        #expect(result == .unsupported(.insufficientStorage))
    }

    @Test
    func qualificationPrecedenceIsEvidenceThenMemoryThenStorage() {
        let model = Self.descriptor(id: .oneBit27B)
        let insufficientFacts = DeviceFacts(
            platform: .mac,
            deviceClass: .macBookProM4,
            physicalMemoryBytes: 1,
            freeStorageBytes: 1
        )

        #expect(
            DeviceQualifier.qualify(model: model, facts: insufficientFacts, evidence: [:])
                == .unverified(.deviceNotMeasured)
        )
        #expect(
            DeviceQualifier.qualify(
                model: model,
                facts: insufficientFacts,
                evidence: Self.measuredEvidence(for: model.id)
            ) == .unsupported(.insufficientMemory)
        )
    }

    @Test
    func qualifiesOnlyCapabilitiesDeclaredByModelAndMeasuredOnDevice() {
        let model = Self.descriptor(
            id: .oneBit27B,
            capabilities: [.textGeneration, .vision]
        )
        let evidence: QualificationEvidence = [
            .oneBit27B: [
                .macBookProM4: [.textGeneration, .vision, .toolCalling, .thinking]
            ]
        ]

        let result = DeviceQualifier.qualify(
            model: model,
            facts: Self.qualifiedFacts(),
            evidence: evidence
        )

        #expect(result == .qualified([.textGeneration, .vision]))
    }

    private static func descriptor(
        id: ModelID,
        requiredInstalledBytes: Int = 5 * gibibyte,
        storageSafetyMarginBytes: Int = gibibyte,
        minimumMemoryBytes: Int = 8 * gibibyte,
        capabilities: Set<ModelCapability> = [
            .textGeneration, .vision, .toolCalling, .thinking
        ]
    ) -> ModelDescriptor {
        do {
            let file = try ModelManifest.File.validated(
                path: "model.safetensors",
                sizeBytes: requiredInstalledBytes,
                sha256: String(repeating: "b", count: 64),
                role: .weight,
                isOptional: false
            )
            let manifest = try ModelManifest.validated(
                id: id,
                repository: "example/model",
                revision: String(repeating: "a", count: 40),
                files: [file]
            )
            return try ModelDescriptor.validated(
                id: id,
                family: id == .oneBit27B ? .bonsai : .ternaryBonsai,
                displayName: id == .oneBit27B ? "Bonsai 27B 1-bit" : "Ternary Bonsai 27B",
                manifest: manifest,
                requirements: .init(
                    capabilities: capabilities,
                    minimumPhysicalMemoryBytes: minimumMemoryBytes,
                    storageSafetyMarginBytes: storageSafetyMarginBytes
                )
            )
        } catch {
            preconditionFailure("Invalid test model fixture: \(error)")
        }
    }

    private static func qualifiedFacts() -> DeviceFacts {
        DeviceFacts(
            platform: .mac,
            deviceClass: .macBookProM4,
            physicalMemoryBytes: 16 * gibibyte,
            freeStorageBytes: 20 * gibibyte
        )
    }

    private static func measuredEvidence(for modelID: ModelID) -> QualificationEvidence {
        [modelID: [.macBookProM4: [.textGeneration, .vision, .toolCalling, .thinking]]]
    }
}
