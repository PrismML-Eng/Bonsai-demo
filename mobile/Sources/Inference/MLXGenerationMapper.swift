import CryptoKit
import Foundation
import MLXLMCommon

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

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
