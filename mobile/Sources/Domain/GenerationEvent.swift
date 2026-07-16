import Foundation

struct GenerationMetrics: Equatable, Sendable {
    let promptTokenCount: Int
    let generatedTokenCount: Int
    let timeToFirstToken: Duration
    let tokensPerSecond: Double
}

enum CompletionReason: String, Equatable, Sendable {
    case stop
    case length
    case cancelled
    case toolRequest
}

enum GenerationEvent: Equatable, Sendable {
    case reasoning(String)
    case answer(String)
    case toolRequest(ToolInvocation)
    case metrics(GenerationMetrics)
    case completed(CompletionReason)
}
