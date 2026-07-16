import Foundation

enum ImageRequestBudgetError: Error, Equatable, Sendable {
  case requiredImagesExceedBudget
  case invalidAttachmentGeometry
}

struct ImageBudgetTrimResult: Sendable {
  let conversation: Conversation
  let removedTurnCount: Int
  let removedMessageCount: Int
}

struct ImageRequestBudget: Sendable {
  static let live = Self(
    maximumImages: 4,
    maximumSourceBytes: 100 * 1_024 * 1_024,
    maximumProcessedPixels: 4 * 1_024 * 1_024,
    maximumVisionTokens: 4_096,
    patchSize: 32)

  let maximumImages: Int
  let maximumSourceBytes: Int64
  let maximumProcessedPixels: Int
  let maximumVisionTokens: Int
  let patchSize: Int

  func trim(
    _ conversation: Conversation,
    appending requiredMessages: [ConversationMessage]
  ) throws -> ImageBudgetTrimResult {
    guard try fits(requiredMessages) else { throw ImageRequestBudgetError.requiredImagesExceedBudget }
    var turns = conversation.completedTurns
    var removedTurns = 0
    var removedMessages = 0
    while try !fits(turns.flatMap(\.messages) + requiredMessages) {
      guard let first = turns.first else {
        throw ImageRequestBudgetError.requiredImagesExceedBudget
      }
      removedTurns += 1
      removedMessages += first.messages.count
      turns.removeFirst()
    }
    return .init(
      conversation: try Conversation(
        id: conversation.id, modelID: conversation.modelID,
        modelRevision: conversation.modelRevision, revision: conversation.revision,
        systemInstruction: conversation.systemInstruction, completedTurns: turns),
      removedTurnCount: removedTurns,
      removedMessageCount: removedMessages)
  }

  private func fits(_ messages: [ConversationMessage]) throws -> Bool {
    let attachments = messages.flatMap(\.attachments)
    guard attachments.count <= maximumImages else { return false }
    var bytes: Int64 = 0
    var pixels = 0
    var tokens = 0
    for attachment in attachments {
      let nextBytes = bytes.addingReportingOverflow(attachment.byteCount)
      guard !nextBytes.overflow else { return false }
      bytes = nextBytes.partialValue
      guard let sourcePixels = attachment.pixelSize.pixelCount else {
        throw ImageRequestBudgetError.invalidAttachmentGeometry
      }
      let imageTokens = try effectiveTokens(attachment)
      let imagePixels = attachment.detailPolicy == .fast1024
        ? min(sourcePixels, imageTokens * patchSize * patchSize)
        : sourcePixels
      let nextPixels = pixels.addingReportingOverflow(imagePixels)
      let nextTokens = tokens.addingReportingOverflow(imageTokens)
      guard !nextPixels.overflow, !nextTokens.overflow else { return false }
      pixels = nextPixels.partialValue
      tokens = nextTokens.partialValue
    }
    return bytes <= maximumSourceBytes
      && pixels <= maximumProcessedPixels
      && tokens <= maximumVisionTokens
  }

  private func effectiveTokens(_ attachment: ImageAttachmentReference) throws -> Int {
    guard patchSize > 0 else { throw ImageRequestBudgetError.invalidAttachmentGeometry }
    let columns = (attachment.pixelSize.width + patchSize - 1) / patchSize
    let rows = (attachment.pixelSize.height + patchSize - 1) / patchSize
    let area = columns.multipliedReportingOverflow(by: rows)
    guard !area.overflow else { throw ImageRequestBudgetError.invalidAttachmentGeometry }
    return attachment.detailPolicy == .fast1024 ? min(1_024, area.partialValue) : area.partialValue
  }
}
