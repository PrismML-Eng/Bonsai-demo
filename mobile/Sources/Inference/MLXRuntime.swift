import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

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

protocol MLXRuntimeResource: AnyObject, Sendable {
    var reasoningConfig: ReasoningConfig? { get }
    var hasSession: Bool { get }
    func configure(_ request: GenerationRequest)
    func streamDetails(
        to prompt: String
    ) -> AsyncThrowingStream<MLXLMCommon.Generation, Error>
    func streamDetails(
        to messages: [ConversationMessage]
    ) throws -> AsyncThrowingStream<MLXLMCommon.Generation, Error>
    func releaseOptionalSession()
    func preparedPromptTokenCount(
        for messages: [ConversationMessage],
        reasoningEnabled: Bool,
        tools: [GenerationToolSpecification]
    ) async throws -> Int
}

extension MLXRuntimeResource {
    var hasSession: Bool { true }
    func releaseOptionalSession() {}
    func streamDetails(
        to messages: [ConversationMessage]
    ) throws -> AsyncThrowingStream<MLXLMCommon.Generation, Error> {
        throw MLXInferenceError.tokenCountingUnavailable
    }
    func preparedPromptTokenCount(
        for messages: [ConversationMessage],
        reasoningEnabled: Bool,
        tools: [GenerationToolSpecification]
    ) async throws -> Int {
        throw MLXInferenceError.tokenCountingUnavailable
    }
}

protocol MLXCacheClearing: Sendable {
    func clear()
}

struct DefaultMLXCacheClearer: MLXCacheClearing {
    func clear() {
        Memory.clearCache()
    }
}

protocol MLXRuntimeLoading: Sendable {
    func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource
}

struct DefaultMLXRuntimeLoader: MLXRuntimeLoading {
    func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource {
        guard FileManager.default.fileExists(atPath: installation.directory.path) else {
            throw MLXInferenceError.modelDirectoryMissing
        }
        let container = try await VLMModelFactory.shared.loadContainer(
            from: installation.directory,
            using: #huggingFaceTokenizerLoader()
        )
        let configuration = await container.configuration
        let configData = try Data(
            contentsOf: installation.directory.appending(path: "config.json")
        )
        let reasoningConfig = LocalReasoningConfigResolver.resolve(
            runtimeConfig: configuration.reasoningConfig,
            configData: configData,
            modelID: installation.directory.lastPathComponent
        )
        return LiveMLXRuntimeResource(container: container, reasoningConfig: reasoningConfig)
    }
}

private final class LiveMLXRuntimeResource: MLXRuntimeResource, @unchecked Sendable {
    private let container: ModelContainer
    private var session: MLXLMCommon.ChatSession?
    private var configuredRequest: GenerationRequest?
    let reasoningConfig: ReasoningConfig?
    var hasSession: Bool { session != nil }

    init(container: ModelContainer, reasoningConfig: ReasoningConfig?) {
        self.container = container
        self.reasoningConfig = reasoningConfig
        session = Self.makeSession(container: container)
    }

    func configure(_ request: GenerationRequest) {
        configuredRequest = request
        let session = ensureSession()
        Self.configure(session, request: request)
    }

    func streamDetails(
        to prompt: String
    ) -> AsyncThrowingStream<MLXLMCommon.Generation, Error> {
        ensureSession().streamDetails(to: prompt)
    }

    func streamDetails(
        to messages: [ConversationMessage]
    ) throws -> AsyncThrowingStream<MLXLMCommon.Generation, Error> {
        guard let configuredRequest else { throw MLXInferenceError.tokenCountingUnavailable }
        let created = Self.makeSession(container: container)
        Self.configure(created, request: configuredRequest)
        session = created
        return created.streamDetails(to: try MLXPromptComposer.chatMessages(messages))
    }

    func releaseOptionalSession() {
        session = nil
    }

    func preparedPromptTokenCount(
        for messages: [ConversationMessage],
        reasoningEnabled: Bool,
        tools: [GenerationToolSpecification]
    ) async throws -> Int {
        let input = UserInput(
            chat: try MLXPromptComposer.chatMessages(messages),
            processing: Self.processing,
            tools: try MLXPromptComposer.toolSpecs(tools),
            additionalContext: ["enable_thinking": reasoningEnabled]
        )
        return try await container.prepare(input: input).text.tokens.size
    }

    private func ensureSession() -> MLXLMCommon.ChatSession {
        if let session { return session }
        let created = Self.makeSession(container: container)
        session = created
        return created
    }

    private static func makeSession(container: ModelContainer) -> MLXLMCommon.ChatSession {
        MLXLMCommon.ChatSession(
            container,
            generateParameters: parameters(maxTokens: GenerationRequest.defaultMaxTokens),
            processing: processing
        )
    }

    private static let processing = UserInput.Processing(
        resize: CGSize(width: 512, height: 512)
    )

    private static func configure(_ session: MLXLMCommon.ChatSession, request: GenerationRequest) {
        session.generateParameters = parameters(maxTokens: request.maxTokens)
        session.additionalContext = ["enable_thinking": request.reasoningEnabled]
        session.tools = try? MLXPromptComposer.toolSpecs(request.tools)
    }

    private static func parameters(maxTokens: Int) -> GenerateParameters {
        GenerateParameters(maxTokens: maxTokens, temperature: 0, seed: 0)
    }
}

enum MLXPromptComposer {
    static func chatMessages(_ messages: [ConversationMessage]) throws -> [Chat.Message] {
        try messages.map { message in
            switch message.role {
            case .system: .system(message.content)
            case .user: .user(message.content)
            case .assistant: .assistant(message.content)
            case .toolCall:
                try .assistant(
                    "",
                    toolCalls: [toolCall(message)]
                )
            case .toolResult:
                .tool(message.content, id: message.transactionID)
            }
        }
    }

    static func toolSpecs(
        _ tools: [GenerationToolSpecification]
    ) throws -> [ToolSpec]? {
        guard !tools.isEmpty else { return nil }
        return try tools.map { tool in
            let parameters = try JSONDecoder().decode(
                [String: JSONValue].self,
                from: Data(tool.parametersJSON.utf8)
            )
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": parameters.mapValues(sendableValue)
                ] as [String: any Sendable]
            ]
        }
    }

    private static func toolCall(_ message: ConversationMessage) throws -> MLXLMCommon.ToolCall {
        let invocation = try JSONDecoder().decode(
            ToolInvocation.self,
            from: Data(message.content.utf8)
        )
        let arguments = try JSONDecoder().decode(
            [String: JSONValue].self,
            from: Data(invocation.argumentsJSON.utf8)
        )
        return .init(
            function: .init(name: invocation.name, arguments: arguments),
            id: message.transactionID ?? invocation.id
        )
    }

    private static func sendableValue(_ value: JSONValue) -> any Sendable {
        switch value {
        case .null: NSNull()
        case .bool(let value): value
        case .int(let value): value
        case .double(let value): value
        case .string(let value): value
        case .array(let values): values.map(sendableValue)
        case .object(let values): values.mapValues(sendableValue)
        }
    }
}
