import Foundation
import MLXLMCommon

// swiftlint:disable file_length

enum MLXInferenceError: Error, Equatable, Sendable {
  case modelDirectoryMissing
  case modelNotLoaded
  case generationAlreadyActive
  case reasoningUnavailable
  case invalidToolArgumentsEncoding
  case tokenCountingUnavailable
  case conversationModelMismatch(expected: ModelID, attempted: ModelID)
}

// swiftlint:disable:next type_body_length
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
  private let cacheClearer: any MLXCacheClearing
  private var installation: ModelInstallation?
  private var runtime: (any MLXRuntimeResource)?
  private var activeGeneration: (id: UUID, task: Task<Void, Never>)?
  private var activeLoad: ActiveLoad?
  private var latestIntent: UInt64 = 0
  private var lastRequest: GenerationRequest?

  init(
    loader: any MLXRuntimeLoading = DefaultMLXRuntimeLoader(),
    cacheClearer: any MLXCacheClearing = DefaultMLXCacheClearer()
  ) {
    self.loader = loader
    self.cacheClearer = cacheClearer
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
    lastRequest = request

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

  func continueAfterTools(
    _ exchange: AgentToolExchange
  ) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
    if let previous = activeGeneration {
      await previous.task.value
      generationFinished(id: previous.id)
    }
    guard let runtime, let request = lastRequest else { throw MLXInferenceError.modelNotLoaded }
    let mlxStream = try runtime.continueAfterTools(exchange)
    let (stream, continuation) = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
    let generationID = UUID()
    let task = Task { [weak self] in
      await Self.runGenerationStream(
        mlxStream,
        request: request,
        reasoningConfig: runtime.reasoningConfig,
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

  /// Invalidates and awaits both generation and model loading before callers
  /// clear process-wide MLX caches. A cancellation-insensitive loader may
  /// finish late, but its superseded intent can never install that resource.
  func cancelForCriticalRecovery() async {
    _ = issueIntent()
    await cancel()
    await cancelActiveLoad()
  }

  func unload() async {
    _ = issueIntent()
    await cancel()
    await cancelActiveLoad()
    releaseLoadedModel()
  }

  /// Drops the current MLX chat session and its optional vision/KV state while
  /// retaining the loaded ModelContainer. The pinned runtime has no public
  /// vision-only cache API, so the next generation recreates a clean session.
  func releaseOptionalVisionState() async {
    await cancel()
    runtime?.releaseOptionalSession()
  }

  func clearReusableCaches() {
    cacheClearer.clear()
  }

  func trimContext(
    _ conversation: Conversation,
    limit: Int = ContextTrimmer.defaultLimit,
    reasoningEnabled: Bool = true,
    tools: [GenerationToolSpecification] = []
  ) async throws -> ContextTrimResult {
    guard activeGeneration == nil else {
      throw MLXInferenceError.generationAlreadyActive
    }
    guard let runtime, let installation else {
      throw MLXInferenceError.modelNotLoaded
    }
    guard conversation.modelID == installation.modelID else {
      throw MLXInferenceError.conversationModelMismatch(
        expected: installation.modelID,
        attempted: conversation.modelID
      )
    }
    let intent = latestIntent
    let result = try await ContextTrimmer(
      limit: limit,
      promptCounter: MLXConversationPromptCounter(
        runtime: runtime,
        reasoningEnabled: reasoningEnabled,
        tools: tools
      )
    ).trim(conversation)
    try ensureCurrent(intent)
    return result
  }

  func preparedGeneration(
    for conversation: Conversation,
    appending requiredMessages: [ConversationMessage] = [],
    limit: Int = ContextTrimmer.defaultLimit,
    reasoningEnabled: Bool = true,
    reasoningBudget: Int? = nil,
    tools: [GenerationToolSpecification] = [],
    maxTokens: Int = GenerationRequest.defaultMaxTokens
  ) async throws -> (trim: ContextTrimResult, request: GenerationRequest) {
    guard activeGeneration == nil, let runtime, let installation else {
      throw activeGeneration == nil ? MLXInferenceError.modelNotLoaded : MLXInferenceError.generationAlreadyActive
    }
    guard conversation.modelID == installation.modelID else {
      throw MLXInferenceError.conversationModelMismatch(expected: installation.modelID,
                                                         attempted: conversation.modelID)
    }
    let enabled = (reasoningBudget ?? (reasoningEnabled ? -1 : 0)) != 0
    let trim = try await ContextTrimmer(
      limit: limit,
      promptCounter: MLXConversationPromptCounter(runtime: runtime, reasoningEnabled: enabled,
                                                   tools: tools)
    ).trim(conversation, appending: requiredMessages)
    return (
      trim,
      try GenerationRequest(
        messages: trim.keptMessages,
        tools: tools,
        reasoningEnabled: enabled,
        reasoningBudget: reasoningBudget,
        maxTokens: maxTokens
      )
    )
  }

  func debugSnapshot() -> DebugSnapshot {
    DebugSnapshot(
      loadedModelID: installation?.modelID,
      hasContainer: runtime != nil,
      hasSession: runtime?.hasSession == true,
      hasActiveGeneration: activeGeneration != nil,
      hasActiveLoad: activeLoad != nil
    )
  }

  func continuationDebugSnapshot() -> MLXContinuationDebugSnapshot {
    runtime?.continuationDebugSnapshot ?? .unavailable
  }

  private nonisolated static func runGeneration(
    request: GenerationRequest,
    runtime: any MLXRuntimeResource,
    reasoningConfig: ReasoningConfig?,
    continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
  ) async {
    do {
      let stream =
        try request.messages.map { try runtime.streamDetails(to: $0) }
        ?? runtime.streamDetails(to: request.prompt)
      await runGenerationStream(
        stream,
        request: request,
        reasoningConfig: reasoningConfig,
        continuation: continuation
      )
    } catch {
      continuation.finish(throwing: error)
    }
  }

  private nonisolated static func runGenerationStream(
    _ stream: AsyncThrowingStream<MLXLMCommon.Generation, Error>,
    request: GenerationRequest,
    reasoningConfig: ReasoningConfig?,
    continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
  ) async {
    var state = MLXGenerationState(request: request, reasoningConfig: reasoningConfig)
    do {
      for try await generation in stream {
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
    lastRequest = nil
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
      !load.task.isCancelled
    else {
      throw CancellationError()
    }
    activeLoad = nil
    runtime = resource
    installation = load.installation
  }
}

extension MLXInferenceEngine: AgentInferenceStreaming {}

private struct MLXConversationPromptCounter: ConversationPromptCounting {
  let runtime: any MLXRuntimeResource
  let reasoningEnabled: Bool
  let tools: [GenerationToolSpecification]

  func promptTokenCount(for messages: [ConversationMessage]) async throws -> Int {
    try await runtime.preparedPromptTokenCount(
      for: messages,
      reasoningEnabled: reasoningEnabled,
      tools: tools
    )
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
    router =
      request.reasoningEnabled
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
