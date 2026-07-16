import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Conversation persistence")
struct ConversationStoreTests {
    @Test
    func conversationsRemainBoundToTheirModel() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ConversationStore(root: root)
        let conversation = try Self.conversation(revision: 1)

        try await store.save(conversation)

        #expect(try await store.load(conversation.id, for: .ternary27B) == nil)
        #expect(try await store.load(conversation.id, for: .oneBit27B) == conversation)
    }

    @Test
    func failedStaleSavePreservesLastGoodConversation() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ConversationStore(root: root)
        let latest = try Self.conversation(revision: 2, answer: "last good")
        try await store.save(latest)

        await #expect(throws: ConversationStoreError.staleRevision(current: 2, attempted: 1)) {
            try await store.save(Self.conversation(revision: 1, answer: "stale"))
        }

        #expect(try await store.load(latest.id, for: .oneBit27B) == latest)
    }

    @Test
    func pendingToolTransactionCannotBecomeACompletedTurn() throws {
        #expect(throws: ConversationContractError.invalidTurn("turn-pending")) {
            try Conversation(
                id: ConversationID("pending"),
                modelID: .oneBit27B,
                modelRevision: String(repeating: "a", count: 40),
                revision: 1,
                systemInstruction: ConversationMessage(
                    id: MessageID("system"),
                    role: .system,
                    content: "system"
                ),
                completedTurns: [
                    CompletedConversationTurn(
                        id: "turn-pending",
                        messages: [
                            ConversationMessage(
                                id: MessageID("user"),
                                role: .user,
                                content: "question"
                            ),
                            ConversationMessage(
                                id: MessageID("tool-call"),
                                role: .toolCall,
                                content: "{}",
                                transactionID: "call-1"
                            ),
                            ConversationMessage(
                                id: MessageID("assistant"),
                                role: .assistant,
                                content: "partial"
                            )
                        ]
                    )
                ]
            )
        }
    }

    @Test
    func concurrentSavesCannotLetTheOlderRevisionWin() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ConversationStore(root: root)

        async let older: Void = store.save(Self.conversation(revision: 2, answer: "older"))
        async let newer: Void = store.save(Self.conversation(revision: 3, answer: "newer"))
        _ = try? await (older, newer)

        let loaded = try await store.load(ConversationID("garden-1"), for: .oneBit27B)
        #expect(loaded?.revision == 3)
        #expect(loaded?.completedTurns.last?.messages.last?.content == "newer")
    }

    @Test
    func corruptConversationIsQuarantinedWithTypedError() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appending(path: "Conversations")
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: conversations.appending(path: "garden-1.json"))
        let store = try ConversationStore(root: root)
        let id = try ConversationID("garden-1")

        await #expect(throws: ConversationStoreError.corruptConversation(id)) {
            _ = try await store.load(id, for: .oneBit27B)
        }

        #expect(!FileManager.default.fileExists(atPath: conversations.appending(path: "garden-1.json").path))
        let names = try FileManager.default.contentsOfDirectory(atPath: conversations.path)
        #expect(names.count == 1)
        #expect(names[0].hasPrefix("garden-1.corrupt."))
    }

    @Test
    func symlinkedConversationRootIsRejected() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: target) }
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "Conversations"),
            withDestinationURL: target
        )

        #expect(throws: AtomicJSONStoreError.unsafeRoot) {
            _ = try ConversationStore(root: root)
        }
    }

    @Test
    func unsafeConversationIdentifierIsRejected() {
        #expect(throws: ConversationContractError.unsafeIdentifier("../escape")) {
            _ = try ConversationID("../escape")
        }
    }

    @Test
    func unsafeMessageIdentifierIsRejectedBeforePersistence() throws {
        #expect(throws: ConversationContractError.unsafeIdentifier("")) {
            try Conversation(
                id: ConversationID("unsafe-message"),
                modelID: .oneBit27B,
                modelRevision: String(repeating: "a", count: 40),
                revision: 1,
                systemInstruction: ConversationMessage(
                    id: MessageID(""), role: .system, content: "system"
                ),
                completedTurns: []
            )
        }
    }

    @Test
    func deterministicEncodingContainsCompletedContentOnly() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try AtomicJSONStore(root: root)
        let conversation = try Self.conversation(revision: 1)

        let first = try await storage.encoded(conversation)
        let second = try await storage.encoded(conversation)
        let text = try #require(String(data: first, encoding: .utf8))

        #expect(first == second)
        #expect(text.contains("completedTurns"))
        #expect(!text.contains("reasoning"))
        #expect(!text.contains("pending"))
        #expect(!text.contains("cancelled"))
    }

    private static func conversation(
        revision: UInt64,
        answer: String = "answer"
    ) throws -> Conversation {
        try Conversation(
            id: ConversationID("garden-1"),
            modelID: .oneBit27B,
            modelRevision: String(repeating: "a", count: 40),
            revision: revision,
            systemInstruction: ConversationMessage(
                id: MessageID("system"),
                role: .system,
                content: "You are Bonsai."
            ),
            completedTurns: [
                CompletedConversationTurn(
                    id: "turn-1",
                    messages: [
                        ConversationMessage(id: MessageID("user-1"), role: .user, content: "hello"),
                        ConversationMessage(
                            id: MessageID("assistant-1"),
                            role: .assistant,
                            content: answer
                        )
                    ]
                )
            ]
        )
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "bonsai-conversation-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
