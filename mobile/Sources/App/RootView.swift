import SwiftUI
// Root composition intentionally keeps adaptive navigation and deterministic fixtures together.
// swiftlint:disable file_length
#if os(iOS)
import UIKit
#endif

enum RootLayout: Equatable, Sendable { case stack, split }
enum RootNavigationState {
  static func layout(platform: Platform, compactWidth: Bool) -> RootLayout {
    switch platform {
    case .iPhone: .stack
    case .iPad: compactWidth ? .stack : .split
    case .mac: .split
    }
  }
}

enum UIFixture: String, CaseIterable, Sendable {
  case emptyLibrary = "empty-library"
  case downloading
  case unsupportedTernary = "unsupported-ternary"
  case readyChat = "ready-chat"
  case streamingReasoning = "streaming-reasoning"
  case pendingNoteWrite = "pending-note-write"
  case toolFailure = "tool-failure"
  case recoverableFailure = "recoverable-failure"
  case cancelledGeneration = "cancelled-generation"
  case contextTrimmed = "context-trimmed"
  case toolDenied = "tool-denied"
  case attachmentDraft = "attachment-draft"
  case fullDetailWarning = "full-detail-warning"
  case permissionDenied = "permission-denied"
  case preprocessingError = "preprocessing-error"
  case visionStreaming = "vision-streaming"
  case attachmentRecovery = "attachment-recovery"

  // Fixture coverage intentionally keeps every deterministic product state together.
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  func makeState() -> UIFixtureState {
    let assistantID = UUID(uuidString: "F17109A6-83C2-4FC7-9513-882049015BE3")!
    let baseMessages = [
      ChatMessagePresentation(id: UUID(uuidString: "20A859B9-56D2-4EF9-A5AF-FD460B25C56B")!,
                              role: .user, text: "What makes local inference useful?"),
      ChatMessagePresentation(id: assistantID, role: .assistant,
                              text: "Your prompt, model, and tool results stay on this device.")
    ]
    switch self {
    case .emptyLibrary:
      return .init(library: .fixture(.empty), platform: .mac, modelReady: false)
    case .downloading:
      return .init(library: .fixture(.downloading), platform: .mac, modelReady: false)
    case .unsupportedTernary:
      return .init(library: .fixture(.ready), platform: .iPhone, modelReady: true)
    case .readyChat:
      return .init(library: .fixture(.ready), platform: .mac, modelReady: true,
                   messages: baseMessages)
    case .streamingReasoning:
      return .init(library: .fixture(.ready), platform: .mac, modelReady: true,
                   messages: baseMessages, reasoning: .init(text: "Comparing privacy and latency…",
                                                            status: "Thinking · Medium"),
                   metrics: .init(promptTokenCount: 96, generatedTokenCount: 18,
                                  timeToFirstToken: .milliseconds(184), tokensPerSecond: 14.8))
    case .pendingNoteWrite:
      let invocation = ToolInvocation(id: "note-write-1", name: "local_notes", argumentsJSON: "{}")
      return .init(library: .fixture(.ready), platform: .mac, modelReady: true,
                   messages: baseMessages,
                   activities: [.pendingApproval(
                     id: invocation.id,
                     toolName: "Local notes",
                     effect: "Create note titled ‘Packing list’ with body ‘Passport, charger’",
                     invocation: invocation
                   )])
    case .toolFailure:
      return .init(library: .fixture(.ready), platform: .mac, modelReady: true,
                   messages: baseMessages,
                   activities: [.init(id: "tool-1", kind: .failed, title: "Calculator failed",
                                      detail: "The expression contains an unsupported identifier.", actions: []),
                                .init(id: "terminal", kind: .terminal, title: "Agent stopped",
                                      detail: "Review the tool request and retry.", actions: [])])
    case .recoverableFailure:
      return .init(library: .fixture(.recoverableFailure), platform: .mac, modelReady: false)
    case .cancelledGeneration:
      return .init(library: .fixture(.ready), platform: .mac, modelReady: true,
                   messages: baseMessages, terminalStatus: "Stopped")
    case .contextTrimmed:
      return .init(library: .fixture(.ready), platform: .mac, modelReady: true,
                   messages: baseMessages, contextTrimNotice: "Older turns were removed to fit context.")
    case .toolDenied:
      return .init(library: .fixture(.ready), platform: .mac, modelReady: true,
                   messages: baseMessages,
                   activities: [.init(id: "denied", kind: .denied, title: "Local notes denied",
                                      detail: "No changes were made.", actions: [])])
    case .attachmentDraft:
      return .init(library: .fixture(.ready), platform: .iPhone, modelReady: true,
                   draftAttachment: Self.fixtureAttachment())
    case .fullDetailWarning:
      var attachment = Self.fixtureAttachment()
      attachment.detailPolicy = .fullDetail
      return .init(library: .fixture(.ready), platform: .iPhone, modelReady: true,
                   draftAttachment: attachment, showsFullDetailWarning: true)
    case .permissionDenied:
      return .init(library: .fixture(.ready), platform: .iPhone, modelReady: true,
                   attachmentError: "Camera access is denied. Open Settings to allow camera access.")
    case .preprocessingError:
      return .init(library: .fixture(.ready), platform: .mac, modelReady: true,
                   draftAttachment: Self.fixtureAttachment(),
                   attachmentError: "Could not prepare this image. Choose a smaller supported image.")
    case .visionStreaming:
      return .init(library: .fixture(.ready), platform: .mac, modelReady: true,
                   messages: baseMessages,
                   reasoning: .init(text: "Inspecting the private image…", status: "Thinking · Medium"),
                   metrics: .init(promptTokenCount: 1_120, generatedTokenCount: 18,
                                  timeToFirstToken: .milliseconds(384), tokensPerSecond: 12.4))
    case .attachmentRecovery:
      return .init(library: .fixture(.ready), platform: .iPhone, modelReady: true,
                   draftAttachment: Self.fixtureAttachment(),
                   attachmentError: "Generation stopped before the image was consumed. Your draft is intact.")
    }
  }

  private static func fixtureAttachment() -> ImageAttachment {
    .init(id: UUID(uuidString: "7F34B8BC-B904-4D25-88AF-52404CC531F0")!,
          originalFilename: "garden.jpg", managedRelativePath: "garden.jpg",
          pixelSize: .init(width: 4_000, height: 3_000), byteCount: 2_400_000,
          contentType: "image/jpeg", detailPolicy: .fast1024, lifecycle: .managedDraft,
          accessibleLabel: "Garden photo")
  }

  static func from(arguments: [String]) -> UIFixture? {
    #if !DEBUG
    return nil
    #else
    guard let index = arguments.firstIndex(where: { $0 == "-ui-fixture" || $0 == "--ui-fixture" }),
          arguments.indices.contains(index + 1) else { return nil }
    return UIFixture(rawValue: arguments[index + 1])
    #endif
  }
}

struct UIFixtureState: Equatable, Sendable {
  let library: ModelLibrarySnapshot
  let platform: Platform
  let modelReady: Bool
  var messages: [ChatMessagePresentation] = []
  var reasoning = ReasoningPresentation()
  var metrics: GenerationMetrics?
  var activities: [AgentActivityPresentation] = []
  var terminalStatus: String?
  var contextTrimNotice: String?
  var draftAttachment: ImageAttachment?
  var attachmentError: String?
  var showsFullDetailWarning = false
}

@MainActor enum CoherentConversationActions {
  static func create(
    navigation: ConversationNavigationViewModel,
    chat: ChatViewModel
  ) async {
    await chat.withConversationAdmission { lease in
      await chat.stop()
      guard await chat.isConversationAdmissionCurrent(lease) else { return }
      let result = await navigation.createResult()
      await chat.publishIfConversationAdmissionCurrent(lease) {
        navigation.publish(result)
      }
      guard await chat.isConversationAdmissionCurrent(lease) else { return }
      await chat.reloadHistory(admittedBy: lease)
    }
  }

  static func select(
    _ id: ConversationID,
    navigation: ConversationNavigationViewModel,
    chat: ChatViewModel
  ) async {
    await chat.withConversationAdmission { lease in
      await chat.stop()
      guard await chat.isConversationAdmissionCurrent(lease) else { return }
      let result = await navigation.selectResult(id)
      await chat.publishIfConversationAdmissionCurrent(lease) {
        navigation.publish(result)
      }
      guard await chat.isConversationAdmissionCurrent(lease) else { return }
      await chat.reloadHistory(admittedBy: lease)
    }
  }
}

struct RootView: View {
  private static let modelDescriptors = ModelCatalogLoader.bundledDescriptors()
  @State private var libraryViewModel: ModelLibraryViewModel
  @State private var chatViewModel: ChatViewModel
  @State private var conversationViewModel: ConversationNavigationViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var showsLibrary = false
  @State private var showsSettings = false
  @State private var didStartRecoveredServices = false
  private let platform: Platform
  private let reduceMotionOverride: Bool?
  private let settingsService: (any SettingsServing)?
  private let imageDetailSettings: PersistedImageDetailSettings

  init(composition: RootComposition = .process()) {
    _libraryViewModel = State(initialValue: composition.libraryViewModel)
    _chatViewModel = State(initialValue: composition.chatViewModel)
    _conversationViewModel = State(initialValue: composition.conversationViewModel)
    _showsLibrary = State(initialValue: composition.showsLibraryOnLaunch)
    platform = composition.platform
    reduceMotionOverride = composition.reduceMotionOverride
    settingsService = composition.settingsService
    imageDetailSettings = composition.imageDetailSettings
  }

  var body: some View {
    Group {
        if RootNavigationState.layout(platform: platform, compactWidth: horizontalSizeClass == .compact) == .stack {
          NavigationStack {
            ChatView(viewModel: chatViewModel)
              #if os(iOS)
              .navigationBarTitleDisplayMode(.inline)
              #endif
              .toolbar { compactToolbar }
          }
        } else {
          regularWorkspace
        }
      }
      .animation(QuietGardenTheme.animation(
        reduceMotion: reduceMotionOverride ?? reduceMotion), value: horizontalSizeClass)
    .tint(QuietGardenTheme.accent)
    .accessibilityIdentifier(UIAccessibility.root)
    .task {
      if let settingsService {
        _ = await chatViewModel.recoverPendingLocalDataClear(using: settingsService)
      } else {
        startRecoveredServicesIfNeeded()
      }
      if chatViewModel.localDataIsCoherent { startRecoveredServicesIfNeeded() }
    }
    .onChange(of: chatViewModel.localDataIsCoherent) {
      if chatViewModel.localDataIsCoherent { startRecoveredServicesIfNeeded() }
    }
    .onChange(of: libraryViewModel.loadedQualification) {
      let qualification = libraryViewModel.loadedQualification
      chatViewModel.isModelReady = qualification != nil
      chatViewModel.loadedModelName = switch qualification?.modelID {
      case .oneBit27B: "Bonsai 27B · 1-bit"
      case .ternary27B: "Ternary Bonsai 27B"
      case nil: nil
      }
      Task { await chatViewModel.setEffectiveCapabilities(qualification?.capabilities ?? []) }
      Task { await chatViewModel.reloadHistory() }
    }
    .sheet(isPresented: $showsLibrary) {
      NavigationStack { ModelLibraryView(viewModel: libraryViewModel) }
        .frame(minWidth: 320, minHeight: 600)
    }
    .sheet(isPresented: $showsSettings) {
      NavigationStack {
        SettingsView(
          detailSettings: imageDetailSettings,
          isClearInProgress: chatViewModel.isPrivateDataClearInProgress
        ) { intent in
          switch intent {
          case .setDefaultImageDetail(let policy):
            chatViewModel.defaultImageDetail = policy
          case .clearConversationsNotesAndImages:
            guard let settingsService, !chatViewModel.isPrivateDataClearInProgress else { return }
            await chatViewModel.clearLocalData(using: settingsService)
          }
        }
      }
      .frame(minWidth: 320, minHeight: 520)
    }
    .alert("Clear data failed", isPresented: Binding(
      get: { chatViewModel.clearDataError != nil },
      set: { if !$0 { chatViewModel.dismissClearDataError() } }
    )) {
      Button("Retry clear data") {
        guard let settingsService else { return }
        Task { await chatViewModel.clearLocalData(using: settingsService) }
      }
      .disabled(chatViewModel.isPrivateDataClearInProgress)
      Button("Cancel", role: .cancel) { chatViewModel.dismissClearDataError() }
    } message: { Text(chatViewModel.clearDataError ?? "") }
  }

  private func startRecoveredServicesIfNeeded() {
    guard !didStartRecoveredServices else { return }
    didStartRecoveredServices = true
    libraryViewModel.start()
    conversationViewModel.start()
    Task { await chatViewModel.start() }
  }

  @ViewBuilder private var regularWorkspace: some View {
    #if os(macOS)
    HSplitView {
      regularSidebar.frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
      ChatView(viewModel: chatViewModel).frame(minWidth: 520)
    }
    #else
    NavigationSplitView {
      regularSidebar
        .navigationSplitViewColumnWidth(min: 300, ideal: 360)
    } detail: {
      ChatView(viewModel: chatViewModel)
    }
    .navigationSplitViewStyle(.balanced)
    #endif
  }

  @ToolbarContentBuilder private var compactToolbar: some ToolbarContent {
    ToolbarItem(placement: compactLeadingPlacement) {
      Button { showsLibrary = true } label: {
        Image(systemName: "shippingbox")
      }
      .accessibilityLabel("Model Library")
      .accessibilityHint("Manage local Bonsai models")
    }
    ToolbarItemGroup(placement: compactTrailingPlacement) {
      Button { showsSettings = true } label: {
        Image(systemName: "gearshape")
      }
      .disabled(chatViewModel.isPrivateDataClearInProgress)
      .accessibilityLabel("Settings")
      .accessibilityHint(chatViewModel.isPrivateDataClearInProgress
        ? "Unavailable until clearing local data finishes"
        : "Review local privacy, image detail, and clear-data controls")
      Menu {
        Button("New conversation") {
          Task {
            await CoherentConversationActions.create(
              navigation: conversationViewModel, chat: chatViewModel)
          }
        }
        ForEach(conversationViewModel.conversations) { item in
          Button(item.title) {
            Task {
              await CoherentConversationActions.select(
                item.id, navigation: conversationViewModel, chat: chatViewModel)
            }
          }
        }
      } label: {
        Image(systemName: "bubble.left.and.bubble.right")
      }
      .disabled(!chatViewModel.localDataIsCoherent)
      .accessibilityLabel("Conversations")
      .accessibilityHint(chatViewModel.localDataIsCoherent
        ? "Create or switch private on-device conversations"
        : "Unavailable until clearing local data finishes")
    }
  }

  private var compactLeadingPlacement: ToolbarItemPlacement {
    #if os(iOS)
    .topBarLeading
    #else
    .navigation
    #endif
  }

  private var compactTrailingPlacement: ToolbarItemPlacement {
    #if os(iOS)
    .topBarTrailing
    #else
    .automatic
    #endif
  }

  private var regularSidebar: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Bonsai").font(.title2.weight(.semibold))
          Text(chatViewModel.loadedModelName ?? "No model loaded")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(16)
      HStack {
        Button("Settings", systemImage: "gearshape") { showsSettings = true }
          .disabled(chatViewModel.isPrivateDataClearInProgress)
          .accessibilityHint(chatViewModel.isPrivateDataClearInProgress
            ? "Unavailable until clearing local data finishes"
            : "Review local privacy, image detail, and clear-data controls")
        Spacer()
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 16)
      .padding(.bottom, 8)
      List(selection: Binding(
        get: { conversationViewModel.selectedID },
        set: { id in
          guard let id else { return }
          Task {
            await CoherentConversationActions.select(
              id, navigation: conversationViewModel, chat: chatViewModel)
          }
        }
      )) {
        Section("Conversations") {
          ForEach(conversationViewModel.conversations) { item in
            Text(item.title).tag(item.id)
          }
          Button("New conversation", systemImage: "square.and.pencil") {
            Task {
              await CoherentConversationActions.create(
                navigation: conversationViewModel, chat: chatViewModel)
            }
          }
        }
      }
      .disabled(!chatViewModel.localDataIsCoherent)
      .accessibilityHint(chatViewModel.localDataIsCoherent
        ? "Create or switch private on-device conversations"
        : "Unavailable until clearing local data finishes")
      .frame(minHeight: 150, idealHeight: 220)
      Divider()
      ModelLibraryView(viewModel: libraryViewModel)
    }
    .background(QuietGardenTheme.paper)
  }
}

@MainActor
struct RootComposition {
  let libraryViewModel: ModelLibraryViewModel
  let chatViewModel: ChatViewModel
  let conversationViewModel: ConversationNavigationViewModel
  let platform: Platform
  let showsLibraryOnLaunch: Bool
  let reduceMotionOverride: Bool?
  let settingsService: (any SettingsServing)?
  let imageDetailSettings: PersistedImageDetailSettings

  static func process() -> RootComposition {
    if let fixture = UIFixture.from(arguments: ProcessInfo.processInfo.arguments) {
      return fixtureComposition(fixture.makeState())
    }
    do { return try live() } catch {
      let composition = fixtureComposition(UIFixture.emptyLibrary.makeState())
      composition.libraryViewModel.present(error: "App setup failed: \(error.localizedDescription)")
      return composition
    }
  }

  static func fixture(
    _ fixture: UIFixture,
    platform: Platform? = nil,
    showsLibrary: Bool = false,
    reduceMotion: Bool? = nil
  ) -> RootComposition {
    fixtureComposition(
      fixture.makeState(),
      platform: platform,
      showsLibrary: showsLibrary,
      reduceMotion: reduceMotion)
  }

  private static func fixtureComposition(
    _ state: UIFixtureState,
    platform: Platform? = nil,
    showsLibrary: Bool = false,
    reduceMotion: Bool? = nil
  ) -> RootComposition {
    let resolvedPlatform = platform ?? state.platform
    let library = FixtureModelLibraryService(snapshot: state.library)
    let chat = FixtureChatService()
    let fixtureRevision = String(repeating: "f", count: 40)
    let fixtureInstallation = ModelInstallation(
      modelID: .oneBit27B,
      directory: URL(fileURLWithPath: "/fixture/one-bit"),
      revision: fixtureRevision)
    let fixtureConversationID: ConversationID
    do {
      fixtureConversationID = try ConversationID("fixture-chat")
    } catch {
      preconditionFailure("The static fixture conversation identifier must remain valid: \(error)")
    }
    let fixtureConversation = ConversationListItem(
      id: fixtureConversationID,
      modelID: .oneBit27B,
      modelRevision: fixtureRevision,
      title: "Private on-device chat")
    let navigationSnapshot = ConversationNavigationSnapshot(
      installation: state.modelReady ? fixtureInstallation : nil,
      conversations: state.modelReady ? [fixtureConversation] : [],
      selectedID: state.modelReady ? fixtureConversation.id : nil)
    let navigation = FixtureConversationService(snapshot: navigationSnapshot)
    let libraryViewModel = ModelLibraryViewModel(service: library, platform: resolvedPlatform,
                                                 initial: state.library)
    let imageDetailSettings = PersistedImageDetailSettings(
      defaults: UserDefaults(suiteName: "fixture.\(UUID().uuidString)")!)
    let chatViewModel = ChatViewModel(service: chat, isModelReady: state.modelReady)
    chatViewModel.defaultImageDetail = imageDetailSettings.value
    chatViewModel.applyFixture(state)
    return RootComposition(
      libraryViewModel: libraryViewModel,
      chatViewModel: chatViewModel,
      conversationViewModel: ConversationNavigationViewModel(
        service: navigation, initial: navigationSnapshot),
      platform: resolvedPlatform,
      showsLibraryOnLaunch: showsLibrary,
      reduceMotionOverride: reduceMotion,
      settingsService: nil,
      imageDetailSettings: imageDetailSettings)
  }

  private static func live() throws -> RootComposition {
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
      .appending(path: "BonsaiMobile", directoryHint: .isDirectory)
    let engine = MLXInferenceEngine()
    let conversations = try ConversationStore(root: support)
    let coordinator = try ConversationCoordinator(root: support, store: conversations)
    let sessionGate = ModelSessionGate()
    let library = try LiveModelLibraryService(
      root: support.appending(path: "Models"),
      engine: engine,
      conversations: coordinator,
      sessionGate: sessionGate)
    let notes = try NotesStore(root: support)
    let attachmentRoot = support.appending(path: "Attachments", directoryHint: .isDirectory)
    let attachmentStore = try ManagedAttachmentStore(root: attachmentRoot)
    let attachmentService = LiveAttachmentService(store: attachmentStore)
    let settingsService = try LiveSettingsService(
      root: support, conversations: coordinator, notes: notes, attachments: attachmentStore)
    let imageDetailSettings = PersistedImageDetailSettings()
    let registry = try ToolRegistry.live(notes: notes)
    let approvalGate = InteractiveApprovalGate()
    let loop = AgentLoop(engine: engine, registry: registry, approvals: approvalGate)
    let chat = AgentLoopChatService(loop: loop, approvals: approvalGate, engine: engine,
                                    conversations: coordinator, sessionGate: sessionGate,
                                    attachmentStore: attachmentStore, attachmentRoot: attachmentRoot)
    let initial = ModelLibrarySnapshot.fixture(.empty)
    return RootComposition(
      libraryViewModel: ModelLibraryViewModel(service: library, platform: Self.platform, initial: initial),
      chatViewModel: {
        let viewModel = ChatViewModel(
          service: chat, isModelReady: false, attachments: attachmentService,
          requiresClearRecovery: true)
        viewModel.defaultImageDetail = imageDetailSettings.value
        return viewModel
      }(),
      conversationViewModel: ConversationNavigationViewModel(service: coordinator),
      platform: Self.platform,
      showsLibraryOnLaunch: false,
      reduceMotionOverride: nil,
      settingsService: settingsService,
      imageDetailSettings: imageDetailSettings
    )
  }

  private static var platform: Platform {

    #if os(macOS)
    .mac
    #else
    UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    #endif
  }
}

private actor FixtureModelLibraryService: ModelLibraryServing {
  let snapshot: ModelLibrarySnapshot
  init(snapshot: ModelLibrarySnapshot) { self.snapshot = snapshot }
  func snapshots() async -> AsyncStream<ModelLibrarySnapshot> {
    AsyncStream { continuation in continuation.yield(snapshot); continuation.finish() }
  }
  func perform(_ intent: ModelLibraryIntent, for modelID: ModelID) async throws {}
}

private actor FixtureChatService: ChatSessionServing {
  func stream(_ request: ChatSendRequest) async throws -> AsyncThrowingStream<ChatSessionEvent, any Error> {
    let id = UUID()
    return AsyncThrowingStream { continuation in
      continuation.yield(.assistantStarted(id: id))
      continuation.yield(.answer("This deterministic preview does not start the model runtime."))
      continuation.yield(.completed(.stop))
      continuation.finish()
    }
  }
  func cancel() async {}
}

private actor FixtureConversationService: ConversationNavigationServing {
  let snapshot: ConversationNavigationSnapshot

  init(snapshot: ConversationNavigationSnapshot) {
    self.snapshot = snapshot
  }

  func snapshots() -> AsyncStream<ConversationNavigationSnapshot> {
    AsyncStream { continuation in
      continuation.yield(snapshot)
      continuation.finish()
    }
  }

  func createConversation() async throws {}
  func selectConversation(_ id: ConversationID) async throws {}
}
// swiftlint:enable file_length
