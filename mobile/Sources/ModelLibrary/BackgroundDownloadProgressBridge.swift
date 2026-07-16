import Foundation

/// Serializes synchronous URLSession delegate progress into an async consumer.
///
/// URLSession reports bytes for the current task. The model library reports bytes
/// for the complete file, so a restored range request must add its durable prefix.
final class BackgroundDownloadProgressBridge: @unchecked Sendable {
    private struct Entry {
        let generation: UUID
        let existingBytes: Int
        let expectedBytes: Int
        let progress: @Sendable (Int) async -> Void
        var lastTaskBytes: Int
        var tail: RetainedTail?
    }

    private struct RetainedTail {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var retainedTails: [UUID: RetainedTail] = [:]

    func attach(
        id: UUID,
        existingBytes: Int,
        expectedBytes: Int,
        taskBytesReceived: Int64,
        progress: @escaping @Sendable (Int) async -> Void
    ) {
        let taskBytes = Self.safeInt(taskBytesReceived)
        lock.withLock {
            let generation = UUID()
            entries[id] = Entry(
                generation: generation,
                existingBytes: max(0, existingBytes),
                expectedBytes: max(0, expectedBytes),
                progress: progress,
                lastTaskBytes: max(0, taskBytes),
                tail: nil
            )
            enqueueLocked(id: id, generation: generation)
        }
    }

    func report(id: UUID, taskBytesReceived: Int64) {
        let received = max(0, Self.safeInt(taskBytesReceived))
        lock.withLock {
            guard var entry = entries[id], received > entry.lastTaskBytes else { return }
            entry.lastTaskBytes = received
            entries[id] = entry
            enqueueLocked(id: id, generation: entry.generation)
        }
    }

    func detach(id: UUID) {
        lock.withLock {
            guard let entry = entries.removeValue(forKey: id), let tail = entry.tail else { return }
            retainLocked(tail, id: id)
        }
    }

    func flush(id: UUID) async {
        let tail = lock.withLock { entries[id]?.tail?.task ?? retainedTails[id]?.task }
        await tail?.value
    }

    private func enqueueLocked(id: UUID, generation: UUID) {
        guard var entry = entries[id], entry.generation == generation else { return }
        let previous = entry.tail?.task
        let callback = entry.progress
        let value = min(
            entry.expectedBytes,
            Self.saturatingAdd(entry.existingBytes, entry.lastTaskBytes)
        )
        let delivery = Task { [weak self] in
            await previous?.value
            guard self?.isAttached(id: id, generation: generation) == true else { return }
            await callback(value)
        }
        let retained = RetainedTail(token: UUID(), task: delivery)
        entry.tail = retained
        entries[id] = entry
        retainLocked(retained, id: id)
    }

    private func retainLocked(_ retained: RetainedTail, id: UUID) {
        retainedTails[id] = retained
        Task { [weak self] in
            await retained.task.value
            self?.releaseRetainedTail(id: id, token: retained.token)
        }
    }

    private func releaseRetainedTail(id: UUID, token: UUID) {
        lock.withLock {
            guard retainedTails[id]?.token == token else { return }
            retainedTails.removeValue(forKey: id)
        }
    }

    private func isAttached(id: UUID, generation: UUID) -> Bool {
        lock.withLock { entries[id]?.generation == generation }
    }

    private static func safeInt(_ value: Int64) -> Int {
        if value <= 0 { return 0 }
        if value >= Int64(Int.max) { return Int.max }
        return Int(value)
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}
