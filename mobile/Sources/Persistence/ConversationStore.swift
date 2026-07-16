import Foundation

enum ConversationStoreError: Error, Equatable, Sendable {
    case ownershipMismatch(expected: ModelID, attempted: ModelID)
    case staleRevision(current: UInt64, attempted: UInt64)
    case corruptConversation(ConversationID)
}

actor ConversationStore {
    private struct SaveOperation {
        let id: UUID
        let task: Task<Void, any Error>
    }

    private let storage: AtomicJSONStore
    private var saveOperations: [ConversationID: SaveOperation] = [:]

    init(root: URL) throws {
        storage = try AtomicJSONStore(root: root.appending(path: "Conversations"))
    }

    func save(_ conversation: Conversation) async throws {
        if let preceding = saveOperations[conversation.id] {
            _ = try? await preceding.task.value
        }

        let operationID = UUID()
        let operation = Task { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.performSave(conversation)
        }
        saveOperations[conversation.id] = SaveOperation(id: operationID, task: operation)
        defer {
            if saveOperations[conversation.id]?.id == operationID {
                saveOperations[conversation.id] = nil
            }
        }
        try await operation.value
    }

    private func performSave(_ conversation: Conversation) async throws {
        if let current = try await decoded(conversation.id) {
            guard current.modelID == conversation.modelID else {
                throw ConversationStoreError.ownershipMismatch(
                    expected: current.modelID,
                    attempted: conversation.modelID
                )
            }
            guard conversation.revision > current.revision else {
                throw ConversationStoreError.staleRevision(
                    current: current.revision,
                    attempted: conversation.revision
                )
            }
        }
        let data = try await storage.encoded(conversation)
        try await storage.write(data, identifier: conversation.id.rawValue)
    }

    func load(_ id: ConversationID, for modelID: ModelID) async throws -> Conversation? {
        guard let conversation = try await decoded(id) else { return nil }
        guard conversation.modelID == modelID else { return nil }
        return conversation
    }

    private func decoded(_ id: ConversationID) async throws -> Conversation? {
        guard let data = try await storage.read(identifier: id.rawValue) else { return nil }
        do {
            return try JSONDecoder().decode(Conversation.self, from: data)
        } catch {
            try await storage.quarantine(identifier: id.rawValue)
            throw ConversationStoreError.corruptConversation(id)
        }
    }
}
