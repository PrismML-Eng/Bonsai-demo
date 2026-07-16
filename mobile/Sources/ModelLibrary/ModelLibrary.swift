import Darwin
import Foundation

// The actor keeps transactional install, verify, import, and recovery invariants together.
// swiftlint:disable file_length type_body_length

actor ModelLibrary {
    private let root: URL
    private let transport: any ModelFileTransport
    private let managedFileSystem: any ModelLibraryFileSystem
    private let verifier: any ModelFileVerifying
    private let knownManifests: [ModelID: ModelManifest]
    private var states: [ModelID: ModelLibraryState]
    private var observers: [UUID: AsyncStream<ModelLibrarySnapshot>.Continuation] = [:]
    private var activeOperations: [ModelID: UUID] = [:]
    private var didStartLaunchVerification = false

    init(
        root: URL,
        transport: any ModelFileTransport = URLSessionModelFileTransport(),
        manifests: [ModelManifest]? = nil,
        managedFileSystem: any ModelLibraryFileSystem = DefaultModelLibraryFileSystem(),
        verifier: any ModelFileVerifying = SHA256Verifier()
    ) throws {
        self.root = root.standardizedFileURL
        self.transport = transport
        self.managedFileSystem = managedFileSystem
        self.verifier = verifier
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        try Self.validateManagedRoot(self.root)
        try Self.prepareTrash(at: self.root, fileSystem: managedFileSystem)
        try Self.applyStoragePolicyRecursively(to: self.root, rejectingSymlinks: false)
        let resolvedManifests = manifests ?? Self.bundledManifests()
        knownManifests = Dictionary(uniqueKeysWithValues: resolvedManifests.map { ($0.id, $0) })
        states = try Self.discoverStates(root: self.root, manifests: knownManifests)
    }

    func snapshots() -> AsyncStream<ModelLibrarySnapshot> {
        startLaunchVerificationIfNeeded()
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

    private func startLaunchVerificationIfNeeded() {
        guard !didStartLaunchVerification else { return }
        didStartLaunchVerification = true
        Task(priority: .utility) { verifyDiscoveredInstallations() }
    }

    private func verifyDiscoveredInstallations() {
        for id in ModelID.allCases {
            guard case .verifying = state(for: id), let manifest = knownManifests[id] else { continue }
            do {
                let operation = try beginOperation(for: id)
                defer { endOperation(operation, for: id) }
                let directory = installedURL(for: id)
                let required = manifest.files.filter { !$0.isOptional }
                let total = required.reduce(0) { $0 + $1.sizeBytes }
                var base = 0
                for file in required {
                    try Task.checkCancellation()
                    let fileBase = base
                    try verifier.verify(file, at: try descendant(file.path, under: directory)) { bytes in
                        self.publish(.verifying(completedBytes: fileBase + bytes, totalBytes: total), for: id)
                    }
                    base += file.sizeBytes
                }
                publish(.ready(ModelInstallation(
                    modelID: id, directory: directory, revision: manifest.revision
                )), for: id)
            } catch {
                publish(.failed("installation verification failed: \(error.localizedDescription)"), for: id)
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
            let totalBytes = required.reduce(0) { $0 + $1.sizeBytes }
            var completedBytes = 0
            publish(.transferring(completedBytes: 0, totalBytes: totalBytes), for: manifest.id)
            for file in required {
                try Task.checkCancellation()
                let destination = try descendant(file.path, under: staging)
                if isVerified(file, at: destination) {
                    completedBytes += file.sizeBytes
                    publish(.transferring(completedBytes: completedBytes, totalBytes: totalBytes), for: manifest.id)
                    continue
                }
                let source = try sourceURL(for: file, manifest: manifest)
                if let progressTransport = transport as? any ProgressReportingModelFileTransport {
                    let base = completedBytes
                    try await progressTransport.download(file, from: source, to: destination) { [weak self] bytes in
                        await self?.publish(.transferring(completedBytes: base + bytes,
                                                         totalBytes: totalBytes), for: manifest.id)
                    }
                } else {
                    try await transport.download(file, from: source, to: destination)
                }
                do {
                    try verifier.verify(file, at: destination, progress: nil)
                    try Self.applyStoragePolicyRecursively(to: destination)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }
                completedBytes += file.sizeBytes
                publish(.transferring(completedBytes: completedBytes, totalBytes: totalBytes), for: manifest.id)
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

    func verify(_ manifest: ModelManifest) throws {
        let operation = try beginOperation(for: manifest.id)
        defer { endOperation(operation, for: manifest.id) }
        guard case .ready(let installation) = state(for: manifest.id) else {
            throw ModelLibraryError.missingFile(manifest.id.rawValue)
        }
        let required = manifest.files.filter { !$0.isOptional }
        let total = required.reduce(0) { $0 + $1.sizeBytes }
        var base = 0
        publish(.verifying(completedBytes: 0, totalBytes: total), for: manifest.id)
        do {
            for file in required {
                let fileBase = base
                try verifier.verify(file, at: try descendant(file.path, under: installation.directory)) {
                    self.publish(.verifying(completedBytes: fileBase + $0, totalBytes: total), for: manifest.id)
                }
                base += file.sizeBytes
            }
            publish(.ready(installation), for: manifest.id)
        } catch {
            publish(.failed(String(describing: error)), for: manifest.id)
            throw error
        }
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
                try verifier.verify(file, at: try descendant(file.path, under: staging), progress: nil)
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
        let installed = installedURL(for: id)
        let staging = stagingURL(for: id)
        let trashRoot = trashRootURL()
        let trash = trashURL(for: id)
        for url in [installed, staging, trashRoot, trash] {
            try validateManagedAncestors(for: url)
            guard let type = try Self.lstatTypeIfPresent(at: url) else { continue }
            guard type != .typeSymbolicLink else {
                throw ModelLibraryError.unsafeManagedPath(url.lastPathComponent)
            }
        }

        if try Self.lstatTypeIfPresent(at: staging) != nil {
            try managedFileSystem.removeItem(at: staging)
        }
        guard try Self.lstatTypeIfPresent(at: installed) != nil else {
            publish(.notInstalled, for: id)
            return
        }

        try managedFileSystem.moveItem(at: installed, to: trash)
        publish(.notInstalled, for: id)
        try? managedFileSystem.removeItem(at: trash)
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
        let record = ModelInstallationRecord(modelID: manifest.id, revision: manifest.revision)
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
            try verifier.verify(file, at: url, progress: nil)
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

    private func trashRootURL() -> URL { root.appending(path: ".trash", directoryHint: .isDirectory) }
    private func trashURL(for id: ModelID) -> URL {
        trashRootURL().appending(
            path: "\(id.rawValue)-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
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
// swiftlint:enable type_body_length

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

    private static func prepareTrash(
        at root: URL,
        fileSystem: any ModelLibraryFileSystem
    ) throws {
        let trashRoot = root.appending(path: ".trash", directoryHint: .isDirectory)
        if let type = try lstatTypeIfPresent(at: trashRoot) {
            guard type == .typeDirectory else {
                throw ModelLibraryError.unsafeManagedPath(trashRoot.path)
            }
        } else {
            try fileSystem.createDirectory(at: trashRoot, withIntermediateDirectories: false)
        }
        try applyStoragePolicyRecursively(to: trashRoot)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: trashRoot,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for entry in entries where (try? lstatType(at: entry)) == .typeDirectory {
            try? fileSystem.removeItem(at: entry)
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
    private static func discoverStates(
        root: URL, manifests: [ModelID: ModelManifest]
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
            guard let data = try? NoFollowRegularFile.readAll(
                at: recordURL, logicalPath: ".bonsai-installation.json",
                maximumSize: 64 * 1_024
            ),
                  let record = try? JSONDecoder().decode(ModelInstallationRecord.self, from: data),
                  record.modelID == id,
                  record.revision == manifest.revision else {
                result[id] = .failed("invalid installation record")
                continue
            }
            let total = manifest.files.lazy.filter { !$0.isOptional }.reduce(0) { $0 + $1.sizeBytes }
            result[id] = .verifying(completedBytes: 0, totalBytes: total)
        }
        return result
    }
    private static func applyStoragePolicyRecursively(to url: URL, rejectingSymlinks: Bool = true) throws {
        try applyStoragePolicy(to: url)
        guard (try? lstatType(at: url)) == .typeDirectory,
              let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return
        }
        for case let child as URL in enumerator {
            if try lstatType(at: child) == .typeSymbolicLink {
                guard rejectingSymlinks else { continue }
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
// swiftlint:enable file_length
