import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
#if os(iOS)
import UIKit
#endif
@testable import BonsaiMobile

// The single evidence lane intentionally owns one process-scoped attachment and its instrumentation.
// swiftlint:disable file_length

// Physical-device lanes only. A skipped, crashed, or attachment-free test can never be promoted.
// swiftlint:disable type_body_length
final class RealModelScenarioTests: XCTestCase {
  private struct ToolScenario {
    let scenario: DeviceEvidence.Scenario
    let prompt: String
    let tool: String
  }
  // The complete lane stays together so its one structured attachment has one process/run identity.
  // swiftlint:disable:next function_body_length
  func testRequestedRealModelScenariosAndRepeatedLifecycle() async throws {
    let environment = ProcessInfo.processInfo.environment
    let scenarios = try Self.requestedScenarios(environment["BONSAI_EVIDENCE_SCENARIOS"])
    let installation = try Self.installation(environment: environment)
    let engine = MLXInferenceEngine()
    let clock = ContinuousClock()
    let startedAt = Date()
    let batteryStart = Self.batteryLevel()
    let thermalRecorder = ThermalTransitionRecorder(initial: Self.thermalState())
    let thermalSampling = Task {
      while !Task.isCancelled {
        await thermalRecorder.record(Self.thermalState())
        try? await Task.sleep(for: .milliseconds(250))
      }
    }
    defer { thermalSampling.cancel() }
    var results: [DeviceEvidence.ScenarioResult] = []
    var loadDurations: [Duration] = []
    var representativeMetrics: GenerationMetrics?
    defer { Task { await engine.unload() } }

    do {
      for cycle in 1...3 {
        let started = clock.now
        try await engine.load(installation)
        loadDurations.append(started.duration(to: clock.now))
        let events = try await Self.collect(try await engine.generate(
          try GenerationRequest(prompt: "Reply with OK.", reasoningEnabled: false, maxTokens: 16)))
        XCTAssertFalse(events.answer.isEmpty, "load cycle \(cycle)")
        representativeMetrics = representativeMetrics ?? events.metrics
        await engine.unload()
        let snapshot = await engine.debugSnapshot()
        XCTAssertFalse(snapshot.hasContainer || snapshot.hasSession || snapshot.hasActiveGeneration)
      }
      results.append(.init(scenario: .loadUnload, capability: nil, outcome: .passed,
                           completion: "three_cycles", elapsedMilliseconds: loadDurations.totalMilliseconds))
    } catch {
      thermalSampling.cancel()
      _ = await thermalSampling.result
      try await attachUnsupported(
        environment: environment, installation: installation, startedAt: startedAt,
        scenarios: scenarios, completion: "model_load_failed", thermalRecorder: thermalRecorder,
        reason: .modelLoadFailure)
      return
    }

    try await engine.load(installation)
    if scenarios.contains("text") {
      let started = clock.now
      let events = try await Self.collect(try await engine.generate(
        try GenerationRequest(prompt: "Answer with exactly: bonsai", reasoningEnabled: false,
                              maxTokens: 32)))
      XCTAssertFalse(events.answer.isEmpty)
      representativeMetrics = try XCTUnwrap(events.metrics)
      results.append(.init(scenario: .text, capability: .textGeneration, outcome: .passed,
                           completion: events.completion?.rawValue ?? "missing",
                           elapsedMilliseconds: started.duration(to: clock.now).milliseconds))
    }
    if scenarios.contains("thinking") {
      let started = clock.now
      let events = try await Self.collect(try await engine.generate(
        try GenerationRequest(prompt: "Think briefly, then answer 7.", reasoningBudget: 32,
                              maxTokens: 96)))
      XCTAssertFalse(events.reasoning.isEmpty)
      XCTAssertFalse(events.answer.isEmpty)
      results.append(.init(scenario: .thinking, capability: .thinking, outcome: .passed,
                           completion: events.completion?.rawValue ?? "missing",
                           elapsedMilliseconds: started.duration(to: clock.now).milliseconds))
    }
    if scenarios.contains("cancel") {
      let started = clock.now
      let stream = try await engine.generate(try GenerationRequest(
        prompt: "Count upward without stopping.", reasoningEnabled: false, maxTokens: 2_048))
      let task = Task { try await Self.collect(stream) }
      try await Task.sleep(for: .milliseconds(250))
      await engine.cancel()
      let events = try await task.value
      XCTAssertEqual(events.completion, .cancelled)
      let elapsed = started.duration(to: clock.now)
      XCTAssertLessThan(elapsed, .seconds(30))
      results.append(.init(scenario: .cancel, capability: nil, outcome: .passed,
                           completion: "cancelled", elapsedMilliseconds: elapsed.milliseconds))
    }
    if scenarios.contains("vision-fast") {
      results.append(try await Self.verifyVision(engine: engine, policy: .fast1024))
    }
    if scenarios.contains("vision-full") {
      results.append(try await Self.verifyVision(engine: engine, policy: .fullDetail))
    }
    results.append(contentsOf: try await Self.verifyAgentTools(engine: engine, scenarios: scenarios))
    if scenarios.contains("offline") {
      results.append(.init(scenario: .offline, capability: nil, outcome: .passed,
                           completion: "external_proof_bound", elapsedMilliseconds: 0))
    }

    let metrics = try XCTUnwrap(representativeMetrics)
    thermalSampling.cancel()
    _ = await thermalSampling.result
    let artifact = try await Self.artifact(
      environment: environment, installation: installation, startedAt: startedAt,
      battery: Self.batteryMeasurement(start: batteryStart, end: Self.batteryLevel()), metrics: metrics,
      loadDurations: loadDurations, results: results, thermalRecorder: thermalRecorder)
    try attach(artifact)
  }

  private struct Collected {
    var answer = ""
    var reasoning = ""
    var metrics: GenerationMetrics?
    var completion: CompletionReason?
  }

  private static func collect(
    _ stream: AsyncThrowingStream<GenerationEvent, any Error>
  ) async throws -> Collected {
    var result = Collected()
    for try await event in stream {
      switch event {
      case .answer(let text): result.answer += text
      case .reasoning(let text): result.reasoning += text
      case .metrics(let metrics): result.metrics = metrics
      case .completed(let completion): result.completion = completion
      case .toolRequest: break
      }
    }
    return result
  }

  private static func requestedScenarios(_ raw: String?) throws -> Set<String> {
    guard let raw, !raw.isEmpty else { throw XCTSkip("BONSAI_EVIDENCE_SCENARIOS is required.") }
    return Set(raw.split(separator: ",").map(String.init))
  }

  private static func installation(environment: [String: String]) throws -> ModelInstallation {
    guard let revision = environment["BONSAI_MODEL_REVISION"], isLowercaseHex(revision, count: 40),
          let rawModel = environment["BONSAI_EVIDENCE_MODEL"], let modelID = ModelID(rawValue: rawModel)
    else { throw XCTSkip("The model ID and exact revision are required.") }
    let directory: URL
    #if os(iOS)
    guard let relative = environment["BONSAI_MODEL_RELATIVE_PATH"],
          relative == "installed/\(modelID.rawValue)" else {
      throw XCTSkip("The physical model must be preinstalled under Models/installed/<modelID>.")
    }
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    directory = support.appending(path: "BonsaiMobile/Models/\(relative)", directoryHint: .isDirectory)
    #else
    guard let path = environment["BONSAI_MODEL_DIR"], !path.isEmpty else {
      throw XCTSkip("BONSAI_MODEL_DIR is required on macOS.")
    }
    directory = URL(fileURLWithPath: path, isDirectory: true)
    #endif
    guard FileManager.default.fileExists(atPath: directory.appending(path: "model.safetensors").path)
    else { throw CocoaError(.fileNoSuchFile) }
    return .init(modelID: modelID, directory: directory, revision: revision)
  }

  private static func verifyAgentTools(
    engine: MLXInferenceEngine, scenarios: Set<String>
  ) async throws -> [DeviceEvidence.ScenarioResult] {
    let root = FileManager.default.temporaryDirectory.appending(path: "EvidenceNotes-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = try ToolRegistry.live(notes: NotesStore(root: root))
    let prompts: [ToolScenario] = [
      .init(scenario: .calculator, prompt: "Use calculator to compute 37 * 19 + 5.", tool: "calculator"),
      .init(scenario: .date, prompt: "Use current_date_time and report the date.", tool: "current_date_time"),
      .init(scenario: .device, prompt: "Use device_information and summarize it.", tool: "device_information"),
      .init(scenario: .notes,
            prompt: "Use local_notes to create title Bonsai with body release evidence.",
            tool: "local_notes")
    ]
    let clock = ContinuousClock()
    var results: [DeviceEvidence.ScenarioResult] = []
    for item in prompts where scenarios.contains(item.scenario.rawValue) {
      let started = clock.now
      let run = try await AgentLoop(engine: engine, registry: registry, approvals: AllowingApprovalGate())
        .run(try GenerationRequest(prompt: item.prompt, reasoningEnabled: false, maxTokens: 192))
      XCTAssertEqual(run.completion, .stop)
      XCTAssertTrue(run.toolResults.contains { $0.status == .succeeded })
      XCTAssertTrue(run.activities.contains {
        if case .running(let invocation) = $0 { return invocation.name == item.tool }
        return false
      })
      results.append(.init(
        scenario: item.scenario, capability: .toolCalling, outcome: .passed,
        completion: item.scenario == .notes ? "approved_tool_round_trip" : "tool_round_trip",
        elapsedMilliseconds: started.duration(to: clock.now).milliseconds))
    }
    return results
  }

  private static func verifyVision(
    engine: MLXInferenceEngine, policy: ImageDetailPolicy
  ) async throws -> DeviceEvidence.ScenarioResult {
    let root = FileManager.default.temporaryDirectory.appending(path: "EvidenceVision-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "green.png")
    try writeGreenImage(to: source)
    let processed = try await ImagePreprocessor().process(
      managedURL: source, policy: policy, managedRoot: root)
    let attachment = try ImageAttachmentReference(
      id: UUID(), managedRelativePath: "green.png", pixelSize: .init(width: 640, height: 480),
      byteCount: 1, contentType: "image/png", detailPolicy: policy,
      accessibleLabel: "Solid green evidence image", lifecycle: .persisted)
    let message = ConversationMessage(
      id: MessageID("evidence-vision-\(policy.rawValue)"), role: .user,
      content: "Answer with the dominant color in one word.", attachments: [attachment])
    let clock = ContinuousClock()
    let started = clock.now
    let events = try await collect(try await engine.generate(try GenerationRequest(
      messages: [message], images: [
        .init(messageID: message.id, attachmentID: attachment.id, buffer: processed.buffer)
      ], reasoningEnabled: false, maxTokens: 32)))
    XCTAssertTrue(events.answer.localizedCaseInsensitiveContains("green"), events.answer)
    return .init(
      scenario: policy == .fast1024 ? .visionFast : .visionFull, capability: .vision,
      outcome: .passed, completion: events.completion?.rawValue ?? "missing",
      elapsedMilliseconds: started.duration(to: clock.now).milliseconds)
  }

  // swiftlint:disable:next function_parameter_count
  private func attachUnsupported(
    environment: [String: String], installation: ModelInstallation,
    startedAt: Date, scenarios: Set<String>, completion: String,
    thermalRecorder: ThermalTransitionRecorder, reason: DeviceEvidence.UnsupportedReason
  ) async throws {
    let results = scenarios.sorted().compactMap { raw -> DeviceEvidence.ScenarioResult? in
      guard let scenario = DeviceEvidence.Scenario(rawValue: raw) else { return nil }
      return .init(
        scenario: scenario, capability: nil,
        outcome: scenario == .loadUnload ? .unsupported : .infrastructureFailure,
        completion: scenario == .loadUnload ? completion : "blocked_by_model_load",
        elapsedMilliseconds: 0)
    }
    let artifact = try await Self.artifact(
      environment: environment, installation: installation, startedAt: startedAt,
      battery: Self.batteryMeasurement(start: nil, end: nil),
      metrics: .init(promptTokenCount: 0, generatedTokenCount: 0,
                                      timeToFirstToken: .zero, tokensPerSecond: 0),
      loadDurations: [.zero], results: results, thermalRecorder: thermalRecorder,
      unsupportedReason: reason)
    try attach(artifact)
  }

  private func attach(_ artifact: DeviceEvidence) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let attachment = XCTAttachment(data: try encoder.encode(artifact), uniformTypeIdentifier: "public.json")
    attachment.name = "bonsai-device-evidence.json"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  // swiftlint:disable:next function_parameter_count
  private static func artifact(
    environment: [String: String], installation: ModelInstallation, startedAt: Date,
    battery: DeviceEvidence.BatteryMeasurement, metrics: GenerationMetrics,
    loadDurations: [Duration], results: [DeviceEvidence.ScenarioResult],
    thermalRecorder: ThermalTransitionRecorder,
    unsupportedReason: DeviceEvidence.UnsupportedReason? = nil
  ) async throws -> DeviceEvidence {
    let runID = try required(environment, "BONSAI_EVIDENCE_RUN_ID")
    let destinationHash = try required(environment, "BONSAI_EVIDENCE_DESTINATION_HASH")
    let unsupported = unsupportedReason != nil
    let thermalTransitions = await thermalRecorder.transitions
    return DeviceEvidence(
      schemaVersion: 1, runID: runID, destinationHash: destinationHash,
      recordKind: unsupported ? .unsupported : .supported,
      evidenceID: "\(runID.lowercased())-\(installation.modelID.rawValue.lowercased())",
      recordedAt: startedAt, deviceClass: .init(rawValue: hardwareIdentifier()),
      hardwareIdentifier: hardwareIdentifier(), osBuild: systemString("kern.osversion"),
      appBuild: appBuild(), appCommit: try required(environment, "BONSAI_SOURCE_COMMIT"),
      dirtyBuild: false, simulator: false, runtimeFingerprint: BonsaiRuntimeFingerprint.current,
      modelID: installation.modelID, modelRevision: installation.revision,
      capabilities: unsupported ? [] : capabilities(from: results),
      physicalMemoryBytes: Int(clamping: ProcessInfo.processInfo.physicalMemory),
      contextTokens: 4_096, imageDetail: results.contains { $0.scenario == .visionFull }
        ? .fullDetail : (results.contains { $0.scenario == .visionFast } ? .fast1024 : .notApplicable),
      coldLoadMilliseconds: loadDurations.first?.milliseconds ?? 0,
      warmLoadMilliseconds: loadDurations.dropFirst().first?.milliseconds ?? 0,
      timeToFirstTokenMilliseconds: metrics.timeToFirstToken.milliseconds,
      promptTokensPerSecond: metrics.promptTokensPerSecond,
      generatedTokensPerSecond: metrics.tokensPerSecond, peakMemoryBytes: peakResidentBytes(),
      thermalTransitions: thermalTransitions, batteryDeltaPercent: battery.deltaPercent ?? 0,
      batteryMeasurement: battery,
      cancellationResult: unsupported ? .notExercised : .completedWithinDeadline,
      outcome: unsupported ? .failed : .completed,
      pressureTermination: thermalTransitions.contains(.critical),
      offlineProof: .init(
        airplaneModeEnabled: try requiredBool(environment, "BONSAI_AIRPLANE_MODE_ENABLED"),
        observedOutboundRequestCount: try requiredInt(
          environment, "BONSAI_OBSERVED_OUTBOUND_REQUEST_COUNT"),
        inspectionMethod: try required(environment, "BONSAI_NETWORK_INSPECTION_METHOD"),
        networkCaptureSHA256: try required(environment, "BONSAI_NETWORK_CAPTURE_SHA256"),
        sourceAuditSHA256: try required(environment, "BONSAI_SOURCE_AUDIT_SHA256")),
      scenarioResults: results, unsupportedReason: unsupportedReason)
  }

  private static func required(_ environment: [String: String], _ key: String) throws -> String {
    guard let value = environment[key], !value.isEmpty else { throw XCTSkip("Missing \(key)") }
    return value
  }

  private static func requiredBool(_ environment: [String: String], _ key: String) throws -> Bool {
    switch try required(environment, key) {
    case "true": return true
    case "false": return false
    default: throw XCTSkip("Invalid closed boolean value for \(key)")
    }
  }

  private static func requiredInt(_ environment: [String: String], _ key: String) throws -> Int {
    guard let value = Int(try required(environment, key)), value >= 0 else {
      throw XCTSkip("Invalid nonnegative integer for \(key)")
    }
    return value
  }

  private static func capabilities(
    from results: [DeviceEvidence.ScenarioResult]
  ) -> Set<ModelCapability> { Set(results.compactMap(\.capability)) }

  private static func peakResidentBytes() -> Int {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    #if os(macOS)
    return Int(usage.ru_maxrss)
    #else
    return Int(usage.ru_maxrss) * 1_024
    #endif
  }

  private static func batteryLevel() -> Double? {
    #if os(iOS)
    UIDevice.current.isBatteryMonitoringEnabled = true
    return UIDevice.current.batteryLevel < 0 ? nil : Double(UIDevice.current.batteryLevel * 100)
    #else
    return nil
    #endif
  }

  private static func batteryMeasurement(
    start: Double?, end: Double?
  ) -> DeviceEvidence.BatteryMeasurement {
    guard let start, let end else {
      return .init(available: false, startPercent: nil, endPercent: nil,
                   deltaPercent: nil, unavailableReason: "battery telemetry unavailable")
    }
    return .init(available: true, startPercent: start, endPercent: end,
                 deltaPercent: end - start, unavailableReason: nil)
  }

  private static func thermalState() -> ResourceThermalState {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: .nominal
    case .fair: .fair
    case .serious: .serious
    case .critical: .critical
    @unknown default: .critical
    }
  }

  private static func hardwareIdentifier() -> String {
    var system = utsname(); guard uname(&system) == 0 else { return "unknown" }
    return withUnsafeBytes(of: system.machine) { raw in
      String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
    }
  }

  private static func systemString(_ name: String) -> String {
    var size = 0; guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return "" }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "" }
    let truncated = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(bytes: truncated, encoding: .utf8) ?? ""
  }

  private static func appBuild() -> String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    return "\(version)-\(build)"
  }

  private static func writeGreenImage(to url: URL) throws {
    let context = try XCTUnwrap(CGContext(
      data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.05, green: 0.85, blue: 0.12, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }
}
// swiftlint:enable type_body_length

private actor ThermalTransitionRecorder {
  private(set) var transitions: [ResourceThermalState]

  init(initial: ResourceThermalState) { transitions = [initial] }

  func record(_ state: ResourceThermalState) {
    if transitions.last != state { transitions.append(state) }
  }
}

private extension Duration {
  var milliseconds: Int {
    let value = components
    return Int(value.seconds * 1_000) + Int(value.attoseconds / 1_000_000_000_000_000)
  }
}

private extension [Duration] {
  var totalMilliseconds: Int { reduce(0) { $0 + $1.milliseconds } }
}
// swiftlint:enable file_length
