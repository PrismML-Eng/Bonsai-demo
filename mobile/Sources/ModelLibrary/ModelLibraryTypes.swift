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
    case transferring(completedBytes: Int, totalBytes: Int)
    case verifying(completedBytes: Int, totalBytes: Int)
    case loading
    case ready(ModelInstallation)
    case cancelled
    case failed(String)
}

struct ModelLibrarySnapshot: Equatable, Sendable {
    let states: [ModelID: ModelLibraryState]
}

enum ModelLibraryError: Error, Equatable, Sendable, LocalizedError {
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

    var errorDescription: String? {
        switch self {
        case .unqualified:
            "This model is not admitted on the current device. Unsupported hardware stays blocked. Release builds also block load without a validated support row; Debug builds may load an unverified physical-device install for measurement."
        case .invalidSourceURL:
            "The model download URL is invalid."
        case .invalidFileType(let path):
            "A model file is the wrong type: \(path)."
        case .sizeMismatch(let path):
            "A model file has the wrong size: \(path)."
        case .hashMismatch(let path):
            "A model file failed integrity verification: \(path)."
        case .unsafeImport(let path):
            "The import was rejected as unsafe: \(path)."
        case .missingFile(let path):
            "A required model file is missing: \(path)."
        case .duplicatePath(let path):
            "The model archive contains a duplicate path: \(path)."
        case .archiveTooLarge:
            "The model archive exceeds the allowed size."
        case .operationInProgress(let id):
            "Another \(id.rawValue) library operation is already running."
        case .unsafeManagedPath(let path):
            "A managed model path is unsafe: \(path)."
        }
    }
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
