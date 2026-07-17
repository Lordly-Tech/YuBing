import SwiftUI

@main
struct YuBingWatchApp: App {
    @WKExtensionDelegateAdaptor(WatchExtensionDelegate.self) private var extensionDelegate
    @StateObject private var store = WatchLibraryStore()
    @StateObject private var player = WatchAudioPlayer()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                .environmentObject(player)
        }
    }
}
