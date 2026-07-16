import Foundation

/// Counts the fully prepared model input for a complete structured candidate.
/// Implementations must apply the same chat template, tools, reasoning context,
/// processing options, and generation prompt used by generation.
protocol ConversationPromptCounting: Sendable {
    func promptTokenCount(for messages: [ConversationMessage]) async throws -> Int
}

enum ContextTrimmerError: Error, Equatable, Sendable {
    case invalidLimit(Int)
    case invalidPromptTokenCount(Int)
    case duplicateMessageID(MessageID)
    case requiredContextExceedsLimit(required: Int, limit: Int)
}

struct ContextTrimNotice: Equatable, Sendable {
    let removedTurnCount: Int
    let removedMessageCount: Int
}

struct ContextTrimResult: Equatable, Sendable {
    let keptMessages: [ConversationMessage]
    let keptTokenCount: Int
    let removedMessageIDs: [MessageID]
    let notice: ContextTrimNotice
}

struct ContextTrimmer: Sendable {
    static let defaultLimit = 4_096

    let limit: Int
    let promptCounter: any ConversationPromptCounting

    init(
        limit: Int = Self.defaultLimit,
        promptCounter: any ConversationPromptCounting
    ) {
        self.limit = limit
        self.promptCounter = promptCounter
    }

    func trim(
        _ conversation: Conversation,
        appending requiredMessages: [ConversationMessage] = []
    ) async throws -> ContextTrimResult {
        guard limit >= 0 else { throw ContextTrimmerError.invalidLimit(limit) }
        try validateUniqueIDs(conversation.contextMessages + requiredMessages)

        guard let newestIndex = conversation.completedTurns.indices.last else {
            let messages = [conversation.systemInstruction] + requiredMessages
            let count = try await count(messages)
            guard count <= limit else {
                throw ContextTrimmerError.requiredContextExceedsLimit(
                    required: count,
                    limit: limit
                )
            }
            return ContextTrimResult(
                keptMessages: messages,
                keptTokenCount: count,
                removedMessageIDs: [],
                notice: .init(removedTurnCount: 0, removedMessageCount: 0)
            )
        }

        var keptStart = newestIndex
        var keptMessages = candidateMessages(conversation, start: keptStart) + requiredMessages
        var keptTokenCount = try await count(keptMessages)
        guard keptTokenCount <= limit else {
            throw ContextTrimmerError.requiredContextExceedsLimit(
                required: keptTokenCount,
                limit: limit
            )
        }

        if newestIndex > 0 {
            for index in stride(from: newestIndex - 1, through: 0, by: -1) {
                let candidate = candidateMessages(conversation, start: index) + requiredMessages
                let candidateCount = try await count(candidate)
                guard candidateCount <= limit else { break }
                keptStart = index
                keptMessages = candidate
                keptTokenCount = candidateCount
            }
        }

        let removedTurns = conversation.completedTurns[..<keptStart]
        let removedIDs = removedTurns.flatMap(\.messages).map(\.id)
        return ContextTrimResult(
            keptMessages: keptMessages,
            keptTokenCount: keptTokenCount,
            removedMessageIDs: removedIDs,
            notice: .init(
                removedTurnCount: removedTurns.count,
                removedMessageCount: removedIDs.count
            )
        )
    }

    private func count(_ messages: [ConversationMessage]) async throws -> Int {
        let count = try await promptCounter.promptTokenCount(for: messages)
        guard count >= 0 else { throw ContextTrimmerError.invalidPromptTokenCount(count) }
        return count
    }

    private func candidateMessages(
        _ conversation: Conversation,
        start: Int
    ) -> [ConversationMessage] {
        [conversation.systemInstruction]
            + conversation.completedTurns[start...].flatMap(\.messages)
    }

    private func validateUniqueIDs(_ messages: [ConversationMessage]) throws {
        var seen: Set<MessageID> = []
        for message in messages where !seen.insert(message.id).inserted {
            throw ContextTrimmerError.duplicateMessageID(message.id)
        }
    }
}
