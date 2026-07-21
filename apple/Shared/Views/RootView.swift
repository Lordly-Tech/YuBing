import Combine
import SwiftUI

extension Notification.Name {
    static let yuBingOpenSection = Notification.Name("YuBingOpenSection")
    static let yuBingImmersiveDetailMode = Notification.Name("YuBingImmersiveDetailMode")
}

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var presentedPlayer: LibraryItem?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                CompactRootView(openPlayer: presentPlayer)
            } else {
                SplitRootView(openPlayer: presentPlayer)
            }
            #else
            SplitRootView(openPlayer: presentPlayer)
            #endif
        }
        #if os(iOS)
        .fullScreenCover(item: $presentedPlayer) { item in
            NowPlayingView(startingItem: item)
        }
        #else
        .sheet(item: $presentedPlayer) { item in
            NowPlayingView(startingItem: item)
                .frame(minWidth: 360, minHeight: 560)
        }
        #endif
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(AppLocalization.string(alert.title)),
                message: Text(AppLocalization.string(alert.message)),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func presentPlayer(_ item: LibraryItem) {
        presentedPlayer = item
    }
}

private struct CompactRootView: View {
    @EnvironmentObject private var player: AudioPlayerController
    let openPlayer: (LibraryItem) -> Void
    @State private var selection: AppSection = .home

    private var hideMiniPlayer: Bool {
        selection == .reading || selection == .gallery || player.isNowPlayingVisible
    }

    var body: some View {
        TabView(selection: $selection) {
            compactTab(.home) { DashboardView() }
            compactTab(.music) { MusicLibraryView() }
            compactTab(.reading) { ReadingLibraryView() }
            compactTab(.gallery) { GalleryView() }
            compactTab(.more) { MoreView() }
        }
        .overlay(alignment: .bottom) {
            if !hideMiniPlayer, player.currentItem != nil {
                MiniPlayerView(openPlayer: openPlayer)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 62)
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: .yuBingWatchTransferDidStart)) { _ in
            selection = .home
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .yuBingOpenSection)) { notification in
            if let section = notification.object as? AppSection { selection = section }
        }
    }

    private func compactTab<Content: View>(
        _ section: AppSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .libraryDestinations()
        }
        .tabItem { Label(section.title, systemImage: section.symbol) }
        .tag(section)
    }
}

private struct SplitRootView: View {
    @EnvironmentObject private var player: AudioPlayerController
    let openPlayer: (LibraryItem) -> Void
    @State private var selection: AppSection? = .home
    @State private var immersiveDetailDepth = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var hideMiniPlayer: Bool {
        selection == .reading || selection == .gallery || player.isNowPlayingVisible
    }

    private var shouldHideSidebar: Bool {
        selection == .reading || immersiveDetailDepth > 0
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: YuBingMetrics.sidebarWidth, max: 290)
        } detail: {
            NavigationStack {
                SectionDestinationView(section: selection ?? .home)
                    .libraryDestinations()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !hideMiniPlayer, player.currentItem != nil {
                    HStack {
                        Spacer(minLength: 0)
                        MiniPlayerView(openPlayer: openPlayer)
                            .frame(maxWidth: 660)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: .yuBingWatchTransferDidStart)) { _ in
            selection = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: .yuBingImmersiveDetailMode)) { notification in
            guard let delta = notification.object as? Int else { return }
            immersiveDetailDepth = max(0, immersiveDetailDepth + delta)
            updateSidebarVisibility()
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .yuBingOpenSection)) { notification in
            if let section = notification.object as? AppSection { selection = section }
        }
        .onAppear {
            updateSidebarVisibility()
        }
        .onChange(of: selection) { _, _ in
            updateSidebarVisibility()
        }
    }

    private func updateSidebarVisibility() {
        #if os(iOS)
        columnVisibility = shouldHideSidebar ? .detailOnly : .all
        #endif
    }
}

private struct SidebarView: View {
    @Binding var selection: AppSection?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label(AppSection.home.title, systemImage: AppSection.home.symbol)
                    .tag(AppSection.home)
                Label(AppSection.music.title, systemImage: AppSection.music.symbol)
                    .tag(AppSection.music)
                Label(AppSection.reading.title, systemImage: AppSection.reading.symbol)
                    .tag(AppSection.reading)
                Label(AppSection.gallery.title, systemImage: AppSection.gallery.symbol)
                    .tag(AppSection.gallery)
                Label(AppSection.more.title, systemImage: AppSection.more.symbol)
                    .tag(AppSection.more)
            }
        }
        .navigationTitle("鱼饼")
        .toolbar {
            ToolbarItem {
                FileImportButton(title: "导入")
                    .labelStyle(.iconOnly)
                    .help("导入文件")
            }
        }
    }
}

private struct SectionDestinationView: View {
    let section: AppSection

    @ViewBuilder
    var body: some View {
        switch section {
        case .home:
            DashboardView()
        case .music:
            MusicLibraryView()
        case .reading:
            ReadingLibraryView()
        case .gallery:
            GalleryView()
        case .more:
            MoreView()
        }
    }
}

private extension View {
    func libraryDestinations() -> some View {
        navigationDestination(for: LibraryItem.self) { item in
            ItemDestinationView(item: item)
        }
    }
}

extension View {
    func immersiveSplitDetail() -> some View {
        modifier(ImmersiveSplitDetailModifier())
    }
}

struct ImmersiveSplitDetailModifier: ViewModifier {
    @State private var isActive = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isActive else { return }
                isActive = true
                NotificationCenter.default.post(name: .yuBingImmersiveDetailMode, object: 1)
            }
            .onDisappear {
                guard isActive else { return }
                isActive = false
                NotificationCenter.default.post(name: .yuBingImmersiveDetailMode, object: -1)
            }
    }
}
