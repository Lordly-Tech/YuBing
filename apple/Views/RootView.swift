import Combine
import SwiftUI

extension Notification.Name {
    static let yuBingOpenSection = Notification.Name("YuBingOpenSection")
    static let yuBingImmersiveDetailMode = Notification.Name("YuBingImmersiveDetailMode")
}

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @State private var presentedPlayer: LibraryItem?
    @Namespace private var playerTransitionNamespace

    private let playerTransitionID = "now-playing"

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                CompactRootView(
                    openPlayer: presentPlayer,
                    playerTransitionID: playerTransitionID,
                    playerTransitionNamespace: playerTransitionNamespace
                )
            } else {
                SplitRootView(
                    openPlayer: presentPlayer,
                    playerTransitionID: playerTransitionID,
                    playerTransitionNamespace: playerTransitionNamespace
                )
            }
            #else
            SplitRootView(
                openPlayer: presentPlayer,
                playerTransitionID: playerTransitionID,
                playerTransitionNamespace: playerTransitionNamespace
            )
            #endif
        }
        #if os(iOS)
        .fullScreenCover(item: $presentedPlayer) { item in
            NowPlayingView(startingItem: item)
                .presentationBackground(.clear)
                .navigationTransition(
                    .zoom(
                        sourceID: playerTransitionID,
                        in: playerTransitionNamespace
                    )
                )
        }
        #else
        .sheet(item: $presentedPlayer) { item in
            NowPlayingView(startingItem: item)
                .frame(minWidth: 860, minHeight: 560)
        }
        #endif
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(AppLocalization.string(alert.title)),
                message: Text(AppLocalization.string(alert.message)),
                dismissButton: .default(Text("好"))
            )
        }
        .alert("播放失败", isPresented: playbackErrorPresented) {
            Button("好", role: .cancel) { player.playbackError = nil }
        } message: {
            Text(player.playbackError ?? "无法播放当前歌曲。")
        }
    }

    private func presentPlayer(_ item: LibraryItem) {
        presentedPlayer = item
    }

    private var playbackErrorPresented: Binding<Bool> {
        Binding(
            get: { player.playbackError != nil },
            set: { if !$0 { player.playbackError = nil } }
        )
    }
}

private struct CompactRootView: View {
    @EnvironmentObject private var player: AudioPlayerController
    let openPlayer: (LibraryItem) -> Void
    let playerTransitionID: String
    let playerTransitionNamespace: Namespace.ID
    @State private var selection: AppSection = .home

    @ViewBuilder
    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            modernTabs
        } else {
            fallbackTabs
        }
        #else
        fallbackTabs
        #endif
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            compactTab(.home) { DashboardView() }
            compactTab(.music) { MusicLibraryView() }
            compactTab(.reading) { ReadingLibraryView() }
            compactTab(.gallery) { GalleryView() }
            compactTab(.more) { MoreView() }
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

    #if os(iOS)
    @available(iOS 26.0, *)
    private var modernTabs: some View {
        tabs
            .tabViewBottomAccessory {
                if player.currentItem != nil {
                    MeloXMiniPlayerAccessory {
                        if let item = player.currentItem { openPlayer(item) }
                    }
                    .matchedTransitionSource(
                        id: playerTransitionID,
                        in: playerTransitionNamespace
                    )
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
    }
    #endif

    private var fallbackTabs: some View {
        tabs.overlay(alignment: .bottom) {
            floatingMiniPlayer(maxWidth: 620)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func floatingMiniPlayer(maxWidth: CGFloat) -> some View {
        if player.currentItem != nil {
            MiniPlayerView {
                if let item = player.currentItem { openPlayer(item) }
            }
            .matchedTransitionSource(
                id: playerTransitionID,
                in: playerTransitionNamespace
            )
            .frame(maxWidth: maxWidth)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
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
    let playerTransitionID: String
    let playerTransitionNamespace: Namespace.ID
    @State private var selection: AppSection = .home

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            modernNav
        } else {
            legacyNav
        }
    }

    @ViewBuilder
    private var modernNav: some View {
        VStack(spacing: 0) {
            NavigationStack {
                SectionDestinationView(section: selection)
                    .libraryDestinations()
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Picker("板块", selection: $selection) {
                                ForEach(AppSection.allCases) { section in
                                    Label(section.title, systemImage: section.symbol)
                                        .tag(section)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                floatingMiniPlayer(maxWidth: 720)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .yuBingOpenSection)) { notification in
            if let section = notification.object as? AppSection { selection = section }
        }
    }

    @ViewBuilder
    private var legacyNav: some View {
        NavigationSplitView {
            List {
                ForEach(AppSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        Label(section.title, systemImage: section.symbol)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("鱼饼")
        } detail: {
            NavigationStack {
                SectionDestinationView(section: selection)
                    .libraryDestinations()
            }
        }
        .overlay(alignment: .bottom) {
            floatingMiniPlayer(maxWidth: 720)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
        .onReceive(NotificationCenter.default.publisher(for: .yuBingOpenSection)) { notification in
            if let section = notification.object as? AppSection { selection = section }
        }
    }

    @ViewBuilder
    private func floatingMiniPlayer(maxWidth: CGFloat) -> some View {
        if player.currentItem != nil {
            MiniPlayerView {
                if let item = player.currentItem { openPlayer(item) }
            }
            .matchedTransitionSource(
                id: playerTransitionID,
                in: playerTransitionNamespace
            )
            .frame(maxWidth: maxWidth)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 22, y: 10)
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
