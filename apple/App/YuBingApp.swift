import SwiftUI

@main
struct YuBingApp: App {
    @AppStorage(AppLocalization.preferenceKey) private var appLanguageRaw = AppLanguage.system.rawValue
    @StateObject private var store = LibraryStore()
    @StateObject private var player = AudioPlayerController()
    @State private var appSettings: AppSettings
    @StateObject private var readingStore = ReadingStore()
    @StateObject private var wifiTransfer = WiFiTransferService()
    #if os(iOS)
    @StateObject private var watchTransfer = WatchTransferService()
    #endif

    init() {
        _appSettings = State(initialValue: AppSettings())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
                .environmentObject(store)
                .environmentObject(player)
                .environment(appSettings)
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

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }
}
