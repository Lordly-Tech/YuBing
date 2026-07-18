import SwiftUI

@main
struct YuBingApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var player = AudioPlayerController()
    @StateObject private var readingStore = ReadingStore()
    #if os(iOS)
    @StateObject private var watchTransfer = WatchTransferService()
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(player)
                .environmentObject(readingStore)
                #if os(iOS)
                .environmentObject(watchTransfer)
                .onAppear { watchTransfer.attach(readingStore: readingStore) }
                #endif
                .onOpenURL { url in
                    store.importFiles([url])
                }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        #endif
    }
}
