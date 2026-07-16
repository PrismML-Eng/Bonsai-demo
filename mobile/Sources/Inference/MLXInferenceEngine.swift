import CryptoKit
import Foundation
import MLXLMCommon

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
    private struct ActiveLoad {
        let id: UUID
        let intent: UInt64
        let installation: ModelInstallation
        let task: Task<any MLXRuntimeResource, any Error>
    }

    struct DebugSnapshot: Equatable, Sendable {
        let loadedModelID: ModelID?
        let hasContainer: Bool
        let hasSession: Bool
        let hasActiveGeneration: Bool
        let hasActiveLoad: Bool
    }

    private let loader: any MLXRuntimeLoading
    private var installation: ModelInstallation?
    private var runtime: (any MLXRuntimeResource)?
    private var activeGeneration: (id: UUID, task: Task<Void, Never>)?
    private var activeLoad: ActiveLoad?
    private var latestIntent: UInt64 = 0

    init(loader: any MLXRuntimeLoading = DefaultMLXRuntimeLoader()) {
        self.loader = loader
    }

    func load(_ installation: ModelInstallation) async throws {
        if self.installation == installation { return }
        if let activeLoad,
           activeLoad.installation == installation,
           !activeLoad.task.isCancelled {
            let resource = try await activeLoad.task.value
            try completeLoad(activeLoad, resource: resource)
            return
        }

        let intent = issueIntent()
        await cancel()
        try ensureCurrent(intent)
        releaseLoadedModel()
        await cancelActiveLoad()
        try ensureCurrent(intent)

        let id = UUID()
        let task = Task { [loader] in try await loader.load(installation) }
        let load = ActiveLoad(
            id: id,
            intent: intent,
            installation: installation,
            task: task
        )
        activeLoad = load
        do {
            let resource = try await task.value
            try completeLoad(load, resource: resource)
        } catch {
            if activeLoad?.id == id { activeLoad = nil }
            throw error
        }
    }

    func generate(
        _ request: GenerationRequest
    ) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
        guard activeGeneration == nil else {
            throw MLXInferenceError.generationAlreadyActive
        }
        guard let runtime else { throw MLXInferenceError.modelNotLoaded }
        if request.reasoningEnabled, runtime.reasoningConfig == nil {
            throw MLXInferenceError.reasoningUnavailable
        }

        runtime.configure(request)

        let (stream, continuation) = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
        let generationID = UUID()
        let config = runtime.reasoningConfig
        let task = Task { [weak self] in
            await Self.runGeneration(
                request: request,
                runtime: runtime,
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
        _ = issueIntent()
        await cancel()
        await cancelActiveLoad()
        releaseLoadedModel()
    }

    func debugSnapshot() -> DebugSnapshot {
        DebugSnapshot(
            loadedModelID: installation?.modelID,
            hasContainer: runtime != nil,
            hasSession: runtime != nil,
            hasActiveGeneration: activeGeneration != nil,
            hasActiveLoad: activeLoad != nil
        )
    }

    private nonisolated static func runGeneration(
        request: GenerationRequest,
        runtime: any MLXRuntimeResource,
        reasoningConfig: ReasoningConfig?,
        continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) async {
        var state = MLXGenerationState(request: request, reasoningConfig: reasoningConfig)

        do {
            for try await generation in runtime.streamDetails(to: request.prompt) {
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
            if state.hasTerminal {
                continuation.finish()
            } else {
                continuation.finish(throwing: error)
            }
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
        runtime = nil
        installation = nil
    }

    private func issueIntent() -> UInt64 {
        latestIntent &+= 1
        return latestIntent
    }

    private func ensureCurrent(_ intent: UInt64) throws {
        guard latestIntent == intent else { throw CancellationError() }
    }

    private func cancelActiveLoad() async {
        guard let activeLoad else { return }
        activeLoad.task.cancel()
        _ = await activeLoad.task.result
        if self.activeLoad?.id == activeLoad.id { self.activeLoad = nil }
    }

    private func completeLoad(
        _ load: ActiveLoad,
        resource: any MLXRuntimeResource
    ) throws {
        if installation == load.installation { return }
        guard latestIntent == load.intent,
              activeLoad?.id == load.id,
              !load.task.isCancelled else {
            throw CancellationError()
        }
        activeLoad = nil
        runtime = resource
        installation = load.installation
    }
}

private struct MLXGenerationState {
    private let started = ContinuousClock().now
    private var timeToFirstToken: Duration?
    private var router: ReasoningRouter
    private var sawToolCall = false
    private var terminalEmitted = false

    var hasTerminal: Bool { terminalEmitted }

    init(request: GenerationRequest, reasoningConfig: ReasoningConfig?) {
        router = request.reasoningEnabled
            ? reasoningConfig.map { ReasoningRouter(config: $0, primed: true) } ?? .disabled
            : .disabled(config: reasoningConfig)
    }

    mutating func consume(
        _ generation: MLXLMCommon.Generation,
        continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) throws {
        guard !terminalEmitted else { return }
        switch generation {
        case .chunk(let chunk):
            if !chunk.isEmpty { recordFirstToken() }
            router.consume(chunk).forEach { continuation.yield($0) }
        case .toolCall(let call):
            recordFirstToken()
            finalizeReasoning(continuation: continuation)
            continuation.yield(.toolRequest(try MLXGenerationMapper.toolInvocation(call)))
            sawToolCall = true
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
                sawToolCall
                    ? .toolRequest
                    : MLXGenerationMapper.completionReason(info.stopReason),
                continuation: continuation
            )
        }
    }

    mutating func finishNormally(
        continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) {
        finalizeReasoning(continuation: continuation)
        emitTerminal(sawToolCall ? .toolRequest : .stop, continuation: continuation)
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
