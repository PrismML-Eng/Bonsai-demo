#if os(iOS)
import UIKit

final class BonsaiAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundModelDownloadCoordinator.sessionIdentifier else {
            completionHandler()
            return
        }
        let completion = BackgroundEventsCompletion(completionHandler)
        BackgroundModelDownloadCoordinator.shared.setBackgroundEventsCompletion { completion.call() }
    }
}

/// UIKit owns this callback and permits exactly one invocation after background events drain.
/// The coordinator serializes and clears it under a lock before calling it.
private final class BackgroundEventsCompletion: @unchecked Sendable {
    private let completion: () -> Void
    init(_ completion: @escaping () -> Void) { self.completion = completion }
    func call() { completion() }
}
#endif
