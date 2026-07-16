import Foundation
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

enum RuntimeProbe {
    enum Error: Swift.Error, Equatable {
        case modelDirectoryMissing
    }

    static func run(modelDirectory: URL) -> AsyncThrowingStream<String, Swift.Error> {
        AsyncThrowingStream<String, Swift.Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
                    continuation.finish(throwing: Error.modelDirectoryMissing)
                    return
                }

                do {
                    let container = try await VLMModelFactory.shared.loadContainer(
                        from: modelDirectory,
                        using: #huggingFaceTokenizerLoader()
                    )
                    let session = ChatSession(container)
                    for try await chunk in session.streamResponse(
                        to: "Reply with exactly: bonsai ready"
                    ) {
                        continuation.yield(chunk)
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
