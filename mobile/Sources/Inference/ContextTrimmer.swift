import Foundation

protocol ConversationTokenCounting: Sendable {
    func tokenCount(for message: ConversationMessage) throws -> Int
}

enum ContextTrimmerError: Error, Equatable, Sendable {
    case invalidLimit(Int)
    case invalidTokenCount(messageID: MessageID, count: Int)
    case tokenCountOverflow
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
    let tokenCounter: any ConversationTokenCounting

    init(
        limit: Int = Self.defaultLimit,
        tokenCounter: any ConversationTokenCounting
    ) {
        self.limit = limit
        self.tokenCounter = tokenCounter
    }

    func trim(_ conversation: Conversation) throws -> ContextTrimResult {
        guard limit >= 0 else { throw ContextTrimmerError.invalidLimit(limit) }

        let messages = [conversation.systemInstruction]
            + conversation.completedTurns.flatMap(\.messages)
        let counts = try validatedCounts(messages)
        let systemCount = counts[conversation.systemInstruction.id] ?? 0

        guard let newestIndex = conversation.completedTurns.indices.last else {
            return try systemOnlyResult(conversation.systemInstruction, tokenCount: systemCount)
        }

        let newestCount = try total(
            conversation.completedTurns[newestIndex].messages,
            counts: counts
        )
        var keptTokenCount = try adding(systemCount, newestCount)
        guard keptTokenCount <= limit else {
            throw ContextTrimmerError.requiredContextExceedsLimit(
                required: keptTokenCount,
                limit: limit
            )
        }

        var keptStart = newestIndex
        if newestIndex > 0 {
            for index in stride(from: newestIndex - 1, through: 0, by: -1) {
                let turnCount = try total(conversation.completedTurns[index].messages, counts: counts)
                let candidate = try adding(keptTokenCount, turnCount)
                guard candidate <= limit else { break }
                keptStart = index
                keptTokenCount = candidate
            }
        }

        let removedTurns = Array(conversation.completedTurns[..<keptStart])
        let keptTurns = conversation.completedTurns[keptStart...]
        let removedIDs = removedTurns.flatMap(\.messages).map(\.id)
        return ContextTrimResult(
            keptMessages: [conversation.systemInstruction] + keptTurns.flatMap(\.messages),
            keptTokenCount: keptTokenCount,
            removedMessageIDs: removedIDs,
            notice: .init(
                removedTurnCount: removedTurns.count,
                removedMessageCount: removedIDs.count
            )
        )
    }

    private func systemOnlyResult(
        _ systemInstruction: ConversationMessage,
        tokenCount: Int
    ) throws -> ContextTrimResult {
        guard tokenCount <= limit else {
            throw ContextTrimmerError.requiredContextExceedsLimit(
                required: tokenCount,
                limit: limit
            )
        }
        return ContextTrimResult(
            keptMessages: [systemInstruction],
            keptTokenCount: tokenCount,
            removedMessageIDs: [],
            notice: .init(removedTurnCount: 0, removedMessageCount: 0)
        )
    }

    private func validatedCounts(
        _ messages: [ConversationMessage]
    ) throws -> [MessageID: Int] {
        var seen: Set<MessageID> = []
        var counts: [MessageID: Int] = [:]
        for message in messages {
            guard seen.insert(message.id).inserted else {
                throw ContextTrimmerError.duplicateMessageID(message.id)
            }
            let count = try tokenCounter.tokenCount(for: message)
            guard count >= 0 else {
                throw ContextTrimmerError.invalidTokenCount(messageID: message.id, count: count)
            }
            counts[message.id] = count
        }
        return counts
    }

    private func total(
        _ messages: [ConversationMessage],
        counts: [MessageID: Int]
    ) throws -> Int {
        try messages.reduce(into: 0) { result, message in
            result = try adding(result, counts[message.id] ?? 0)
        }
    }

    private func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw ContextTrimmerError.tokenCountOverflow }
        return result
    }
}
