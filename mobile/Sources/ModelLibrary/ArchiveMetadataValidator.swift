import Darwin
import Foundation

struct ArchiveMetadataValidator: Sendable {
    private let hardLinkMetadataIDs: Set<UInt16> = [0x000D, 0x756E]

    func validate(at url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let tailSize = min(size, 65_557)
        try handle.seek(toOffset: size - tailSize)
        let tail = try handle.read(upToCount: Int(tailSize)) ?? Data()
        guard let endOffset = lastIndex(of: 0x0605_4B50, in: tail) else {
            throw ModelLibraryError.unsafeImport(url.lastPathComponent)
        }
        var directorySize = UInt64(readUInt32(tail, at: endOffset + 12))
        var directoryOffset = UInt64(readUInt32(tail, at: endOffset + 16))
        if directorySize == UInt64(UInt32.max) || directoryOffset == UInt64(UInt32.max) {
            let locatorOffset = endOffset - 20
            guard locatorOffset >= 0,
                  readUInt32(tail, at: locatorOffset) == 0x0706_4B50 else {
                throw ModelLibraryError.unsafeImport(url.lastPathComponent)
            }
            let zip64Offset = readUInt64(tail, at: locatorOffset + 8)
            try handle.seek(toOffset: zip64Offset)
            let zip64 = try handle.read(upToCount: 56) ?? Data()
            guard zip64.count >= 56, readUInt32(zip64, at: 0) == 0x0606_4B50 else {
                throw ModelLibraryError.unsafeImport(url.lastPathComponent)
            }
            directorySize = readUInt64(zip64, at: 40)
            directoryOffset = readUInt64(zip64, at: 48)
        }
        guard directoryOffset <= size, directorySize <= size - directoryOffset else {
            throw ModelLibraryError.archiveTooLarge
        }
        try validateDirectory(handle: handle, offset: directoryOffset, size: directorySize)
    }

    func validateUnixMetadata(mode: mode_t, extraFieldIDs: Set<UInt16>) throws {
        let type = mode & S_IFMT
        guard type == S_IFREG || type == S_IFDIR else {
            throw ModelLibraryError.unsafeImport("unsupported archive entry type")
        }
        guard extraFieldIDs.isDisjoint(with: hardLinkMetadataIDs) else {
            throw ModelLibraryError.unsafeImport("hard-link archive metadata")
        }
    }

    private func validateDirectory(handle: FileHandle, offset: UInt64, size: UInt64) throws {
        try handle.seek(toOffset: offset)
        var consumed: UInt64 = 0
        while consumed < size {
            let header = try handle.read(upToCount: 46) ?? Data()
            guard header.count == 46, readUInt32(header, at: 0) == 0x0201_4B50 else {
                throw ModelLibraryError.unsafeImport("invalid central directory")
            }
            let nameLength = Int(readUInt16(header, at: 28))
            let extraLength = Int(readUInt16(header, at: 30))
            let commentLength = Int(readUInt16(header, at: 32))
            let variableLength = nameLength + extraLength + commentLength
            let variable = try handle.read(upToCount: variableLength) ?? Data()
            guard variable.count == variableLength else {
                throw ModelLibraryError.unsafeImport("truncated central directory")
            }
            let operatingSystem = readUInt16(header, at: 4) >> 8
            if operatingSystem == 3 || operatingSystem == 19 {
                let mode = mode_t(readUInt32(header, at: 38) >> 16)
                let extra = variable.subdata(in: nameLength ..< nameLength + extraLength)
                try validateUnixMetadata(mode: mode, extraFieldIDs: extraFieldIDs(extra))
            }
            consumed += UInt64(46 + variableLength)
        }
        guard consumed == size else { throw ModelLibraryError.unsafeImport("invalid central directory size") }
    }

    private func extraFieldIDs(_ data: Data) -> Set<UInt16> {
        var result: Set<UInt16> = []
        var offset = 0
        while offset + 4 <= data.count {
            let identifier = readUInt16(data, at: offset)
            let length = Int(readUInt16(data, at: offset + 2))
            guard offset + 4 + length <= data.count else { break }
            result.insert(identifier)
            offset += 4 + length
        }
        return result
    }

    private func lastIndex(of signature: UInt32, in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        for offset in stride(from: data.count - 4, through: 0, by: -1)
        where readUInt32(data, at: offset) == signature {
            return offset
        }
        return nil
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return data[offset ..< offset + 2].enumerated().reduce(0) { result, pair in
            result | UInt16(pair.element) << (8 * pair.offset)
        }
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return data[offset ..< offset + 4].enumerated().reduce(0) { result, pair in
            result | UInt32(pair.element) << (8 * pair.offset)
        }
    }

    private func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else { return 0 }
        return data[offset ..< offset + 8].enumerated().reduce(0) { result, pair in
            result | UInt64(pair.element) << (8 * pair.offset)
        }
    }
}
