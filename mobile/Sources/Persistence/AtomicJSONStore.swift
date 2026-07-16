import Foundation

enum AtomicJSONStoreError: Error, Equatable, Sendable {
    case unsafeRoot
    case unsafeIdentifier(String)
    case symbolicLink
    case unreadable
}

actor AtomicJSONStore {
    private let root: URL
    private let fileManager: FileManager

    init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
        if fileManager.fileExists(atPath: root.path) {
            guard try !Self.isSymbolicLink(root) else {
                throw AtomicJSONStoreError.unsafeRoot
            }
        } else {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw AtomicJSONStoreError.unsafeRoot
        }
    }

    func read(identifier: String) throws -> Data? {
        let destination = try destinationURL(identifier: identifier)
        guard fileManager.fileExists(atPath: destination.path) else { return nil }
        guard try !Self.isSymbolicLink(destination) else {
            throw AtomicJSONStoreError.symbolicLink
        }
        do {
            return try Data(contentsOf: destination, options: [.mappedIfSafe])
        } catch {
            throw AtomicJSONStoreError.unreadable
        }
    }

    func write(_ data: Data, identifier: String) throws {
        let destination = try destinationURL(identifier: identifier)
        if fileManager.fileExists(atPath: destination.path),
           try Self.isSymbolicLink(destination) {
            throw AtomicJSONStoreError.symbolicLink
        }

        let temporary = root.appending(
            path: ".\(identifier).\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )
        defer { try? fileManager.removeItem(at: temporary) }
        guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: temporary.path
        )
        #endif
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    func quarantine(identifier: String) throws {
        let source = try destinationURL(identifier: identifier)
        guard fileManager.fileExists(atPath: source.path) else { return }
        guard try !Self.isSymbolicLink(source) else {
            throw AtomicJSONStoreError.symbolicLink
        }
        let quarantine = root.appending(
            path: "\(identifier).corrupt.\(UUID().uuidString)",
            directoryHint: .notDirectory
        )
        try fileManager.moveItem(at: source, to: quarantine)
    }

    func encoded<T: Encodable & Sendable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func destinationURL(identifier: String) throws -> URL {
        guard !identifier.isEmpty,
              identifier.count <= 128,
              identifier.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics
                      .union(CharacterSet(charactersIn: "-_."))
                      .contains($0)
              }),
              identifier != ".",
              identifier != ".." else {
            throw AtomicJSONStoreError.unsafeIdentifier(identifier)
        }
        return root.appending(path: "\(identifier).json", directoryHint: .notDirectory)
    }

    private static func isSymbolicLink(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
    }
}
