import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Context trimming")
struct ContextTrimmerTests {
    @Test
    func defaultLimitUsesWholePreparedCandidateAndKeepsNewestCompleteSuffix() async throws {
        let conversation = try Self.conversation(turns: [
            Self.turn("old", roles: [.user, .assistant]),
            Self.turn("new", roles: [.user, .assistant])
        ])
        let counter = ExactPromptCounter(counts: [
            "system,old-0,old-1,new-0,new-1": 4_500,
            "system,new-0,new-1": 2_100
        ])

        let result = try await ContextTrimmer(promptCounter: counter).trim(conversation)

        #expect(result.keptTokenCount == 2_100)
        #expect(result.keptMessages.map(\.id.rawValue) == ["system", "new-0", "new-1"])
        #expect(result.removedMessageIDs.map(\.rawValue) == ["old-0", "old-1"])
        #expect(result.notice == .init(removedTurnCount: 1, removedMessageCount: 2))
    }

    @Test
    func neverSplitsAToolCallResultTransaction() async throws {
        let conversation = try Self.conversation(turns: [
            Self.turn("old", roles: [.user, .toolCall, .toolResult, .assistant]),
            Self.turn("new", roles: [.user, .assistant])
        ])
        let result = try await ContextTrimmer(
            limit: 4_096,
            promptCounter: ExactPromptCounter(counts: [
                "system,old-0,old-1,old-2,old-3,new-0,new-1": 7_000,
                "system,new-0,new-1": 1_800
            ])
        ).trim(conversation)

        #expect(result.keptMessages.map(\.id.rawValue) == ["system", "new-0", "new-1"])
        #expect(result.removedMessageIDs.map(\.rawValue) == [
            "old-0", "old-1", "old-2", "old-3"
        ])
    }

    @Test
    func throwsWhenSystemAndNewestIndivisibleTurnExceedLimit() async throws {
        let conversation = try Self.conversation(turns: [
            Self.turn("new", roles: [.user, .assistant])
        ])
        let counter = ExactPromptCounter(counts: ["system,new-0,new-1": 4_100])

        await #expect(throws: ContextTrimmerError.requiredContextExceedsLimit(required: 4_100, limit: 4_096)) {
            try await ContextTrimmer(promptCounter: counter).trim(conversation)
        }
    }

    @Test
    func rejectsNegativePreparedPromptTokenCount() async throws {
        let conversation = try Self.conversation(turns: [])

        await #expect(throws: ContextTrimmerError.invalidPromptTokenCount(-1)) {
            try await ContextTrimmer(promptCounter: ExactPromptCounter(counts: ["system": -1]))
                .trim(conversation)
        }
    }

    @Test
    func wholePromptCounterIsNotAssumedAdditiveAcrossCandidateSuffixes() async throws {
        let conversation = try Self.conversation(turns: [
            Self.turn("old", roles: [.user, .assistant]),
            Self.turn("new", roles: [.user, .assistant])
        ])
        let counter = ExactPromptCounter(counts: [
            "system,old-0,old-1,new-0,new-1": 4_097,
            "system,new-0,new-1": 4_096
        ])

        let result = try await ContextTrimmer(promptCounter: counter).trim(conversation)
        #expect(result.keptTokenCount == 4_096)
        #expect(result.keptMessages.map(\.id.rawValue) == ["system", "new-0", "new-1"])
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

    @Test
    func conversationDecodeRejectsUnicodePseudoSHAAndTypesSchemaMismatchSeparately() throws {
        let valid = try Self.conversation(turns: [])
        let encoded = try JSONEncoder().encode(valid)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["modelRevision"] = String(repeating: "ａ", count: 40)
        let unicodeRevision = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ConversationContractError.invalidModelRevision) {
            try JSONDecoder().decode(Conversation.self, from: unicodeRevision)
        }

        object["modelRevision"] = String(repeating: "a", count: 40)
        object["schemaVersion"] = 99
        let unsupportedSchema = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ConversationContractError.unsupportedSchemaVersion(99)) {
            try JSONDecoder().decode(Conversation.self, from: unsupportedSchema)
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

private struct ExactPromptCounter: ConversationPromptCounting {
    let counts: [String: Int]

    func promptTokenCount(for messages: [ConversationMessage]) async throws -> Int {
        counts[messages.map(\.id.rawValue).joined(separator: ","), default: 0]
    }
}

private extension Conversation {
    var allMessages: [ConversationMessage] {
        [systemInstruction] + completedTurns.flatMap(\.messages)
    }
}
