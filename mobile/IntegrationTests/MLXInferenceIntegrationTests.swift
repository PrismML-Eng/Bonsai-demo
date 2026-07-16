import Foundation
import XCTest
@testable import BonsaiMobile

final class MLXInferenceIntegrationTests: XCTestCase {
    func testPublicOneBitReasoningCancellationAndReloadCycles() async throws {
        let modelDirectory = try Self.modelDirectory()
        let installation = ModelInstallation(
            modelID: .oneBit27B,
            directory: modelDirectory,
            revision: "public-local-fixture"
        )
        let engine = MLXInferenceEngine()
        let clock = ContinuousClock()

        let loadStarted = clock.now
        try await engine.load(installation)
        let loadDuration = loadStarted.duration(to: clock.now)

        try await Self.verifyReasoningOn(engine)
        try await Self.verifyReasoningOff(engine)
        let cancellationDuration = try await Self.verifyCancellation(engine, clock: clock)
        await Self.verifyUnload(engine)
        let cycleDurations = try await Self.verifyReloadCycles(engine, installation: installation)

        print("MLXInference model-load=\(loadDuration)")
        print("MLXInference cancellation=\(cancellationDuration)")
        print("MLXInference cycles=\(cycleDurations)")
    }

    private static func verifyReasoningOn(_ engine: MLXInferenceEngine) async throws {
        let events = try await collect(
            try await engine.generate(
                try GenerationRequest(
                    prompt: "Think briefly, then answer with exactly: green",
                    reasoningEnabled: true,
                    maxTokens: 256
                )
            )
        )
        let reasoning = events.text(for: .reasoning)
        let reasoningAnswer = events.text(for: .answer)
        XCTAssertFalse(reasoning.isEmpty)
        XCTAssertFalse(reasoningAnswer.isEmpty)
        XCTAssertFalse(reasoning.contains("<think>"))
        XCTAssertFalse(reasoningAnswer.contains("</think>"))
        XCTAssertEqual(events.terminalCount, 1)
        printMetrics(label: "reasoning-on", events: events)
    }

    private static func verifyReasoningOff(_ engine: MLXInferenceEngine) async throws {
        let events = try await collect(
            try await engine.generate(
                try GenerationRequest(
                    prompt: "Reply with exactly: blue",
                    reasoningEnabled: false,
                    maxTokens: 64
                )
            )
        )
        XCTAssertTrue(events.text(for: .reasoning).isEmpty)
        let answer = events.text(for: .answer)
        XCTAssertFalse(answer.isEmpty)
        XCTAssertFalse(answer.contains("<think>"))
        XCTAssertFalse(answer.contains("</think>"))
        XCTAssertEqual(events.terminalCount, 1)
        printMetrics(label: "reasoning-off", events: events)
    }

    private static func verifyCancellation(
        _ engine: MLXInferenceEngine,
        clock: ContinuousClock
    ) async throws -> Duration {
        let cancellationStream = try await engine.generate(
            try GenerationRequest(
                prompt: "Write a detailed 100-section field guide to botany.",
                reasoningEnabled: true,
                maxTokens: 4_096
            )
        )
        var iterator = cancellationStream.makeAsyncIterator()
        var cancellationEvents: [GenerationEvent] = []
        var sawDecodedPayload = false
        while let event = try await iterator.next() {
            cancellationEvents.append(event)
            if event.isDecodedPayload {
                sawDecodedPayload = true
                break
            }
        }
        XCTAssertTrue(sawDecodedPayload)

        let cancellationStarted = clock.now
        await engine.cancel()
        while let event = try await iterator.next() { cancellationEvents.append(event) }
        let cancellationDuration = cancellationStarted.duration(to: clock.now)
        XCTAssertEqual(cancellationEvents.terminalReasons, [.cancelled])
        XCTAssertEqual(cancellationEvents.last?.terminalReason, .cancelled)
        XCTAssertLessThan(cancellationDuration, .seconds(30))
        let snapshot = await engine.debugSnapshot()
        XCTAssertEqual(
            snapshot,
            .init(
                loadedModelID: .oneBit27B,
                hasContainer: true,
                hasSession: true,
                hasActiveGeneration: false,
                hasActiveLoad: false
            )
        )
        return cancellationDuration
    }

    private static func verifyUnload(_ engine: MLXInferenceEngine) async {
        await engine.unload()
        let unloadedSnapshot = await engine.debugSnapshot()
        XCTAssertEqual(
            unloadedSnapshot,
            .init(
                loadedModelID: nil,
                hasContainer: false,
                hasSession: false,
                hasActiveGeneration: false,
                hasActiveLoad: false
            )
        )
    }

    private static func verifyReloadCycles(
        _ engine: MLXInferenceEngine,
        installation: ModelInstallation
    ) async throws -> [Duration] {
        let clock = ContinuousClock()
        var cycleDurations: [Duration] = []
        for cycle in 1...3 {
            let cycleStarted = clock.now
            try await engine.load(installation)
            let events = try await Self.collect(
                try await engine.generate(
                    try GenerationRequest(
                        prompt: "Reply OK",
                        reasoningEnabled: false,
                        maxTokens: 16
                    )
                )
            )
            XCTAssertFalse(events.text(for: .answer).isEmpty, "cycle \(cycle)")
            await engine.unload()
            let snapshot = await engine.debugSnapshot()
            XCTAssertFalse(snapshot.hasContainer, "cycle \(cycle)")
            XCTAssertFalse(snapshot.hasSession, "cycle \(cycle)")
            XCTAssertFalse(snapshot.hasActiveGeneration, "cycle \(cycle)")
            XCTAssertFalse(snapshot.hasActiveLoad, "cycle \(cycle)")
            cycleDurations.append(cycleStarted.duration(to: clock.now))
        }
        return cycleDurations
    }

    private static func modelDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["BONSAI_MODEL_DIR"],
              !path.isEmpty else {
            throw XCTSkip("Set BONSAI_MODEL_DIR to the public 1-bit Bonsai-27B MLX directory.")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(
            atPath: directory.appending(path: "model.safetensors").path
        ) else {
            XCTFail("BONSAI_MODEL_DIR does not contain model.safetensors")
            throw MLXInferenceError.modelDirectoryMissing
        }
        return directory
    }

    private static func collect(
        _ stream: AsyncThrowingStream<GenerationEvent, any Error>
    ) async throws -> [GenerationEvent] {
        var events: [GenerationEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private static func printMetrics(label: String, events: [GenerationEvent]) {
        for event in events {
            if case .metrics(let metrics) = event {
                print(
                    "MLXInference \(label) ttft=\(metrics.timeToFirstToken) "
                        + "generated=\(metrics.generatedTokenCount) "
                        + "tokens-per-second=\(metrics.tokensPerSecond)"
                )
            }
        }
    }
}

private enum TextEventKind { case reasoning, answer }

private extension Array where Element == GenerationEvent {
    func text(for kind: TextEventKind) -> String {
        compactMap { event in
            switch (kind, event) {
            case (.reasoning, .reasoning(let text)), (.answer, .answer(let text)): text
            default: nil
            }
        }.joined()
    }

    var terminalReasons: [CompletionReason] {
        compactMap { event in
            if case .completed(let reason) = event { reason } else { nil }
        }
    }

    var terminalCount: Int { terminalReasons.count }
}

private extension GenerationEvent {
    var isDecodedPayload: Bool {
        switch self {
        case .reasoning, .answer, .toolRequest: true
        case .metrics, .completed: false
        }
    }

    var terminalReason: CompletionReason? {
        if case .completed(let reason) = self { reason } else { nil }
    }
}
