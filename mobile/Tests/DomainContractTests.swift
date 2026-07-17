import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Streaming and tool contracts")
struct DomainContractTests {
    @Test
    func bundledCatalogDecodesBothPinnedPublicModels() throws {
        let url = try #require(ModelCatalogLoader.bundledCatalogURL())
        let catalog = try JSONDecoder().decode(
            ModelCatalog.self,
            from: Data(contentsOf: url)
        )

        #expect(catalog.schemaVersion == 1)
        #expect(catalog.models.map(\.id) == [.oneBit27B, .ternary27B])
        #expect(catalog.models.allSatisfy { !$0.manifest.files.isEmpty })
        #expect(
            catalog.models.allSatisfy { model in
                model.manifest.files.allSatisfy { !$0.isOptional }
            }
        )
        #expect(!ModelCatalogLoader.bundledDescriptors().isEmpty)
        #expect(ModelCatalogLoader.bundledManifests()[.oneBit27B] != nil)
    }

    @Test
    func requiredInstalledBytesExcludeOptionalFiles() throws {
        let manifest = try ModelManifest.validated(
            id: .oneBit27B,
            repository: "example/model",
            revision: String(repeating: "a", count: 40),
            files: [
                .validated(
                    path: "required.safetensors",
                    sizeBytes: 10,
                    sha256: String(repeating: "b", count: 64),
                    role: .weight,
                    isOptional: false
                ),
                .validated(
                    path: "optional.json",
                    sizeBytes: 20,
                    sha256: String(repeating: "c", count: 64),
                    role: .configuration,
                    isOptional: true
                )
            ]
        )

        #expect(manifest.requiredInstalledBytes == 10)
    }

    @Test
    func decodingRejectsNegativeFileSize() throws {
        let data = try Self.descriptorData(fileSizes: [-1])

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ModelDescriptor.self, from: data)
        }
    }

    @Test
    func decodingRejectsDuplicateLogicalPaths() throws {
        let data = try Self.descriptorData(
            fileSizes: [10, 20],
            filePaths: ["model.safetensors", "model.safetensors"]
        )

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ModelDescriptor.self, from: data)
        }
    }

    @Test
    func decodingRejectsRequiredByteOverflow() throws {
        let data = try Self.descriptorData(fileSizes: [Int.max, 1])

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ModelDescriptor.self, from: data)
        }
    }

    @Test
    func decodingRejectsDescriptorIDMismatchAndInvalidArithmetic() throws {
        let mismatch = try Self.descriptorData(manifestID: "ternary27B")
        let negativeMargin = try Self.descriptorData(storageSafetyMarginBytes: -1)
        let storageOverflow = try Self.descriptorData(
            fileSizes: [Int.max],
            storageSafetyMarginBytes: 1
        )

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ModelDescriptor.self, from: mismatch)
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ModelDescriptor.self, from: negativeMargin)
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ModelDescriptor.self, from: storageOverflow)
        }
    }

    @Test
    func decodingRejectsMalformedManifestIdentityAndFileIntegrity() throws {
        let badRevision = try Self.descriptorData(revision: "main")
        let badPath = try Self.descriptorData(filePaths: ["../model.safetensors"])
        let badDigest = try Self.descriptorData(sha256: "not-a-sha")

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ModelDescriptor.self, from: badRevision)
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ModelDescriptor.self, from: badPath)
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ModelDescriptor.self, from: badDigest)
        }
    }

    @Test
    func validatedConstructionRejectsInvalidFilesAndTotals() throws {
        #expect(throws: (any Error).self) {
            try ModelManifest.File.validated(
                path: "model.safetensors",
                sizeBytes: -1,
                sha256: String(repeating: "b", count: 64),
                role: .weight,
                isOptional: false
            )
        }

        let large = try Self.validFile(path: "large.safetensors", sizeBytes: Int.max)
        let extra = try Self.validFile(path: "extra.safetensors", sizeBytes: 1)
        #expect(throws: (any Error).self) {
            try ModelManifest.validated(
                id: .oneBit27B,
                repository: "example/model",
                revision: String(repeating: "a", count: 40),
                files: [large, extra]
            )
        }

        let duplicate = try Self.validFile(path: "duplicate.safetensors", sizeBytes: 1)
        #expect(throws: (any Error).self) {
            try ModelManifest.validated(
                id: .oneBit27B,
                repository: "example/model",
                revision: String(repeating: "a", count: 40),
                files: [duplicate, duplicate]
            )
        }
    }

    @Test
    func validatedDescriptorRejectsMismatchedIDAndStorageOverflow() throws {
        let manifest = try ModelManifest.validated(
            id: .oneBit27B,
            repository: "example/model",
            revision: String(repeating: "a", count: 40),
            files: [try Self.validFile(sizeBytes: Int.max)]
        )

        #expect(throws: (any Error).self) {
            try ModelDescriptor.validated(
                id: .ternary27B,
                family: .ternaryBonsai,
                displayName: "Mismatch",
                manifest: manifest,
                requirements: .init(
                    capabilities: [.textGeneration],
                    minimumPhysicalMemoryBytes: 0,
                    storageSafetyMarginBytes: 0
                )
            )
        }
        #expect(throws: (any Error).self) {
            try ModelDescriptor.validated(
                id: .oneBit27B,
                family: .bonsai,
                displayName: "Overflow",
                manifest: manifest,
                requirements: .init(
                    capabilities: [.textGeneration],
                    minimumPhysicalMemoryBytes: 0,
                    storageSafetyMarginBytes: 1
                )
            )
        }
    }

    @Test
    func generationEventsKeepReasoningAndAnswersDistinct() {
        let events: [GenerationEvent] = [
            .reasoning("plan"),
            .answer("result"),
            .completed(.stop)
        ]

        #expect(events == [.reasoning("plan"), .answer("result"), .completed(.stop)])
    }

    @Test
    func toolInvocationRoundTripsItsValidatedWirePayload() throws {
        let invocation = ToolInvocation(
            id: "call-1",
            name: "calculator",
            argumentsJSON: #"{"expression":"6*7"}"#
        )

        let data = try JSONEncoder().encode(invocation)
        let decoded = try JSONDecoder().decode(ToolInvocation.self, from: data)

        #expect(decoded == invocation)
    }

    @Test
    func toolApprovalDistinguishesReadsFromWrites() {
        #expect(ToolApproval.automaticReadOnly != .requireAllowOnce)
    }

    private static func descriptorData(
        descriptorID: String = "oneBit27B",
        manifestID: String = "oneBit27B",
        revision: String = String(repeating: "a", count: 40),
        fileSizes: [Int] = [10],
        filePaths: [String]? = nil,
        sha256: String = String(repeating: "b", count: 64),
        storageSafetyMarginBytes: Int = 0
    ) throws -> Data {
        let paths = filePaths ?? fileSizes.indices.map { "model-\($0).safetensors" }
        let files = zip(paths, fileSizes).map { path, size in
            [
                "isOptional": false,
                "path": path,
                "role": "weight",
                "sha256": sha256,
                "sizeBytes": size
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "capabilities": ["textGeneration"],
            "displayName": "Test model",
            "family": "bonsai",
            "id": descriptorID,
            "manifest": [
                "files": files,
                "id": manifestID,
                "repository": "example/model",
                "revision": revision
            ],
            "minimumPhysicalMemoryBytes": 0,
            "storageSafetyMarginBytes": storageSafetyMarginBytes
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private static func validFile(
        path: String = "model.safetensors",
        sizeBytes: Int = 10
    ) throws -> ModelManifest.File {
        try ModelManifest.File.validated(
            path: path,
            sizeBytes: sizeBytes,
            sha256: String(repeating: "b", count: 64),
            role: .weight,
            isOptional: false
        )
    }
}
