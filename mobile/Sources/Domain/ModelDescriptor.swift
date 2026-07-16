import Foundation

enum ModelID: String, Codable, CaseIterable, Sendable {
    case oneBit27B
    case ternary27B
}

enum ModelFamily: String, Codable, Sendable {
    case bonsai
    case ternaryBonsai
}

enum ModelCapability: String, Codable, Hashable, Sendable {
    case textGeneration
    case vision
    case toolCalling
    case thinking
}

enum ModelFileRole: String, Codable, Sendable {
    case configuration
    case tokenizer
    case processor
    case weight
}

struct ModelManifest: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        let path: String
        let sizeBytes: Int
        let sha256: String
        let role: ModelFileRole
        let isOptional: Bool
    }

    let id: ModelID
    let repository: String
    let revision: String
    let files: [File]

    var requiredInstalledBytes: Int {
        files.lazy.filter { !$0.isOptional }.reduce(into: 0) { total, file in
            total += file.sizeBytes
        }
    }
}

struct ModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: ModelID
    let family: ModelFamily
    let displayName: String
    let manifest: ModelManifest
    let capabilities: Set<ModelCapability>
    let minimumPhysicalMemoryBytes: Int

    /// Extra free space retained during installation for staging and filesystem overhead.
    let storageSafetyMarginBytes: Int
}

struct ModelCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let models: [ModelDescriptor]
}
