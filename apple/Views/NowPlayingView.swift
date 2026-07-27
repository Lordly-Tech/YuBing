import SwiftUI

enum NowPlayingPage: String, Hashable {
    case artwork
    case details
    case lyrics
    case queue

    /// Every page change goes through this one animation.
    ///
    /// The page used to be animated three different ways at once (an implicit
    /// `.animation(value: page)` on the whole player, a `withAnimation` in the
    /// page selector and another one in the artwork/details toggles). Three
    /// overlapping curves on the same transition is what made the switch flash.
    static let changeAnimation = Animation.smooth(duration: 0.32)
}

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(AppSettings.self) private var settings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController

    let startingItem: LibraryItem
    var queueItems: [LibraryItem]? = nil

    @AppStorage("yubing.player.rememberedPage") private var rememberedPage = NowPlayingPage.artwork.rawValue
    @State private var page = NowPlayingPage.artwork
    @State private var showsLyricsControls = true
    @State private var showsSleepTimer = false
    @State private var highlightedLyricID: LyricLine.ID?
    @State private var controlsHeight: CGFloat = 226
    @Namespace private var pageArtworkNamespace

    private var localTracks: [LibraryItem] {
        (queueItems ?? store.items(of: .music).sorted(by: .name))
            .filter { $0.kind == .music }
    }

    private var activeItem: LibraryItem {
        player.currentItem ?? startingItem
    }

    private var song: NowPlayingSong {
        NowPlayingSong(
            item: activeItem,
            metadata: player.currentMetadata,
            duration: player.duration
        )
    }

    private var lyrics: [LyricLine] {
        player.currentMetadata.lyrics?.meloXLyricLines ?? []
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                NowPlayingBackground(artworkData: song.artworkData)

                if proxy.size.width > proxy.size.height {
                    NowPlayingLandscapeView(
                        showsSleepTimer: $showsSleepTimer,
                        song: song,
                        lyrics: lyrics,
                        lyricError: lyricError,
                        highlightedLyricID: highlightedLyricID,
                        artworkNamespace: pageArtworkNamespace,
                        onDismiss: { dismiss() }
                    )
                } else {
                    portraitContent
                }
            }
            .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            page = NowPlayingPage(rawValue: rememberedPage) ?? .artwork
            if let queueItems {
                player.setQueue(queueItems)
            } else if player.queue.isEmpty {
                player.setQueue(localTracks)
            }
            if player.currentItem != startingItem {
                player.play(startingItem, in: queueItems ?? localTracks)
            }
            if startingItem.url.isFileURL {
                store.markOpened(startingItem)
            }
        }
        .task(id: lyricSynchronizationTrigger) {
            await synchronizeHighlightedLyric()
        }
        .onChange(of: page) { _, newPage in
            if newPage != .lyrics {
                showsLyricsControls = true
            }
            rememberedPage = (
                newPage == .details ? NowPlayingPage.artwork : newPage
            ).rawValue
        }
        .confirmationDialog("定时关闭", isPresented: $showsSleepTimer, titleVisibility: .visible) {
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                Button("\(minutes) 分钟") {
                    player.setSleepTimer(minutes: minutes)
                }
            }
            Button("本曲结束") {
                player.sleepAfterCurrentTrack()
            }
            if player.sleepTimerEnd != nil || player.stopAfterCurrentTrack {
                Button("关闭定时", role: .destructive) {
                    player.cancelSleepTimer()
                }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .immersiveSplitDetail()
    }

    /// The controls stay in one place in the view tree for every page.
    ///
    /// Branching the layout on `page` used to tear down and rebuild the progress
    /// slider, transport row and volume slider whenever the lyrics page was
    /// entered or left, which is what made the switch flash.
    private var portraitContent: some View {
        VStack(spacing: 0) {
            dismissalHandle

            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, page == .lyrics ? 0 : controlsHeight)
                .overlay(alignment: .bottom) {
                    portraitPlayerControls
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            guard height > 0 else { return }
                            controlsHeight = height
                        }
                        .opacity(hidesLyricsControls ? 0 : 1)
                        .allowsHitTesting(!hidesLyricsControls)
                        .accessibilityHidden(hidesLyricsControls)
                }
        }
        .padding(.horizontal, 28)
        .safeAreaPadding(.top, 4)
        .safeAreaPadding(.bottom, 8)
    }

    private var portraitPlayerControls: some View {
        VStack(spacing: 0) {
            NowPlayingProgressControl(song: song)
            NowPlayingTransportControls()
            NowPlayingVolumeControl()
            NowPlayingPageSelector(page: $page)
        }
    }

    private var hidesLyricsControls: Bool {
        page == .lyrics && !showsLyricsControls
    }

    private var dismissalHandle: some View {
        Capsule()
            .fill(.white.opacity(0.52))
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(.rect)
            .onTapGesture {
                dismiss()
            }
            .gesture(dismissalDragGesture)
            .accessibilityElement()
            .accessibilityLabel("收起播放器")
            .accessibilityHint("轻点收起，或向下拖动播放器")
            .accessibilityAction {
                dismiss()
            }
    }

    @ViewBuilder
    private var pageContent: some View {
        ZStack(alignment: .center) {
            NowPlayingArtworkPage(
                song: song,
                showsSleepTimer: $showsSleepTimer,
                artworkNamespace: pageArtworkNamespace,
                onShowDetails: showDetails
            )
            .opacity(page == .artwork ? 1 : 0)
            .allowsHitTesting(page == .artwork)
            .accessibilityHidden(page != .artwork)

            NowPlayingSongDetailsPage(
                song: song,
                showsSleepTimer: $showsSleepTimer,
                showsArtworkToggle: true,
                artworkNamespace: pageArtworkNamespace,
                onShowArtwork: showArtwork
            )
            .opacity(page == .details ? 1 : 0)
            .allowsHitTesting(page == .details)
            .accessibilityHidden(page != .details)

            NowPlayingLyricsPage(
                song: song,
                lyrics: lyrics,
                untimedText: player.currentMetadata.lyrics?.untimedText,
                errorMessage: lyricError,
                highlightedLyricID: highlightedLyricID,
                isInterfaceHidden: hidesLyricsControls,
                bottomOverlayHeight: page == .lyrics ? controlsHeight : 0,
                artworkNamespace: pageArtworkNamespace,
                showsSleepTimer: $showsSleepTimer,
                onToggleInterface: toggleLyricsControls,
                onShowDetails: showDetails
            )
            .opacity(page == .lyrics ? 1 : 0)
            .allowsHitTesting(page == .lyrics)
            .accessibilityHidden(page != .lyrics)
            .accessibilityAction(
                named: showsLyricsControls ? "隐藏播放器控制" : "显示播放器控制"
            ) {
                toggleLyricsControls()
            }

            NowPlayingQueuePage()
                .opacity(page == .queue ? 1 : 0)
                .allowsHitTesting(page == .queue)
                .accessibilityHidden(page != .queue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .clipped()
    }

    private var lyricError: String? {
        if player.currentMetadata.lyrics == nil {
            return "当前歌曲暂无滚动歌词。"
        }
        return lyrics.isEmpty ? "当前歌曲暂无滚动歌词。" : nil
    }

    private var lyricSynchronizationTrigger: LocalLyricSynchronizationTrigger {
        LocalLyricSynchronizationTrigger(
            itemID: player.currentItem?.id,
            progress: player.progress,
            isPlaying: player.isPlaying,
            lyricCount: lyrics.count,
            firstLyricID: lyrics.first?.id,
            lastLyricID: lyrics.last?.id
        )
    }

    private func synchronizeHighlightedLyric() async {
        let synchronizedLyrics = lyrics

        while !Task.isCancelled {
            let adjustedProgress = player.estimatedProgress() + settings.lyricsAdvanceTime
            let position = LyricPlaybackTimeline.position(
                at: adjustedProgress,
                in: synchronizedLyrics
            )
            if highlightedLyricID != position.highlightedLyricID {
                highlightedLyricID = position.highlightedLyricID
            }

            guard player.isPlaying,
                  let nextTransitionTime = position.nextTransitionTime else {
                return
            }

            let remainingTime = nextTransitionTime
                - (player.estimatedProgress() + settings.lyricsAdvanceTime)
            guard remainingTime > 0 else {
                await Task.yield()
                continue
            }

            do {
                try await Task.sleep(for: .seconds(remainingTime))
            } catch {
                return
            }
        }
    }

    private var dismissalDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard value.translation.height > 60,
                      abs(value.translation.height) > abs(value.translation.width) else {
                    return
                }
                dismiss()
            }
    }

    private func showDetails() {
        page = .details
    }

    private func showArtwork() {
        page = .artwork
    }

    private func toggleLyricsControls() {
        withAnimation(accessibilityReduceMotion ? nil : .smooth(duration: 0.3)) {
            showsLyricsControls.toggle()
        }
    }
}

private struct LocalLyricSynchronizationTrigger: Hashable {
    let itemID: String?
    let progress: TimeInterval
    let isPlaying: Bool
    let lyricCount: Int
    let firstLyricID: LyricLine.ID?
    let lastLyricID: LyricLine.ID?
}
