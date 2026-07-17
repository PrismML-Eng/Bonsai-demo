import Foundation

// The release artifact's closed field allowlist and validation intentionally stay auditable together.
// swiftlint:disable type_body_length

/// Content-free measurements used only to decide whether a model capability is releasable.
/// The closed schema intentionally has no prompt, response, attachment, note, path, or URL field.
struct DeviceEvidence: Codable, Equatable, Sendable {
  enum RecordKind: String, Codable, Equatable, Sendable { case supported, unsupported }
  enum Scenario: String, Codable, Hashable, Sendable {
    case text, thinking, cancel, calculator, date, device, notes
    case visionFast = "vision-fast"
    case visionFull = "vision-full"
    case offline
    case loadUnload = "load-unload"
  }
  enum ScenarioOutcome: String, Codable, Equatable, Sendable {
    case passed, unsupported, infrastructureFailure
  }
  struct ScenarioResult: Codable, Equatable, Sendable {
    let scenario: Scenario
    let capability: ModelCapability?
    let outcome: ScenarioOutcome
    let completion: String
    let elapsedMilliseconds: Int
  }
  enum ImageDetail: String, Codable, Sendable { case notApplicable, fast1024, fullDetail }
  enum CancellationResult: String, Codable, Sendable {
    case notExercised, completedWithinDeadline, timedOut, processTerminated
  }
  enum Outcome: String, Codable, Sendable { case completed, cancelledAsExpected, failed }
  enum UnsupportedReason: String, Codable, Equatable, Sendable {
    case modelLoadFailure = "model_load_failure"
  }

  struct OfflineProof: Codable, Equatable, Sendable {
    let airplaneModeEnabled: Bool
    let observedOutboundRequestCount: Int
    let inspectionMethod: String
    let networkCaptureSHA256: String
    let sourceAuditSHA256: String
  }
  struct BatteryMeasurement: Codable, Equatable, Sendable {
    let available: Bool
    let startPercent: Double?
    let endPercent: Double?
    let deltaPercent: Double?
    let unavailableReason: String?
  }

  enum ValidationError: Error, Equatable, Sendable {
    case missing(String)
    case invalid(String)
    case unknownFields([String])
    case pressureTermination
    case unsuccessfulOutcome
    case cancellationIncomplete
    case offlineProofIncomplete
    case incompleteScenario(String)
  }

  let schemaVersion: Int?
  let runID: String?
  let destinationHash: String?
  let recordKind: RecordKind?
  let evidenceID: String?
  let recordedAt: Date?
  let deviceClass: DeviceClass?
  let hardwareIdentifier: String?
  let osBuild: String?
  let appBuild: String?
  let appCommit: String?
  let dirtyBuild: Bool?
  let simulator: Bool?
  let runtimeFingerprint: String?
  let modelID: ModelID?
  let modelRevision: String?
  let capabilities: Set<ModelCapability>?
  let physicalMemoryBytes: Int?
  let contextTokens: Int?
  let imageDetail: ImageDetail?
  let coldLoadMilliseconds: Int?
  let warmLoadMilliseconds: Int?
  let timeToFirstTokenMilliseconds: Int?
  let promptTokensPerSecond: Double?
  let generatedTokensPerSecond: Double?
  let peakMemoryBytes: Int?
  let thermalTransitions: [ResourceThermalState]?
  let batteryDeltaPercent: Double?
  let batteryMeasurement: BatteryMeasurement?
  let cancellationResult: CancellationResult?
  let outcome: Outcome?
  let pressureTermination: Bool?
  let offlineProof: OfflineProof?
  let scenarioResults: [ScenarioResult]?
  let unsupportedReason: UnsupportedReason?

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion, runID, destinationHash, recordKind
    case evidenceID, recordedAt, deviceClass, hardwareIdentifier
    case osBuild, appBuild, appCommit, dirtyBuild, simulator, runtimeFingerprint
    case modelID, modelRevision, capabilities
    case physicalMemoryBytes, contextTokens, imageDetail, coldLoadMilliseconds
    case warmLoadMilliseconds, timeToFirstTokenMilliseconds, promptTokensPerSecond
    case generatedTokensPerSecond, peakMemoryBytes, thermalTransitions
    case batteryDeltaPercent, batteryMeasurement, cancellationResult, outcome
    case pressureTermination, offlineProof
    case scenarioResults, unsupportedReason
  }

  init(
    schemaVersion: Int?, runID: String?, destinationHash: String?, recordKind: RecordKind?,
    evidenceID: String?, recordedAt: Date?, deviceClass: DeviceClass?,
    hardwareIdentifier: String?, osBuild: String?, appBuild: String?, appCommit: String?,
    dirtyBuild: Bool?, simulator: Bool?, runtimeFingerprint: String?,
    modelID: ModelID?, modelRevision: String?, capabilities: Set<ModelCapability>?,
    physicalMemoryBytes: Int?, contextTokens: Int?, imageDetail: ImageDetail?,
    coldLoadMilliseconds: Int?, warmLoadMilliseconds: Int?,
    timeToFirstTokenMilliseconds: Int?, promptTokensPerSecond: Double?,
    generatedTokensPerSecond: Double?, peakMemoryBytes: Int?,
    thermalTransitions: [ResourceThermalState]?, batteryDeltaPercent: Double?,
    batteryMeasurement: BatteryMeasurement?,
    cancellationResult: CancellationResult?, outcome: Outcome?, pressureTermination: Bool?,
    offlineProof: OfflineProof?, scenarioResults: [ScenarioResult]?,
    unsupportedReason: UnsupportedReason?
  ) {
    self.schemaVersion = schemaVersion
    self.runID = runID
    self.destinationHash = destinationHash
    self.recordKind = recordKind
    self.evidenceID = evidenceID
    self.recordedAt = recordedAt
    self.deviceClass = deviceClass
    self.hardwareIdentifier = hardwareIdentifier
    self.osBuild = osBuild
    self.appBuild = appBuild
    self.appCommit = appCommit
    self.dirtyBuild = dirtyBuild
    self.simulator = simulator
    self.runtimeFingerprint = runtimeFingerprint
    self.modelID = modelID
    self.modelRevision = modelRevision
    self.capabilities = capabilities
    self.physicalMemoryBytes = physicalMemoryBytes
    self.contextTokens = contextTokens
    self.imageDetail = imageDetail
    self.coldLoadMilliseconds = coldLoadMilliseconds
    self.warmLoadMilliseconds = warmLoadMilliseconds
    self.timeToFirstTokenMilliseconds = timeToFirstTokenMilliseconds
    self.promptTokensPerSecond = promptTokensPerSecond
    self.generatedTokensPerSecond = generatedTokensPerSecond
    self.peakMemoryBytes = peakMemoryBytes
    self.thermalTransitions = thermalTransitions
    self.batteryDeltaPercent = batteryDeltaPercent
    self.batteryMeasurement = batteryMeasurement
    self.cancellationResult = cancellationResult
    self.outcome = outcome
    self.pressureTermination = pressureTermination
    self.offlineProof = offlineProof
    self.scenarioResults = scenarioResults
    self.unsupportedReason = unsupportedReason
  }

  init(from decoder: Decoder) throws {
    let dynamic = try decoder.container(keyedBy: EvidenceCodingKey.self)
    let expected = Set(CodingKeys.allCases.map(\.rawValue))
    let unknown = dynamic.allKeys.map(\.stringValue).filter { !expected.contains($0) }.sorted()
    guard unknown.isEmpty else { throw ValidationError.unknownFields(unknown) }
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
    runID = try values.decodeIfPresent(String.self, forKey: .runID)
    destinationHash = try values.decodeIfPresent(String.self, forKey: .destinationHash)
    recordKind = try values.decodeIfPresent(RecordKind.self, forKey: .recordKind)
    evidenceID = try values.decodeIfPresent(String.self, forKey: .evidenceID)
    recordedAt = try values.decodeIfPresent(Date.self, forKey: .recordedAt)
    deviceClass = try values.decodeIfPresent(DeviceClass.self, forKey: .deviceClass)
    hardwareIdentifier = try values.decodeIfPresent(String.self, forKey: .hardwareIdentifier)
    osBuild = try values.decodeIfPresent(String.self, forKey: .osBuild)
    appBuild = try values.decodeIfPresent(String.self, forKey: .appBuild)
    appCommit = try values.decodeIfPresent(String.self, forKey: .appCommit)
    dirtyBuild = try values.decodeIfPresent(Bool.self, forKey: .dirtyBuild)
    simulator = try values.decodeIfPresent(Bool.self, forKey: .simulator)
    runtimeFingerprint = try values.decodeIfPresent(String.self, forKey: .runtimeFingerprint)
    modelID = try values.decodeIfPresent(ModelID.self, forKey: .modelID)
    modelRevision = try values.decodeIfPresent(String.self, forKey: .modelRevision)
    capabilities = try values.decodeIfPresent(Set<ModelCapability>.self, forKey: .capabilities)
    physicalMemoryBytes = try values.decodeIfPresent(Int.self, forKey: .physicalMemoryBytes)
    contextTokens = try values.decodeIfPresent(Int.self, forKey: .contextTokens)
    imageDetail = try values.decodeIfPresent(ImageDetail.self, forKey: .imageDetail)
    coldLoadMilliseconds = try values.decodeIfPresent(Int.self, forKey: .coldLoadMilliseconds)
    warmLoadMilliseconds = try values.decodeIfPresent(Int.self, forKey: .warmLoadMilliseconds)
    timeToFirstTokenMilliseconds = try values.decodeIfPresent(
      Int.self, forKey: .timeToFirstTokenMilliseconds)
    promptTokensPerSecond = try values.decodeIfPresent(Double.self, forKey: .promptTokensPerSecond)
    generatedTokensPerSecond = try values.decodeIfPresent(
      Double.self, forKey: .generatedTokensPerSecond)
    peakMemoryBytes = try values.decodeIfPresent(Int.self, forKey: .peakMemoryBytes)
    thermalTransitions = try values.decodeIfPresent(
      [ResourceThermalState].self, forKey: .thermalTransitions)
    batteryDeltaPercent = try values.decodeIfPresent(Double.self, forKey: .batteryDeltaPercent)
    batteryMeasurement = try values.decodeIfPresent(
      BatteryMeasurement.self, forKey: .batteryMeasurement)
    cancellationResult = try values.decodeIfPresent(
      CancellationResult.self, forKey: .cancellationResult)
    outcome = try values.decodeIfPresent(Outcome.self, forKey: .outcome)
    pressureTermination = try values.decodeIfPresent(Bool.self, forKey: .pressureTermination)
    offlineProof = try values.decodeIfPresent(OfflineProof.self, forKey: .offlineProof)
    scenarioResults = try values.decodeIfPresent([ScenarioResult].self, forKey: .scenarioResults)
    unsupportedReason = try values.decodeIfPresent(UnsupportedReason.self, forKey: .unsupportedReason)
  }

  // Every field is checked explicitly so adding a metric cannot silently loosen the release gate.
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  func validateForRelease() throws {
    guard schemaVersion != nil else { throw ValidationError.missing("schemaVersion") }
    guard schemaVersion == 1 else { throw ValidationError.invalid("schemaVersion") }
    try requireNonempty(runID, "runID")
    guard UUID(uuidString: runID ?? "") != nil else { throw ValidationError.invalid("runID") }
    guard let destinationHash else { throw ValidationError.missing("destinationHash") }
    guard isLowercaseHex(destinationHash, count: 64) else {
      throw ValidationError.invalid("destinationHash")
    }
    guard let recordKind else { throw ValidationError.missing("recordKind") }
    guard let scenarioResults else { throw ValidationError.missing("scenarioResults") }
    try validateScenarioResults(scenarioResults, recordKind: recordKind)
    try requireNonempty(evidenceID, "evidenceID")
    guard recordedAt != nil else { throw ValidationError.missing("recordedAt") }
    guard let deviceClass else { throw ValidationError.missing("deviceClass") }
    try requireNonempty(hardwareIdentifier, "hardwareIdentifier")
    guard deviceClass.rawValue == hardwareIdentifier else {
      throw ValidationError.invalid("deviceClass")
    }
    try requireNonempty(osBuild, "osBuild")
    try requireNonempty(appBuild, "appBuild")
    guard let appCommit else { throw ValidationError.missing("appCommit") }
    guard isLowercaseHex(appCommit, count: 40) else { throw ValidationError.invalid("appCommit") }
    guard let dirtyBuild else { throw ValidationError.missing("dirtyBuild") }
    guard !dirtyBuild else { throw ValidationError.invalid("dirtyBuild") }
    guard let simulator else { throw ValidationError.missing("simulator") }
    guard !simulator else { throw ValidationError.invalid("simulator") }
    guard let runtimeFingerprint else { throw ValidationError.missing("runtimeFingerprint") }
    guard isLowercaseHex(runtimeFingerprint, count: 64) else {
      throw ValidationError.invalid("runtimeFingerprint")
    }
    guard modelID != nil else { throw ValidationError.missing("modelID") }
    guard let modelRevision else { throw ValidationError.missing("modelRevision") }
    guard isLowercaseHex(modelRevision, count: 40) else {
      throw ValidationError.invalid("modelRevision")
    }
    guard let capabilities else { throw ValidationError.missing("capabilities") }
    if recordKind == .unsupported {
      guard unsupportedReason != nil else { throw ValidationError.missing("unsupportedReason") }
      guard capabilities.isEmpty else { throw ValidationError.invalid("capabilities") }
      guard scenarioResults.contains(where: { $0.outcome == .unsupported }) else {
        throw ValidationError.incompleteScenario("unsupported")
      }
      return
    }
    guard !capabilities.isEmpty else { throw ValidationError.invalid("capabilities") }
    try requirePositive(physicalMemoryBytes, "physicalMemoryBytes")
    try requirePositive(contextTokens, "contextTokens")
    guard imageDetail != nil else { throw ValidationError.missing("imageDetail") }
    try requireNonnegative(coldLoadMilliseconds, "coldLoadMilliseconds")
    try requireNonnegative(warmLoadMilliseconds, "warmLoadMilliseconds")
    try requireNonnegative(timeToFirstTokenMilliseconds, "timeToFirstTokenMilliseconds")
    try requireFinitePositive(promptTokensPerSecond, "promptTokensPerSecond")
    try requireFinitePositive(generatedTokensPerSecond, "generatedTokensPerSecond")
    try requirePositive(peakMemoryBytes, "peakMemoryBytes")
    guard let thermalTransitions else { throw ValidationError.missing("thermalTransitions") }
    guard !thermalTransitions.isEmpty else { throw ValidationError.invalid("thermalTransitions") }
    guard let batteryDeltaPercent else { throw ValidationError.missing("batteryDeltaPercent") }
    guard batteryDeltaPercent.isFinite, (-100...100).contains(batteryDeltaPercent) else {
      throw ValidationError.invalid("batteryDeltaPercent")
    }
    guard let batteryMeasurement else { throw ValidationError.missing("batteryMeasurement") }
    if batteryMeasurement.available {
      guard let start = batteryMeasurement.startPercent, let end = batteryMeasurement.endPercent,
            let delta = batteryMeasurement.deltaPercent,
            start.isFinite, end.isFinite, delta.isFinite,
            abs((end - start) - delta) < 0.001,
            abs(delta - batteryDeltaPercent) < 0.001 else {
        throw ValidationError.invalid("batteryMeasurement")
      }
    } else {
      guard batteryMeasurement.startPercent == nil, batteryMeasurement.endPercent == nil,
            batteryMeasurement.deltaPercent == nil,
            !(batteryMeasurement.unavailableReason ?? "").isEmpty else {
        throw ValidationError.invalid("batteryMeasurement")
      }
    }
    guard let cancellationResult else { throw ValidationError.missing("cancellationResult") }
    guard cancellationResult == .completedWithinDeadline else {
      throw ValidationError.cancellationIncomplete
    }
    guard let outcome else { throw ValidationError.missing("outcome") }
    guard outcome == .completed || outcome == .cancelledAsExpected else {
      throw ValidationError.unsuccessfulOutcome
    }
    guard let pressureTermination else { throw ValidationError.missing("pressureTermination") }
    guard !pressureTermination else { throw ValidationError.pressureTermination }
    guard let offlineProof else { throw ValidationError.missing("offlineProof") }
    guard offlineProof.airplaneModeEnabled,
          offlineProof.observedOutboundRequestCount == 0,
          !offlineProof.inspectionMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          isLowercaseHex(offlineProof.networkCaptureSHA256, count: 64),
          isLowercaseHex(offlineProof.sourceAuditSHA256, count: 64)
    else { throw ValidationError.offlineProofIncomplete }
  }

  private func validateScenarioResults(
    _ results: [ScenarioResult], recordKind: RecordKind
  ) throws {
    guard !results.isEmpty else { throw ValidationError.invalid("scenarioResults") }
    var seen: Set<Scenario> = []
    for result in results {
      guard seen.insert(result.scenario).inserted,
            result.elapsedMilliseconds >= 0,
            !result.completion.isEmpty else { throw ValidationError.invalid("scenarioResults") }
    }
    guard recordKind == .supported else { return }
    let required: Set<Scenario> = [
      .text, .cancel, .calculator, .date, .device, .notes, .offline, .loadUnload
    ]
    for scenario in required where results.first(where: { $0.scenario == scenario })?.outcome != .passed {
      throw ValidationError.incompleteScenario(scenario.rawValue)
    }
    let capabilityScenarios: [ModelCapability: Set<Scenario>] = [
      .textGeneration: [.text], .thinking: [.thinking],
      .toolCalling: [.calculator, .date, .device, .notes],
      .vision: [.visionFast, .visionFull]
    ]
    for capability in capabilities ?? [] {
      for scenario in capabilityScenarios[capability] ?? []
      where results.first(where: { $0.scenario == scenario })?.outcome != .passed {
        throw ValidationError.incompleteScenario(scenario.rawValue)
      }
    }
  }

  private func requireNonempty(_ value: String?, _ field: String) throws {
    guard let value else { throw ValidationError.missing(field) }
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ValidationError.invalid(field)
    }
  }

  private func requirePositive(_ value: Int?, _ field: String) throws {
    guard let value else { throw ValidationError.missing(field) }
    guard value > 0 else { throw ValidationError.invalid(field) }
  }

  private func requireNonnegative(_ value: Int?, _ field: String) throws {
    guard let value else { throw ValidationError.missing(field) }
    guard value >= 0 else { throw ValidationError.invalid(field) }
  }

  private func requireFinitePositive(_ value: Double?, _ field: String) throws {
    guard let value else { throw ValidationError.missing(field) }
    guard value.isFinite, value > 0 else { throw ValidationError.invalid(field) }
  }
}

private struct EvidenceCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
// swiftlint:enable type_body_length
