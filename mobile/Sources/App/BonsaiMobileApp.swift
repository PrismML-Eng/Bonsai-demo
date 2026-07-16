import SwiftUI

@main
struct BonsaiMobileApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(BonsaiAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 360, minHeight: 520)
        }
    }
}
