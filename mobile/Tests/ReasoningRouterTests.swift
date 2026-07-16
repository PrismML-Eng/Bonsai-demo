import Testing
@testable import BonsaiMobile

@Suite("Reasoning stream router")
struct ReasoningRouterTests {
    @Test
    func routesDelimitersSplitAtEveryBoundary() {
        let input = "<think>plan</think>answer"

        for boundary in 0...input.count {
            var router = ReasoningRouter(start: "<think>", end: "</think>", primed: false)
            let index = input.index(input.startIndex, offsetBy: boundary)
            let events = router.consume(String(input[..<index]))
                + router.consume(String(input[index...]))
                + router.finalize()

            #expect(events.reasoningText == "plan")
            #expect(events.answerText == "answer")
            #expect(!events.description.contains("<think>"))
            #expect(!events.description.contains("</think>"))
        }
    }

    @Test
    func routesPrimedReasoningAndFlushesPartialDelimiter() {
        var router = ReasoningRouter(start: "<think>", end: "</think>", primed: true)

        #expect(router.consume("plan</thi") == [.reasoning("plan")])
        #expect(router.consume("nk>answer<thi") == [.answer("answer")])
        #expect(router.finalize() == [.answer("<thi")])
    }

    @Test
    func routesMultipleReasoningBlocksWithoutLeakingMarkers() {
        var router = ReasoningRouter(start: "<think>", end: "</think>", primed: false)
        let events = router.consume("<think>one</think>A<think>two</think>B") + router.finalize()

        #expect(events == [
            .reasoning("one"), .answer("A"), .reasoning("two"), .answer("B")
        ])
    }

    @Test
    func offModeRoutesAllTextAsAnswer() {
        var router = ReasoningRouter.disabled

        #expect(router.consume("literal <think>text</think>") == [
            .answer("literal <think>text</think>")
        ])
        #expect(router.finalize().isEmpty)
    }
}

private extension Array where Element == GenerationEvent {
    var reasoningText: String {
        compactMap { event in
            if case .reasoning(let text) = event { text } else { nil }
        }.joined()
    }

    var answerText: String {
        compactMap { event in
            if case .answer(let text) = event { text } else { nil }
        }.joined()
    }
}
