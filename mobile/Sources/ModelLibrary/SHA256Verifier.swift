import Darwin
import CryptoKit
import Foundation

struct SHA256Verifier: Sendable {
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func verify(_ file: ModelManifest.File, at url: URL) throws {
        let actual = try NoFollowRegularFile.withDescriptor(at: url, logicalPath: file.path) { descriptor, info in
            guard info.st_size == file.sizeBytes else {
                throw ModelLibraryError.sizeMismatch(file.path)
            }
            var hasher = SHA256()
            var buffer = [UInt8](repeating: 0, count: 1_048_576)
            while true {
                try Task.checkCancellation()
                let byteCount = try NoFollowRegularFile.read(descriptor, into: &buffer)
                guard byteCount > 0 else { break }
                hasher.update(data: Data(buffer[0..<byteCount]))
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        guard actual == file.sha256 else {
            throw ModelLibraryError.hashMismatch(file.path)
        }
    }
}

enum NoFollowRegularFile {
    static func readAll(at url: URL, logicalPath: String, maximumSize: Int) throws -> Data {
        try withDescriptor(at: url, logicalPath: logicalPath) { descriptor, info in
            guard info.st_size <= maximumSize else { throw CocoaError(.fileReadTooLarge) }
            var data = Data()
            data.reserveCapacity(Int(info.st_size))
            var buffer = [UInt8](repeating: 0, count: min(maximumSize, 64 * 1_024))
            while true {
                let byteCount = try read(descriptor, into: &buffer)
                guard byteCount > 0 else { return data }
                data.append(contentsOf: buffer[0..<byteCount])
            }
        }
    }

    static func withDescriptor<Result>(
        at url: URL,
        logicalPath: String,
        _ body: (Int32, stat) throws -> Result
    ) throws -> Result {
        var pathInfo = stat()
        guard lstat(url.path, &pathInfo) == 0 else { throw posixError() }
        guard pathInfo.st_mode & S_IFMT == S_IFREG else {
            throw ModelLibraryError.invalidFileType(logicalPath)
        }

        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ELOOP { throw ModelLibraryError.invalidFileType(logicalPath) }
            throw posixError()
        }
        defer { close(descriptor) }

        var openedInfo = stat()
        guard fstat(descriptor, &openedInfo) == 0 else { throw posixError() }
        guard openedInfo.st_mode & S_IFMT == S_IFREG,
              openedInfo.st_dev == pathInfo.st_dev,
              openedInfo.st_ino == pathInfo.st_ino else {
            throw ModelLibraryError.invalidFileType(logicalPath)
        }
        return try body(descriptor, openedInfo)
    }

    static func read(_ descriptor: Int32, into buffer: inout [UInt8]) throws -> Int {
        while true {
            let result = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if result >= 0 { return result }
            guard errno == EINTR else { throw posixError() }
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(.init(rawValue: errno) ?? .EIO)
    }
}
