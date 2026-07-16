import Foundation
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

protocol MLXRuntimeResource: AnyObject, Sendable {
    var reasoningConfig: ReasoningConfig? { get }
    func configure(_ request: GenerationRequest)
    func streamDetails(
        to prompt: String
    ) -> AsyncThrowingStream<MLXLMCommon.Generation, Error>
}

protocol MLXRuntimeLoading: Sendable {
    func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource
}

struct DefaultMLXRuntimeLoader: MLXRuntimeLoading {
    func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource {
        guard FileManager.default.fileExists(atPath: installation.directory.path) else {
            throw MLXInferenceError.modelDirectoryMissing
        }
        let container = try await VLMModelFactory.shared.loadContainer(
            from: installation.directory,
            using: #huggingFaceTokenizerLoader()
        )
        let configuration = await container.configuration
        let configData = try Data(
            contentsOf: installation.directory.appending(path: "config.json")
        )
        let reasoningConfig = LocalReasoningConfigResolver.resolve(
            runtimeConfig: configuration.reasoningConfig,
            configData: configData,
            modelID: installation.directory.lastPathComponent
        )
        return LiveMLXRuntimeResource(container: container, reasoningConfig: reasoningConfig)
    }
}

private final class LiveMLXRuntimeResource: MLXRuntimeResource, @unchecked Sendable {
    private let container: ModelContainer
    private let session: MLXLMCommon.ChatSession
    let reasoningConfig: ReasoningConfig?

    init(container: ModelContainer, reasoningConfig: ReasoningConfig?) {
        self.container = container
        self.reasoningConfig = reasoningConfig
        session = MLXLMCommon.ChatSession(
            container,
            generateParameters: Self.parameters(maxTokens: GenerationRequest.defaultMaxTokens)
        )
    }

    func configure(_ request: GenerationRequest) {
        session.generateParameters = Self.parameters(maxTokens: request.maxTokens)
        session.additionalContext = ["enable_thinking": request.reasoningEnabled]
    }

    func streamDetails(
        to prompt: String
    ) -> AsyncThrowingStream<MLXLMCommon.Generation, Error> {
        session.streamDetails(to: prompt)
    }

    private static func parameters(maxTokens: Int) -> GenerateParameters {
        GenerateParameters(maxTokens: maxTokens, temperature: 0, seed: 0)
    }
}
