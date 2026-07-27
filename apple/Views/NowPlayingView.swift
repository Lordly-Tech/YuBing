import SwiftUI

enum NowPlayingPage: String, Hashable {
    case artwork
    case details
    case lyrics
    case queue
}

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(AppSettings.self) private var settings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController

    let startingItem: LibraryItem
    var queueItems: [LibraryItem]? = nil
    var topSafeAreaInset: CGFloat? = nil
    var bottomSafeAreaInset: CGFloat? = nil
    var onDismiss: (() -> Void)? = nil

    @AppStorage("yubing.player.rememberedPage") private var rememberedPage = NowPlayingPage.artwork.rawValue
    @State private var page = NowPlayingPage.artwork
    @State private var showsLyricsControls = true
    @State private var showsSleepTimer = false
    @State private var highlightedLyricID: LyricLine.ID?
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
                        page: $page,
                        showsLyricsControls: $showsLyricsControls,
                        showsSleepTimer: $showsSleepTimer,
                        song: song,
                        lyrics: lyrics,
                        lyricError: lyricError,
                        highlightedLyricID: highlightedLyricID,
                        artworkNamespace: pageArtworkNamespace,
                        onDismiss: dismissPlayer
                    )
                } else {
                    portraitContent(
                        topSafeInset: max(
                            topSafeAreaInset ?? 0,
                            proxy.safeAreaInsets.top
                        ),
                        bottomSafeInset: max(
                            bottomSafeAreaInset ?? 0,
                            proxy.safeAreaInsets.bottom
                        )
                    )
                }
            }
            .foregroundStyle(Color.primary)
        }
        .ignoresSafeArea(.container, edges: .all)
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
                Button {
                    player.setSleepTimer(minutes: minutes)
                } label: {
                    Label("\(minutes) 分钟", systemImage: sleepTimerIcon(for: minutes))
                }
            }

            Button {
                player.sleepAfterCurrentTrack()
            } label: {
                Label("本曲结束", systemImage: "music.note")
            }

            if player.sleepTimerEnd != nil || player.stopAfterCurrentTrack {
                Button(role: .destructive) {
                    player.cancelSleepTimer()
                } label: {
                    Label("关闭定时", systemImage: "timer.circle.fill")
                }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .immersiveSplitDetail()
        .animation(.smooth(duration: 0.4), value: page)
    }


    private func sleepTimerIcon(for minutes: Int) -> String {
        switch minutes {
        case 15: "timer"
        case 30: "clock"
        case 45: "clock.badge"
        case 60: "clock.circle"
        case 90: "moon.zzz"
        default: "timer"
        }
    }

    private func portraitContent(
        topSafeInset: CGFloat,
        bottomSafeInset: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            dismissalHandle
                .padding(.top, max(topSafeInset + 4, 18))

            if usesExpandedAppleMusicLyricsLayout {
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        portraitPlayerControls
                            .opacity(hidesLyricsControls ? 0 : 1)
                            .allowsHitTesting(!hidesLyricsControls)
                            .accessibilityHidden(hidesLyricsControls)
                    }
            } else {
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                portraitPlayerControls
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, max(bottomSafeInset + 4, 12))
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

    private var usesExpandedAppleMusicLyricsLayout: Bool {
        page == .lyrics
    }

    private var dismissalHandle: some View {
        Capsule()
            .fill(Color.primary.opacity(0.76))
            .frame(width: 38, height: 5)
            .shadow(color: .black.opacity(0.22), radius: 4, y: 1)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(.rect)
            .onTapGesture {
                dismissPlayer()
            }
            .accessibilityElement()
            .accessibilityLabel("收起播放器")
            .accessibilityHint("轻点收起，或向下拖动播放器")
            .accessibilityAction {
                dismissPlayer()
            }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .artwork:
            NowPlayingArtworkPage(
                song: song,
                showsSleepTimer: $showsSleepTimer,
                artworkNamespace: pageArtworkNamespace,
                onShowDetails: showDetails
            )
            .transition(.opacity)
        case .details:
            NowPlayingSongDetailsPage(
                song: song,
                showsSleepTimer: $showsSleepTimer,
                showsArtworkToggle: true,
                artworkNamespace: pageArtworkNamespace,
                onShowArtwork: showArtwork
            )
            .transition(.opacity)
        case .lyrics:
            NowPlayingLyricsPage(
                song: song,
                lyrics: lyrics,
                untimedText: player.currentMetadata.lyrics?.untimedText,
                errorMessage: lyricError,
                highlightedLyricID: highlightedLyricID,
                isInterfaceHidden: hidesLyricsControls,
                artworkNamespace: pageArtworkNamespace,
                showsSleepTimer: $showsSleepTimer,
                onToggleInterface: toggleLyricsControls,
                onShowDetails: showDetails
            )
            .accessibilityAction(
                named: showsLyricsControls ? "隐藏播放器控制" : "显示播放器控制"
            ) {
                toggleLyricsControls()
            }
            .transition(.opacity)
        case .queue:
            NowPlayingQueuePage()
                .transition(.opacity)
        }
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

    private func dismissPlayer() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func showDetails() {
        withAnimation(.smooth(duration: 0.3)) {
            page = .details
        }
    }

    private func showArtwork() {
        withAnimation(.smooth(duration: 0.3)) {
            page = .artwork
        }
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
