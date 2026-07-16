import Foundation

struct ModelInstallation: Equatable, Sendable {
    let modelID: ModelID
    let directory: URL
    let revision: String
}

struct ModelInstallationRecord: Codable {
    let modelID: ModelID
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

protocol ModelLibraryFileSystem: Sendable {
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func removeItem(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
}

struct DefaultModelLibraryFileSystem: ModelLibraryFileSystem {
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: withIntermediateDirectories
        )
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
