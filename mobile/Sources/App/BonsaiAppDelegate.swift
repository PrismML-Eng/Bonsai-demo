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
        BackgroundModelDownloadCoordinator.shared.setBackgroundEventsCompletion(completionHandler)
    }
}
#endif
