import CoreGraphics
import Foundation
import XCTest
@testable import BonsaiMobile

final class VisionRequestTests: XCTestCase {
  func testRequestCarriesOneManagedImageOnItsOwningUserTurn() throws {
    let attachment = try ImageAttachmentReference(
      id: UUID(), managedRelativePath: "image.jpg", pixelSize: .init(width: 640, height: 480),
      byteCount: 120, contentType: "image/jpeg", detailPolicy: .fast1024,
      accessibleLabel: "Desk photo")
    let user = ConversationMessage(
      id: MessageID("user-1"), role: .user, content: "What is here?", attachments: [attachment])
    let request = try GenerationRequest(messages: [user], images: [
      .init(messageID: user.id, attachmentID: attachment.id,
            buffer: try testImageBuffer())
    ])

    XCTAssertEqual(request.images.count, 1)
    XCTAssertEqual(request.images.first?.messageID, user.id)
    let messages = try MLXPromptComposer.chatMessages(request.messages ?? [], images: request.images)
    XCTAssertEqual(messages.first?.images.count, 1)
  }

  func testVisionToolPrefaceAnchorsToolUseBeforeImageTurn() throws {
    let attachment = try ImageAttachmentReference(
      id: UUID(), managedRelativePath: "image.jpg", pixelSize: .init(width: 640, height: 480),
      byteCount: 120, contentType: "image/jpeg", detailPolicy: .fast1024,
      accessibleLabel: "Desk photo")
    let user = ConversationMessage(
      id: MessageID("user-1"), role: .user, content: "Inspect", attachments: [attachment])
    let tools = [GenerationToolSpecification(name: "calculator", description: "calc", parametersJSON: "{}")]
    let messages = try MLXPromptComposer.chatMessages(
      [user],
      images: [.init(messageID: user.id, attachmentID: attachment.id, buffer: try testImageBuffer())],
      tools: tools)
    let content = try XCTUnwrap(messages.first?.content)
    XCTAssertTrue(content.hasPrefix("If my request requires a tool"))
    XCTAssertTrue(content.hasSuffix("Inspect"))
  }

  func testDuplicateImageBindingsAreRejectedBeforePromptComposition() throws {
    let attachment = try ImageAttachmentReference(
      id: UUID(), managedRelativePath: "image.jpg", pixelSize: .init(width: 640, height: 480),
      byteCount: 120, contentType: "image/jpeg", detailPolicy: .fast1024,
      accessibleLabel: "Desk photo", lifecycle: .persisted)
    let user = ConversationMessage(
      id: MessageID("user-1"), role: .user, content: "Inspect", attachments: [attachment])
    let binding = GenerationImage(
      messageID: user.id, attachmentID: attachment.id,
      buffer: try testImageBuffer())
    XCTAssertThrowsError(try MLXPromptComposer.chatMessages([user], images: [binding, binding])) {
      XCTAssertEqual($0 as? MLXInferenceError, .invalidImageBinding)
    }
  }

  func testCorruptAttachmentReferencesAndNonUserOwnershipAreRejected() throws {
    let invalid = """
    {"id":"7F34B8BC-B904-4D25-88AF-52404CC531F0","managedRelativePath":"../x.jpg",\
    "pixelSize":{"width":10,"height":10},"byteCount":1,"contentType":"image/jpeg",\
    "detailPolicy":"fast1024","accessibleLabel":"x","lifecycle":"persisted"}
    """
    XCTAssertThrowsError(try JSONDecoder().decode(
      ImageAttachmentReference.self, from: Data(invalid.utf8)))

    let reference = try ImageAttachmentReference(
      id: UUID(), managedRelativePath: "x.jpg", pixelSize: .init(width: 10, height: 10),
      byteCount: 1, contentType: "image/jpeg", detailPolicy: .fast1024,
      accessibleLabel: "x", lifecycle: .persisted)
    XCTAssertThrowsError(try Conversation(
      id: ConversationID("invalid-attachments"), modelID: .oneBit27B,
      modelRevision: String(repeating: "a", count: 40), revision: 0,
      systemInstruction: .init(id: MessageID("system"), role: .system, content: "System"),
      completedTurns: [.init(id: "turn", messages: [
        .init(id: MessageID("user"), role: .user, content: "Hi"),
        .init(id: MessageID("assistant"), role: .assistant, content: "No", attachments: [reference])
      ])]))
  }

  func testContinuationDoesNotReinjectInitialImage() throws {
    let exchange = AgentToolExchange(invocations: [], results: [])
    let continuation = try MLXPromptComposer.toolContinuationPrompt(exchange)
    XCTAssertFalse(continuation.contains("processed.jpg"))
  }

  func testImageBudgetRemovesOldestWholeTurnBeforeAnyDecode() throws {
    let old = try imageReference(name: "old.jpg", detail: .fast1024)
    let recent = try imageReference(name: "recent.jpg", detail: .fast1024)
    let conversation = try conversation(turns: [turn(id: "old", attachment: old),
                                                turn(id: "recent", attachment: recent)])
    let required = ConversationMessage(
      id: MessageID("required"), role: .user, content: "inspect",
      attachments: [try imageReference(name: "required.jpg", detail: .fast1024)])
    let budget = ImageRequestBudget(
      maximumImages: 2, maximumSourceBytes: 1_000_000,
      maximumProcessedPixels: 3_000_000, maximumVisionTokens: 2_048, patchSize: 32)

    let result = try budget.trim(conversation, appending: [required])

    XCTAssertEqual(result.removedTurnCount, 1)
    XCTAssertEqual(result.conversation.completedTurns.map(\.id), ["recent"])
  }

  func testAggregateFullDetailImagesAreRejectedBeforePreprocessing() throws {
    let required = ConversationMessage(
      id: MessageID("required"), role: .user, content: "OCR",
      attachments: [try imageReference(name: "huge.jpg", detail: .fullDetail,
                                       size: .init(width: 4_000, height: 3_000))])
    XCTAssertThrowsError(try ImageRequestBudget.live.trim(
      try conversation(turns: []), appending: [required])) {
      XCTAssertEqual($0 as? ImageRequestBudgetError, .requiredImagesExceedBudget)
    }
  }

  private func imageReference(
    name: String, detail: ImageDetailPolicy, size: PixelSize = .init(width: 1_024, height: 1_024)
  ) throws -> ImageAttachmentReference {
    try .init(id: UUID(), managedRelativePath: name, pixelSize: size, byteCount: 100,
              contentType: "image/jpeg", detailPolicy: detail, accessibleLabel: name)
  }

  private func turn(id: String, attachment: ImageAttachmentReference) -> CompletedConversationTurn {
    .init(id: id, messages: [
      .init(id: MessageID("\(id)-user"), role: .user, content: "image", attachments: [attachment]),
      .init(id: MessageID("\(id)-assistant"), role: .assistant, content: "answer")
    ])
  }

  private func conversation(turns: [CompletedConversationTurn]) throws -> Conversation {
    try .init(id: ConversationID("vision-budget"), modelID: .oneBit27B,
              modelRevision: String(repeating: "a", count: 40), revision: 1,
              systemInstruction: .init(id: MessageID("system"), role: .system, content: "system"),
              completedTurns: turns)
  }

  private func testImageBuffer() throws -> ProcessedImageBuffer {
    let context = try XCTUnwrap(CGContext(
      data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    return .init(image: try XCTUnwrap(context.makeImage()))
  }
}
