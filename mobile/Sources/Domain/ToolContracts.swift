import Foundation

struct ToolInvocation: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let argumentsJSON: String
}

enum ToolApproval: String, Codable, Equatable, Sendable {
    case automaticReadOnly
    case requireAllowOnce
}
