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

enum ModelContractError: Error, Equatable, Sendable {
    case invalidPath(String)
    case invalidSize(path: String)
    case invalidSHA256(path: String)
    case invalidRepository(String)
    case invalidRevision(String)
    case emptyManifest
    case noRequiredFiles
    case duplicatePath(String)
    case requiredBytesOverflow
    case descriptorIDMismatch
    case descriptorFamilyMismatch
    case invalidMinimumPhysicalMemory
    case invalidStorageSafetyMargin
    case requiredStorageOverflow
}

struct ModelManifest: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        let path: String
        let sizeBytes: Int
        let sha256: String
        let role: ModelFileRole
        let isOptional: Bool

        private init(
            path: String,
            sizeBytes: Int,
            sha256: String,
            role: ModelFileRole,
            isOptional: Bool
        ) {
            self.path = path
            self.sizeBytes = sizeBytes
            self.sha256 = sha256
            self.role = role
            self.isOptional = isOptional
        }

        static func validated(
            path: String,
            sizeBytes: Int,
            sha256: String,
            role: ModelFileRole,
            isOptional: Bool
        ) throws -> Self {
            guard isValidLogicalPath(path) else {
                throw ModelContractError.invalidPath(path)
            }
            guard sizeBytes >= 0 else {
                throw ModelContractError.invalidSize(path: path)
            }
            guard isLowercaseHex(sha256, count: 64) else {
                throw ModelContractError.invalidSHA256(path: path)
            }
            return Self(
                path: path,
                sizeBytes: sizeBytes,
                sha256: sha256,
                role: role,
                isOptional: isOptional
            )
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self = try Self.validated(
                path: container.decode(String.self, forKey: .path),
                sizeBytes: container.decode(Int.self, forKey: .sizeBytes),
                sha256: container.decode(String.self, forKey: .sha256),
                role: container.decode(ModelFileRole.self, forKey: .role),
                isOptional: container.decode(Bool.self, forKey: .isOptional)
            )
        }
    }

    let id: ModelID
    let repository: String
    let revision: String
    let files: [File]
    let requiredInstalledBytes: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case repository
        case revision
        case files
    }

    private init(
        id: ModelID,
        repository: String,
        revision: String,
        files: [File],
        requiredInstalledBytes: Int
    ) {
        self.id = id
        self.repository = repository
        self.revision = revision
        self.files = files
        self.requiredInstalledBytes = requiredInstalledBytes
    }

    static func validated(
        id: ModelID,
        repository: String,
        revision: String,
        files: [File]
    ) throws -> Self {
        guard isValidRepository(repository) else {
            throw ModelContractError.invalidRepository(repository)
        }
        guard isLowercaseHex(revision, count: 40) else {
            throw ModelContractError.invalidRevision(revision)
        }
        guard !files.isEmpty else {
            throw ModelContractError.emptyManifest
        }

        var paths: Set<String> = []
        var requiredInstalledBytes = 0
        var hasRequiredFile = false
        for file in files {
            guard paths.insert(file.path).inserted else {
                throw ModelContractError.duplicatePath(file.path)
            }
            guard !file.isOptional else {
                continue
            }
            hasRequiredFile = true
            let (nextTotal, overflow) = requiredInstalledBytes
                .addingReportingOverflow(file.sizeBytes)
            guard !overflow else {
                throw ModelContractError.requiredBytesOverflow
            }
            requiredInstalledBytes = nextTotal
        }
        guard hasRequiredFile else {
            throw ModelContractError.noRequiredFiles
        }

        return Self(
            id: id,
            repository: repository,
            revision: revision,
            files: files,
            requiredInstalledBytes: requiredInstalledBytes
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try Self.validated(
            id: container.decode(ModelID.self, forKey: .id),
            repository: container.decode(String.self, forKey: .repository),
            revision: container.decode(String.self, forKey: .revision),
            files: container.decode([File].self, forKey: .files)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(repository, forKey: .repository)
        try container.encode(revision, forKey: .revision)
        try container.encode(files, forKey: .files)
    }
}

struct ModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    struct RuntimeRequirements: Equatable, Sendable {
        let capabilities: Set<ModelCapability>
        let minimumPhysicalMemoryBytes: Int
        let storageSafetyMarginBytes: Int
    }

    let id: ModelID
    let family: ModelFamily
    let displayName: String
    let manifest: ModelManifest
    let capabilities: Set<ModelCapability>
    let minimumPhysicalMemoryBytes: Int

    /// Extra free space retained during installation for staging and filesystem overhead.
    let storageSafetyMarginBytes: Int

    private init(
        id: ModelID,
        family: ModelFamily,
        displayName: String,
        manifest: ModelManifest,
        capabilities: Set<ModelCapability>,
        minimumPhysicalMemoryBytes: Int,
        storageSafetyMarginBytes: Int
    ) {
        self.id = id
        self.family = family
        self.displayName = displayName
        self.manifest = manifest
        self.capabilities = capabilities
        self.minimumPhysicalMemoryBytes = minimumPhysicalMemoryBytes
        self.storageSafetyMarginBytes = storageSafetyMarginBytes
    }

    static func validated(
        id: ModelID,
        family: ModelFamily,
        displayName: String,
        manifest: ModelManifest,
        requirements: RuntimeRequirements
    ) throws -> Self {
        guard id == manifest.id else {
            throw ModelContractError.descriptorIDMismatch
        }
        let expectedFamily: ModelFamily = id == .oneBit27B ? .bonsai : .ternaryBonsai
        guard family == expectedFamily else {
            throw ModelContractError.descriptorFamilyMismatch
        }
        guard requirements.minimumPhysicalMemoryBytes >= 0 else {
            throw ModelContractError.invalidMinimumPhysicalMemory
        }
        guard requirements.storageSafetyMarginBytes >= 0 else {
            throw ModelContractError.invalidStorageSafetyMargin
        }
        let (_, overflow) = manifest.requiredInstalledBytes
            .addingReportingOverflow(requirements.storageSafetyMarginBytes)
        guard !overflow else {
            throw ModelContractError.requiredStorageOverflow
        }
        return Self(
            id: id,
            family: family,
            displayName: displayName,
            manifest: manifest,
            capabilities: requirements.capabilities,
            minimumPhysicalMemoryBytes: requirements.minimumPhysicalMemoryBytes,
            storageSafetyMarginBytes: requirements.storageSafetyMarginBytes
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try Self.validated(
            id: container.decode(ModelID.self, forKey: .id),
            family: container.decode(ModelFamily.self, forKey: .family),
            displayName: container.decode(String.self, forKey: .displayName),
            manifest: container.decode(ModelManifest.self, forKey: .manifest),
            requirements: RuntimeRequirements(
                capabilities: container.decode(
                    Set<ModelCapability>.self,
                    forKey: .capabilities
                ),
                minimumPhysicalMemoryBytes: container.decode(
                    Int.self,
                    forKey: .minimumPhysicalMemoryBytes
                ),
                storageSafetyMarginBytes: container.decode(
                    Int.self,
                    forKey: .storageSafetyMarginBytes
                )
            )
        )
    }
}

struct ModelCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let models: [ModelDescriptor]
}

private func isLowercaseHex(_ value: String, count: Int) -> Bool {
    value.utf8.count == count && value.utf8.allSatisfy { byte in
        (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
    }
}

private func isValidLogicalPath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
        return false
    }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return components.allSatisfy { component in
        !component.isEmpty && component != "." && component != ".."
    }
}

private func isValidRepository(_ repository: String) -> Bool {
    let components = repository.split(separator: "/", omittingEmptySubsequences: false)
    return components.count == 2 && components.allSatisfy { !$0.isEmpty }
}
