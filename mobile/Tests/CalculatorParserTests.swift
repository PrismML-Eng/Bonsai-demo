import Testing

@testable import BonsaiMobile

@Suite("Bounded calculator")
struct CalculatorParserTests {
  @Test func respectsPrecedenceAndParentheses() throws {
    #expect(try CalculatorParser.evaluate("2 + 3 * (4 - 1)") == 11)
    #expect(try CalculatorParser.evaluate("-(8 % 3)") == -2)
  }

  @Test func rejectsUnsafeAndUndefinedExpressions() {
    #expect(throws: CalculatorError.invalidToken) {
      try CalculatorParser.evaluate("system(1)")
    }
    #expect(throws: CalculatorError.divisionByZero) {
      try CalculatorParser.evaluate("1 / 0")
    }
    #expect(throws: CalculatorError.excessiveNesting) {
      try CalculatorParser.evaluate(
        String(repeating: "(", count: 33) + "1" + String(repeating: ")", count: 33))
    }
    #expect(throws: CalculatorError.excessiveTokens) {
      try CalculatorParser.evaluate(Array(repeating: "1", count: 130).joined(separator: "+"))
    }
  }
}
