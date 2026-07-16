# Bonsai Mobile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a native universal SwiftUI agent-chat app that runs 1-bit Bonsai-27B on qualified iPhones and runs 1-bit or Ternary-Bonsai-27B on qualified iPad/Mac hardware, with public model acquisition, vision, thinking, and safe offline tools.

**Architecture:** SwiftUI renders snapshots from actor-owned model-library and chat-session state. A narrow `InferenceEngine` protocol isolates Prism's pinned MLX Swift runtime, while model acquisition, device qualification, local persistence, and tool execution remain testable Foundation-only components. Exactly one model is resident, model support is evidence-gated, and no inference or tool call leaves the device.

**Tech Stack:** Swift 6.3, SwiftUI, Foundation, CryptoKit, PhotosUI, AVFoundation, XCTest/Swift Testing, XCUITest, XcodeGen, SwiftLint, Prism MLX Swift at `e40e0a57a6f7ad08dc3fd87ad598a7aa6407d230`, MLX Swift LM at `4ca25fd901e2db2703cbe5a6ea339b29642c754f`, ZIPFoundation, Python `huggingface_hub` for release-manifest generation.

## Global Constraints

- Minimum OS: iOS/iPadOS 17 and macOS 14.
- Keep all prompts, images, notes, tools, conversation data, and inference on device.
- Use public Hugging Face downloads with pinned revisions and SHA-256 verification; no token or account UI.
- Keep exactly one model resident.
- Default text context: 4,096 tokens.
- Default image budget: approximately 1,024 vision tokens; full detail is explicit per image.
- Reasoning effort values: Off `0`, Low `512`, Medium `2,048`, High `8,192`, Max `-1`.
- Stop an agent run after six tool turns.
- Require `Allow once` for every state-changing tool invocation.
- Never load Ternary-Bonsai-27B on iPhone.
- Device support claims require physical-device evidence; iPhone 16e is a required measurement target.
- Follow strict Red → Green → Refactor. Test doubles are allowed only at I/O/runtime boundaries; final proof uses real MLX integration and real devices.
- Preserve existing shell, llama.cpp, MLX Python, and Open WebUI demos.

## Standards Check

- Canonical sources: `AGENTS.md`, `README.md`, `VISION.md`, `TOOLS.md`, and `docs/superpowers/specs/2026-07-16-bonsai-mobile-design.md`.
- External contracts: public Prism model cards, Prism `mlx-swift` fork, and upstream `mlx-swift-lm` source inspected at the pinned revisions above.
- Alignment: this plan starts with real runtime proof, carries every EARS criterion and verification obligation into a task, and keeps unsupported hardware visibly blocked.
- Quality commands: `xcodebuild`, `swiftlint`, Python manifest tests, simulator/generic builds, and human-assisted real-device lanes.
- Pre-implementation gate: satisfied when Task 1's pinned package graph builds and the real 1-bit probe streams tokens; failure blocks Task 2 onward.

## File map

| Path | Responsibility |
|---|---|
| `mobile/project.yml` | Reproducible universal Xcode project definition |
| `mobile/Brewfile` | XcodeGen and lint toolchain |
| `mobile/scripts/bootstrap_dependencies.sh` | Fetch and patch pinned MLX dependency graph |
| `mobile/Patches/mlx-swift-lm-local-mlx.patch` | Replace upstream MLX dependency with pinned Prism local package |
| `mobile/Sources/App/` | App entry, dependency composition, adaptive navigation |
| `mobile/Sources/Domain/` | Sendable identifiers, manifests, messages, tools, errors, state |
| `mobile/Sources/ModelLibrary/` | Qualification, download/import, verification, managed storage |
| `mobile/Sources/Inference/` | Runtime protocol, MLX adapter, reasoning routing, resource monitoring |
| `mobile/Sources/Agent/` | Tool registry, calculator, device/date/notes tools, bounded loop |
| `mobile/Sources/Features/` | Quiet Garden SwiftUI feature surfaces and models |
| `mobile/Sources/Persistence/` | Atomic JSON conversation and note stores |
| `mobile/Resources/Models/manifest.json` | Generated pinned public model manifest |
| `mobile/Tests/` | Unit and integration tests, grouped by source feature |
| `mobile/UITests/` | Observable product, recovery, accessibility, and offline flows |
| `scripts/generate_mobile_model_manifest.py` | Reproducible Hugging Face manifest generator |
| `tests/test_generate_mobile_model_manifest.py` | Generator selection and failure tests |
| `docs/mobile/DEVICE-SUPPORT.md` | Evidence-backed support matrix |
| `docs/mobile/PRIVACY.md` | Local-data and network behavior |

---

### Task 1: Reproducible Xcode Foundation and Real MLX Proof

**Files:**
- Create: `mobile/Brewfile`
- Create: `mobile/project.yml`
- Create: `mobile/Config/Base.xcconfig`
- Create: `mobile/scripts/bootstrap_dependencies.sh`
- Create: `mobile/Patches/mlx-swift-lm-local-mlx.patch`
- Create: `mobile/Sources/App/BonsaiMobileApp.swift`
- Create: `mobile/Sources/Inference/RuntimeProbe.swift`
- Create: `mobile/Tests/RuntimeProbeTests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `RuntimeProbe.run(modelDirectory: URL) -> AsyncThrowingStream<String, Error>` and generated `mobile/BonsaiMobile.xcodeproj`.
- Blocks all later tasks until a real pinned MLX build and token stream succeed.

- [ ] **Step 1: Write the failing package/runtime smoke test**

```swift
import Testing
@testable import BonsaiMobile

@Suite("Runtime probe")
struct RuntimeProbeTests {
    @Test func rejectsMissingModelDirectory() async {
        let missing = URL(fileURLWithPath: "/tmp/bonsai-model-does-not-exist")
        await #expect(throws: RuntimeProbe.Error.modelDirectoryMissing) {
            for try await _ in RuntimeProbe.run(modelDirectory: missing) {}
        }
    }
}
```

- [ ] **Step 2: Run RED before the app target exists**

Run: `xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test`

Expected: FAIL because `mobile/BonsaiMobile.xcodeproj` and `RuntimeProbe` do not exist.

- [ ] **Step 3: Add the pinned dependency bootstrap**

`mobile/Brewfile`:

```ruby
brew "xcodegen"
brew "swiftlint"
```

`mobile/scripts/bootstrap_dependencies.sh` must clone the two exact SHAs into `mobile/.build-dependencies`, initialize Prism MLX submodules recursively, verify both `HEAD` values, and apply `mobile/Patches/mlx-swift-lm-local-mlx.patch`. The patch replaces:

```swift
.package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.4"))
```

with:

```swift
.package(path: "../mlx-swift")
```

Use this complete script:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/.build-dependencies"
MLX_SHA=e40e0a57a6f7ad08dc3fd87ad598a7aa6407d230
LM_SHA=4ca25fd901e2db2703cbe5a6ea339b29642c754f

clone_at() {
  local url="$1" sha="$2" destination="$3"
  if [[ ! -d "$destination/.git" ]]; then
    git clone --filter=blob:none "$url" "$destination"
  fi
  git -C "$destination" fetch --depth 1 origin "$sha"
  git -C "$destination" checkout --detach "$sha"
  test "$(git -C "$destination" rev-parse HEAD)" = "$sha"
  test -z "$(git -C "$destination" status --porcelain)"
}

mkdir -p "$DEPS"
clone_at https://github.com/PrismML-Eng/mlx-swift.git "$MLX_SHA" "$DEPS/mlx-swift"
git -C "$DEPS/mlx-swift" submodule update --init --recursive
clone_at https://github.com/ml-explore/mlx-swift-lm.git "$LM_SHA" "$DEPS/mlx-swift-lm"
git -C "$DEPS/mlx-swift-lm" apply --check "$ROOT/Patches/mlx-swift-lm-local-mlx.patch"
git -C "$DEPS/mlx-swift-lm" apply "$ROOT/Patches/mlx-swift-lm-local-mlx.patch"
```

The checked-in patch is:

```diff
diff --git a/Package.swift b/Package.swift
--- a/Package.swift
+++ b/Package.swift
@@
-.package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.4")),
+.package(path: "../mlx-swift"),
```

Add `mobile/.build-dependencies/`, `mobile/DerivedData/`, and `mobile/TestResults/` to `.gitignore`.

- [ ] **Step 4: Add XcodeGen configuration and minimal runtime adapter**

Use this `mobile/project.yml` as the starting project contract:

```yaml
name: BonsaiMobile
options:
  deploymentTarget:
    iOS: "17.0"
    macOS: "14.0"
packages:
  MLXSwiftLM:
    path: .build-dependencies/mlx-swift-lm
  ZIPFoundation:
    url: https://github.com/weichsel/ZIPFoundation.git
    exactVersion: 0.9.19
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    GCC_TREAT_WARNINGS_AS_ERRORS: YES
    SWIFT_TREAT_WARNINGS_AS_ERRORS: YES
targets:
  BonsaiMobile:
    type: application
    supportedDestinations: [iOS, macOS]
    platform: iOS
    sources: [Sources]
    resources: [Resources]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.prismml.BonsaiMobile
        INFOPLIST_KEY_CFBundleDisplayName: Bonsai
        INFOPLIST_KEY_NSCameraUsageDescription: Add a photo to a private on-device conversation.
        INFOPLIST_KEY_NSPhotoLibraryUsageDescription: Add a photo to a private on-device conversation.
    dependencies:
      - package: MLXSwiftLM
        product: MLXLLM
      - package: MLXSwiftLM
        product: MLXVLM
      - package: MLXSwiftLM
        product: MLXLMCommon
      - package: ZIPFoundation
  BonsaiMobileTests:
    type: bundle.unit-test
    supportedDestinations: [iOS, macOS]
    platform: iOS
    sources: [Tests, IntegrationTests]
    dependencies:
      - target: BonsaiMobile
  BonsaiMobileUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies:
      - target: BonsaiMobile
schemes:
  BonsaiMobile:
    build:
      targets:
        BonsaiMobile: all
        BonsaiMobileTests: [test]
        BonsaiMobileUITests: [test]
    test:
      targets: [BonsaiMobileTests, BonsaiMobileUITests]
```

If the installed XcodeGen rejects `supportedDestinations`, pin the current XcodeGen release in `Brewfile.lock.json` and update the schema usage to that release before continuing; do not hand-edit the generated project.

```swift
import Foundation
import MLXLMCommon
import MLXVLM

enum RuntimeProbe {
    enum Error: Swift.Error, Equatable { case modelDirectoryMissing }

    static func run(modelDirectory: URL) -> AsyncThrowingStream<String, Swift.Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
                    continuation.finish(throwing: Error.modelDirectoryMissing)
                    return
                }
                do {
                    let configuration = ModelConfiguration(directory: modelDirectory)
                    let container = try await VLMModelFactory.shared.loadContainer(
                        configuration: configuration)
                    let session = ChatSession(container)
                    for try await chunk in session.streamResponse(to: "Reply with exactly: bonsai ready") {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 5: Generate, build, and run GREEN**

Run:

```bash
brew bundle --file mobile/Brewfile
mobile/scripts/bootstrap_dependencies.sh
xcodegen generate --spec mobile/project.yml
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test
```

Expected: `RuntimeProbeTests` passes and the package graph contains only the local Prism `mlx-swift` identity.

- [ ] **Step 6: Run the maintained real-model proof**

Run: `BONSAI_MODEL_DIR="$PWD/models/Bonsai-27B-mlx" xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme RuntimeProbe -destination 'platform=macOS' test`

Expected: the probe loads the actual public 1-bit pack, outputs `bonsai ready`, records load/first-token/token-rate metrics, and exits successfully. If the model is absent, acquire it through the repository's existing model downloader before rerunning; do not substitute a mock.

- [ ] **Step 7: Commit the proven foundation**

```bash
git add .gitignore mobile
git commit -m "feat(mobile): prove pinned MLX runtime"
```

### Task 2: Domain Contracts, Device Qualification, and Public Manifest

**Files:**
- Create: `mobile/Sources/Domain/ModelDescriptor.swift`
- Create: `mobile/Sources/Domain/DeviceQualification.swift`
- Create: `mobile/Sources/Domain/GenerationEvent.swift`
- Create: `mobile/Sources/Domain/ToolContracts.swift`
- Create: `mobile/Sources/ModelLibrary/DeviceQualifier.swift`
- Create: `scripts/generate_mobile_model_manifest.py`
- Create: `tests/test_generate_mobile_model_manifest.py`
- Create: `mobile/Resources/Models/manifest.json`
- Create: `mobile/Tests/DeviceQualifierTests.swift`

**Interfaces:**
- Produces: `ModelDescriptor`, `ModelManifest`, `DeviceFacts`, `DeviceQualification`, and `DeviceQualifier.qualify(model:facts:evidence:)`.
- Consumes: exact OS/model constraints from the approved design.

- [ ] **Step 1: Write failing qualification tests**

```swift
@Test func ternaryIsAlwaysBlockedOnIPhone() {
    let result = DeviceQualifier.qualify(
        model: .ternary27B,
        facts: .init(platform: .iPhone, physicalMemoryGB: 16, freeStorageGB: 100),
        evidence: [.ternary27B: [.macBookProM4]])
    #expect(result == .unsupported(.ternaryProhibitedOnIPhone))
}

@Test func oneBitNeedsVerifiedDeviceEvidence() {
    let result = DeviceQualifier.qualify(
        model: .oneBit27B,
        facts: .init(platform: .iPhone, physicalMemoryGB: 8, freeStorageGB: 20),
        evidence: [:])
    #expect(result == .unverified(.deviceNotMeasured))
}
```

- [ ] **Step 2: Verify RED**

Run: `xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test -only-testing:BonsaiMobileTests/DeviceQualifierTests`

Expected: FAIL because qualification types are missing.

- [ ] **Step 3: Implement the smallest qualification precedence**

```swift
enum ModelID: String, Codable, Sendable { case oneBit27B, ternary27B }
enum Platform: String, Codable, Sendable { case iPhone, iPad, mac }
struct DeviceFacts: Equatable, Sendable {
    let platform: Platform
    let physicalMemoryGB: Int
    let freeStorageGB: Int
}
enum QualificationReason: Equatable, Sendable {
    case ternaryProhibitedOnIPhone, deviceNotMeasured, insufficientMemory, insufficientStorage
}
enum DeviceQualification: Equatable, Sendable {
    case qualified(Set<ModelCapability>), unverified(QualificationReason), unsupported(QualificationReason)
}
```

Implement precedence exactly as: platform prohibition → evidence → physical memory → storage → capability set. Use 8 GB for 1-bit and 16 GB for Ternary; keep vision as a separate evidence capability.

- [ ] **Step 4: Write RED tests for manifest generation**

```python
def test_selects_runtime_files_and_excludes_drafter():
    files = [
        FakeFile("config.json", 10, None),
        FakeFile("model-00001-of-00002.safetensors", 20, "a" * 64),
        FakeFile("model-00002-of-00002.safetensors", 30, "b" * 64),
        FakeFile("dspark.safetensors", 40, "c" * 64),
    ]
    selected = select_runtime_files(files)
    assert [f.path for f in selected] == [
        "config.json", "model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors"
    ]
```

- [ ] **Step 5: Implement and generate the pinned public manifest**

Use `huggingface_hub.HfApi().model_info(repo_id, revision="main", files_metadata=True)` for the two MLX repositories. Persist the returned commit SHA as `revision`; require `config.json`, tokenizer/chat-template files, safetensor index when present, every referenced safetensor shard, and processor/preprocessor files. Exclude README, images, demos, and drafter weights. Fail when size or LFS SHA-256 is absent for a weight.

Run:

```bash
uv run pytest tests/test_generate_mobile_model_manifest.py -q
uv run python scripts/generate_mobile_model_manifest.py --output mobile/Resources/Models/manifest.json
```

Expected: tests pass and both entries contain immutable revisions, byte counts, and hashes.

- [ ] **Step 6: Run all domain tests and commit**

```bash
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test
git add mobile scripts/generate_mobile_model_manifest.py tests/test_generate_mobile_model_manifest.py
git commit -m "feat(mobile): define model qualification and manifest"
```

### Task 3: Atomic Download, Resume, Verification, Import, and Deletion

**Files:**
- Create: `mobile/Sources/ModelLibrary/ModelFileTransport.swift`
- Create: `mobile/Sources/ModelLibrary/URLSessionModelFileTransport.swift`
- Create: `mobile/Sources/ModelLibrary/SHA256Verifier.swift`
- Create: `mobile/Sources/ModelLibrary/ModelImporter.swift`
- Create: `mobile/Sources/ModelLibrary/ModelLibrary.swift`
- Create: `mobile/Tests/ModelLibraryTests.swift`
- Create: `mobile/Tests/SHA256VerifierTests.swift`

**Interfaces:**
- Consumes: `ModelManifest`, `DeviceQualification`.
- Produces: `ModelLibrary.install(_:)`, `resume(_:)`, `import(from:)`, `delete(_:)`, and `AsyncStream<ModelLibrarySnapshot>`.

- [ ] **Step 1: Write the failing atomic-install test**

```swift
@Test func corruptShardNeverBecomesReady() async throws {
    let transport = RecordingTransport(files: ["model.safetensors": Data("bad".utf8)])
    let library = try ModelLibrary(root: temporaryDirectory(), transport: transport)
    await #expect(throws: ModelLibraryError.hashMismatch("model.safetensors")) {
        try await library.install(.fixture(expectedSHA256: String(repeating: "0", count: 64)))
    }
    #expect(await library.state(for: .oneBit27B) == .notInstalled)
}
```

- [ ] **Step 2: Verify RED**

Run: `xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test -only-testing:BonsaiMobileTests/ModelLibraryTests`

Expected: FAIL because `ModelLibrary` is missing.

- [ ] **Step 3: Implement transport and atomic staging**

```swift
protocol ModelFileTransport: Sendable {
    func download(_ file: ModelManifest.File, to destination: URL) async throws
}

actor ModelLibrary {
    func install(_ manifest: ModelManifest) async throws {
        let staging = root.appending(path: ".staging/\(manifest.id.rawValue)")
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        for file in manifest.files where !isVerified(file, in: staging) {
            try await transport.download(file, to: staging.appending(path: file.path))
            try verifier.verify(file, at: staging.appending(path: file.path))
        }
        try promoteAtomically(staging, to: installedURL(for: manifest.id))
    }
}
```

Production transport uses a background `URLSessionConfiguration` on iOS and resumable file downloads. Unit tests keep `RecordingTransport` at the network boundary; add a real local HTTP integration test that interrupts a transfer, honors Range, resumes, and verifies the final hash.

- [ ] **Step 4: Add safe folder and `.bonsaimodel.zip` import tests**

Test missing files, duplicate paths, `../` traversal, absolute paths, symlinks escaping staging, executable entries, and hash mismatch. Implement extraction through pinned ZIPFoundation into staging; validate canonical descendant paths before writing each entry. Copy directory imports without modifying the security-scoped source.

- [ ] **Step 5: Verify GREEN and commit**

```bash
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test
git add mobile
git commit -m "feat(mobile): manage verified model installations"
```

### Task 4: Streaming MLX Engine, Thinking Separation, and One-Model Lifecycle

**Files:**
- Create: `mobile/Sources/Inference/InferenceEngine.swift`
- Create: `mobile/Sources/Inference/MLXInferenceEngine.swift`
- Create: `mobile/Sources/Inference/ReasoningRouter.swift`
- Create: `mobile/Sources/Inference/ChatSession.swift`
- Create: `mobile/Tests/ReasoningRouterTests.swift`
- Create: `mobile/Tests/ChatSessionTests.swift`
- Create: `mobile/IntegrationTests/MLXInferenceIntegrationTests.swift`

**Interfaces:**
- Produces: `InferenceEngine.load`, `generate`, `cancel`, `unload`; `ChatSession.send` and snapshots.
- Emits: `GenerationEvent.reasoning`, `.answer`, `.toolRequest`, `.metrics`, `.completed`.

- [ ] **Step 1: Write RED for split delimiters and cancellation**

```swift
@Test func routesDelimiterAcrossChunks() {
    var router = ReasoningRouter(start: "<think>", end: "</think>", primed: false)
    #expect(router.consume("<thi") == [])
    #expect(router.consume("nk>plan</thi") == [.reasoning("plan")])
    #expect(router.consume("nk>answer") == [.answer("answer")])
}

@Test func switchingModelsCancelsThenUnloads() async throws {
    let engine = RecordingInferenceEngine()
    let session = ChatSession(engine: engine)
    try await session.load(.oneBitFixture)
    try await session.load(.ternaryFixture)
    #expect(await engine.calls == [.load(.oneBit27B), .cancel, .unload, .load(.ternary27B)])
}
```

- [ ] **Step 2: Verify RED, then implement the domain protocol**

```swift
protocol InferenceEngine: Sendable {
    func load(_ installation: ModelInstallation) async throws
    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error>
    func cancel() async
    func unload() async
}
```

`ChatSession` is an actor with states `idle`, `loading`, `ready`, `generating`, `awaitingApproval`, `failed`. It cancels and awaits the active task before unload and never persists partial assistant output.

- [ ] **Step 3: Implement the pinned MLX adapter using inspected APIs**

Load local directories with `ModelConfiguration(directory:)` and `VLMModelFactory.shared.loadContainer(configuration:)`. Create MLX `ChatSession` with `GenerateParameters(maxTokens: request.maxTokens)` and `additionalContext: ["enable_thinking": request.reasoningBudget != 0]`. Iterate `streamDetails`; map `.chunk` through `ReasoningRouter`, `.toolCall` to the domain tool call, and `.info` to metrics. Bind `AsyncThrowingStream.onTermination` to task cancellation and release container/session references in `unload()`.

- [ ] **Step 4: Run a real model integration lane**

```bash
BONSAI_MODEL_DIR="$PWD/models/Bonsai-27B-mlx" xcodebuild \
  -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobileIntegrationTests \
  -destination 'platform=macOS' test
```

Expected: real output contains separate reasoning/answer events, cancellation ends promptly, and three load/generate/unload cycles complete without a retained active session.

- [ ] **Step 5: Commit**

```bash
git add mobile
git commit -m "feat(mobile): stream local Bonsai inference"
```

### Task 5: Conversations, Context Limits, Resource Pressure, and Diagnostics

**Files:**
- Create: `mobile/Sources/Persistence/AtomicJSONStore.swift`
- Create: `mobile/Sources/Persistence/ConversationStore.swift`
- Create: `mobile/Sources/Inference/ContextTrimmer.swift`
- Create: `mobile/Sources/Inference/ResourceMonitor.swift`
- Create: `mobile/Sources/Domain/Diagnostics.swift`
- Create: `mobile/Tests/ConversationStoreTests.swift`
- Create: `mobile/Tests/ContextTrimmerTests.swift`
- Create: `mobile/Tests/ResourceRecoveryTests.swift`

**Interfaces:**
- Produces: model-specific persisted conversations, 4,096-token trimming decisions, local redacted metrics, and `ResourcePressureEvent`.

- [ ] **Step 1: Write RED for model isolation and trimming**

```swift
@Test func conversationsRemainBoundToTheirModel() async throws {
    let store = try ConversationStore(root: temporaryDirectory())
    try await store.save(.fixture(id: "c1", modelID: .oneBit27B))
    #expect(try await store.load("c1", for: .ternary27B) == nil)
}

@Test func keepsSystemAndNewestTurnsWithin4096() {
    let result = ContextTrimmer(limit: 4_096).trim(.fixture(tokenCounts: [100, 2_500, 2_000]))
    #expect(result.keptTokenCount <= 4_096)
    #expect(result.removedMessageIDs == ["old-user", "old-assistant"])
}
```

- [ ] **Step 2: Implement atomic JSON persistence and explicit trimming**

Write a temporary file, apply complete-file data protection on iOS, call `synchronize`, and replace the destination atomically. Persist completed turns only. Exclude model directories from backup. Expose trimmed-turn count in the chat snapshot; never silently drop the system instruction.

- [ ] **Step 3: Implement pressure ordering and redacted diagnostics**

On critical memory/thermal events: cancel generation → unload vision state → clear reusable caches → offer full unload. Diagnostics store stage, category, elapsed milliseconds, token counts, token rate, thermal state, and memory-warning count; their types contain no prompt/image/note/generated-text field.

- [ ] **Step 4: Run GREEN and commit**

```bash
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test
git add mobile
git commit -m "feat(mobile): persist chats and recover resources"
```

### Task 6: Safe Offline Tools and Bounded Agent Loop

**Files:**
- Create: `mobile/Sources/Agent/OfflineTool.swift`
- Create: `mobile/Sources/Agent/ToolRegistry.swift`
- Create: `mobile/Sources/Agent/CalculatorParser.swift`
- Create: `mobile/Sources/Agent/DateTool.swift`
- Create: `mobile/Sources/Agent/DeviceInfoTool.swift`
- Create: `mobile/Sources/Agent/NotesTool.swift`
- Create: `mobile/Sources/Persistence/NotesStore.swift`
- Create: `mobile/Sources/Agent/AgentLoop.swift`
- Create: `mobile/Tests/AgentLoopTests.swift`
- Create: `mobile/Tests/CalculatorParserTests.swift`
- Create: `mobile/Tests/NotesToolTests.swift`

**Interfaces:**
- Produces: four compiled schemas, automatic read-only policy, per-invocation write approval, and six-turn termination.

- [ ] **Step 1: Write RED for calculator safety, approval, and limit**

```swift
@Test func calculatorRejectsIdentifiers() {
    #expect(throws: CalculatorError.invalidToken) { try CalculatorParser.evaluate("system(1)") }
}

@Test func writeWaitsForAllowOnce() async throws {
    let approvals = RecordingApprovalGate(decision: .deny)
    let loop = AgentLoop(engine: ScriptedEngine.callsCreateNote(), tools: .liveForTests, approvals: approvals)
    let result = try await loop.run(.fixture)
    #expect(await approvals.requests.count == 1)
    #expect(result.toolResults.last?.status == .denied)
}

@Test func stopsAtSixToolTurns() async throws {
    let loop = AgentLoop(engine: ScriptedEngine.infiniteCalculatorCalls(), tools: .liveForTests)
    #expect(try await loop.run(.fixture).completion == .toolTurnLimit(6))
}
```

- [ ] **Step 2: Implement the constrained tool boundary**

```swift
protocol OfflineTool: Sendable {
    var name: String { get }
    var schema: ToolSchema { get }
    var approval: ToolApprovalPolicy { get }
    func execute(arguments: JSONValue) async throws -> JSONValue
}

enum ToolApprovalPolicy: Sendable { case automaticReadOnly, requireAllowOnce }
```

Calculator grammar supports decimal numbers, parentheses, unary minus, and `+ - * / %`; it contains no dynamic evaluation. Device information exposes model class, OS version, locale, physical-memory bucket, and thermal state but no identifier. Notes list/read are automatic; create/update/delete show exact proposed changes and require `Allow once` every time.

- [ ] **Step 3: Map the registry into MLX tool schemas and continue sessions**

Convert domain schemas into MLX `ToolSpec` dictionaries. On `.toolRequest`, append a visible activity entry, execute/deny, then continue the same MLX chat session with a correlated tool result so the KV cache remains warm. Stop on cancellation, fatal tool error, runtime failure, or turn seven before execution.

- [ ] **Step 4: Run GREEN, real tool round-trip, and commit**

```bash
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test
BONSAI_MODEL_DIR="$PWD/models/Bonsai-27B-mlx" xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobileIntegrationTests -destination 'platform=macOS' test -only-testing:MLXInferenceIntegrationTests/realToolRoundTrip
git add mobile
git commit -m "feat(mobile): run bounded offline tools"
```

### Task 7: Quiet Garden Model Library, Chat, and Agent Activity UI

**Files:**
- Create: `mobile/Sources/Features/DesignSystem/QuietGardenTheme.swift`
- Create: `mobile/Sources/Features/ModelLibrary/ModelLibraryViewModel.swift`
- Create: `mobile/Sources/Features/ModelLibrary/ModelLibraryView.swift`
- Create: `mobile/Sources/Features/Chat/ChatViewModel.swift`
- Create: `mobile/Sources/Features/Chat/ChatView.swift`
- Create: `mobile/Sources/Features/Chat/ComposerView.swift`
- Create: `mobile/Sources/Features/Chat/ReasoningDisclosure.swift`
- Create: `mobile/Sources/Features/Activity/AgentActivityView.swift`
- Create: `mobile/Sources/App/RootView.swift`
- Create: `mobile/UITests/CoreFlowUITests.swift`

**Interfaces:**
- Consumes actor snapshots only; sends user intents through view models.
- Produces the adaptive iPhone, iPad, and Mac flows approved in the design.

- [ ] **Step 1: Write failing UI tests for observable product states**

```swift
func testUnsupportedModelExplainsWhyAndCannotLoad() {
    app.launchArguments = ["-ui-fixture", "iphone-ternary-unsupported"]
    app.launch()
    app.buttons["Model Library"].tap()
    XCTAssertTrue(app.staticTexts["Ternary requires a verified high-memory iPad or Mac."].exists)
    XCTAssertFalse(app.buttons["Load Ternary Bonsai 27B"].isEnabled)
}

func testWriteToolRequiresAllowOnce() {
    app.launchArguments = ["-ui-fixture", "pending-note-write"]
    app.launch()
    XCTAssertTrue(app.buttons["Allow once"].exists)
    XCTAssertTrue(app.buttons["Deny"].exists)
}
```

- [ ] **Step 2: Verify RED with the generic iOS build lane**

Run: `xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'generic/platform=iOS Simulator' build`

Expected: build fails because feature views do not exist.

- [ ] **Step 3: Implement the adaptive Quiet Garden shell**

Use `NavigationSplitView` on regular horizontal size classes/macOS and `NavigationStack` plus sheets on compact iPhone. Define semantic colors in the asset catalog, one botanical accent, system body typography, and a restrained serif wordmark. The chat list uses plain layout; cards exist only for model rows/attachments/tool approvals. Composer exposes attachment, reasoning effort, send, and stop with 44-point minimum targets.

- [ ] **Step 4: Bind streaming without layout churn**

View models observe `AsyncStream` snapshots on `@MainActor`. Stable message IDs update the current text node in place. Thinking is a separate accessible disclosure; metrics appear only after generation info arrives. Every error has a named recovery action and preserves the user's message.

- [ ] **Step 5: Run UI snapshots/flows, lint, and commit**

```bash
swiftlint --strict mobile/Sources mobile/Tests mobile/UITests
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'generic/platform=iOS Simulator' build
git add mobile
git commit -m "feat(mobile): add Quiet Garden agent chat UI"
```

### Task 8: Camera/Photos Vision, Detail Cap, Privacy, and Accessibility

**Files:**
- Create: `mobile/Sources/Features/Vision/ImageAttachment.swift`
- Create: `mobile/Sources/Features/Vision/ImagePicker.swift`
- Create: `mobile/Sources/Features/Vision/CameraPicker.swift`
- Create: `mobile/Sources/Inference/ImagePreprocessor.swift`
- Create: `mobile/Sources/Features/Settings/SettingsView.swift`
- Create: `mobile/Tests/ImagePreprocessorTests.swift`
- Create: `mobile/UITests/VisionAccessibilityUITests.swift`
- Create: `mobile/Resources/PrivacyInfo.xcprivacy`
- Modify: `mobile/project.yml`

**Interfaces:**
- Produces: `.fast1024` and `.fullDetail` attachment policy, permission-on-use flows, and accessible settings.

- [ ] **Step 1: Write RED for image budgeting**

```swift
@Test func fastDetailDownscalesLargeImageButNeverUpscales() throws {
    let processor = ImagePreprocessor(tokenBudget: 1_024, patchSize: 32)
    #expect(try processor.targetSize(for: .init(width: 4_000, height: 3_000)) == .init(width: 1_184, height: 864))
    #expect(try processor.targetSize(for: .init(width: 640, height: 480)) == .init(width: 640, height: 480))
}
```

- [ ] **Step 2: Implement explicit preprocessing and MLX input**

Normalize orientation, preserve aspect ratio, calculate a patch-aligned target whose area does not exceed the 1,024-token budget, and write a temporary HEIF/JPEG inside the app container. Pass `.url(processedURL)` as `UserInput.Image`. Full detail retains source dimensions after orientation normalization and displays the memory/latency warning before send.

- [ ] **Step 3: Add privacy and accessibility behaviors**

Request Camera/Photos only from the relevant action. Add purpose strings, privacy manifest, VoiceOver labels/hints/values, Dynamic Type layouts, Reduce Motion alternatives, keyboard shortcuts for send/cancel, and focus restoration after sheets/approvals. Add UI tests at AX5 text size and with Reduce Motion launch arguments.

- [ ] **Step 4: Run GREEN and commit**

```bash
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
swiftlint --strict mobile/Sources mobile/Tests mobile/UITests
git add mobile
git commit -m "feat(mobile): add private accessible vision input"
```

### Task 9: Real-Device Evidence, Offline Proof, Documentation, and Release Gate

**Files:**
- Create: `mobile/IntegrationTests/RealModelScenarioTests.swift`
- Create: `mobile/UITests/OfflineScenarioUITests.swift`
- Create: `mobile/scripts/run_device_evidence.sh`
- Create: `docs/mobile/DEVICE-SUPPORT.md`
- Create: `docs/mobile/PRIVACY.md`
- Modify: `README.md`

**Interfaces:**
- Produces: evidence rows for model/device/capability combinations and the final supported-device policy consumed by `DeviceQualifier`.

- [ ] **Step 1: Add the failing evidence-schema test**

```swift
@Test func evidenceRequiresEveryReleaseMetric() throws {
    let row = DeviceEvidence.fixture(tokenRate: nil)
    #expect(throws: DeviceEvidence.ValidationError.missing("generatedTokensPerSecond")) {
        try row.validateForRelease()
    }
}
```

- [ ] **Step 2: Implement evidence capture and validation**

Capture device model class, OS/app/model revision, physical memory, context, detail mode, cold/warm load, TTFT, prompt/generation rate, peak memory, thermal transitions, battery delta, cancellation result, and outcome. The release support manifest accepts a capability only when its row validates and the scenario completed without pressure termination.

- [ ] **Step 3: Execute the physical iPhone 16e lane**

Run with the connected device identifier:

```bash
mobile/scripts/run_device_evidence.sh \
  --destination 'platform=iOS,name=iPhone 16e' \
  --model oneBit27B \
  --scenarios text,thinking,cancel,calculator,date,device,notes,vision-fast,vision-full,offline
```

Pass: text/thinking/cancellation/tools complete; airplane-mode inference produces no outbound requests; repeated load/unload does not crash. Vision is qualified independently. If reliable loading fails, commit an unsupported iPhone 16e evidence row and keep the release UI blocked.

- [ ] **Step 4: Execute Ternary on qualified high-memory hardware**

```bash
mobile/scripts/run_device_evidence.sh \
  --destination 'platform=macOS' \
  --model ternary27B \
  --scenarios text,thinking,cancel,calculator,date,device,notes,offline
```

Pass: all scenarios and three cold load/unload cycles complete without critical pressure. Add a high-memory iPad lane when such hardware is available; leave it unverified until then.

- [ ] **Step 5: Run the complete release gate**

```bash
uv run pytest -q
swiftlint --strict mobile/Sources mobile/Tests mobile/UITests
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'platform=macOS' test
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -destination 'generic/platform=iOS Simulator' build
xcodebuild -project mobile/BonsaiMobile.xcodeproj -scheme BonsaiMobile -configuration Release -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
git diff --check
```

Expected: all commands pass with no warnings promoted by project settings and no uncommitted generated dependency content.

- [ ] **Step 6: Document measured support and privacy**

`DEVICE-SUPPORT.md` distinguishes supported, unsupported, and unverified combinations and links each supported claim to an evidence artifact. `PRIVACY.md` states that Hugging Face is contacted only for model download, lists local data locations/deletion behavior, and records the offline network-inspection result. README adds build, model acquisition/import, storage, and device requirements without promising unmeasured performance.

- [ ] **Step 7: Final review and commit**

```bash
git add mobile docs/mobile README.md
git commit -m "docs(mobile): publish verified device support"
git log --oneline --show-signature -10
```

## Verification placement summary

| Design obligation | Tasks |
|---|---|
| Pinned real MLX runtime and one linked copy | 1, 4 |
| Public authenticated-free acquisition and checksums | 2, 3 |
| Device/model capability tiering | 2, 9 |
| One-model lifecycle, cancellation, resource recovery | 4, 5, 9 |
| Model-specific conversations and explicit context trimming | 5 |
| Thinking, vision, and image-token policy | 4, 8, 9 |
| Safe six-turn offline agent loop | 6, 9 |
| Quiet Garden adaptive UI and recovery states | 7, 8 |
| Accessibility and privacy | 8, 9 |
| iPhone 16e and Ternary evidence | 9 |

## Failure-mode checklist

- Dependency revision or package graph drift: Task 1 SHA and single-identity checks.
- Partial/corrupt/hostile model content: Tasks 2-3 manifest, staging, hash, and archive tests.
- Unsupported allocation or process termination: Tasks 2, 5, and 9 evidence gates.
- Cancellation races and retained native state: Tasks 4-5 repeated lifecycle tests.
- Reasoning leakage into answer text: Task 4 split-delimiter tests plus real output.
- Tool schema abuse or unapproved writes: Task 6 constrained registry and approval tests.
- UI state loss or inaccessible recovery: Tasks 7-8 observable UI/accessibility tests.
- False offline/privacy claim: Task 9 airplane-mode and network-inspection evidence.
