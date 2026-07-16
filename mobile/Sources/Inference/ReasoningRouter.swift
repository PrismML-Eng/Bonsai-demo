import MLXLMCommon

struct ReasoningRouter: Sendable {
    private var emitter: ReasoningEventEmitter?

    static var disabled: Self { Self(emitter: nil) }

    init(start: String, end: String, primed: Bool) {
        emitter = ReasoningEventEmitter(
            config: ReasoningConfig(
                startDelimiter: start,
                endDelimiter: end,
                promptStrategy: .templateFlag(key: "enable_thinking", defaultOn: true)
            ),
            primedInside: primed
        )
    }

    init(config: ReasoningConfig, primed: Bool) {
        emitter = ReasoningEventEmitter(config: config, primedInside: primed)
    }

    private init(emitter: ReasoningEventEmitter?) {
        self.emitter = emitter
    }

    mutating func consume(_ chunk: String) -> [GenerationEvent] {
        guard var emitter else { return chunk.isEmpty ? [] : [.answer(chunk)] }
        let events = emitter.process(chunk).map(Self.map)
        self.emitter = emitter
        return events
    }

    mutating func finalize() -> [GenerationEvent] {
        guard var emitter else { return [] }
        let events = emitter.finalize().map(Self.map)
        self.emitter = emitter
        return events
    }

    private static func map(_ segment: ReasoningEventEmitter.Segment) -> GenerationEvent {
        switch segment {
        case .reasoning(let text): .reasoning(text)
        case .response(let text): .answer(text)
        }
    }
}
