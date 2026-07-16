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
}

actor ModelLibrary {
    private let root: URL
    private let transport: any ModelFileTransport
    private let verifier = SHA256Verifier()
    private var states: [ModelID: ModelLibraryState] = [:]
    private var observers: [UUID: AsyncStream<ModelLibrarySnapshot>.Continuation] = [:]

    init(root: URL, transport: any ModelFileTransport = URLSessionModelFileTransport()) throws {
        self.root = root.standardizedFileURL
        self.transport = transport
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        try Self.applyStoragePolicy(to: self.root)
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
        states[id] ?? discoveredState(for: id)
    }

    func install(_ manifest: ModelManifest, qualification: DeviceQualification) async throws {
        guard case .qualified = qualification else { throw ModelLibraryError.unqualified }
        let staging = stagingURL(for: manifest.id)
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
        let staging = stagingURL(for: manifest.id)
        try resetDirectory(staging)
        do {
            try ModelImporter().copy(manifest: manifest, from: source, to: staging)
            for file in manifest.files where !file.isOptional {
                try verifier.verify(file, at: try descendant(file.path, under: staging))
            }
            try promote(staging, manifest: manifest)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            publish(.notInstalled, for: manifest.id)
            throw error
        }
    }

    func delete(_ id: ModelID) throws {
        for url in [installedURL(for: id), stagingURL(for: id)] {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw ModelLibraryError.unsafeImport(url.lastPathComponent)
            }
            try FileManager.default.removeItem(at: url)
        }
        publish(.notInstalled, for: id)
    }

    private func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.applyStoragePolicy(to: directory)
    }

    private func resetDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try prepareDirectory(directory)
    }

    private func promote(_ staging: URL, manifest: ModelManifest) throws {
        let destination = installedURL(for: manifest.id)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.applyStoragePolicy(to: destination.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
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

    private func discoveredState(for id: ModelID) -> ModelLibraryState {
        if FileManager.default.fileExists(atPath: installedURL(for: id).path) {
            return .failed("unverified installation")
        }
        return .notInstalled
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

    private static func applyStoragePolicy(to url: URL) throws {
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
