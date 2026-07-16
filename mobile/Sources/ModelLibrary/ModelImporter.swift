import Darwin
import Foundation
import ZIPFoundation

struct ModelImporter: Sendable {
    private var files: FileManager { .default }

    func copy(manifest: ModelManifest, from source: URL, to staging: URL) throws {
        try validateManifestCollisions(manifest)
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw ModelLibraryError.unsafeImport(source.lastPathComponent)
        }
        if values.isDirectory == true {
            try copyFolder(manifest: manifest, source: source, staging: staging)
        } else if source.pathExtension.lowercased() == "zip"
            || source.lastPathComponent.lowercased().hasSuffix(".bonsaimodel.zip") {
            try copyArchive(manifest: manifest, source: source, staging: staging)
        } else {
            throw ModelLibraryError.unsafeImport(source.lastPathComponent)
        }
    }

    private func copyFolder(manifest: ModelManifest, source: URL, staging: URL) throws {
        let sourceRoot = source.standardizedFileURL.resolvingSymlinksInPath()
        let expected = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.path, $0) })
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = files.enumerator(
            at: source,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw ModelLibraryError.unsafeImport(source.lastPathComponent)
        }

        var seen: Set<String> = []
        for case let candidate as URL in enumerator {
            try Task.checkCancellation()
            let logical = try logicalPath(candidate, under: source)
            let values = try candidate.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true { continue }
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                throw ModelLibraryError.unsafeImport(logical)
            }
            guard expected[logical] != nil else { throw ModelLibraryError.unsafeImport(logical) }
            guard seen.insert(logical).inserted else { throw ModelLibraryError.duplicatePath(logical) }
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard isDescendant(resolved, of: sourceRoot) else {
                throw ModelLibraryError.unsafeImport(logical)
            }
            try validateRegularFile(candidate, logicalPath: logical)
            let destination = try safeDestination(logical, under: staging)
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.copyItem(at: candidate, to: destination)
        }
        for file in manifest.files where !file.isOptional && !seen.contains(file.path) {
            throw ModelLibraryError.missingFile(file.path)
        }
    }

    private func copyArchive(manifest: ModelManifest, source: URL, staging: URL) throws {
        let archive = try Archive(url: source, accessMode: .read)
        let expected = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.path, $0) })
        let maximumDeclared = manifest.files.reduce(into: UInt64(64 * 1_024 * 1_024)) {
            $0 = $0.addingReportingOverflow(UInt64($1.sizeBytes)).partialValue
        }
        var validation = ArchiveValidationState(maximumDeclared: maximumDeclared)
        for entry in archive {
            try Task.checkCancellation()
            guard let logical = try validatedArchivePath(entry) else { continue }
            try validateArchiveFile(
                entry,
                logical: logical,
                expected: expected,
                validation: &validation
            )
            let destination = try safeDestination(logical, under: staging)
            try extract(entry, from: archive, to: destination)
        }
        for file in manifest.files where !file.isOptional && !validation.seen.contains(file.path) {
            throw ModelLibraryError.missingFile(file.path)
        }
    }

    private func validatedArchivePath(_ entry: Entry) throws -> String? {
        let logical = normalizedArchivePath(entry.path)
        guard !logical.isEmpty, isSafeLogicalPath(logical) else {
            throw ModelLibraryError.unsafeImport(entry.path)
        }
        if entry.type == .directory { return nil }
        guard entry.type == .file else { throw ModelLibraryError.unsafeImport(logical) }
        return logical
    }

    private func validateArchiveFile(
        _ entry: Entry,
        logical: String,
        expected: [String: ModelManifest.File],
        validation: inout ArchiveValidationState
    ) throws {
        guard let expectedFile = expected[logical] else { throw ModelLibraryError.unsafeImport(logical) }
        guard validation.seen.insert(logical).inserted else { throw ModelLibraryError.duplicatePath(logical) }
        guard entry.uncompressedSize == UInt64(expectedFile.sizeBytes) else {
            throw ModelLibraryError.sizeMismatch(logical)
        }
        let (newDeclared, overflow) = validation.declared.addingReportingOverflow(entry.uncompressedSize)
        guard !overflow, newDeclared <= validation.maximumDeclared else {
            throw ModelLibraryError.archiveTooLarge
        }
        validation.declared = newDeclared
        if entry.uncompressedSize > 0 {
            guard entry.compressedSize > 0,
                  entry.uncompressedSize / max(entry.compressedSize, 1) <= 1_000 else {
                throw ModelLibraryError.archiveTooLarge
            }
        }
        let permissions = entry.fileAttributes[.posixPermissions] as? NSNumber
        guard (permissions?.intValue ?? 0) & 0o111 == 0 else {
            throw ModelLibraryError.unsafeImport(logical)
        }
    }

    private func extract(_ entry: Entry, from archive: Archive, to destination: URL) throws {
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard files.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            _ = try archive.extract(entry) { chunk in
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
        } catch {
            try? files.removeItem(at: destination)
            throw error
        }
    }

    private func validateManifestCollisions(_ manifest: ModelManifest) throws {
        let paths = Set(manifest.files.map(\.path))
        for path in paths {
            var components = path.split(separator: "/")
            while components.count > 1 {
                components.removeLast()
                let parent = components.joined(separator: "/")
                guard !paths.contains(parent) else { throw ModelLibraryError.duplicatePath(parent) }
            }
        }
    }

    private func validateRegularFile(_ url: URL, logicalPath: String) throws {
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw ModelLibraryError.unsafeImport(logicalPath)
        }
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard permissions & 0o111 == 0 else { throw ModelLibraryError.unsafeImport(logicalPath) }
        let links = (attributes[.referenceCount] as? NSNumber)?.intValue ?? 1
        guard links <= 1 else { throw ModelLibraryError.unsafeImport(logicalPath) }
    }

    private func logicalPath(_ candidate: URL, under root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        guard candidatePath.hasPrefix(rootPath + "/") else {
            throw ModelLibraryError.unsafeImport(candidate.lastPathComponent)
        }
        let index = candidatePath.index(candidatePath.startIndex, offsetBy: rootPath.count + 1)
        let logical = String(candidatePath[index...])
        guard isSafeLogicalPath(logical) else { throw ModelLibraryError.unsafeImport(logical) }
        return logical
    }

    private func safeDestination(_ logical: String, under root: URL) throws -> URL {
        guard isSafeLogicalPath(logical) else { throw ModelLibraryError.unsafeImport(logical) }
        let root = root.standardizedFileURL
        let destination = root.appending(path: logical).standardizedFileURL
        guard isDescendant(destination, of: root) else { throw ModelLibraryError.unsafeImport(logical) }
        return destination
    }

    private func normalizedArchivePath(_ path: String) -> String {
        var result = path.replacingOccurrences(of: "\\", with: "/")
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }

    private func isSafeLogicalPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"), !path.contains(":") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        candidate.path.hasPrefix(root.path + "/")
    }
}

private struct ArchiveValidationState {
    var seen: Set<String> = []
    var declared: UInt64 = 0
    let maximumDeclared: UInt64
}
