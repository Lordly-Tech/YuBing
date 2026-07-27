import Combine
import SwiftUI

#if os(iOS)
import UIKit
#endif

extension Notification.Name {
    static let yuBingOpenSection = Notification.Name("YuBingOpenSection")
    static let yuBingOpenPlayer = Notification.Name("YuBingOpenPlayer")
    static let yuBingImmersiveDetailMode = Notification.Name("YuBingImmersiveDetailMode")
}

private struct PresentedPlayer: Identifiable {
    let id = UUID()
    let item: LibraryItem
}

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @State private var presentedPlayer: PresentedPlayer?
    @Namespace private var playerTransitionNamespace

    private let playerTransitionID = "now-playing"

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        ZStack {
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
            if let presentation = presentedPlayer {
                PlayerPresentationContainer(
                    item: presentation.item,
                    onDismiss: { dismissPresentedPlayer(id: presentation.id) }
                )
                .id(presentation.id)
                .ignoresSafeArea(.container, edges: .all)
                .zIndex(100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            #endif
        }
        #if !os(iOS)
        .sheet(item: $presentedPlayer) { presentation in
            NowPlayingView(startingItem: presentation.item)
                .frame(minWidth: 860, minHeight: 560)
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .yuBingOpenPlayer)) { notification in
            if let item = notification.object as? LibraryItem {
                presentPlayer(item)
            }
        }
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
        guard presentedPlayer == nil else { return }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.9)) {
            presentedPlayer = PresentedPlayer(item: item)
        }
    }

    private func dismissPresentedPlayer(id: UUID) {
        guard presentedPlayer?.id == id else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentedPlayer = nil
        }
    }

    private var playbackErrorPresented: Binding<Bool> {
        Binding(
            get: { player.playbackError != nil },
            set: { if !$0 { player.playbackError = nil } }
        )
    }
}

#if os(iOS)
private enum PlayerPresentationDragAxis {
    case vertical
    case horizontal
}

private struct PlayerPresentationDragState {
    var axis: PlayerPresentationDragAxis?
    var translation: CGFloat = 0
}

private struct PlayerPresentationContainer: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let item: LibraryItem
    let onDismiss: () -> Void

    @GestureState(
        resetTransaction: Transaction(
            animation: .interactiveSpring(response: 0.34, dampingFraction: 0.88)
        )
    ) private var dragState = PlayerPresentationDragState()
    @State private var closingOffset: CGFloat = 0
    @State private var isClosing = false

    var body: some View {
        GeometryReader { proxy in
            let safeAreaInsets = resolvedSafeAreaInsets(
                geometryInsets: proxy.safeAreaInsets
            )
            let verticalOffset = isClosing ? closingOffset : dragState.translation
            let revealProgress = min(
                max(verticalOffset / max(proxy.size.height * 0.42, 1), 0),
                1
            )

            ZStack(alignment: .top) {
                Color.black
                    .opacity(0.2 * (1 - revealProgress))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                NowPlayingView(
                    startingItem: item,
                    topSafeAreaInset: safeAreaInsets.top,
                    bottomSafeAreaInset: safeAreaInsets.bottom,
                    onDismiss: { closePlayer(containerHeight: proxy.size.height) }
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 30 * revealProgress,
                        style: .continuous
                    )
                )
                .shadow(
                    color: .black.opacity(0.3 * revealProgress),
                    radius: 28 * revealProgress,
                    y: 12 * revealProgress
                )
                .scaleEffect(1 - (0.035 * revealProgress), anchor: .top)
                .offset(y: verticalOffset)
                .compositingGroup()

                topInteractionSurface(
                    safeAreaTop: safeAreaInsets.top,
                    containerHeight: proxy.size.height
                )
                .offset(y: verticalOffset)
            }
        }
        .ignoresSafeArea(.container, edges: .all)
        .ignoresSafeArea(.keyboard)
        .accessibilityAddTraits(.isModal)
    }

    private func topInteractionSurface(
        safeAreaTop: CGFloat,
        containerHeight: CGFloat
    ) -> some View {
        Color.clear
            .frame(height: max(safeAreaTop + 58, 96))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                closePlayer(containerHeight: containerHeight)
            }
            .gesture(dismissalGesture(containerHeight: containerHeight))
            .accessibilityElement()
            .accessibilityLabel("收起播放器")
            .accessibilityHint("轻点收起，或向下拖动播放器")
            .accessibilityAction {
                closePlayer(containerHeight: containerHeight)
            }
    }

    private func dismissalGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($dragState) { value, state, _ in
                guard !isClosing else { return }

                let horizontalDistance = abs(value.translation.width)
                let verticalDistance = abs(value.translation.height)

                if state.axis == nil, max(horizontalDistance, verticalDistance) >= 7 {
                    if verticalDistance > horizontalDistance * 1.05 {
                        state.axis = .vertical
                    } else if horizontalDistance > verticalDistance * 1.15 {
                        state.axis = .horizontal
                    }
                }

                guard state.axis == .vertical else { return }
                state.translation = max(value.translation.height, 0)
            }
            .onEnded { value in
                guard !isClosing else { return }

                let verticalDistance = max(value.translation.height, 0)
                let predictedDistance = max(value.predictedEndTranslation.height, 0)
                let isVertical = abs(value.translation.height)
                    >= abs(value.translation.width) * 0.9
                let distanceThreshold = min(max(containerHeight * 0.14, 96), 150)
                let projectedThreshold = min(max(containerHeight * 0.26, 190), 300)
                let hasDownwardVelocity = predictedDistance - verticalDistance > 110

                if isVertical,
                   verticalDistance > 0,
                   (verticalDistance >= distanceThreshold
                    || predictedDistance >= projectedThreshold
                    || hasDownwardVelocity) {
                    closePlayer(
                        containerHeight: containerHeight,
                        from: verticalDistance,
                        projectedDistance: predictedDistance
                    )
                }
            }
    }

    private func closePlayer(
        containerHeight: CGFloat,
        from currentOffset: CGFloat = 0,
        projectedDistance: CGFloat = 0
    ) {
        guard !isClosing else { return }
        isClosing = true
        closingOffset = max(currentOffset, 0)

        guard !accessibilityReduceMotion else {
            onDismiss()
            return
        }

        let exitOffset = max(containerHeight + 44, projectedDistance)
        let duration = currentOffset > 0 ? 0.26 : 0.34
        withAnimation(.easeOut(duration: duration)) {
            closingOffset = exitOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            onDismiss()
            }
    }

    private func resolvedSafeAreaInsets(
        geometryInsets: EdgeInsets
    ) -> EdgeInsets {
        let windowInsets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets

        return EdgeInsets(
            top: max(geometryInsets.top, windowInsets?.top ?? 0),
            leading: max(geometryInsets.leading, windowInsets?.left ?? 0),
            bottom: max(geometryInsets.bottom, windowInsets?.bottom ?? 0),
            trailing: max(geometryInsets.trailing, windowInsets?.right ?? 0)
        )
    }
}
#endif

private struct CompactRootView: View {
    @EnvironmentObject private var player: AudioPlayerController
    let openPlayer: (LibraryItem) -> Void
    let playerTransitionID: String
    let playerTransitionNamespace: Namespace.ID
    @State private var selection: AppSection = .home
    @State private var isMiniPlayerHiddenByGesture = false

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
        .onChange(of: selection) { _, _ in
            isMiniPlayerHiddenByGesture = false
        }
    }

    #if os(iOS)
    @available(iOS 26.0, *)
    @ViewBuilder
    private var modernTabs: some View {
        if shouldShowMiniPlayer {
            tabs
                .tabViewBottomAccessory {
                    MeloXMiniPlayerAccessory {
                        if let item = player.currentItem { openPlayer(item) }
                    }
                    .gesture(hideMiniPlayerGesture)
                    .matchedTransitionSource(
                        id: playerTransitionID,
                        in: playerTransitionNamespace
                    )
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs
                .tabBarMinimizeBehavior(.onScrollDown)
        }
    }
    #endif

    private var fallbackTabs: some View {
        tabs
    }

    @ViewBuilder
    private func floatingMiniPlayer(maxWidth: CGFloat) -> some View {
        if shouldShowMiniPlayer {
            MiniPlayerView(isInline: false, alwaysShowsSubtitle: true) {
                if let item = player.currentItem { openPlayer(item) }
            }
            .yuBingMatchedTransitionSource(
                id: playerTransitionID,
                in: playerTransitionNamespace
            )
            .frame(maxWidth: maxWidth)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .gesture(hideMiniPlayerGesture)
        }
    }

    private var shouldShowMiniPlayer: Bool {
        player.hasActivePlaybackSession
            && player.currentItem != nil
            && selection != .reading
            && !isMiniPlayerHiddenByGesture
    }

    private var hideMiniPlayerGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard value.translation.height > 34,
                      value.predictedEndTranslation.height > 54,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                withAnimation(.smooth(duration: 0.28)) {
                    isMiniPlayerHiddenByGesture = true
                }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            #if os(iOS)
            if #unavailable(iOS 26.0) {
                fallbackMiniPlayerInset(for: section)
            }
            #else
            fallbackMiniPlayerInset(for: section)
            #endif
        }
        .tabItem { Label(section.title, systemImage: section.symbol) }
        .tag(section)
    }

    @ViewBuilder
    private func fallbackMiniPlayerInset(for section: AppSection) -> some View {
        if selection == section {
            floatingMiniPlayer(maxWidth: 620)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
        }
    }
}

private struct SplitRootView: View {
    @EnvironmentObject private var player: AudioPlayerController
    let openPlayer: (LibraryItem) -> Void
    let playerTransitionID: String
    let playerTransitionNamespace: Namespace.ID
    @State private var selection: AppSection = .home
    @State private var isMiniPlayerHiddenByGesture = false

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
                            sectionToolbar
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                floatingMiniPlayer(maxWidth: 720)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .yuBingOpenSection)) { notification in
            if let section = notification.object as? AppSection { selection = section }
        }
        .onChange(of: selection) { _, _ in
            isMiniPlayerHiddenByGesture = false
        }
    }

    @ViewBuilder
    private var sectionToolbar: some View {
        #if os(iOS)
        ViewThatFits(in: .horizontal) {
            sectionPicker.frame(width: 640)
            sectionPicker.frame(width: 560)
            sectionPicker.frame(width: 480)
            sectionPicker
        }
        .controlSize(.large)
        .font(.body.weight(.semibold))
        .frame(minHeight: 44)
        #else
        sectionPicker
        #endif
    }

    private var sectionPicker: some View {
        Picker("板块", selection: $selection) {
            ForEach(AppSection.allCases) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var legacyNav: some View {
        NavigationSplitView {
            List {
                ForEach(AppSection.allCases) { section in
                    HStack {
                        Label(section.title, systemImage: section.symbol)
                            .foregroundStyle(selection == section ? .primary : .secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background {
                        if selection == section {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.regularMaterial)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture {
                        selection = section
                    }
                }
            }
            .navigationTitle("鱼饼")
        } detail: {
            NavigationStack {
                SectionDestinationView(section: selection)
                    .libraryDestinations()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingMiniPlayer(maxWidth: 720)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 18)
        }
        .onReceive(NotificationCenter.default.publisher(for: .yuBingOpenSection)) { notification in
            if let section = notification.object as? AppSection { selection = section }
        }
        .onChange(of: selection) { _, _ in
            isMiniPlayerHiddenByGesture = false
        }
    }

    @ViewBuilder
    private func floatingMiniPlayer(maxWidth: CGFloat) -> some View {
        if player.hasActivePlaybackSession, player.currentItem != nil,
           selection != .reading, !isMiniPlayerHiddenByGesture {
            MiniPlayerView(isInline: false, alwaysShowsSubtitle: true) {
                if let item = player.currentItem { openPlayer(item) }
            }
            .yuBingMatchedTransitionSource(
                id: playerTransitionID,
                in: playerTransitionNamespace
            )
            .frame(maxWidth: maxWidth)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 22, y: 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .gesture(hideMiniPlayerGesture)
        }
    }

    private var hideMiniPlayerGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard value.translation.height > 34,
                      value.predictedEndTranslation.height > 54,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                withAnimation(.smooth(duration: 0.28)) {
                    isMiniPlayerHiddenByGesture = true
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
    @ViewBuilder
    func yuBingMatchedTransitionSource(
        id: String,
        in namespace: Namespace.ID
    ) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

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
