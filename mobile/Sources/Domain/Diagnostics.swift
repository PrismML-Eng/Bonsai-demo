import Foundation

enum DiagnosticStage: String, Codable, Sendable {
    case download
    case load
    case prefill
    case generation
    case tool
    case recovery
}

enum DiagnosticCategory: String, Codable, Sendable {
    case started
    case completed
    case cancelled
    case failure
    case resourcePressure
}

enum DiagnosticValidationError: Error, Equatable, Sendable {
    case negativeElapsedMilliseconds
    case negativePromptTokenCount
    case negativeGeneratedTokenCount
    case invalidTokenRate
    case negativeMemoryWarningCount
    case invalidModelRevision
}

/// An intentionally closed, content-free diagnostic schema. There is no
/// arbitrary metadata, prompt, response, path, URL, note, or tool-content field.
struct DiagnosticRecord: Codable, Equatable, Sendable {
    let stage: DiagnosticStage
    let category: DiagnosticCategory
    let elapsedMilliseconds: Int
    let promptTokenCount: Int
    let generatedTokenCount: Int
    let tokenRate: Double
    let thermalState: ResourceThermalState
    let memoryWarningCount: Int
    let modelID: ModelID
    let modelRevision: String
    let timestamp: Date

    init(
        stage: DiagnosticStage,
        category: DiagnosticCategory,
        elapsedMilliseconds: Int,
        promptTokenCount: Int,
        generatedTokenCount: Int,
        tokenRate: Double,
        thermalState: ResourceThermalState,
        memoryWarningCount: Int,
        modelID: ModelID,
        modelRevision: String,
        timestamp: Date
    ) throws {
        self.stage = stage
        self.category = category
        self.elapsedMilliseconds = elapsedMilliseconds
        self.promptTokenCount = promptTokenCount
        self.generatedTokenCount = generatedTokenCount
        self.tokenRate = tokenRate
        self.thermalState = thermalState
        self.memoryWarningCount = memoryWarningCount
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.timestamp = timestamp
        try validate()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stage = try container.decode(DiagnosticStage.self, forKey: .stage)
        category = try container.decode(DiagnosticCategory.self, forKey: .category)
        elapsedMilliseconds = try container.decode(Int.self, forKey: .elapsedMilliseconds)
        promptTokenCount = try container.decode(Int.self, forKey: .promptTokenCount)
        generatedTokenCount = try container.decode(Int.self, forKey: .generatedTokenCount)
        tokenRate = try container.decode(Double.self, forKey: .tokenRate)
        thermalState = try container.decode(ResourceThermalState.self, forKey: .thermalState)
        memoryWarningCount = try container.decode(Int.self, forKey: .memoryWarningCount)
        modelID = try container.decode(ModelID.self, forKey: .modelID)
        modelRevision = try container.decode(String.self, forKey: .modelRevision)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        try validate()
    }

    private func validate() throws {
        guard elapsedMilliseconds >= 0 else {
            throw DiagnosticValidationError.negativeElapsedMilliseconds
        }
        guard promptTokenCount >= 0 else {
            throw DiagnosticValidationError.negativePromptTokenCount
        }
        guard generatedTokenCount >= 0 else {
            throw DiagnosticValidationError.negativeGeneratedTokenCount
        }
        guard tokenRate.isFinite, tokenRate >= 0 else {
            throw DiagnosticValidationError.invalidTokenRate
        }
        guard memoryWarningCount >= 0 else {
            throw DiagnosticValidationError.negativeMemoryWarningCount
        }
        guard isLowercaseHex(modelRevision, count: 40) else {
            throw DiagnosticValidationError.invalidModelRevision
        }
    }
}
