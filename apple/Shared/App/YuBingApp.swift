import SwiftUI

@main
struct YuBingApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var player = AudioPlayerController()
    #if os(iOS)
    @StateObject private var watchTransfer = WatchTransferService()
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(player)
                #if os(iOS)
                .environmentObject(watchTransfer)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        #endif
    }
}

