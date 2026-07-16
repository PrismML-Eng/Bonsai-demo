import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Context trimming")
struct ContextTrimmerTests {
    @Test
    func defaultLimitKeepsSystemAndNewestCompleteSuffixWithin4096() throws {
        let conversation = try Self.conversation(turns: [
            Self.turn("old", roles: [.user, .assistant]),
            Self.turn("new", roles: [.user, .assistant])
        ])
        let counter = ExactTokenCounter(counts: [
            "system": 100,
            "old-0": 1_200,
            "old-1": 1_300,
            "new-0": 1_000,
            "new-1": 1_000
        ])

        let result = try ContextTrimmer(tokenCounter: counter).trim(conversation)

        #expect(result.keptTokenCount == 2_100)
        #expect(result.keptMessages.map(\.id.rawValue) == ["system", "new-0", "new-1"])
        #expect(result.removedMessageIDs.map(\.rawValue) == ["old-0", "old-1"])
        #expect(result.notice == .init(removedTurnCount: 1, removedMessageCount: 2))
    }

    @Test
    func neverSplitsAToolCallResultTransaction() throws {
        let conversation = try Self.conversation(turns: [
            Self.turn("old", roles: [.user, .toolCall, .toolResult, .assistant]),
            Self.turn("new", roles: [.user, .assistant])
        ])
        let counts = Dictionary(
            uniqueKeysWithValues: conversation.allMessages.map { ($0.id.rawValue, 900) }
        )

        let result = try ContextTrimmer(limit: 4_096, tokenCounter: ExactTokenCounter(counts: counts))
            .trim(conversation)

        #expect(result.keptMessages.map(\.id.rawValue) == ["system", "new-0", "new-1"])
        #expect(result.removedMessageIDs.map(\.rawValue) == [
            "old-0", "old-1", "old-2", "old-3"
        ])
    }

    @Test
    func throwsWhenSystemAndNewestIndivisibleTurnExceedLimit() throws {
        let conversation = try Self.conversation(turns: [
            Self.turn("new", roles: [.user, .assistant])
        ])
        let counter = ExactTokenCounter(counts: ["system": 100, "new-0": 2_000, "new-1": 2_000])

        #expect(throws: ContextTrimmerError.requiredContextExceedsLimit(required: 4_100, limit: 4_096)) {
            try ContextTrimmer(tokenCounter: counter).trim(conversation)
        }
    }

    @Test
    func rejectsNegativeRuntimeTokenCounts() throws {
        let conversation = try Self.conversation(turns: [])

        #expect(throws: ContextTrimmerError.invalidTokenCount(
            messageID: MessageID("system"),
            count: -1
        )) {
            try ContextTrimmer(tokenCounter: ExactTokenCounter(counts: ["system": -1]))
                .trim(conversation)
        }
    }

    @Test
    func rejectsOverflowInsteadOfWrappingTokenTotals() throws {
        let conversation = try Self.conversation(turns: [
            Self.turn("new", roles: [.user, .assistant])
        ])
        let counter = ExactTokenCounter(counts: [
            "system": Int.max,
            "new-0": 1,
            "new-1": 1
        ])

        #expect(throws: ContextTrimmerError.tokenCountOverflow) {
            try ContextTrimmer(limit: Int.max, tokenCounter: counter).trim(conversation)
        }
    }

    @Test
    func conversationValidationRejectsDuplicateIDsAndInvalidOrder() throws {
        let system = ConversationMessage(id: MessageID("duplicate"), role: .system, content: "s")
        #expect(throws: ConversationContractError.duplicateMessageID("duplicate")) {
            try Conversation(
                id: ConversationID("duplicate"),
                modelID: .oneBit27B,
                modelRevision: String(repeating: "a", count: 40),
                revision: 1,
                systemInstruction: system,
                completedTurns: [
                    CompletedConversationTurn(
                        id: "turn",
                        messages: [
                            ConversationMessage(id: MessageID("duplicate"), role: .user, content: "u"),
                            ConversationMessage(id: MessageID("a"), role: .assistant, content: "a")
                        ]
                    )
                ]
            )
        }
        #expect(throws: ConversationContractError.invalidTurn("bad-order")) {
            try Self.conversation(turns: [
                CompletedConversationTurn(
                    id: "bad-order",
                    messages: [
                        ConversationMessage(id: MessageID("a"), role: .assistant, content: "a"),
                        ConversationMessage(id: MessageID("u"), role: .user, content: "u")
                    ]
                )
            ])
        }
    }

    private static func conversation(turns: [CompletedConversationTurn]) throws -> Conversation {
        try Conversation(
            id: ConversationID("trim"),
            modelID: .oneBit27B,
            modelRevision: String(repeating: "a", count: 40),
            revision: 1,
            systemInstruction: ConversationMessage(
                id: MessageID("system"), role: .system, content: "system"
            ),
            completedTurns: turns
        )
    }

    private static func turn(
        _ id: String,
        roles: [ConversationRole]
    ) -> CompletedConversationTurn {
        CompletedConversationTurn(
            id: id,
            messages: roles.enumerated().map { index, role in
                let transactionID = role == .toolCall || role == .toolResult ? "\(id)-tool" : nil
                return ConversationMessage(
                    id: MessageID("\(id)-\(index)"),
                    role: role,
                    content: "\(role.rawValue)",
                    transactionID: transactionID
                )
            }
        )
    }
}

private struct ExactTokenCounter: ConversationTokenCounting {
    let counts: [String: Int]

    func tokenCount(for message: ConversationMessage) throws -> Int {
        counts[message.id.rawValue, default: 0]
    }
}

private extension Conversation {
    var allMessages: [ConversationMessage] {
        [systemInstruction] + completedTurns.flatMap(\.messages)
    }
}
