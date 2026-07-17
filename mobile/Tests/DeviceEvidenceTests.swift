import Foundation
import Testing
@testable import BonsaiMobile

// Evidence fixtures intentionally keep the closed schema and every negative gate together.
// swiftlint:disable type_body_length
@Suite("Release device evidence")
struct DeviceEvidenceTests {
  @Test func supportedEvidenceRequiresIndependentCapabilityScenarios() {
    let row = Self.fixture(
      capabilities: [.textGeneration, .thinking],
      scenarioResults: Self.requiredScenarioResults.filter { $0.scenario != .thinking })

    #expect(throws: DeviceEvidence.ValidationError.incompleteScenario("thinking")) {
      try row.validateForRelease()
    }
  }

  @Test func deterministicUnsupportedEvidenceIsValidButCannotQualify() throws {
    let row = Self.fixture(
      recordKind: .unsupported,
      outcome: .failed,
      capabilities: [],
      scenarioResults: [
        .init(scenario: .loadUnload, capability: nil, outcome: .unsupported,
              completion: "model_load_failed", elapsedMilliseconds: 1)
      ],
      unsupportedReason: .modelLoadFailure)

    try row.validateForRelease()
  }

  @Test func physicalHardwareIdentifiersMapToStableEvidenceClasses() {
    #expect(DeviceClass.evidenceClass(hardwareIdentifier: "iPhone17,5").rawValue == "iPhone17,5")
    #expect(DeviceClass.evidenceClass(hardwareIdentifier: "future-device,1").rawValue
            == "future-device,1")
  }

  @Test func evidenceRequiresEveryReleaseMetric() throws {
    let row = Self.fixture(generatedTokensPerSecond: nil)

    #expect(throws: DeviceEvidence.ValidationError.missing("generatedTokensPerSecond")) {
      try row.validateForRelease()
    }
  }

  @Test func releaseEvidenceRejectsPressureTerminationAndFailedOutcome() {
    #expect(throws: DeviceEvidence.ValidationError.pressureTermination) {
      try Self.fixture(pressureTermination: true).validateForRelease()
    }
    #expect(throws: DeviceEvidence.ValidationError.unsuccessfulOutcome) {
      try Self.fixture(outcome: .failed).validateForRelease()
    }
  }

  @Test func releaseEvidenceRequiresObservedOfflineProof() {
    #expect(throws: DeviceEvidence.ValidationError.offlineProofIncomplete) {
      try Self.fixture(offlineProof: .init(
        airplaneModeEnabled: true,
        observedOutboundRequestCount: 1,
        inspectionMethod: "Packet capture attached to the evidence run",
        networkCaptureSHA256: String(repeating: "e", count: 64),
        sourceAuditSHA256: String(repeating: "f", count: 64)
      )).validateForRelease()
    }
  }

  @Test func manifestFailsClosedWhenArtifactDigestDoesNotMatch() throws {
    let row = Self.fixture()
    let data = try Self.encoder.encode(row)
    let identity = Self.identity(row)
    let reference = SupportEvidenceReference(
      modelID: identity.modelID,
      modelRevision: identity.modelRevision,
      runtimeFingerprint: BonsaiRuntimeFingerprint.current,
      osBuild: "25F90", appBuild: "1.0-1", appCommit: String(repeating: "a", count: 40),
      deviceClass: identity.deviceClass,
      capability: .textGeneration,
      scenario: .text,
      artifactPath: "Evidence/device-run.json",
      artifactSHA256: String(repeating: "0", count: 64)
    )
    let manifest = ReleaseSupportManifest(schemaVersion: 1, evidence: [reference])

    #expect(throws: ReleaseSupportManifest.ValidationError.digestMismatch("Evidence/device-run.json")) {
      try manifest.qualificationEvidence { path in
        #expect(path == "Evidence/device-run.json")
        return data
      }
    }
  }

  @Test func validManifestQualifiesOnlyProvenCapability() throws {
    let row = Self.fixture(capabilities: [.textGeneration])
    let data = try Self.encoder.encode(row)
    let identity = Self.identity(row)
    let reference = SupportEvidenceReference(
      modelID: identity.modelID,
      modelRevision: identity.modelRevision,
      runtimeFingerprint: BonsaiRuntimeFingerprint.current,
      osBuild: "25F90", appBuild: "1.0-1", appCommit: String(repeating: "a", count: 40),
      deviceClass: identity.deviceClass,
      capability: .textGeneration,
      scenario: .text,
      artifactPath: "Evidence/device-run.json",
      artifactSHA256: SHA256Verifier.digest(data)
    )
    let manifest = ReleaseSupportManifest(schemaVersion: 1, evidence: [reference])

    let evidence = try manifest.qualificationEvidence { _ in data }

    #expect(evidence == [.oneBit27B: [.init(rawValue: "Mac16,1"): [.textGeneration]]])
  }

  @Test(arguments: ["osBuild", "appBuild", "appCommit", "modelRevision", "runtimeFingerprint", "deviceClass"])
  func manifestCannotRelabelArtifactProvenance(_ field: String) throws {
    let row = Self.fixture()
    let data = try Self.encoder.encode(row)
    let identity = Self.identity(row)
    let reference = SupportEvidenceReference(
      modelID: identity.modelID,
      modelRevision: field == "modelRevision" ? String(repeating: "c", count: 40) : identity.modelRevision,
      runtimeFingerprint: field == "runtimeFingerprint" ? String(repeating: "d", count: 64)
        : BonsaiRuntimeFingerprint.current,
      osBuild: field == "osBuild" ? "DIFFERENT" : "25F90",
      appBuild: field == "appBuild" ? "2.0-9" : "1.0-1",
      appCommit: field == "appCommit" ? String(repeating: "d", count: 40)
        : String(repeating: "a", count: 40),
      deviceClass: field == "deviceClass" ? .init(rawValue: "Mac99,9") : identity.deviceClass,
      capability: .textGeneration, scenario: .text,
      artifactPath: "Evidence/device-run.json", artifactSHA256: SHA256Verifier.digest(data))
    let manifest = ReleaseSupportManifest(schemaVersion: 1, evidence: [reference])

    #expect(throws: ReleaseSupportManifest.ValidationError.evidenceIdentityMismatch(
      "Evidence/device-run.json")) {
      try manifest.qualificationEvidence { _ in data }
    }
  }

  @Test func successfulTextEvidenceRequiresPositiveThroughput() {
    #expect(throws: DeviceEvidence.ValidationError.invalid("promptTokensPerSecond")) {
      try Self.fixture(promptTokensPerSecond: 0).validateForRelease()
    }
    #expect(throws: DeviceEvidence.ValidationError.invalid("generatedTokensPerSecond")) {
      try Self.fixture(generatedTokensPerSecond: 0).validateForRelease()
    }
  }

  @Test func unsupportedEvidenceAcceptsOnlyClosedReasonCodes() {
    let row = Self.fixture(
      recordKind: .unsupported, outcome: .failed, capabilities: [],
      scenarioResults: [.init(scenario: .loadUnload, capability: nil, outcome: .unsupported,
                              completion: "model_load_failed", elapsedMilliseconds: 1)],
      unsupportedReason: nil)
    #expect(throws: DeviceEvidence.ValidationError.missing("unsupportedReason")) {
      try row.validateForRelease()
    }
  }

  @Test func deviceQualifierConsumesValidatedManifest() throws {
    let row = Self.fixture(capabilities: [.textGeneration])
    let data = try Self.encoder.encode(row)
    let identity = Self.identity(row)
    let manifest = ReleaseSupportManifest(schemaVersion: 1, evidence: [
      .init(modelID: identity.modelID, modelRevision: identity.modelRevision,
            runtimeFingerprint: BonsaiRuntimeFingerprint.current,
            osBuild: "25F90", appBuild: "1.0-1", appCommit: String(repeating: "a", count: 40),
            deviceClass: identity.deviceClass, capability: .textGeneration,
            scenario: .text,
            artifactPath: "Evidence/device-run.json",
            artifactSHA256: SHA256Verifier.digest(data))
    ])

    let result = DeviceQualifier.qualify(
      model: Self.descriptor(),
      facts: .init(platform: .mac, deviceClass: .init(rawValue: "Mac16,1"),
                   physicalMemoryBytes: 16 * 1_073_741_824,
                   freeStorageBytes: 20 * 1_073_741_824,
                   osBuild: "25F90", appBuild: "1.0-1",
                   appCommit: String(repeating: "a", count: 40),
                   runtimeFingerprint: BonsaiRuntimeFingerprint.current),
      manifest: manifest,
      artifactLoader: { _ in data }
    )

    #expect(result == .qualified([.textGeneration]))
  }

  @Test func staleOSOrCriticalThermalCannotReuseEvidence() throws {
    let row = Self.fixture(capabilities: [.textGeneration])
    let data = try Self.encoder.encode(row)
    let identity = Self.identity(row)
    let manifest = ReleaseSupportManifest(schemaVersion: 1, evidence: [
      .init(modelID: identity.modelID, modelRevision: identity.modelRevision,
            runtimeFingerprint: BonsaiRuntimeFingerprint.current,
            osBuild: "25F90", appBuild: "1.0-1",
            appCommit: String(repeating: "a", count: 40),
            deviceClass: identity.deviceClass, capability: .textGeneration, scenario: .text,
            artifactPath: "Evidence/device-run.json", artifactSHA256: SHA256Verifier.digest(data))
    ])
    let base = DeviceFacts(
      platform: .mac, deviceClass: identity.deviceClass,
      physicalMemoryBytes: 16 * 1_073_741_824, freeStorageBytes: 20 * 1_073_741_824,
      osBuild: "DIFFERENT", appBuild: "1.0-1", appCommit: String(repeating: "a", count: 40),
      runtimeFingerprint: BonsaiRuntimeFingerprint.current)
    #expect(DeviceQualifier.qualify(
      model: Self.descriptor(), facts: base, manifest: manifest, artifactLoader: { _ in data })
      == .unverified(.deviceNotMeasured))
    let critical = DeviceFacts(
      platform: .mac, deviceClass: identity.deviceClass,
      physicalMemoryBytes: 16 * 1_073_741_824, freeStorageBytes: 20 * 1_073_741_824,
      osBuild: "25F90", appBuild: "1.0-1", appCommit: String(repeating: "a", count: 40),
      runtimeFingerprint: BonsaiRuntimeFingerprint.current, thermalState: .critical)
    #expect(DeviceQualifier.qualify(
      model: Self.descriptor(), facts: critical, manifest: manifest, artifactLoader: { _ in data })
      == .unsupported(.criticalThermalState))
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private struct EvidenceIdentity {
    let modelID: ModelID
    let modelRevision: String
    let deviceClass: DeviceClass
  }

  private static func identity(_ row: DeviceEvidence) -> EvidenceIdentity {
    guard let modelID = row.modelID,
          let modelRevision = row.modelRevision,
          let deviceClass = row.deviceClass else {
      preconditionFailure("The complete fixture must contain its support identity")
    }
    return EvidenceIdentity(
      modelID: modelID, modelRevision: modelRevision, deviceClass: deviceClass)
  }

  private static func fixture(
    promptTokensPerSecond: Double? = 122.4,
    generatedTokensPerSecond: Double? = 12.5,
    pressureTermination: Bool = false,
    outcome: DeviceEvidence.Outcome = .completed,
    offlineProof: DeviceEvidence.OfflineProof? = .init(
      airplaneModeEnabled: true,
      observedOutboundRequestCount: 0,
      inspectionMethod: "Packet capture attached to the evidence run",
      networkCaptureSHA256: String(repeating: "e", count: 64),
      sourceAuditSHA256: String(repeating: "f", count: 64)),
    capabilities: Set<ModelCapability> = [.textGeneration],
    recordKind: DeviceEvidence.RecordKind = .supported,
    scenarioResults: [DeviceEvidence.ScenarioResult] = Self.requiredScenarioResults,
    unsupportedReason: DeviceEvidence.UnsupportedReason? = nil
  ) -> DeviceEvidence {
    DeviceEvidence(
      schemaVersion: 1,
      runID: "11111111-1111-4111-8111-111111111111",
      destinationHash: String(repeating: "d", count: 64),
      recordKind: recordKind,
      evidenceID: "2026-07-17-macbookprom4-onebit27b-text",
      recordedAt: Date(timeIntervalSince1970: 1_768_521_600),
      deviceClass: .init(rawValue: "Mac16,1"),
      hardwareIdentifier: "Mac16,1",
      osBuild: "25F90",
      appBuild: "1.0-1",
      appCommit: String(repeating: "a", count: 40),
      dirtyBuild: false,
      simulator: false,
      runtimeFingerprint: BonsaiRuntimeFingerprint.current,
      modelID: .oneBit27B,
      modelRevision: String(repeating: "b", count: 40),
      capabilities: capabilities,
      physicalMemoryBytes: 16 * 1_073_741_824,
      contextTokens: 4_096,
      imageDetail: .notApplicable,
      coldLoadMilliseconds: 2_100,
      warmLoadMilliseconds: 480,
      timeToFirstTokenMilliseconds: 930,
      promptTokensPerSecond: promptTokensPerSecond,
      generatedTokensPerSecond: generatedTokensPerSecond,
      peakMemoryBytes: 7 * 1_073_741_824,
      thermalTransitions: [.nominal, .fair],
      batteryDeltaPercent: 4,
      batteryMeasurement: .init(
        available: true, startPercent: 90, endPercent: 94,
        deltaPercent: 4, unavailableReason: nil),
      cancellationResult: .completedWithinDeadline,
      outcome: outcome,
      pressureTermination: pressureTermination,
      offlineProof: offlineProof,
      scenarioResults: scenarioResults,
      unsupportedReason: unsupportedReason
    )
  }

  private static let requiredScenarioResults: [DeviceEvidence.ScenarioResult] = [
    .init(scenario: .text, capability: .textGeneration, outcome: .passed,
          completion: "stop", elapsedMilliseconds: 10),
    .init(scenario: .thinking, capability: .thinking, outcome: .passed,
          completion: "stop", elapsedMilliseconds: 10),
    .init(scenario: .cancel, capability: nil, outcome: .passed,
          completion: "cancelled", elapsedMilliseconds: 10),
    .init(scenario: .calculator, capability: .toolCalling, outcome: .passed,
          completion: "tool_round_trip", elapsedMilliseconds: 10),
    .init(scenario: .date, capability: .toolCalling, outcome: .passed,
          completion: "tool_round_trip", elapsedMilliseconds: 10),
    .init(scenario: .device, capability: .toolCalling, outcome: .passed,
          completion: "tool_round_trip", elapsedMilliseconds: 10),
    .init(scenario: .notes, capability: .toolCalling, outcome: .passed,
          completion: "approved_tool_round_trip", elapsedMilliseconds: 10),
    .init(scenario: .offline, capability: nil, outcome: .passed,
          completion: "external_proof_bound", elapsedMilliseconds: 10),
    .init(scenario: .loadUnload, capability: nil, outcome: .passed,
          completion: "three_cycles", elapsedMilliseconds: 10)
  ]

  private static func descriptor() -> ModelDescriptor {
    do {
      let file = try ModelManifest.File.validated(
        path: "model.safetensors", sizeBytes: 1,
        sha256: String(repeating: "c", count: 64), role: .weight, isOptional: false)
      let manifest = try ModelManifest.validated(
        id: .oneBit27B, repository: "example/model",
        revision: String(repeating: "b", count: 40), files: [file])
      return try ModelDescriptor.validated(
        id: .oneBit27B, family: .bonsai, displayName: "Bonsai",
        manifest: manifest,
        requirements: .init(capabilities: [.textGeneration],
                            minimumPhysicalMemoryBytes: 8 * 1_073_741_824,
                            storageSafetyMarginBytes: 1))
    } catch {
      preconditionFailure("Fixture must remain valid: \(error)")
    }
  }
}
// swiftlint:enable type_body_length
