import Foundation

struct SupportEvidenceReference: Codable, Equatable, Sendable {
  let modelID: ModelID
  let modelRevision: String
  let runtimeFingerprint: String
  let osBuild: String
  let appBuild: String
  let appCommit: String
  let deviceClass: DeviceClass
  let capability: ModelCapability
  let scenario: DeviceEvidence.Scenario
  let artifactPath: String
  let artifactSHA256: String
}

struct ReleaseSupportManifest: Codable, Equatable, Sendable {
  enum ValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion
    case invalidArtifactPath(String)
    case invalidDigest(String)
    case duplicateClaim
    case digestMismatch(String)
    case evidenceIdentityMismatch(String)
    case capabilityNotProven(String)
  }

  let schemaVersion: Int
  let evidence: [SupportEvidenceReference]

  // swiftlint:disable:next cyclomatic_complexity
  func qualificationEvidence(
    artifactLoader: (String) throws -> Data
  ) throws -> QualificationEvidence {
    guard schemaVersion == 1 else { throw ValidationError.unsupportedSchemaVersion }
    var claims = Set<String>()
    var result: QualificationEvidence = [:]
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    for reference in evidence {
      guard reference.runtimeFingerprint == BonsaiRuntimeFingerprint.current else {
        throw ValidationError.evidenceIdentityMismatch(reference.artifactPath)
      }
      guard Self.isStableArtifactPath(reference.artifactPath) else {
        throw ValidationError.invalidArtifactPath(reference.artifactPath)
      }
      guard isLowercaseHex(reference.artifactSHA256, count: 64) else {
        throw ValidationError.invalidDigest(reference.artifactPath)
      }
      let claim = "\(reference.modelID.rawValue)|\(reference.deviceClass.rawValue)|\(reference.capability.rawValue)"
      guard claims.insert(claim).inserted else { throw ValidationError.duplicateClaim }
      let data = try artifactLoader(reference.artifactPath)
      guard SHA256Verifier.digest(data) == reference.artifactSHA256 else {
        throw ValidationError.digestMismatch(reference.artifactPath)
      }
      let row = try decoder.decode(DeviceEvidence.self, from: data)
      try row.validateForRelease()
      guard row.recordKind == .supported else {
        throw ValidationError.capabilityNotProven(reference.artifactPath)
      }
      guard row.modelID == reference.modelID,
            row.modelRevision == reference.modelRevision,
            row.runtimeFingerprint == reference.runtimeFingerprint,
            row.osBuild == reference.osBuild,
            row.appBuild == reference.appBuild,
            row.appCommit == reference.appCommit,
            row.deviceClass == reference.deviceClass else {
        throw ValidationError.evidenceIdentityMismatch(reference.artifactPath)
      }
      guard row.capabilities?.contains(reference.capability) == true else {
        throw ValidationError.capabilityNotProven(reference.artifactPath)
      }
      guard row.scenarioResults?.contains(where: {
        $0.scenario == reference.scenario && $0.capability == reference.capability
          && $0.outcome == .passed
      }) == true else { throw ValidationError.capabilityNotProven(reference.artifactPath) }
      result[reference.modelID, default: [:]][reference.deviceClass, default: []]
        .insert(reference.capability)
    }
    return result
  }

  private static func isStableArtifactPath(_ path: String) -> Bool {
    guard path.hasPrefix("Evidence/"), path.hasSuffix(".json"),
          !path.hasPrefix("/"), !path.contains("\\"), !path.contains("..") else { return false }
    return path.split(separator: "/").allSatisfy { !$0.isEmpty && $0 != "." }
  }
}

enum BonsaiRuntimeFingerprint {
  private static let mlxSwiftRevision = "e40e0a57a6f7ad08dc3fd87ad598a7aa6407d230"
  private static let mlxLMRevision = "4ca25fd901e2db2703cbe5a6ea339b29642c754f"
  private static let compatibilityPatchSHA256 =
    "e202d355b4d68e5784fc82e230e762c083219cb244e528d73737c0f59fe89fbd"
  static let current = SHA256Verifier.digest(
    Data("\(mlxSwiftRevision):\(mlxLMRevision):\(compatibilityPatchSHA256)".utf8))
}

enum ReleaseSupportManifestLoader {
  static func bundled(
    bundle: Bundle = .main,
    expectedRevisions: [ModelID: String] = [:],
    currentFacts: DeviceFacts? = nil
  ) throws -> QualificationEvidence {
    guard let manifestURL = bundle.url(
      forResource: "support-manifest", withExtension: "json", subdirectory: "Evidence")
      ?? bundle.url(forResource: "support-manifest", withExtension: "json")
    else { return [:] }
    let decoder = JSONDecoder()
    let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
    let manifest = try decoder.decode(ReleaseSupportManifest.self, from: manifestData)
    guard manifest.evidence.allSatisfy({ reference in
      (expectedRevisions.isEmpty || expectedRevisions[reference.modelID] == reference.modelRevision)
        && (currentFacts == nil || reference.deviceClass != currentFacts?.deviceClass || (
            reference.osBuild == currentFacts?.osBuild
            && reference.appBuild == currentFacts?.appBuild
            && reference.appCommit == currentFacts?.appCommit
            && reference.runtimeFingerprint == currentFacts?.runtimeFingerprint))
    }) else { throw ReleaseSupportManifest.ValidationError.evidenceIdentityMismatch("modelRevision") }
    let resources = bundle.resourceURL ?? manifestURL.deletingLastPathComponent()
    let qualified = try manifest.qualificationEvidence { path in
      let relative = URL(filePath: path).pathComponents.dropFirst().joined(separator: "/")
      let artifactURL = resources.appending(path: "Evidence/\(relative)")
      return try Data(contentsOf: artifactURL, options: .mappedIfSafe)
    }
    guard let currentFacts else { return qualified }
    return qualified.mapValues { devices in
      devices.filter { $0.key == currentFacts.deviceClass }
    }.filter { !$0.value.isEmpty }
  }
}
