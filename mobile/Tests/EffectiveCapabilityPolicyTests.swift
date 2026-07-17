import Testing
@testable import BonsaiMobile

@Suite("Evidence-qualified feature admission")
struct EffectiveCapabilityPolicyTests {
  @Test func textOnlyDisablesThinkingToolsAndVision() {
    let policy = EffectiveCapabilityPolicy([.textGeneration])
    #expect(policy.reasoningBudget(requested: .high) == 0)
    #expect(policy.allowsTools == false)
    #expect(policy.allowsVision == false)
  }

  @Test func eachFeatureRequiresItsOwnCapability() {
    #expect(EffectiveCapabilityPolicy([.textGeneration, .thinking])
      .reasoningBudget(requested: .low) == ReasoningEffort.low.tokenBudget)
    #expect(EffectiveCapabilityPolicy([.textGeneration, .toolCalling]).allowsTools)
    #expect(EffectiveCapabilityPolicy([.textGeneration, .vision]).allowsVision)
  }
}
