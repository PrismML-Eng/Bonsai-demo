import Foundation

struct ToolRegistry: Sendable {
  private let tools: [String: any OfflineTool]
  let specifications: [GenerationToolSpecification]

  init(_ tools: [any OfflineTool]) throws {
    var indexed: [String: any OfflineTool] = [:]
    for tool in tools {
      guard indexed[tool.schema.name] == nil else {
        throw ToolBoundaryError.duplicateToolName(tool.schema.name)
      }
      indexed[tool.schema.name] = tool
    }
    self.tools = indexed
    specifications = tools.map {
      GenerationToolSpecification(
        name: $0.schema.name,
        description: $0.schema.description,
        parametersJSON: $0.schema.parametersJSON
      )
    }
  }

  static func live(notes: NotesStore) throws -> ToolRegistry {
    try ToolRegistry([CalculatorTool(), DateTool(), DeviceInfoTool(), NotesTool(store: notes)])
  }

  func resolve(_ invocation: ToolInvocation) throws -> (any OfflineTool, ToolJSON) {
    guard let tool = tools[invocation.name] else {
      throw ToolBoundaryError.unknownTool(invocation.name)
    }
    let arguments = try ToolJSON.decode(invocation.argumentsJSON)
    try tool.validate(arguments: arguments)
    return (tool, arguments)
  }
}
