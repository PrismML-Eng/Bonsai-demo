import MLXLMCommon

struct ReasoningRouter: Sendable {
    private var emitter: ReasoningEventEmitter?
    private let answerOnly: Bool

    static var disabled: Self {
        disabled(start: "<think>", end: "</think>")
    }

    static func disabled(start: String, end: String) -> Self {
        Self(
            emitter: ReasoningEventEmitter(
                config: ReasoningConfig(
                    startDelimiter: start,
                    endDelimiter: end,
                    promptStrategy: .templateFlag(key: "enable_thinking", defaultOn: true)
                ),
                primedInside: false
            ),
            answerOnly: true
        )
    }

    static func disabled(config: ReasoningConfig?) -> Self {
        guard let config else { return .disabled }
        return Self(
            emitter: ReasoningEventEmitter(config: config, primedInside: false),
            answerOnly: true
        )
    }

    init(start: String, end: String, primed: Bool) {
        emitter = ReasoningEventEmitter(
            config: ReasoningConfig(
                startDelimiter: start,
                endDelimiter: end,
                promptStrategy: .templateFlag(key: "enable_thinking", defaultOn: true)
            ),
            primedInside: primed
        )
        answerOnly = false
    }

    init(config: ReasoningConfig, primed: Bool) {
        emitter = ReasoningEventEmitter(config: config, primedInside: primed)
        answerOnly = false
    }

    private init(emitter: ReasoningEventEmitter, answerOnly: Bool) {
        self.emitter = emitter
        self.answerOnly = answerOnly
    }

    mutating func consume(_ chunk: String) -> [GenerationEvent] {
        guard var emitter else { return [] }
        let events = emitter.process(chunk).map(map)
        self.emitter = emitter
        return events
    }

    mutating func finalize() -> [GenerationEvent] {
        guard var emitter else { return [] }
        let events = emitter.finalize().map(map)
        self.emitter = emitter
        return events
    }

    private func map(_ segment: ReasoningEventEmitter.Segment) -> GenerationEvent {
        if answerOnly {
            switch segment {
            case .reasoning(let text), .response(let text): return .answer(text)
            }
        }
        switch segment {
        case .reasoning(let text): return .reasoning(text)
        case .response(let text): return .answer(text)
        }
    }
}
