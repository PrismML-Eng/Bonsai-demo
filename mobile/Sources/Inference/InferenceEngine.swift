import Foundation

enum GenerationRequestError: Error, Equatable, Sendable {
    case invalidMaxTokens(Int)
    case invalidReasoningBudget(Int)
}

struct GenerationToolSpecification: Equatable, Sendable {
    let name: String
    let description: String
    let parametersJSON: String
}

struct GenerationImage: Equatable, Sendable {
    let messageID: MessageID
    let attachmentID: UUID
    let buffer: ProcessedImageBuffer
}

struct GenerationRequest: Equatable, Sendable {
    static let defaultMaxTokens = 12_288
    static let maximumMaxTokens = 16_384

    let prompt: String
    let messages: [ConversationMessage]?
    let tools: [GenerationToolSpecification]
    let images: [GenerationImage]
    let reasoningBudget: Int
    var reasoningEnabled: Bool { reasoningBudget != 0 }
    let maxTokens: Int

    init(
        prompt: String,
        reasoningEnabled: Bool = true,
        reasoningBudget: Int? = nil,
        maxTokens: Int = defaultMaxTokens
    ) throws {
        guard (1...Self.maximumMaxTokens).contains(maxTokens) else {
            throw GenerationRequestError.invalidMaxTokens(maxTokens)
        }
        let resolvedBudget = reasoningBudget ?? (reasoningEnabled ? -1 : 0)
        guard resolvedBudget >= -1 else {
            throw GenerationRequestError.invalidReasoningBudget(resolvedBudget)
        }
        self.prompt = prompt
        messages = nil
        tools = []
        images = []
        self.reasoningBudget = resolvedBudget
        self.maxTokens = maxTokens
    }

    init(
        messages: [ConversationMessage],
        tools: [GenerationToolSpecification] = [],
        images: [GenerationImage] = [],
        reasoningEnabled: Bool = true,
        reasoningBudget: Int? = nil,
        maxTokens: Int = defaultMaxTokens
    ) throws {
        guard (1...Self.maximumMaxTokens).contains(maxTokens) else {
            throw GenerationRequestError.invalidMaxTokens(maxTokens)
        }
        let resolvedBudget = reasoningBudget ?? (reasoningEnabled ? -1 : 0)
        guard resolvedBudget >= -1 else {
            throw GenerationRequestError.invalidReasoningBudget(resolvedBudget)
        }
        self.prompt = messages.last?.content ?? ""
        self.messages = messages
        self.tools = tools
        self.images = images
        self.reasoningBudget = resolvedBudget
        self.maxTokens = maxTokens
    }

    func replacingTools(_ tools: [GenerationToolSpecification]) -> GenerationRequest {
        GenerationRequest(
            validatedPrompt: prompt,
            messages: messages,
            tools: tools,
            images: images,
            reasoningBudget: reasoningBudget,
            maxTokens: maxTokens
        )
    }

    func replacingImages(_ images: [GenerationImage]) -> GenerationRequest {
        GenerationRequest(
            validatedPrompt: prompt,
            messages: messages,
            tools: tools,
            images: images,
            reasoningBudget: reasoningBudget,
            maxTokens: maxTokens
        )
    }

    private init(
        validatedPrompt: String,
        messages: [ConversationMessage]?,
        tools: [GenerationToolSpecification],
        images: [GenerationImage],
        reasoningBudget: Int,
        maxTokens: Int
    ) {
        prompt = validatedPrompt
        self.messages = messages
        self.tools = tools
        self.images = images
        self.reasoningBudget = reasoningBudget
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
