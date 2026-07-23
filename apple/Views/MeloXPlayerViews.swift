import AVKit
import SwiftUI

// Player surfaces and landscape composition adapted from youshen2/MeloX (GPL-3.0).

#if os(macOS)
import AppKit
#else
import MediaPlayer
import UIKit
#endif

enum NowPlayingPage: String, Hashable {
    case artwork
    case lyrics
    case queue
}

struct MiniPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var player: AudioPlayerController
    let openPlayer: (LibraryItem) -> Void

    var body: some View {
        if let item = player.currentItem {
            HStack(spacing: 11) {
                Button { openPlayer(item) } label: {
                    HStack(spacing: 11) {
                        AudioArtwork(
                            data: player.currentMetadata.artworkData,
                            fallbackSymbol: "music.note"
                        )
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentMetadata.title ?? item.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(player.currentMetadata.artist ?? "本地音乐")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if player.isPreparing {
                    ProgressView().controlSize(.small).frame(width: 36, height: 36)
                } else {
                    Button { player.togglePlayback() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.headline)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                }

                Button { player.playNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一首")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 56)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 16, y: 7)
            .simultaneousGesture(
                DragGesture(minimumDistance: 28).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 {
                        player.playNext()
                    } else {
                        player.playPrevious()
                    }
                }
            )
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: player.currentItem)
        }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @Environment(\.dismiss) private var dismiss

    let startingItem: LibraryItem
    var queueItems: [LibraryItem]? = nil

    @AppStorage("yubing.player.rememberedPage") private var rememberedPage = NowPlayingPage.artwork.rawValue
    @State private var page: NowPlayingPage = .artwork
    @State private var showsSleepTimer = false

    private var localTracks: [LibraryItem] {
        (queueItems ?? store.items(of: .music).sorted(by: .name)).filter { $0.kind == .music }
    }

    private var activeItem: LibraryItem { player.currentItem ?? startingItem }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PlayerArtworkBackground(
                    artworkData: player.currentMetadata.artworkData,
                    intensity: 0.72
                )

                if proxy.size.width > proxy.size.height * 1.08 {
                    NowPlayingLandscapeView(
                        page: $page,
                        showsSleepTimer: $showsSleepTimer,
                        item: activeItem,
                        onDismiss: { dismiss() }
                    )
                } else {
                    portraitContent
                }
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            .gesture(dismissGesture)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            player.isNowPlayingVisible = true
            page = NowPlayingPage(rawValue: rememberedPage) ?? .artwork
            if let queueItems {
                player.setQueue(queueItems)
            } else if player.queue.isEmpty {
                player.setQueue(localTracks)
            }
            if player.currentItem != startingItem {
                player.play(startingItem, in: queueItems ?? localTracks)
            }
            if startingItem.url.isFileURL { store.markOpened(startingItem) }
        }
        .onDisappear { player.isNowPlayingVisible = false }
        .onChange(of: page) { _, value in rememberedPage = value.rawValue }
        .confirmationDialog("定时关闭", isPresented: $showsSleepTimer, titleVisibility: .visible) {
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                Button("\(minutes) 分钟") { player.setSleepTimer(minutes: minutes) }
            }
            Button("本曲结束") { player.sleepAfterCurrentTrack() }
            if player.sleepTimerEnd != nil || player.stopAfterCurrentTrack {
                Button("关闭定时", role: .destructive) { player.cancelSleepTimer() }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .immersiveSplitDetail()
        .animation(.smooth(duration: 0.38), value: page)
    }

    private var portraitContent: some View {
        VStack(spacing: 0) {
            dismissalHandle
            pageContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            NowPlayingProgressControl()
            NowPlayingTransportControls()
            NowPlayingVolumeControl()
            NowPlayingPageSelector(page: $page)
        }
        .padding(.horizontal, 28)
        .safeAreaPadding(.top, 4)
        .safeAreaPadding(.bottom, 8)
    }

    private var dismissalHandle: some View {
        Button { dismiss() } label: {
            Capsule()
                .fill(.white.opacity(0.5))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 48)
        .accessibilityLabel("收起播放器")
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .artwork:
            NowPlayingArtworkPage(item: activeItem, showsSleepTimer: $showsSleepTimer)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .lyrics:
            NowPlayingLyricsPage(
                item: activeItem,
                showsSleepTimer: $showsSleepTimer,
                lyrics: player.currentMetadata.lyrics
            )
            .transition(.opacity)
        case .queue:
            NowPlayingQueuePage().transition(.opacity)
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 40).onEnded { value in
            guard value.translation.height > 90,
                  abs(value.translation.height) > abs(value.translation.width) else { return }
            dismiss()
        }
    }
}

private struct NowPlayingLandscapeView: View {
    @EnvironmentObject private var player: AudioPlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var page: NowPlayingPage
    @Binding var showsSleepTimer: Bool
    let item: LibraryItem
    let onDismiss: () -> Void
    @State private var showsLyricsControls = true

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onDismiss) {
                Capsule()
                    .fill(.white.opacity(0.5))
                    .frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .frame(height: 28)
            .accessibilityLabel("收起播放器")

            GeometryReader { proxy in
                let side = min(proxy.size.height, proxy.size.width * 0.42, 460)
                HStack(spacing: min(max(proxy.size.width * 0.035, 18), 38)) {
                    AudioArtwork(data: player.currentMetadata.artworkData, fallbackSymbol: "music.note")
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .scaleEffect(player.isPlaying ? 1 : 0.9)
                        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: player.isPlaying)

                    rightPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: 1_100, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.top, 2)
        .safeAreaPadding(.bottom, 8)
    }

    private var rightPanel: some View {
        VStack(spacing: 0) {
            landscapeHeader

            Group {
                switch page {
                case .artwork:
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        NowPlayingProgressControl()
                        NowPlayingTransportControls()
                        NowPlayingVolumeControl()
                        Spacer(minLength: 0)
                    }
                case .lyrics:
                    NowPlayingLyricsPage(
                        item: item,
                        showsSleepTimer: $showsSleepTimer,
                        lyrics: player.currentMetadata.lyrics,
                        presentation: .landscape,
                        onToggleInterface: toggleLyricsControls
                    )
                case .queue:
                    NowPlayingQueuePage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if page != .lyrics || showsLyricsControls {
                NowPlayingPageSelector(page: $page)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var landscapeHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentMetadata.title ?? item.displayName)
                    .font(.headline).lineLimit(1)
                Text(player.currentMetadata.artist ?? player.currentMetadata.album ?? "本地音乐")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NowPlayingSongActions(item: item, showsSleepTimer: $showsSleepTimer)
        }
        .frame(height: 52)
    }

    private func toggleLyricsControls() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            showsLyricsControls.toggle()
        }
    }
}

private struct NowPlayingArtworkPage: View {
    @EnvironmentObject private var player: AudioPlayerController
    let item: LibraryItem
    @Binding var showsSleepTimer: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = max(170, min(proxy.size.width - 28, proxy.size.height - 104))
            VStack(spacing: 0) {
                Spacer(minLength: 8)
                AudioArtwork(data: player.currentMetadata.artworkData, fallbackSymbol: "music.note")
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .scaleEffect(player.isPlaying ? 1 : 0.9)
                    .shadow(color: .black.opacity(0.24), radius: 22, y: 12)
                    .animation(.smooth(duration: 0.45), value: player.isPlaying)
                Spacer(minLength: 20)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentMetadata.title ?? item.displayName)
                            .font(.title3.weight(.semibold)).lineLimit(1)
                        Text(player.currentMetadata.artist ?? player.currentMetadata.album ?? "本地音乐")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NowPlayingSongActions(item: item, showsSleepTimer: $showsSleepTimer)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct NowPlayingSongActions: View {
    @EnvironmentObject private var store: LibraryStore
    let item: LibraryItem
    @Binding var showsSleepTimer: Bool
    @State private var addToPlaylistItem: LibraryItem?

    var body: some View {
        HStack(spacing: 10) {
            if item.url.isFileURL {
                Button { store.toggleFavorite(item) } label: {
                    Image(systemName: store.isFavorite(item) ? "star.fill" : "star")
                        .font(.title3)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isFavorite(item) ? "取消收藏" : "收藏")
            }

            Menu {
                if item.url.isFileURL {
                    Button { addToPlaylistItem = item } label: {
                        Label("添加到歌单", systemImage: "text.badge.plus")
                    }
                }
                Button { showsSleepTimer = true } label: {
                    Label("定时关闭", systemImage: "timer")
                }
                ShareLink(item: item.url) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多")
        }
        .sheet(item: $addToPlaylistItem) { AddToLocalPlaylistSheet(item: $0) }
    }
}

struct NowPlayingProgressControl: View {
    @EnvironmentObject private var player: AudioPlayerController

    var body: some View {
        VStack(spacing: 5) {
            Slider(
                value: Binding(
                    get: { min(player.currentTime, maximum) },
                    set: { player.seek(to: $0) }
                ),
                in: 0...maximum
            )
            .tint(.white)
            .accessibilityLabel("播放进度")

            HStack {
                Text(formatMusicTime(player.currentTime))
                Spacer()
                Text("−\(formatMusicTime(max(player.duration - player.currentTime, 0)))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var maximum: TimeInterval { max(player.duration, 1) }
}

struct NowPlayingTransportControls: View {
    @EnvironmentObject private var player: AudioPlayerController

    var body: some View {
        HStack {
            Button { player.toggleShuffle() } label: {
                Image(systemName: player.isShuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("随机播放")

            Spacer()
            Button { player.playPrevious() } label: {
                Image(systemName: "backward.fill").font(.system(size: 30))
                    .frame(width: 52, height: 52)
            }
            .accessibilityLabel("上一首")
            Spacer()

            Button { player.togglePlayback() } label: {
                Group {
                    if player.isPreparing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .font(.system(size: 40))
                .frame(width: 64, height: 64)
            }
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Spacer()
            Button { player.playNext() } label: {
                Image(systemName: "forward.fill").font(.system(size: 30))
                    .frame(width: 52, height: 52)
            }
            .accessibilityLabel("下一首")
            Spacer()

            Button { player.cycleRepeatMode() } label: {
                Image(systemName: player.repeatMode.symbol)
                    .font(.title3)
                    .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.72) : .pink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(player.repeatMode.title)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

struct NowPlayingVolumeControl: View {
    @EnvironmentObject private var player: AudioPlayerController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.caption)
            #if os(iOS)
            SystemVolumeSlider().frame(height: 28)
            #else
            Slider(
                value: Binding(get: { player.volume }, set: { player.setVolume($0) }),
                in: 0...1
            )
            .tint(.white)
            #endif
            Image(systemName: "speaker.wave.3.fill").font(.caption)
        }
        .foregroundStyle(.white.opacity(0.68))
        .padding(.vertical, 5)
    }
}

struct NowPlayingPageSelector: View {
    @Binding var page: NowPlayingPage

    var body: some View {
        HStack {
            pageButton(.artwork, image: "square.stack", label: "封面")
            Spacer()
            pageButton(.lyrics, image: "quote.bubble", label: "歌词")
            Spacer()
            #if os(iOS)
            AirPlayRouteButton().frame(width: 44, height: 44)
            Spacer()
            #endif
            pageButton(.queue, image: "list.bullet", label: "播放队列")
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
    }

    private func pageButton(_ value: NowPlayingPage, image: String, label: String) -> some View {
        Button { page = value } label: {
            Image(systemName: image)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.white.opacity(page == value ? 0.16 : 0), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(page == value ? .isSelected : [])
    }
}

struct NowPlayingQueuePage: View {
    @EnvironmentObject private var player: AudioPlayerController

    var body: some View {
        Group {
            if player.queue.isEmpty {
                ContentUnavailableView("播放队列为空", systemImage: "list.bullet")
                    .foregroundStyle(.white)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, item in
                            Button { player.playFromQueue(at: index) } label: {
                                HStack(spacing: 11) {
                                    AudioArtwork(
                                        data: player.metadataByPath[item.relativePath]?.artworkData,
                                        fallbackSymbol: "music.note"
                                    )
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(player.metadataByPath[item.relativePath]?.title ?? item.displayName)
                                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(player.metadataByPath[item.relativePath]?.artist ?? "本地音乐")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                                    }
                                    Spacer()
                                    if player.currentItem == item {
                                        Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                                            .foregroundStyle(.pink)
                                    }
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < player.queue.count - 1 {
                                Divider().overlay(.white.opacity(0.14)).padding(.leading, 55)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerArtworkBackground: View {
    let artworkData: Data?
    var intensity: Double = 0.65

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.075)
            if let artworkImage {
                artworkImage
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 72)
                    .saturation(1.35)
                    .scaleEffect(1.35)
                    .opacity(intensity)
            }
            LinearGradient(
                colors: [.black.opacity(0.08), .black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var artworkImage: Image? {
        guard let artworkData else { return nil }
        #if os(macOS)
        guard let image = NSImage(data: artworkData) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: artworkData) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}

struct AudioArtwork: View {
    let data: Data?
    var fallbackSymbol: String = "music.note"

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .overlay {
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
            }
        }
        .clipped()
    }

    private var image: Image? {
        guard let data else { return nil }
        #if os(macOS)
        guard let value = NSImage(data: data) else { return nil }
        return Image(nsImage: value)
        #else
        guard let value = UIImage(data: data) else { return nil }
        return Image(uiImage: value)
        #endif
    }
}

func formatMusicTime(_ value: TimeInterval) -> String {
    guard value.isFinite, value >= 0 else { return "0:00" }
    let seconds = Int(value.rounded(.down))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

#if os(iOS)
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.prioritizesVideoDevices = false
        view.tintColor = .white
        view.activeTintColor = .systemPink
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
