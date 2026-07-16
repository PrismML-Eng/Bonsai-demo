import Foundation
import MLXLMCommon
import Testing
@testable import BonsaiMobile

@Suite("MLX generation event ordering")
struct MLXGenerationOrderingTests {
    @Test
    func multipleToolCallsRemainOrderedAndMetricsPrecedeSingleTerminal() async throws {
        let resource = ScriptedRuntimeResource(events: [
            .chunk("before"),
            .toolCall(Self.call(id: "call-1", name: "first")),
            .chunk("between"),
            .toolCall(Self.call(id: "call-2", name: "second")),
            .info(Self.info),
            .chunk("must-not-escape-after-terminal")
        ])
        let engine = MLXInferenceEngine(loader: ImmediateRuntimeLoader(resource: resource))
        try await engine.load(Self.installation)

        let stream = try await engine.generate(
            try GenerationRequest(prompt: "tools", reasoningEnabled: false)
        )
        let events = try await Array(stream)

        #expect(events.compactMap(\.toolInvocation).map(\.id) == ["call-1", "call-2"])
        #expect(events.filter(\.isMetrics).count == 1)
        #expect(events.filter(\.isTerminal) == [.completed(.toolRequest)])
        #expect(events.last == .completed(.toolRequest))
        #expect(!events.contains(.answer("must-not-escape-after-terminal")))
        let metricsIndex = events.firstIndex { $0.isMetrics } ?? -1
        let terminalIndex = events.firstIndex { $0.isTerminal } ?? -1
        #expect(metricsIndex >= 0)
        #expect(metricsIndex < terminalIndex)
    }

    @Test
    func missingInfoFallsBackToOneToolTerminalLast() async throws {
        let resource = ScriptedRuntimeResource(events: [
            .toolCall(Self.call(id: "call-1", name: "first")),
            .chunk("after")
        ])
        let engine = MLXInferenceEngine(loader: ImmediateRuntimeLoader(resource: resource))
        try await engine.load(Self.installation)

        let stream = try await engine.generate(
            try GenerationRequest(prompt: "tools", reasoningEnabled: false)
        )
        let events = try await Array(stream)

        #expect(events.compactMap(\.toolInvocation).map(\.id) == ["call-1"])
        #expect(events.filter(\.isTerminal) == [.completed(.toolRequest)])
        #expect(events.last == .completed(.toolRequest))
    }

    @Test
    func cancellationAfterToolPayloadFinishesCancelledExactlyOnce() async throws {
        let resource = ScriptedRuntimeResource(
            events: [.toolCall(Self.call(id: "call-1", name: "first"))],
            holdsOpen: true
        )
        let engine = MLXInferenceEngine(loader: ImmediateRuntimeLoader(resource: resource))
        try await engine.load(Self.installation)
        let stream = try await engine.generate(
            try GenerationRequest(prompt: "tools", reasoningEnabled: false)
        )
        var iterator = stream.makeAsyncIterator()

        #expect(try await iterator.next()?.toolInvocation?.id == "call-1")
        await engine.cancel()
        var remaining: [GenerationEvent] = []
        while let event = try await iterator.next() { remaining.append(event) }

        #expect(remaining == [.completed(.cancelled)])
        #expect(await engine.debugSnapshot().hasActiveGeneration == false)
    }

    @Test
    func runtimeErrorBeforeInfoThrowsWithoutInventingACompletion() async throws {
        let resource = ScriptedRuntimeResource(
            events: [.toolCall(Self.call(id: "call-1", name: "first"))],
            failure: ScriptedRuntimeFailure.boom
        )
        let engine = MLXInferenceEngine(loader: ImmediateRuntimeLoader(resource: resource))
        try await engine.load(Self.installation)
        let stream = try await engine.generate(
            try GenerationRequest(prompt: "tools", reasoningEnabled: false)
        )
        var observed: [GenerationEvent] = []

        await #expect(throws: ScriptedRuntimeFailure.boom) {
            for try await event in stream { observed.append(event) }
        }

        #expect(observed.compactMap(\.toolInvocation).map(\.id) == ["call-1"])
        #expect(observed.filter(\.isTerminal).isEmpty)
    }

    @Test
    func runtimeErrorAfterInfoCannotEscapePastTerminal() async throws {
        let resource = ScriptedRuntimeResource(
            events: [
                .toolCall(Self.call(id: "call-1", name: "first")),
                .info(Self.info)
            ],
            failure: ScriptedRuntimeFailure.boom
        )
        let engine = MLXInferenceEngine(loader: ImmediateRuntimeLoader(resource: resource))
        try await engine.load(Self.installation)
        let stream = try await engine.generate(
            try GenerationRequest(prompt: "tools", reasoningEnabled: false)
        )

        let events = try await Array(stream)

        #expect(events.filter(\.isTerminal) == [.completed(.toolRequest)])
        #expect(events.last == .completed(.toolRequest))
    }

    private static let installation = ModelInstallation(
        modelID: .oneBit27B,
        directory: URL(fileURLWithPath: "/tmp/one-bit"),
        revision: String(repeating: "a", count: 40)
    )

    private static let info = GenerateCompletionInfo(
        promptTokenCount: 5,
        generationTokenCount: 3,
        promptTime: 0.1,
        generationTime: 0.3,
        stopReason: .stop
    )

    private static func call(id: String, name: String) -> MLXLMCommon.ToolCall {
        .init(function: .init(name: name, arguments: ["value": .int(1)]), id: id)
    }
}

private enum ScriptedRuntimeFailure: Error, Equatable { case boom }

private struct ImmediateRuntimeLoader: MLXRuntimeLoading {
    let resource: any MLXRuntimeResource

    func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource {
        resource
    }
}

private final class ScriptedRuntimeResource: MLXRuntimeResource, @unchecked Sendable {
    let reasoningConfig: ReasoningConfig? = nil
    private let events: [MLXLMCommon.Generation]
    private let holdsOpen: Bool
    private let failure: (any Error)?

    init(
        events: [MLXLMCommon.Generation],
        holdsOpen: Bool = false,
        failure: (any Error)? = nil
    ) {
        self.events = events
        self.holdsOpen = holdsOpen
        self.failure = failure
    }

    func configure(_ request: GenerationRequest) {}

    func streamDetails(to prompt: String) -> AsyncThrowingStream<MLXLMCommon.Generation, Error> {
        AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            if let failure {
                continuation.finish(throwing: failure)
            } else if !holdsOpen {
                continuation.finish()
            }
        }
    }
}

private extension GenerationEvent {
    var toolInvocation: ToolInvocation? {
        if case .toolRequest(let invocation) = self { invocation } else { nil }
    }

    var isMetrics: Bool {
        if case .metrics = self { true } else { false }
    }

    var isTerminal: Bool {
        if case .completed = self { true } else { false }
    }
}

private extension Array {
    init(_ stream: AsyncThrowingStream<Element, any Error>) async throws {
        self = []
        for try await element in stream { append(element) }
    }
}
