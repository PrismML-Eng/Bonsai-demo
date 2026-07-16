import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

protocol MLXRuntimeResource: AnyObject, Sendable {
    var reasoningConfig: ReasoningConfig? { get }
    var hasSession: Bool { get }
    func configure(_ request: GenerationRequest)
    func streamDetails(
        to prompt: String
    ) -> AsyncThrowingStream<MLXLMCommon.Generation, Error>
    func releaseOptionalSession()
}

extension MLXRuntimeResource {
    var hasSession: Bool { true }
    func releaseOptionalSession() {}
}

protocol MLXCacheClearing: Sendable {
    func clear()
}

struct DefaultMLXCacheClearer: MLXCacheClearing {
    func clear() {
        Memory.clearCache()
    }
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
    private var session: MLXLMCommon.ChatSession?
    let reasoningConfig: ReasoningConfig?
    var hasSession: Bool { session != nil }

    init(container: ModelContainer, reasoningConfig: ReasoningConfig?) {
        self.container = container
        self.reasoningConfig = reasoningConfig
        session = Self.makeSession(container: container)
    }

    func configure(_ request: GenerationRequest) {
        let session = ensureSession()
        session.generateParameters = Self.parameters(maxTokens: request.maxTokens)
        session.additionalContext = ["enable_thinking": request.reasoningEnabled]
    }

    func streamDetails(
        to prompt: String
    ) -> AsyncThrowingStream<MLXLMCommon.Generation, Error> {
        ensureSession().streamDetails(to: prompt)
    }

    func releaseOptionalSession() {
        session = nil
    }

    private func ensureSession() -> MLXLMCommon.ChatSession {
        if let session { return session }
        let created = Self.makeSession(container: container)
        session = created
        return created
    }

    private static func makeSession(container: ModelContainer) -> MLXLMCommon.ChatSession {
        MLXLMCommon.ChatSession(
            container,
            generateParameters: parameters(maxTokens: GenerationRequest.defaultMaxTokens)
        )
    }

    private static func parameters(maxTokens: Int) -> GenerateParameters {
        GenerateParameters(maxTokens: maxTokens, temperature: 0, seed: 0)
    }
}
