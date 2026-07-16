import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Streaming and tool contracts")
struct DomainContractTests {
    @Test
    func bundledCatalogDecodesBothPinnedPublicModels() throws {
        let url = try #require(
            Bundle.main.url(
                forResource: "manifest",
                withExtension: "json"
            )
        )

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
    }

    @Test
    func requiredInstalledBytesExcludeOptionalFiles() {
        let manifest = ModelManifest(
            id: .oneBit27B,
            repository: "example/model",
            revision: String(repeating: "a", count: 40),
            files: [
                .init(
                    path: "required.safetensors",
                    sizeBytes: 10,
                    sha256: String(repeating: "b", count: 64),
                    role: .weight,
                    isOptional: false
                ),
                .init(
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
}
