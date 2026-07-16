import Foundation

enum ConversationContractError: Error, Equatable, Sendable {
    case unsafeIdentifier(String)
    case unsupportedSchemaVersion(Int)
    case invalidModelRevision
    case invalidSystemInstruction
    case invalidTurn(String)
    case duplicateMessageID(String)
}

struct ConversationID: Codable, Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) throws {
        guard Self.isSafe(rawValue) else {
            throw ConversationContractError.unsafeIdentifier(rawValue)
        }
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func isSafe(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
                .contains($0)
        }
    }
}

struct MessageID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum ConversationRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case toolCall
    case toolResult
}

struct ConversationMessage: Codable, Equatable, Sendable {
    let id: MessageID
    let role: ConversationRole
    let content: String
    let transactionID: String?

    init(
        id: MessageID,
        role: ConversationRole,
        content: String,
        transactionID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.transactionID = transactionID
    }
}

struct CompletedConversationTurn: Codable, Equatable, Sendable {
    let id: String
    let messages: [ConversationMessage]
}

struct Conversation: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: ConversationID
    let modelID: ModelID
    let modelRevision: String
    let revision: UInt64
    let systemInstruction: ConversationMessage
    let completedTurns: [CompletedConversationTurn]

    init(
        id: ConversationID,
        modelID: ModelID,
        modelRevision: String,
        revision: UInt64,
        systemInstruction: ConversationMessage,
        completedTurns: [CompletedConversationTurn]
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.id = id
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.revision = revision
        self.systemInstruction = systemInstruction
        self.completedTurns = completedTurns
        try validate()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(ConversationID.self, forKey: .id)
        modelID = try container.decode(ModelID.self, forKey: .modelID)
        modelRevision = try container.decode(String.self, forKey: .modelRevision)
        revision = try container.decode(UInt64.self, forKey: .revision)
        systemInstruction = try container.decode(
            ConversationMessage.self,
            forKey: .systemInstruction
        )
        completedTurns = try container.decode(
            [CompletedConversationTurn].self,
            forKey: .completedTurns
        )
        try validate()
    }

    private func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw ConversationContractError.unsupportedSchemaVersion(schemaVersion)
        }
        guard isLowercaseHex(modelRevision, count: 40) else {
            throw ConversationContractError.invalidModelRevision
        }
        guard systemInstruction.role == .system,
              Self.isSafeMessageID(systemInstruction.id),
              systemInstruction.transactionID == nil else {
            if !Self.isSafeMessageID(systemInstruction.id) {
                throw ConversationContractError.unsafeIdentifier(systemInstruction.id.rawValue)
            }
            throw ConversationContractError.invalidSystemInstruction
        }

        var messageIDs: Set<String> = [systemInstruction.id.rawValue]
        for turn in completedTurns {
            guard !turn.id.isEmpty,
                  turn.messages.first?.role == .user,
                  turn.messages.first?.transactionID == nil,
                  turn.messages.last?.role == .assistant,
                  turn.messages.last?.transactionID == nil,
                  Self.hasCompleteToolTransactions(turn.messages) else {
                throw ConversationContractError.invalidTurn(turn.id)
            }
            for message in turn.messages {
                guard Self.isSafeMessageID(message.id) else {
                    throw ConversationContractError.unsafeIdentifier(message.id.rawValue)
                }
                guard messageIDs.insert(message.id.rawValue).inserted else {
                    throw ConversationContractError.duplicateMessageID(message.id.rawValue)
                }
            }
        }
    }

    private static func isSafeMessageID(_ id: MessageID) -> Bool {
        let value = id.rawValue
        guard !value.isEmpty, value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "-_."))
                .contains($0)
        }
    }

    private static func hasCompleteToolTransactions(
        _ messages: [ConversationMessage]
    ) -> Bool {
        guard messages.count >= 2 else { return false }
        var index = 1
        while index < messages.count - 1 {
            guard index + 1 < messages.count - 1 else { return false }
            let call = messages[index]
            let result = messages[index + 1]
            guard call.role == .toolCall,
                  result.role == .toolResult,
                  let transactionID = call.transactionID,
                  !transactionID.isEmpty,
                  result.transactionID == transactionID else {
                return false
            }
            index += 2
        }
        return true
    }

    var contextMessages: [ConversationMessage] {
        [systemInstruction] + completedTurns.flatMap(\.messages)
    }
}
