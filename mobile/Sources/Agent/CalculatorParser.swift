import Foundation

enum CalculatorError: Error, Equatable, Sendable {
  case emptyExpression
  case excessiveLength
  case excessiveTokens
  case excessiveNesting
  case invalidToken
  case malformedExpression
  case divisionByZero
  case nonFiniteResult
}

enum CalculatorParser {
  static func evaluate(_ expression: String) throws -> Double {
    guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CalculatorError.emptyExpression
    }
    guard expression.utf8.count <= 1_024 else { throw CalculatorError.excessiveLength }
    var parser = Parser(expression)
    let value = try parser.expression()
    parser.skipWhitespace()
    guard parser.isAtEnd else { throw CalculatorError.invalidToken }
    guard value.isFinite else { throw CalculatorError.nonFiniteResult }
    return value
  }

  private struct Parser {
    private let characters: [Character]
    private var index = 0
    private var tokens = 0
    private var depth = 0
    var isAtEnd: Bool { index == characters.count }

    init(_ input: String) { characters = Array(input) }

    mutating func expression() throws -> Double {
      var value = try term()
      while true {
        skipWhitespace()
        if try consume("+") {
          value = try checked(value + term())
        } else if try consume("-") {
          value = try checked(value - term())
        } else {
          return value
        }
      }
    }

    private mutating func term() throws -> Double {
      var value = try unary()
      while true {
        skipWhitespace()
        if try consume("*") {
          value = try checked(value * unary())
        } else if try consume("/") {
          let rhs = try unary()
          guard rhs != 0 else { throw CalculatorError.divisionByZero }
          value = try checked(value / rhs)
        } else if try consume("%") {
          let rhs = try unary()
          guard rhs != 0 else { throw CalculatorError.divisionByZero }
          value = try checked(value.truncatingRemainder(dividingBy: rhs))
        } else {
          return value
        }
      }
    }

    private mutating func unary() throws -> Double {
      skipWhitespace()
      if try consume("-") { return try checked(-unary()) }
      if try consume("+") { return try unary() }
      return try primary()
    }

    private mutating func primary() throws -> Double {
      skipWhitespace()
      if try consume("(") {
        depth += 1
        guard depth <= 32 else { throw CalculatorError.excessiveNesting }
        let value = try expression()
        skipWhitespace()
        guard try consume(")") else { throw CalculatorError.malformedExpression }
        depth -= 1
        return value
      }
      let start = index
      var sawDigit = false
      var sawDot = false
      while index < characters.count {
        let character = characters[index]
        if character.isNumber {
          sawDigit = true
          index += 1
        } else if character == ".", !sawDot {
          sawDot = true
          index += 1
        } else {
          break
        }
      }
      guard sawDigit, let value = Double(String(characters[start..<index])) else {
        throw CalculatorError.invalidToken
      }
      try recordToken()
      return value
    }

    mutating func skipWhitespace() {
      while index < characters.count, characters[index].isWhitespace { index += 1 }
    }

    private mutating func consume(_ character: Character) throws -> Bool {
      guard index < characters.count, characters[index] == character else { return false }
      index += 1
      try recordToken()
      return true
    }

    private mutating func recordToken() throws {
      tokens += 1
      guard tokens <= 128 else { throw CalculatorError.excessiveTokens }
    }

    private func checked(_ value: Double) throws -> Double {
      guard value.isFinite else { throw CalculatorError.nonFiniteResult }
      return value
    }
  }
}

struct CalculatorTool: OfflineTool {
  let schema = OfflineToolSchema(
    name: "calculator",
    description: "Evaluate a bounded arithmetic expression locally.",
    parametersJSON:
      // swiftlint:disable:next line_length
      "{\"additionalProperties\":false,\"properties\":{\"expression\":{\"maxLength\":1024,\"type\":\"string\"}},\"required\":[\"expression\"],\"type\":\"object\"}"
  )

  func validate(arguments: ToolJSON) throws {
    try arguments.requireObjectKeys(allowed: ["expression"], required: ["expression"])
    let expression = try arguments.requiredString("expression")
    guard expression.utf8.count <= 1_024 else { throw ToolBoundaryError.invalid("expression") }
  }
  func execute(arguments: ToolJSON) async throws -> ToolJSON {
    let result = try CalculatorParser.evaluate(arguments.requiredString("expression"))
    return .object(["result": .double(result)])
  }
}
