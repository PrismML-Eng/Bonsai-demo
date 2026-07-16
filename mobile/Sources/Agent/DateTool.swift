import Foundation

struct DateTool: OfflineTool {
  let schema = OfflineToolSchema(
    name: "current_date_time",
    description: "Return the current local and ISO-8601 date and time.",
    parametersJSON: "{\"additionalProperties\":false,\"properties\":{},\"type\":\"object\"}"
  )
  private let now: @Sendable () -> Date
  private let locale: Locale
  private let timeZone: TimeZone

  init(
    now: @escaping @Sendable () -> Date = { Date() },
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) {
    self.now = now
    self.locale = locale
    self.timeZone = timeZone
  }

  func validate(arguments: ToolJSON) throws {
    guard try arguments.object().isEmpty else { throw ToolBoundaryError.invalid("arguments") }
  }

  func execute(arguments: ToolJSON) async throws -> ToolJSON {
    try validate(arguments: arguments)
    let date = now()
    let iso = ISO8601DateFormatter()
    iso.timeZone = timeZone
    iso.formatOptions = [.withInternetDateTime]
    let local = DateFormatter()
    local.locale = locale
    local.timeZone = timeZone
    local.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
    return .object([
      "iso8601": .string(iso.string(from: date)),
      "local": .string(local.string(from: date)),
      "locale": .string(locale.identifier),
      "timeZone": .string(timeZone.identifier)
    ])
  }
}
