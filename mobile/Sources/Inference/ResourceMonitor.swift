import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ResourceThermalState: String, Codable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

enum ResourcePressureEvent: Equatable, Sendable {
    case thermal(ResourceThermalState)
    case memoryWarning(count: Int)

    var isCritical: Bool {
        switch self {
        case .thermal(.critical), .memoryWarning:
            true
        case .thermal:
            false
        }
    }
}

protocol ResourceRecovering: Sendable {
    func cancelGeneration() async
    func releaseOptionalVisionState() async
    func clearReusableCaches() async
    func offerFullUnload() async
}

struct MLXResourceRecoverer: ResourceRecovering {
    private let engine: MLXInferenceEngine
    private let unloadOffer: @Sendable () async -> Void

    init(
        engine: MLXInferenceEngine,
        unloadOffer: @escaping @Sendable () async -> Void
    ) {
        self.engine = engine
        self.unloadOffer = unloadOffer
    }

    func cancelGeneration() async {
        await engine.cancelForCriticalRecovery()
    }

    func releaseOptionalVisionState() async {
        await engine.releaseOptionalVisionState()
    }

    func clearReusableCaches() async {
        await engine.clearReusableCaches()
    }

    func offerFullUnload() async {
        await unloadOffer()
    }
}

struct ResourceRecoverySnapshot: Equatable, Sendable {
    let fullUnloadOffered: Bool
    let coalescedEventCount: Int
}

actor ResourceRecoveryCoordinator {
    private let recoverer: any ResourceRecovering
    private var activeRecovery: Task<Void, Never>?
    private var recoveryCount = 0
    private var coalescedEventCount = 0

    init(recoverer: any ResourceRecovering) {
        self.recoverer = recoverer
    }

    func handle(_ event: ResourcePressureEvent) async {
        guard event.isCritical else { return }
        if let activeRecovery {
            coalescedEventCount += 1
            await activeRecovery.value
            return
        }

        let recovery = Task { [recoverer] in
            await recoverer.cancelGeneration()
            await recoverer.releaseOptionalVisionState()
            await recoverer.clearReusableCaches()
            await recoverer.offerFullUnload()
        }
        activeRecovery = recovery
        await recovery.value
        if activeRecovery != nil {
            activeRecovery = nil
            recoveryCount += 1
        }
    }

    func snapshot() -> ResourceRecoverySnapshot {
        ResourceRecoverySnapshot(
            fullUnloadOffered: recoveryCount > 0,
            coalescedEventCount: coalescedEventCount
        )
    }
}

protocol ResourceEventRegistering: Sendable {
    func install(
        _ yield: @escaping @Sendable (ResourcePressureEvent) -> Void
    ) async -> UUID
    func remove(_ token: UUID) async
}

struct PlatformResourceEventSource: Sendable {
    private let registrar: any ResourceEventRegistering

    init(registrar: any ResourceEventRegistering = NotificationResourceEventRegistrar()) {
        self.registrar = registrar
    }

    func events() -> AsyncStream<ResourcePressureEvent> {
        let lifetime = ResourceEventRegistrationLifetime(registrar: registrar)
        return AsyncStream { continuation in
            let installTask = Task {
                let token = await registrar.install { continuation.yield($0) }
                await lifetime.didInstall(token)
            }
            continuation.onTermination = { _ in
                installTask.cancel()
                Task { await lifetime.terminate() }
            }
        }
    }
}

private actor ResourceEventRegistrationLifetime {
    private let registrar: any ResourceEventRegistering
    private var token: UUID?
    private var terminated = false

    init(registrar: any ResourceEventRegistering) {
        self.registrar = registrar
    }

    func didInstall(_ token: UUID) async {
        if terminated {
            await registrar.remove(token)
        } else {
            self.token = token
        }
    }

    func terminate() async {
        guard !terminated else { return }
        terminated = true
        if let token {
            self.token = nil
            await registrar.remove(token)
        }
    }
}

actor NotificationResourceEventRegistrar: ResourceEventRegistering {
    private let center: NotificationCenter
    private var observers: [UUID: [NSObjectProtocol]] = [:]
    private var memoryWarningCount = 0

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    func install(
        _ yield: @escaping @Sendable (ResourcePressureEvent) -> Void
    ) async -> UUID {
        let id = UUID()
        var tokens: [NSObjectProtocol] = []
        tokens.append(
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: nil
            ) { _ in
                yield(.thermal(Self.thermalState(ProcessInfo.processInfo.thermalState)))
            }
        )
        #if canImport(UIKit)
        tokens.append(
            center.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { await self?.recordMemoryWarning(yield) }
            }
        )
        #endif
        observers[id] = tokens
        return id
    }

    func remove(_ token: UUID) async {
        guard let tokens = observers.removeValue(forKey: token) else { return }
        tokens.forEach(center.removeObserver)
    }

    private func recordMemoryWarning(
        _ yield: @escaping @Sendable (ResourcePressureEvent) -> Void
    ) {
        memoryWarningCount += 1
        yield(.memoryWarning(count: memoryWarningCount))
    }

    private nonisolated static func thermalState(
        _ state: ProcessInfo.ThermalState
    ) -> ResourceThermalState {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .critical
        }
    }
}
