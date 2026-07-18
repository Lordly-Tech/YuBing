import SwiftUI

@main
struct YuBingApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var player = AudioPlayerController()
    @StateObject private var readingStore = ReadingStore()
    @StateObject private var wifiTransfer = WiFiTransferService()
    #if os(iOS)
    @StateObject private var watchTransfer = WatchTransferService()
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(player)
                .environmentObject(readingStore)
                .environmentObject(wifiTransfer)
                .onAppear { wifiTransfer.attach(store: store) }
                #if os(iOS)
                .environmentObject(watchTransfer)
                .onAppear { watchTransfer.attach(readingStore: readingStore) }
                #endif
                .onOpenURL { url in
                    if url.scheme == "yubing", let section = url.host.flatMap(AppSection.init(rawValue:)) {
                        NotificationCenter.default.post(name: .yuBingOpenSection, object: section)
                    } else {
                        store.importFiles([url])
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        #endif
    }
}
