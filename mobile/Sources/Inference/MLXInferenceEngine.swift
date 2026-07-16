import CryptoKit
import Foundation
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

enum MLXInferenceError: Error, Equatable, Sendable {
    case modelDirectoryMissing
    case modelNotLoaded
    case generationAlreadyActive
    case reasoningUnavailable
    case invalidToolArgumentsEncoding
}

enum MLXGenerationMapper {
    static func toolInvocation(_ call: MLXLMCommon.ToolCall) throws -> ToolInvocation {
        let data = try JSONEncoder.sorted.encode(call.function.arguments)
        guard let argumentsJSON = String(data: data, encoding: .utf8) else {
            throw MLXInferenceError.invalidToolArgumentsEncoding
        }
        let id = call.id ?? fallbackID(name: call.function.name, arguments: data)
        return ToolInvocation(id: id, name: call.function.name, argumentsJSON: argumentsJSON)
    }

    static func metrics(
        _ info: GenerateCompletionInfo,
        timeToFirstToken: Duration
    ) -> GenerationMetrics {
        GenerationMetrics(
            promptTokenCount: info.promptTokenCount,
            generatedTokenCount: info.generationTokenCount,
            timeToFirstToken: timeToFirstToken,
            tokensPerSecond: info.tokensPerSecond.isFinite ? info.tokensPerSecond : 0
        )
    }

    static func completionReason(_ reason: GenerateStopReason) -> CompletionReason {
        switch reason {
        case .stop: .stop
        case .length: .length
        case .cancelled: .cancelled
        }
    }

    private static func fallbackID(name: String, arguments: Data) -> String {
        var data = Data(name.utf8)
        data.append(0)
        data.append(arguments)
        let digest = SHA256.hash(data: data)
        return "mlx-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

private struct LocalReasoningBaseConfiguration: Decodable {
    let modelType: String

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
    }
}

enum LocalReasoningConfigResolver {
    static func resolve(
        runtimeConfig: ReasoningConfig?,
        configData: Data,
        modelID: String
    ) -> ReasoningConfig? {
        if let runtimeConfig { return runtimeConfig }
        guard let base = try? JSONDecoder().decode(
            LocalReasoningBaseConfiguration.self,
            from: configData
        ) else {
            return nil
        }
        return ReasoningConfig.infer(
            from: base.modelType,
            modelId: modelID,
            configData: configData
        )
    }
}

actor MLXInferenceEngine: InferenceEngine {
    /// MLX's session is not Sendable. The engine enforces a single active task and
    /// never touches the leased value until that task is cancelled and awaited.
    private final class SessionLease: @unchecked Sendable {
        let value: MLXLMCommon.ChatSession

        init(_ value: MLXLMCommon.ChatSession) {
            self.value = value
        }
    }

    struct DebugSnapshot: Equatable, Sendable {
        let loadedModelID: ModelID?
        let hasContainer: Bool
        let hasSession: Bool
        let hasActiveGeneration: Bool
    }

    private var installation: ModelInstallation?
    private var container: ModelContainer?
    private var session: SessionLease?
    private var reasoningConfig: ReasoningConfig?
    private var activeGeneration: (id: UUID, task: Task<Void, Never>)?

    func load(_ installation: ModelInstallation) async throws {
        if self.installation == installation { return }

        await cancel()
        releaseLoadedModel()

        guard FileManager.default.fileExists(atPath: installation.directory.path) else {
            throw MLXInferenceError.modelDirectoryMissing
        }

        let loaded = try await VLMModelFactory.shared.loadContainer(
            from: installation.directory,
            using: #huggingFaceTokenizerLoader()
        )
        let configuration = await loaded.configuration
        container = loaded
        let configData = try Data(
            contentsOf: installation.directory.appending(path: "config.json")
        )
        reasoningConfig = LocalReasoningConfigResolver.resolve(
            runtimeConfig: configuration.reasoningConfig,
            configData: configData,
            modelID: installation.directory.lastPathComponent
        )
        session = SessionLease(
            MLXLMCommon.ChatSession(
                loaded,
                generateParameters: Self.parameters(
                    maxTokens: GenerationRequest.defaultMaxTokens
                )
            )
        )
        self.installation = installation
    }

    func generate(
        _ request: GenerationRequest
    ) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
        guard activeGeneration == nil else {
            throw MLXInferenceError.generationAlreadyActive
        }
        guard let session else { throw MLXInferenceError.modelNotLoaded }
        if request.reasoningEnabled, reasoningConfig == nil {
            throw MLXInferenceError.reasoningUnavailable
        }

        session.value.generateParameters = Self.parameters(maxTokens: request.maxTokens)
        session.value.additionalContext = ["enable_thinking": request.reasoningEnabled]

        let (stream, continuation) = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
        let generationID = UUID()
        let config = reasoningConfig
        let task = Task { [weak self] in
            await Self.runGeneration(
                request: request,
                session: session,
                reasoningConfig: config,
                continuation: continuation
            )
            await self?.generationFinished(id: generationID)
        }
        activeGeneration = (generationID, task)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.cancelGeneration(id: generationID) }
        }
        return stream
    }

    func cancel() async {
        guard let activeGeneration else { return }
        activeGeneration.task.cancel()
        await activeGeneration.task.value
    }

    func unload() async {
        await cancel()
        releaseLoadedModel()
    }

    func debugSnapshot() -> DebugSnapshot {
        DebugSnapshot(
            loadedModelID: installation?.modelID,
            hasContainer: container != nil,
            hasSession: session != nil,
            hasActiveGeneration: activeGeneration != nil
        )
    }

    private nonisolated static func runGeneration(
        request: GenerationRequest,
        session: SessionLease,
        reasoningConfig: ReasoningConfig?,
        continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) async {
        var state = MLXGenerationState(request: request, reasoningConfig: reasoningConfig)

        do {
            for try await generation in session.value.streamDetails(to: request.prompt) {
                try Task.checkCancellation()
                try state.consume(generation, continuation: continuation)
                // MLX may have several decoded events buffered. Explicitly yield the
                // task so cancel, unload, and dropped-consumer cleanup can interleave.
                await Task.yield()
            }
            // The MLX stream ends normally when its consuming task is cancelled,
            // so cancellation must be checked before synthesizing a stop terminal.
            try Task.checkCancellation()
            state.finishNormally(continuation: continuation)
            continuation.finish()
        } catch is CancellationError {
            state.finishCancellation(continuation: continuation)
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func cancelGeneration(id: UUID) async {
        guard let activeGeneration, activeGeneration.id == id else { return }
        activeGeneration.task.cancel()
        await activeGeneration.task.value
    }

    private func generationFinished(id: UUID) {
        guard activeGeneration?.id == id else { return }
        activeGeneration = nil
    }

    private func releaseLoadedModel() {
        session = nil
        container = nil
        reasoningConfig = nil
        installation = nil
    }

    private static func parameters(maxTokens: Int) -> GenerateParameters {
        GenerateParameters(maxTokens: maxTokens, temperature: 0, seed: 0)
    }
}

private struct MLXGenerationState {
    private let started = ContinuousClock().now
    private var timeToFirstToken: Duration?
    private var router: ReasoningRouter
    private var terminalEmitted = false

    init(request: GenerationRequest, reasoningConfig: ReasoningConfig?) {
        router = request.reasoningEnabled
            ? reasoningConfig.map { ReasoningRouter(config: $0, primed: true) } ?? .disabled
            : .disabled
    }

    mutating func consume(
        _ generation: MLXLMCommon.Generation,
        continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) throws {
        switch generation {
        case .chunk(let chunk):
            if !chunk.isEmpty { recordFirstToken() }
            router.consume(chunk).forEach { continuation.yield($0) }
        case .toolCall(let call):
            recordFirstToken()
            finalizeReasoning(continuation: continuation)
            continuation.yield(.toolRequest(try MLXGenerationMapper.toolInvocation(call)))
            continuation.yield(.completed(.toolRequest))
            terminalEmitted = true
        case .info(let info):
            finalizeReasoning(continuation: continuation)
            continuation.yield(
                .metrics(
                    MLXGenerationMapper.metrics(
                        info,
                        timeToFirstToken: timeToFirstToken ?? elapsed
                    )
                )
            )
            emitTerminal(
                MLXGenerationMapper.completionReason(info.stopReason),
                continuation: continuation
            )
        }
    }

    mutating func finishNormally(
        continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) {
        finalizeReasoning(continuation: continuation)
        emitTerminal(.stop, continuation: continuation)
    }

    mutating func finishCancellation(
        continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) {
        emitTerminal(.cancelled, continuation: continuation)
    }

    private var elapsed: Duration { started.duration(to: ContinuousClock().now) }

    private mutating func recordFirstToken() {
        if timeToFirstToken == nil { timeToFirstToken = elapsed }
    }

    private mutating func finalizeReasoning(
        continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) {
        router.finalize().forEach { continuation.yield($0) }
    }

    private mutating func emitTerminal(
        _ reason: CompletionReason,
        continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) {
        guard !terminalEmitted else { return }
        continuation.yield(.completed(reason))
        terminalEmitted = true
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
