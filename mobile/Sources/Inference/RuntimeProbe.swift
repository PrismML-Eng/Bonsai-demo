import Foundation
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

enum RuntimeProbe {
    static let generationParameters = GenerateParameters(
        maxTokens: 256,
        temperature: 0,
        seed: 0
    )

    enum Error: Swift.Error, Equatable {
        case modelDirectoryMissing
    }

    enum Event: Sendable {
        case modelLoaded(Duration)
        case chunk(String)
        case completed(GenerateCompletionInfo)
    }

    static func run(modelDirectory: URL) -> AsyncThrowingStream<String, Swift.Error> {
        AsyncThrowingStream<String, Swift.Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await event in measuredRun(modelDirectory: modelDirectory) {
                        if case .chunk(let chunk) = event {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func measuredRun(modelDirectory: URL) -> AsyncThrowingStream<Event, Swift.Error> {
        AsyncThrowingStream<Event, Swift.Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
                    continuation.finish(throwing: Error.modelDirectoryMissing)
                    return
                }

                do {
                    let clock = ContinuousClock()
                    let loadStarted = clock.now
                    let container = try await VLMModelFactory.shared.loadContainer(
                        from: modelDirectory,
                        using: #huggingFaceTokenizerLoader()
                    )
                    continuation.yield(.modelLoaded(loadStarted.duration(to: clock.now)))

                    let session = MLXLMCommon.ChatSession(
                        container,
                        generateParameters: generationParameters
                    )
                    for try await generation in session.streamDetails(
                        to: "Reply with exactly: bonsai ready"
                    ) {
                        switch generation {
                        case .chunk(let chunk):
                            continuation.yield(.chunk(chunk))
                        case .info(let info):
                            continuation.yield(.completed(info))
                        case .toolCall:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
