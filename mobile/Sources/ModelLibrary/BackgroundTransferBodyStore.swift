import Foundation

protocol BackgroundTransferStoragePolicy: Sendable {
    func applyRecursively(to url: URL) throws
}

struct DefaultBackgroundTransferStoragePolicy: BackgroundTransferStoragePolicy {
    func applyRecursively(to url: URL) throws {
        let manager = FileManager.default
        var urls = [url]
        if let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            while let child = enumerator.nextObject() as? URL { urls.append(child) }
        }
        for item in urls {
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw ModelLibraryError.unsafeManagedPath(item.lastPathComponent)
            }
            var mutable = item
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try mutable.setResourceValues(resourceValues)
            #if os(iOS)
            try manager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: item.path
            )
            #endif
        }
    }
}

struct BackgroundTransferClaim: Codable, Equatable, Sendable {
    let transferID: UUID
    let bodyURL: URL
    let statusCode: Int
    let contentRange: String?
}

final class BackgroundTransferBodyStore: @unchecked Sendable {
    private let lock = NSLock()
    private let root: URL
    private let policy: any BackgroundTransferStoragePolicy

    init(ledgerFileURL: URL, policy: any BackgroundTransferStoragePolicy) throws {
        root = ledgerFileURL.deletingLastPathComponent()
            .appending(path: "Downloads", directoryHint: .isDirectory)
        self.policy = policy
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try policy.applyRecursively(to: root.deletingLastPathComponent())
    }

    func claim(
        id: UUID,
        temporaryBody: URL,
        statusCode: Int,
        contentRange: String?
    ) throws -> BackgroundTransferClaim {
        try lock.withLock {
            let body = bodyURL(id: id)
            let sidecar = sidecarURL(id: id)
            if let existing = try validClaim(id: id), FileManager.default.fileExists(atPath: body.path) {
                if temporaryBody.standardizedFileURL != body.standardizedFileURL,
                   FileManager.default.fileExists(atPath: temporaryBody.path) {
                    try FileManager.default.removeItem(at: temporaryBody)
                }
                return existing
            }
            try removeIfPresent(sidecar)
            try removeIfPresent(body)
            try FileManager.default.moveItem(at: temporaryBody, to: body)
            try policy.applyRecursively(to: body)
            let claim = BackgroundTransferClaim(
                transferID: id,
                bodyURL: body,
                statusCode: statusCode,
                contentRange: contentRange
            )
            let data = try JSONEncoder().encode(claim)
            try data.write(
                to: sidecar,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try policy.applyRecursively(to: sidecar)
            return claim
        }
    }

    func reconcile(validTransferIDs: Set<UUID>) throws -> [BackgroundTransferClaim] {
        try lock.withLock {
            let manager = FileManager.default
            let contents = try manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            var claims: [UUID: BackgroundTransferClaim] = [:]
            for sidecar in contents where sidecar.pathExtension == "json" {
                guard let id = UUID(uuidString: sidecar.deletingPathExtension().lastPathComponent),
                      validTransferIDs.contains(id),
                      let claim = try? JSONDecoder().decode(
                          BackgroundTransferClaim.self,
                          from: Data(contentsOf: sidecar)
                      ),
                      claim.transferID == id,
                      claim.bodyURL.standardizedFileURL == bodyURL(id: id).standardizedFileURL,
                      manager.fileExists(atPath: claim.bodyURL.path) else {
                    try removeIfPresent(sidecar)
                    continue
                }
                try policy.applyRecursively(to: claim.bodyURL)
                try policy.applyRecursively(to: sidecar)
                claims[id] = claim
            }
            for body in contents where body.pathExtension == "download" {
                guard let id = UUID(uuidString: body.deletingPathExtension().lastPathComponent),
                      claims[id] != nil else {
                    try removeIfPresent(body)
                    continue
                }
            }
            return claims.values.sorted { $0.transferID.uuidString < $1.transferID.uuidString }
        }
    }

    func removeClaim(id: UUID, removeBody: Bool) throws {
        try lock.withLock {
            try removeIfPresent(sidecarURL(id: id))
            if removeBody { try removeIfPresent(bodyURL(id: id)) }
        }
    }

    private func validClaim(id: UUID) throws -> BackgroundTransferClaim? {
        let sidecar = sidecarURL(id: id)
        guard FileManager.default.fileExists(atPath: sidecar.path) else { return nil }
        let claim = try JSONDecoder().decode(BackgroundTransferClaim.self, from: Data(contentsOf: sidecar))
        guard claim.transferID == id,
              claim.bodyURL.standardizedFileURL == bodyURL(id: id).standardizedFileURL else {
            throw ModelLibraryError.unsafeManagedPath(sidecar.lastPathComponent)
        }
        return claim
    }

    private func bodyURL(id: UUID) -> URL {
        root.appending(path: "\(id.uuidString.lowercased()).download")
    }

    private func sidecarURL(id: UUID) -> URL {
        root.appending(path: "\(id.uuidString.lowercased()).json")
    }

    private func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
