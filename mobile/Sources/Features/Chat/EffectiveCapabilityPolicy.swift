struct EffectiveCapabilityPolicy: Equatable, Sendable {
  let capabilities: Set<ModelCapability>
  init(_ capabilities: Set<ModelCapability>) { self.capabilities = capabilities }
  var allowsVision: Bool { capabilities.contains(.vision) }
  var allowsTools: Bool { capabilities.contains(.toolCalling) }
  var allowsThinking: Bool { capabilities.contains(.thinking) }
  func reasoningBudget(requested: ReasoningEffort) -> Int {
    allowsThinking ? requested.tokenBudget : 0
  }
}
