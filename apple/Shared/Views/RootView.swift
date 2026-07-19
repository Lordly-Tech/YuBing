import Combine
import SwiftUI

extension Notification.Name {
    static let yuBingOpenSection = Notification.Name("YuBingOpenSection")
}

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                CompactRootView()
            } else {
                SplitRootView()
            }
            #else
            SplitRootView()
            #endif
        }
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(AppLocalization.string(alert.title)),
                message: Text(AppLocalization.string(alert.message)),
                dismissButton: .default(Text("好"))
            )
        }
    }
}

private struct CompactRootView: View {
    @EnvironmentObject private var player: AudioPlayerController
    @State private var selection: AppSection = .home

    private var hideMiniPlayer: Bool {
        selection == .reading || selection == .gallery
    }

    var body: some View {
        TabView(selection: $selection) {
            compactTab(.home) { DashboardView() }
            compactTab(.reading) { ReadingLibraryView() }
            compactTab(.gallery) { GalleryView() }
            compactTab(.more) { MoreView() }
        }
        .overlay(alignment: .bottom) {
            if !hideMiniPlayer, player.currentItem != nil {
                MiniPlayerView()
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
    @State private var selection: AppSection? = .home

    private var hideMiniPlayer: Bool {
        selection == .reading || selection == .gallery
    }

    var body: some View {
        NavigationSplitView {
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
                        MiniPlayerView()
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
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .yuBingOpenSection)) { notification in
            if let section = notification.object as? AppSection { selection = section }
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: AppSection?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label(AppSection.home.title, systemImage: AppSection.home.symbol)
                    .tag(AppSection.home)
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
