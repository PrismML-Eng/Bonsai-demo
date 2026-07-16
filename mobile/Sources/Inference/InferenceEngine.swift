import Foundation

enum GenerationRequestError: Error, Equatable, Sendable {
    case invalidMaxTokens(Int)
}

struct GenerationToolSpecification: Equatable, Sendable {
    let name: String
    let description: String
    let parametersJSON: String
}

struct GenerationRequest: Equatable, Sendable {
    static let defaultMaxTokens = 512
    static let maximumMaxTokens = 4_096

    let prompt: String
    let messages: [ConversationMessage]?
    let tools: [GenerationToolSpecification]
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
        messages = nil
        tools = []
        self.reasoningEnabled = reasoningEnabled
        self.maxTokens = maxTokens
    }

    init(
        messages: [ConversationMessage],
        tools: [GenerationToolSpecification] = [],
        reasoningEnabled: Bool = true,
        maxTokens: Int = defaultMaxTokens
    ) throws {
        guard (1...Self.maximumMaxTokens).contains(maxTokens) else {
            throw GenerationRequestError.invalidMaxTokens(maxTokens)
        }
        self.prompt = messages.last?.content ?? ""
        self.messages = messages
        self.tools = tools
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
