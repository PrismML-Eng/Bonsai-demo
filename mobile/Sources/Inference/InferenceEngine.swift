import Foundation

enum GenerationRequestError: Error, Equatable, Sendable {
    case invalidMaxTokens(Int)
}

struct GenerationRequest: Equatable, Sendable {
    static let defaultMaxTokens = 512
    static let maximumMaxTokens = 4_096

    let prompt: String
    let reasoningEnabled: Bool
    let maxTokens: Int

    init(
        prompt: String,
        reasoningEnabled: Bool = true,
        maxTokens: Int = defaultMaxTokens
    ) throws {
        guard (1...Self.maximumMaxTokens).contains(maxTokens) else {
            throw GenerationRequestError.invalidMaxTokens(maxTokens)
        }
        self.prompt = prompt
        self.reasoningEnabled = reasoningEnabled
        self.maxTokens = maxTokens
    }
}

protocol InferenceEngine: Sendable {
    func load(_ installation: ModelInstallation) async throws
    func generate(_ request: GenerationRequest) async throws
        -> AsyncThrowingStream<GenerationEvent, any Error>
    func cancel() async
    func unload() async
}
