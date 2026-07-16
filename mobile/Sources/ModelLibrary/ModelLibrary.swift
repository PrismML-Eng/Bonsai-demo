import Darwin
import Foundation

struct ModelInstallation: Equatable, Sendable {
    let modelID: ModelID
    let directory: URL
    let revision: String
}

enum ModelLibraryState: Equatable, Sendable {
    case notInstalled
    case installing(completedFiles: Int, totalFiles: Int)
    case ready(ModelInstallation)
    case cancelled
    case failed(String)
}

struct ModelLibrarySnapshot: Equatable, Sendable {
    let states: [ModelID: ModelLibraryState]
}

enum ModelLibraryError: Error, Equatable, Sendable {
    case unqualified
    case invalidSourceURL
    case invalidFileType(String)
    case sizeMismatch(String)
    case hashMismatch(String)
    case unsafeImport(String)
    case missingFile(String)
    case duplicatePath(String)
    case archiveTooLarge
    case operationInProgress(ModelID)
    case unsafeManagedPath(String)
}

actor ModelLibrary {
    private struct InstallationRecord: Codable {
        let modelID: ModelID
        let revision: String
    }

    private let root: URL
    private let transport: any ModelFileTransport
    private let verifier = SHA256Verifier()
    private let knownManifests: [ModelID: ModelManifest]
    private var states: [ModelID: ModelLibraryState]
    private var observers: [UUID: AsyncStream<ModelLibrarySnapshot>.Continuation] = [:]
    private var activeOperations: [ModelID: UUID] = [:]

    init(
        root: URL,
        transport: any ModelFileTransport = URLSessionModelFileTransport(),
        manifests: [ModelManifest]? = nil
    ) throws {
        self.root = root.standardizedFileURL
        self.transport = transport
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        try Self.validateManagedRoot(self.root)
        try Self.applyStoragePolicyRecursively(to: self.root)
        let resolvedManifests = manifests ?? Self.bundledManifests()
        knownManifests = Dictionary(uniqueKeysWithValues: resolvedManifests.map { ($0.id, $0) })
        states = try Self.reconstructStates(root: self.root, manifests: knownManifests)
    }

    func snapshots() -> AsyncStream<ModelLibrarySnapshot> {
        let id = UUID()
        let initial = snapshot()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    func state(for id: ModelID) -> ModelLibraryState {
        states[id] ?? .notInstalled
    }

    func install(_ manifest: ModelManifest, qualification: DeviceQualification) async throws {
        guard case .qualified = qualification else { throw ModelLibraryError.unqualified }
        let operation = try beginOperation(for: manifest.id)
        defer { endOperation(operation, for: manifest.id) }
        try await performInstall(manifest)
    }

    private func performInstall(_ manifest: ModelManifest) async throws {
        let staging = stagingURL(for: manifest.id)
        try validateManagedAncestors(for: staging)
        try prepareDirectory(staging)
        do {
            let required = manifest.files.filter { !$0.isOptional }
            var completed = 0
            publish(.installing(completedFiles: completed, totalFiles: required.count), for: manifest.id)
            for file in required {
                try Task.checkCancellation()
                let destination = try descendant(file.path, under: staging)
                if isVerified(file, at: destination) {
                    completed += 1
                    publish(.installing(completedFiles: completed, totalFiles: required.count), for: manifest.id)
                    continue
                }
                let source = try sourceURL(for: file, manifest: manifest)
                try await transport.download(file, from: source, to: destination)
                do {
                    try verifier.verify(file, at: destination)
                    try Self.applyStoragePolicyRecursively(to: destination)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }
                completed += 1
                publish(.installing(completedFiles: completed, totalFiles: required.count), for: manifest.id)
            }
            try promote(staging, manifest: manifest)
        } catch is CancellationError {
            publish(.cancelled, for: manifest.id)
            throw CancellationError()
        } catch {
            publish(.notInstalled, for: manifest.id)
            throw error
        }
    }

    func resume(_ manifest: ModelManifest, qualification: DeviceQualification) async throws {
        try await install(manifest, qualification: qualification)
    }

    func importModel(
        _ manifest: ModelManifest,
        from source: URL,
        qualification: DeviceQualification
    ) async throws {
        guard case .qualified = qualification else { throw ModelLibraryError.unqualified }
        let operation = try beginOperation(for: manifest.id)
        defer { endOperation(operation, for: manifest.id) }
        let staging = stagingURL(for: manifest.id)
        try validateManagedAncestors(for: staging)
        try resetDirectory(staging)
        do {
            try ModelImporter().copy(manifest: manifest, from: source, to: staging)
            for file in manifest.files where !file.isOptional {
                try verifier.verify(file, at: try descendant(file.path, under: staging))
            }
            try Self.applyStoragePolicyRecursively(to: staging)
            try promote(staging, manifest: manifest)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            publish(.notInstalled, for: manifest.id)
            throw error
        }
    }

    func delete(_ id: ModelID) throws {
        let operation = try beginOperation(for: id)
        defer { endOperation(operation, for: id) }
        let targets = [installedURL(for: id), stagingURL(for: id)]
        var existingTargets: [URL] = []
        for url in targets {
            try validateManagedAncestors(for: url)
            guard let type = try Self.lstatTypeIfPresent(at: url) else { continue }
            guard type != .typeSymbolicLink else {
                throw ModelLibraryError.unsafeManagedPath(url.lastPathComponent)
            }
            existingTargets.append(url)
        }
        for url in existingTargets {
            try FileManager.default.removeItem(at: url)
        }
        publish(.notInstalled, for: id)
    }

    private func prepareDirectory(_ directory: URL) throws {
        try validateManagedAncestors(for: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try validateManagedAncestors(for: directory)
        try Self.applyStoragePolicyRecursively(to: directory)
    }

    private func resetDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try prepareDirectory(directory)
    }

    private func promote(_ staging: URL, manifest: ModelManifest) throws {
        let destination = installedURL(for: manifest.id)
        try validateManagedAncestors(for: staging)
        try validateManagedAncestors(for: destination)
        let record = InstallationRecord(modelID: manifest.id, revision: manifest.revision)
        let recordURL = staging.appending(path: ".bonsai-installation.json")
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        try Self.applyStoragePolicyRecursively(to: staging)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try validateManagedAncestors(for: destination)
        try Self.applyStoragePolicyRecursively(to: destination.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
        try Self.applyStoragePolicyRecursively(to: destination)
        let installation = ModelInstallation(modelID: manifest.id, directory: destination, revision: manifest.revision)
        publish(.ready(installation), for: manifest.id)
    }

    private func isVerified(_ file: ModelManifest.File, at url: URL) -> Bool {
        do {
            try verifier.verify(file, at: url)
            return true
        } catch {
            return false
        }
    }

    private func sourceURL(for file: ModelManifest.File, manifest: ModelManifest) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(manifest.repository)/resolve/\(manifest.revision)/\(file.path)"
        guard let url = components.url else { throw ModelLibraryError.invalidSourceURL }
        return url
    }

    private func descendant(_ logicalPath: String, under parent: URL) throws -> URL {
        let result = parent.appending(path: logicalPath).standardizedFileURL
        let prefix = parent.standardizedFileURL.path + "/"
        guard result.path.hasPrefix(prefix) else { throw ModelLibraryError.unsafeImport(logicalPath) }
        return result
    }

    private func installedURL(for id: ModelID) -> URL {
        root.appending(path: "installed/\(id.rawValue)", directoryHint: .isDirectory)
    }

    private func stagingURL(for id: ModelID) -> URL {
        root.appending(path: ".staging/\(id.rawValue)", directoryHint: .isDirectory)
    }

    private func snapshot() -> ModelLibrarySnapshot {
        let pairs = ModelID.allCases.map { ($0, state(for: $0)) }
        return ModelLibrarySnapshot(states: Dictionary(uniqueKeysWithValues: pairs))
    }

    private func publish(_ state: ModelLibraryState, for id: ModelID) {
        states[id] = state
        let value = snapshot()
        for observer in observers.values { observer.yield(value) }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
}

private extension ModelLibrary {
    private func beginOperation(for id: ModelID) throws -> UUID {
        guard activeOperations[id] == nil else { throw ModelLibraryError.operationInProgress(id) }
        let operation = UUID()
        activeOperations[id] = operation
        return operation
    }

    private func endOperation(_ operation: UUID, for id: ModelID) {
        guard activeOperations[id] == operation else { return }
        activeOperations.removeValue(forKey: id)
    }

    private func validateManagedAncestors(for target: URL) throws {
        try Self.validateManagedRoot(root)
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let target = target.standardizedFileURL
        guard target.path == root.path || target.path.hasPrefix(root.path + "/") else {
            throw ModelLibraryError.unsafeManagedPath(target.path)
        }
        var current = root
        let relative = target.path.dropFirst(root.path.count).split(separator: "/")
        for component in relative {
            current.append(path: String(component))
            guard FileManager.default.fileExists(atPath: current.path) else { break }
            guard try Self.lstatType(at: current) != .typeSymbolicLink else {
                throw ModelLibraryError.unsafeManagedPath(current.path)
            }
            let canonical = current.resolvingSymlinksInPath().standardizedFileURL
            guard canonical.path == canonicalRoot.path || canonical.path.hasPrefix(canonicalRoot.path + "/") else {
                throw ModelLibraryError.unsafeManagedPath(current.path)
            }
        }
    }

    private static func validateManagedRoot(_ root: URL) throws {
        guard try lstatType(at: root) == .typeDirectory else {
            throw ModelLibraryError.unsafeManagedPath(root.path)
        }
    }

    private static func lstatType(at url: URL) throws -> FileAttributeType {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        switch info.st_mode & S_IFMT {
        case S_IFDIR: return .typeDirectory
        case S_IFREG: return .typeRegular
        case S_IFLNK: return .typeSymbolicLink
        default: return .typeUnknown
        }
    }

    private static func lstatTypeIfPresent(at url: URL) throws -> FileAttributeType? {
        do {
            return try lstatType(at: url)
        } catch let error as POSIXError where error.code == .ENOENT {
            return nil
        }
    }

    private static func bundledManifests() -> [ModelManifest] {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "Models"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(ModelCatalog.self, from: data) else {
            return []
        }
        return catalog.models.map(\.manifest)
    }

    private static func reconstructStates(
        root: URL,
        manifests: [ModelID: ModelManifest]
    ) throws -> [ModelID: ModelLibraryState] {
        var result: [ModelID: ModelLibraryState] = [:]
        for id in ModelID.allCases {
            let directory = root.appending(path: "installed/\(id.rawValue)")
            guard FileManager.default.fileExists(atPath: directory.path) else {
                result[id] = .notInstalled
                continue
            }
            guard try lstatType(at: directory) == .typeDirectory,
                  let manifest = manifests[id] else {
                result[id] = .failed("unverified installation")
                continue
            }
            let recordURL = directory.appending(path: ".bonsai-installation.json")
            guard let data = try? Data(contentsOf: recordURL),
                  let record = try? JSONDecoder().decode(InstallationRecord.self, from: data),
                  record.modelID == id,
                  record.revision == manifest.revision else {
                result[id] = .failed("invalid installation record")
                continue
            }
            do {
                for file in manifest.files where !file.isOptional {
                    try SHA256Verifier().verify(file, at: directory.appending(path: file.path))
                }
                result[id] = .ready(ModelInstallation(modelID: id, directory: directory, revision: manifest.revision))
            } catch {
                result[id] = .failed("installation verification failed")
            }
        }
        return result
    }

    private static func applyStoragePolicyRecursively(to url: URL) throws {
        try applyStoragePolicy(to: url)
        guard (try? lstatType(at: url)) == .typeDirectory,
              let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return
        }
        for case let child as URL in enumerator {
            guard try lstatType(at: child) != .typeSymbolicLink else {
                throw ModelLibraryError.unsafeManagedPath(child.path)
            }
            try applyStoragePolicy(to: child)
        }
    }

    static func applyStoragePolicy(to url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
