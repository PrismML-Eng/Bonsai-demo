import SwiftUI
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
    }
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
}

struct RootView: View {
  @State private var libraryViewModel: ModelLibraryViewModel
  @State private var chatViewModel: ChatViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var showsLibrary = false
  private let platform: Platform

  init(composition: RootComposition = .process()) {
    _libraryViewModel = State(initialValue: composition.libraryViewModel)
    _chatViewModel = State(initialValue: composition.chatViewModel)
    platform = composition.platform
  }

  var body: some View {
    Group {
        if RootNavigationState.layout(platform: platform, compactWidth: horizontalSizeClass == .compact) == .stack {
          NavigationStack { ChatView(viewModel: chatViewModel).toolbar { libraryToolbar } }
        } else {
          NavigationSplitView {
            ModelLibraryView(viewModel: libraryViewModel)
          } detail: {
            ChatView(viewModel: chatViewModel)
          }
          .navigationSplitViewStyle(.balanced)
        }
      }
      .animation(QuietGardenTheme.animation(reduceMotion: reduceMotion), value: horizontalSizeClass)
    .tint(QuietGardenTheme.accent)
    .accessibilityIdentifier(UIAccessibility.root)
    .onChange(of: libraryViewModel.loadedModelID) {
      chatViewModel.isModelReady = libraryViewModel.loadedModelID != nil
      chatViewModel.loadedModelName = switch libraryViewModel.loadedModelID {
      case .oneBit27B: "Bonsai 27B · 1-bit"
      case .ternary27B: "Ternary Bonsai 27B"
      case nil: nil
      }
    }
    .sheet(isPresented: $showsLibrary) {
      NavigationStack { ModelLibraryView(viewModel: libraryViewModel) }
    }
  }

  @ToolbarContentBuilder private var libraryToolbar: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      Button { showsLibrary = true } label: {
        Label("Model Library", systemImage: "shippingbox")
      }
      .accessibilityHint("Manage local Bonsai models")
    }
  }
}

@MainActor
struct RootComposition {
  let libraryViewModel: ModelLibraryViewModel
  let chatViewModel: ChatViewModel
  let platform: Platform

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

  static func fixture(_ fixture: UIFixture) -> RootComposition {
    fixtureComposition(fixture.makeState())
  }

  private static func fixtureComposition(_ state: UIFixtureState) -> RootComposition {
    let library = FixtureModelLibraryService(snapshot: state.library)
    let chat = FixtureChatService()
    let libraryViewModel = ModelLibraryViewModel(service: library, platform: state.platform,
                                                 initial: state.library)
    let chatViewModel = ChatViewModel(service: chat, isModelReady: state.modelReady)
    chatViewModel.applyFixture(state)
    return RootComposition(libraryViewModel: libraryViewModel, chatViewModel: chatViewModel,
                           platform: state.platform)
  }

  private static func live() throws -> RootComposition {
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
      .appending(path: "BonsaiMobile", directoryHint: .isDirectory)
    let engine = MLXInferenceEngine()
    let library = try LiveModelLibraryService(root: support.appending(path: "Models"), engine: engine)
    let notes = try NotesStore(root: support)
    let registry = try ToolRegistry.live(notes: notes)
    let approvalGate = InteractiveApprovalGate()
    let loop = AgentLoop(engine: engine, registry: registry, approvals: approvalGate)
    let conversations = try ConversationStore(root: support)
    let chat = AgentLoopChatService(loop: loop, approvals: approvalGate, engine: engine,
                                    conversationStore: conversations,
                                    conversationID: try ConversationID("main"))
    let initial = ModelLibrarySnapshot.fixture(.empty)
    return RootComposition(
      libraryViewModel: ModelLibraryViewModel(service: library, platform: Self.platform, initial: initial),
      chatViewModel: ChatViewModel(service: chat, isModelReady: false), platform: Self.platform
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
