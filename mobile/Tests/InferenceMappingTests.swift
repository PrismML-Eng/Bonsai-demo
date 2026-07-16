import Foundation
import MLXLMCommon
import Testing
@testable import BonsaiMobile

@Suite("Inference mapping")
struct InferenceMappingTests {
    @Test
    func requestRequiresPositiveFiniteTokenLimit() throws {
        #expect(throws: GenerationRequestError.invalidMaxTokens(0)) {
            try GenerationRequest(prompt: "hello", reasoningEnabled: false, maxTokens: 0)
        }
        #expect(throws: GenerationRequestError.invalidMaxTokens(16_385)) {
            try GenerationRequest(prompt: "hello", reasoningEnabled: false, maxTokens: 16_385)
        }
        #expect(try GenerationRequest(prompt: "hello").maxTokens == 12_288)
    }

    @Test
    func exactReasoningBudgetSurvivesToolReplacement() throws {
        for budget in [-1, 0, 512, 2_048, 8_192] {
            let request = try GenerationRequest(prompt: "hello", reasoningBudget: budget)
            let replaced = request.replacingTools([
                .init(name: "calculator", description: "Calculate", parametersJSON: "{}")
            ])
            #expect(replaced.reasoningBudget == budget)
            #expect(replaced.reasoningEnabled == (budget != 0))
        }
        #expect(throws: GenerationRequestError.invalidReasoningBudget(-2)) {
            try GenerationRequest(prompt: "hello", reasoningBudget: -2)
        }
    }

    @Test
    func toolArgumentsUseStableSortedJSONAndFallbackID() throws {
        let call = MLXLMCommon.ToolCall(
            function: .init(
                name: "calculator",
                arguments: ["z": .int(2), "a": .string("one")]
            )
        )

        let first = try MLXGenerationMapper.toolInvocation(call)
        let second = try MLXGenerationMapper.toolInvocation(call)

        #expect(first.argumentsJSON == #"{"a":"one","z":2}"#)
        #expect(first.id == second.id)
        #expect(first.name == "calculator")
    }

    @Test
    func mapsMetricsAndStopReasons() {
        let info = GenerateCompletionInfo(
            promptTokenCount: 7,
            generationTokenCount: 4,
            promptTime: 0.5,
            generationTime: 2,
            stopReason: .length
        )

        let metrics = MLXGenerationMapper.metrics(
            info,
            timeToFirstToken: .milliseconds(250)
        )

        #expect(metrics.promptTokenCount == 7)
        #expect(metrics.generatedTokenCount == 4)
        #expect(metrics.timeToFirstToken == .milliseconds(250))
        #expect(metrics.tokensPerSecond == 2)
        #expect(MLXGenerationMapper.completionReason(info.stopReason) == .length)
        #expect(MLXGenerationMapper.completionReason(.cancelled) == .cancelled)
        #expect(MLXGenerationMapper.completionReason(.stop) == .stop)
    }

    @Test
    func infersQwenReasoningWhenVLMFactoryLeavesConfigurationEmpty() throws {
        let data = Data(#"{"model_type":"qwen3_5"}"#.utf8)

        let config = try #require(
            LocalReasoningConfigResolver.resolve(
                runtimeConfig: nil,
                configData: data,
                modelID: "Bonsai-27B-mlx"
            )
        )

        #expect(config.startDelimiter == "<think>")
        #expect(config.endDelimiter == "</think>")
    }
}
