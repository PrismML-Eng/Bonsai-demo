import Darwin
import Foundation

enum AtomicJSONStoreError: Error, Equatable, Sendable {
    case unsafeRoot
    case unsafeIdentifier(String)
    case symbolicLink
    case unreadable
}

protocol AtomicDataStoring: Sendable {
    func read(identifier: String) async throws -> Data?
    func write(_ data: Data, identifier: String) async throws
    func quarantine(identifier: String) async throws
}

protocol DirectorySynchronizing: Sendable {
    func synchronize(directoryDescriptor: Int32) throws
}

struct DarwinDirectorySynchronizer: DirectorySynchronizing {
    func synchronize(directoryDescriptor: Int32) throws {
        guard fsync(directoryDescriptor) == 0 else { throw POSIXError(.init(rawValue: errno)!) }
    }
}

protocol AtomicStorePromotionHook: Sendable {
    func willPromote(identifier: String) throws
}

struct NoopAtomicStorePromotionHook: AtomicStorePromotionHook {
    func willPromote(identifier: String) throws {}
}

/// JSON storage confined to the directory object opened at initialization.
///
/// Every leaf operation is relative to the retained `O_NOFOLLOW` directory
/// descriptor. A later rename or replacement of the pathname therefore cannot
/// redirect this store. Successful promotions and quarantines synchronize the
/// directory entry before returning.
actor AtomicJSONStore {
    private let rootDescriptor: Int32
    private let directorySynchronizer: any DirectorySynchronizing
    private let promotionHook: any AtomicStorePromotionHook

    init(
        root: URL,
        fileManager: FileManager = .default,
        directorySynchronizer: any DirectorySynchronizing = DarwinDirectorySynchronizer(),
        promotionHook: any AtomicStorePromotionHook = NoopAtomicStorePromotionHook()
    ) throws {
        let standardized = root.standardizedFileURL
        if !fileManager.fileExists(atPath: standardized.path) {
            try fileManager.createDirectory(at: standardized, withIntermediateDirectories: true)
        }

        let descriptor = Darwin.open(
            standardized.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else { throw AtomicJSONStoreError.unsafeRoot }

        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR else {
            Darwin.close(descriptor)
            throw AtomicJSONStoreError.unsafeRoot
        }
        rootDescriptor = descriptor
        self.directorySynchronizer = directorySynchronizer
        self.promotionHook = promotionHook
    }

    deinit { Darwin.close(rootDescriptor) }

    func read(identifier: String) throws -> Data? {
        let name = try fileName(identifier: identifier)
        let descriptor = name.withCString {
            openat(rootDescriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw AtomicJSONStoreError.symbolicLink }
            throw AtomicJSONStoreError.unreadable
        }
        defer { Darwin.close(descriptor) }
        try validateRegularFile(descriptor)

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { return result }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw AtomicJSONStoreError.unreadable
            }
            result.append(buffer, count: count)
        }
    }

    func write(_ data: Data, identifier: String) throws {
        let destination = try fileName(identifier: identifier)
        try rejectNonRegularExistingLeaf(destination)
        let temporary = ".\(identifier).\(UUID().uuidString).tmp"
        let descriptor = temporary.withCString {
            openat(
                rootDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno)!) }
        var promoted = false
        defer {
            Darwin.close(descriptor)
            if !promoted {
                temporary.withCString { _ = unlinkat(rootDescriptor, $0, 0) }
            }
        }

        #if os(iOS)
        // Descriptor-based protection avoids reopening an attacker-controlled path.
        // Generic iOS compilation validates this branch; physical-device protection
        // behavior remains part of the device verification lane.
        // Darwin's class-A ABI value is stable but the Swift overlay no longer
        // exports the legacy PROTECTION_CLASS_A spelling in the iOS 26 SDK.
        let completeProtectionClass: Int32 = 1
        guard fcntl(descriptor, F_SETPROTECTIONCLASS, completeProtectionClass) == 0 else {
            throw POSIXError(.init(rawValue: errno)!)
        }
        #endif

        try writeAll(data, to: descriptor)
        guard fsync(descriptor) == 0 else { throw POSIXError(.init(rawValue: errno)!) }
        try rejectNonRegularExistingLeaf(destination)
        try promotionHook.willPromote(identifier: identifier)
        try Task.checkCancellation()
        let renameResult = temporary.withCString { temporaryName in
            destination.withCString { destinationName in
                renameat(rootDescriptor, temporaryName, rootDescriptor, destinationName)
            }
        }
        guard renameResult == 0 else { throw POSIXError(.init(rawValue: errno)!) }
        promoted = true
        try directorySynchronizer.synchronize(directoryDescriptor: rootDescriptor)
    }

    /// Serializes a read-check-write transaction across every store instance
    /// opened on the same directory vnode. The advisory directory lock also
    /// coordinates separate process-local actors and cooperating processes.
    func transaction<Result: Sendable>(
        identifier: String,
        _ transform: @Sendable (Data?) throws -> (data: Data, result: Result)
    ) throws -> Result {
        guard flock(rootDescriptor, LOCK_EX) == 0 else {
            throw POSIXError(.init(rawValue: errno)!)
        }
        defer { _ = flock(rootDescriptor, LOCK_UN) }
        let mutation = try transform(try read(identifier: identifier))
        try Task.checkCancellation()
        try write(mutation.data, identifier: identifier)
        return mutation.result
    }

    func quarantine(identifier: String) throws {
        let source = try fileName(identifier: identifier)
        guard try existingLeafKind(source) != nil else { return }
        try rejectNonRegularExistingLeaf(source)
        let quarantine = "\(identifier).corrupt.\(UUID().uuidString)"
        let result = source.withCString { sourceName in
            quarantine.withCString { quarantineName in
                renameat(rootDescriptor, sourceName, rootDescriptor, quarantineName)
            }
        }
        guard result == 0 else {
            if errno == ENOENT { return }
            throw POSIXError(.init(rawValue: errno)!)
        }
        try directorySynchronizer.synchronize(directoryDescriptor: rootDescriptor)
    }

    func delete(identifier: String) throws {
        let name = try fileName(identifier: identifier)
        guard try existingLeafKind(name) != nil else { return }
        try rejectNonRegularExistingLeaf(name)
        let result = name.withCString { unlinkat(rootDescriptor, $0, 0) }
        guard result == 0 || errno == ENOENT else {
            throw POSIXError(.init(rawValue: errno)!)
        }
        try directorySynchronizer.synchronize(directoryDescriptor: rootDescriptor)
    }

    func encoded<T: Encodable & Sendable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func fileName(identifier: String) throws -> String {
        guard !identifier.isEmpty,
              identifier.count <= 128,
              identifier.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...90).contains(byte) ||
                      (97...122).contains(byte) || byte == 45 || byte == 95 || byte == 46
              }),
              identifier != ".",
              identifier != ".." else {
            throw AtomicJSONStoreError.unsafeIdentifier(identifier)
        }
        return "\(identifier).json"
    }

    private func validateRegularFile(_ descriptor: Int32) throws {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw AtomicJSONStoreError.unreadable }
        guard status.st_mode & S_IFMT == S_IFREG else {
            throw AtomicJSONStoreError.symbolicLink
        }
    }

    private func existingLeafKind(_ name: String) throws -> mode_t? {
        var status = stat()
        let result = name.withCString {
            fstatat(rootDescriptor, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 { return status.st_mode & S_IFMT }
        if errno == ENOENT { return nil }
        throw POSIXError(.init(rawValue: errno)!)
    }

    private func rejectNonRegularExistingLeaf(_ name: String) throws {
        guard let kind = try existingLeafKind(name) else { return }
        guard kind == S_IFREG else { throw AtomicJSONStoreError.symbolicLink }
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress!.advanced(by: offset),
                    bytes.count - offset
                )
                guard count >= 0 else {
                    if errno == EINTR { continue }
                    throw POSIXError(.init(rawValue: errno)!)
                }
                offset += count
            }
        }
    }
}

extension AtomicJSONStore: AtomicDataStoring {}
