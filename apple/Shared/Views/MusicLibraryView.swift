import AVKit
import SwiftUI

#if os(macOS)
import AppKit
private typealias AudioPlatformImage = NSImage
#else
import MediaPlayer
import UIKit
private typealias AudioPlatformImage = UIImage
#endif

private struct MusicAlbum: Identifiable {
    let id: String
    let title: String
    let artist: String
    let year: String?
    let genre: String?
    let artworkData: Data?
    let tracks: [LibraryItem]
}

struct MusicLibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @State private var query = ""

    private var audioTracks: [LibraryItem] {
        store.items(of: .music).sorted(by: .name)
    }

    private var filteredTracks: [LibraryItem] {
        audioTracks.filter { item in
            guard !query.isEmpty else { return true }
            let metadata = player.metadataByPath[item.relativePath]
            return [item.displayName, metadata?.title, metadata?.artist, metadata?.album]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var albums: [MusicAlbum] {
        var grouped: [String: [LibraryItem]] = [:]
        for track in filteredTracks {
            guard let metadata = player.metadataByPath[track.relativePath],
                  let album = metadata.album?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !album.isEmpty else { continue }
            let artist = metadata.albumArtist ?? metadata.artist ?? AppLocalization.string("未知艺人")
            grouped["\(album)|\(artist)", default: []].append(track)
        }
        return grouped.compactMap { key, tracks in
            guard let first = tracks.first,
                  let metadata = player.metadataByPath[first.relativePath],
                  let title = metadata.album else { return nil }
            let sortedTracks = tracks.sorted { lhs, rhs in
                trackIndex(player.metadataByPath[lhs.relativePath]?.trackNumber) <
                    trackIndex(player.metadataByPath[rhs.relativePath]?.trackNumber)
            }
            return MusicAlbum(
                id: key,
                title: title,
                artist: metadata.albumArtist ?? metadata.artist ?? AppLocalization.string("未知艺人"),
                year: metadata.year,
                genre: metadata.genre,
                artworkData: metadata.artworkData,
                tracks: sortedTracks
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Group {
            if audioTracks.isEmpty {
                ContentUnavailablePanel(
                    title: "还没有音乐",
                    message: "支持 MP3、FLAC、WAV、AAC、AIFF、M4A、DSD、DSF、APE、OGG、Opus 与 WMA。",
                    symbol: "music.note.list",
                    action: AnyView(FileImportButton(title: "添加音乐", prominent: true))
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        if !albums.isEmpty {
                            albumSection
                        }
                        trackSection
                    }
                    .frame(maxWidth: 1_100)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("音乐")
        .searchable(text: $query, prompt: "搜索歌曲、艺人或专辑")
        .toolbar {
            ToolbarItemGroup {
                #if os(iOS)
                SystemMusicImportButton()
                #endif
                FileImportButton(title: "添加")
                    .labelStyle(.iconOnly)
            }
        }
        .task(id: audioTracks.map(\.relativePath).joined(separator: "|")) {
            for track in audioTracks where player.metadataByPath[track.relativePath] == nil {
                _ = await player.loadMetadata(for: track)
            }
        }
        #if os(iOS)
        .task {
            _ = await SystemMusicLibraryAccess.requestAuthorizationIfNeeded()
        }
        #endif
        .alert("播放失败", isPresented: playbackErrorPresented) {
            Button("好", role: .cancel) { player.playbackError = nil }
        } message: {
            Text(player.playbackError.map(AppLocalization.string) ?? AppLocalization.string("无法播放此文件。"))
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("专辑")
                .font(.title2.weight(.bold))
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                AudioArtwork(data: album.artworkData, fallbackSymbol: "square.stack.fill")
                                    .frame(width: 156, height: 156)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(album.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(album.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 156, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var trackSection: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Text("\(AppLocalization.string("歌曲")) · \(filteredTracks.count)")
                .font(.title2.weight(.bold))
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
            ForEach(filteredTracks) { item in
                AudioTrackRow(item: item, queue: filteredTracks)
                Divider().padding(.leading, 92)
            }
        }
    }

    private var playbackErrorPresented: Binding<Bool> {
        Binding(
            get: { player.playbackError != nil },
            set: { if !$0 { player.playbackError = nil } }
        )
    }

    private func trackIndex(_ value: String?) -> Int {
        Int(value?.split(separator: "/").first ?? "") ?? Int.max
    }
}

private struct AudioTrackRow: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let item: LibraryItem
    let queue: [LibraryItem]

    private var metadata: EmbeddedAudioMetadata? {
        player.metadataByPath[item.relativePath]
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if player.currentItem == item {
                    player.togglePlayback()
                } else {
                    player.play(item, in: queue)
                    store.markOpened(item)
                }
            } label: {
                ZStack {
                    AudioArtwork(data: metadata?.artworkData, fallbackSymbol: "music.note")
                    if player.currentItem == item {
                        Color.black.opacity(0.28)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            NavigationLink {
                NowPlayingView(startingItem: item)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata?.title ?? item.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(artistAndAlbum)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(technicalDetail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            VStack(alignment: .trailing, spacing: 4) {
                if metadata?.isLossless == true {
                    Text("无损")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.pink)
                }
                Text(item.byteCount.formattedFileSize)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var artistAndAlbum: String {
        let values = [metadata?.artist, metadata?.album]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return values.isEmpty ? AppLocalization.string("未知艺人") : values.joined(separator: " · ")
    }

    private var technicalDetail: String {
        let quality = metadata?.qualityDescription ?? ""
        return quality.isEmpty ? item.fileExtension.uppercased() : quality
    }
}

private struct AlbumDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let album: MusicAlbum

    var body: some View {
        ZStack {
            AudioGradientBackground(artworkData: album.artworkData)
            ScrollView {
                VStack(spacing: 20) {
                    AudioArtwork(data: album.artworkData, fallbackSymbol: "square.stack.fill")
                        .frame(maxWidth: 340)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.32), radius: 24, y: 14)

                    VStack(spacing: 5) {
                        Text(album.title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(album.artist)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        Text([album.genre, album.year].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }

                    HStack(spacing: 14) {
                        Button {
                            guard let first = album.tracks.first else { return }
                            player.play(first, in: album.tracks)
                            store.markOpened(first)
                        } label: {
                            Label("播放", systemImage: "play.fill")
                                .frame(minWidth: 150)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)

                        Button {
                            if !player.isShuffleEnabled { player.toggleShuffle() }
                            guard let track = album.tracks.randomElement() else { return }
                            player.play(track, in: album.tracks)
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .adaptiveGlassButton()
                    }

                    LazyVStack(spacing: 0) {
                        ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                            AlbumTrackRow(index: index + 1, item: track, queue: album.tracks)
                            Divider().overlay(.white.opacity(0.16))
                        }
                    }
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 760)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(album.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct AlbumTrackRow: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let index: Int
    let item: LibraryItem
    let queue: [LibraryItem]

    private var metadata: EmbeddedAudioMetadata? { player.metadataByPath[item.relativePath] }

    var body: some View {
        Button {
            player.play(item, in: queue)
            store.markOpened(item)
        } label: {
            HStack(spacing: 14) {
                Text("\(index)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(width: 28, alignment: .trailing)

                VStack(alignment: .leading, spacing: 3) {
                    Text(metadata?.title ?? item.displayName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(metadata?.artist ?? metadata?.album ?? item.fileExtension.uppercased())
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if player.currentItem == item {
                    Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerController
    @State private var isPlayerPresented = false

    var body: some View {
        HStack(spacing: 12) {
            if let item = player.currentItem {
                Button { isPlayerPresented = true } label: {
                    HStack(spacing: 10) {
                        AudioArtwork(data: player.currentMetadata.artworkData, fallbackSymbol: "music.note")
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentMetadata.title ?? item.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(player.currentMetadata.artist ?? AppLocalization.string("鱼饼音乐"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                if player.isPreparing { ProgressView().controlSize(.small) }
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                Button { player.playNext() } label: { Image(systemName: "forward.fill") }
                    .buttonStyle(.plain)
            }
        }
        .padding(8)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        #if os(iOS)
        .fullScreenCover(isPresented: $isPlayerPresented) {
            if let item = player.currentItem {
                NowPlayingView(startingItem: item)
            }
        }
        #else
        .sheet(isPresented: $isPlayerPresented) {
            if let item = player.currentItem {
                NowPlayingView(startingItem: item)
                    .frame(minWidth: 360, minHeight: 560)
            }
        }
        #endif
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @Environment(\.dismiss) private var dismiss
    let startingItem: LibraryItem

    @State private var showsLyrics = false
    @State private var showsSleepTimer = false
    @State private var showsQueue = false

    private var tracks: [LibraryItem] { store.items(of: .music).sorted(by: .name) }
    private var activeItem: LibraryItem { player.currentItem ?? startingItem }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AudioGradientBackground(artworkData: player.currentMetadata.artworkData)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                    #if os(iOS)
                    Capsule()
                        .fill(.white.opacity(0.42))
                        .frame(width: 36, height: 5)
                        .padding(.top, 7)
                        .padding(.bottom, 9)
                    #endif

                    topBar
                    Group {
                        if showsLyrics {
                            SyncedLyricsView(lyrics: player.currentMetadata.lyrics)
                        } else {
                            artworkPanel(size: artworkSize(in: geometry.size))
                        }
                    }
                    .frame(height: showsLyrics ? lyricsHeight(in: geometry.size) : artworkSize(in: geometry.size))
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                    metadataPanel
                    progressPanel
                        .padding(.top, 16)
                    playbackControls
                        .padding(.vertical, 16)
                    volumePanel
                    secondaryControls
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                    }
                    .frame(minHeight: max(geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom, 560), alignment: .top)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, max(8, geometry.safeAreaInsets.bottom * 0.25))
                .frame(maxWidth: 720)
            }
        }
        .onAppear {
            if player.currentItem != startingItem {
                player.play(startingItem, in: tracks)
            }
            store.markOpened(startingItem)
        }
        .confirmationDialog("定时关闭", isPresented: $showsSleepTimer, titleVisibility: .visible) {
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                Button("\(minutes) \(AppLocalization.string("分钟"))") { player.setSleepTimer(minutes: minutes) }
            }
            Button("本曲结束") { player.sleepAfterCurrentTrack() }
            if player.sleepTimerEnd != nil || player.stopAfterCurrentTrack {
                Button("关闭定时", role: .destructive) { player.cancelSleepTimer() }
            }
        }
        .sheet(isPresented: $showsQueue) {
            PlaybackQueueView()
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        #endif
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 2) {
                Text(AppLocalization.string(showsLyrics ? "歌词" : "正在播放"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(player.currentMetadata.album ?? AppLocalization.string("鱼饼音乐"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 200)
            Spacer()
            optionsMenu
        }
    }

    private func artworkPanel(size: CGFloat) -> some View {
        AudioArtwork(data: player.currentMetadata.artworkData, fallbackSymbol: "music.note")
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.34), radius: 24, y: 14)
    }

    private func artworkSize(in size: CGSize) -> CGFloat {
        let width = max(size.width - 56, 150)
        let height = max(size.height - 470, 150)
        return max(150, min(width, 420, height))
    }

    private func lyricsHeight(in size: CGSize) -> CGFloat {
        max(240, min(430, size.height - 430))
    }

    private var metadataPanel: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.currentMetadata.title ?? activeItem.displayName)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(player.currentMetadata.artist ?? player.currentMetadata.album ?? AppLocalization.string("本地音乐"))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            Button { store.toggleFavorite(activeItem) } label: {
                Image(systemName: store.isFavorite(activeItem) ? "star.fill" : "star")
            }
            .adaptiveGlassButton()
        }
    }

    private var progressPanel: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                in: 0...max(player.duration, 1)
            )
            .tint(.white)
            HStack {
                Text(player.currentTime.formattedPlaybackTime)
                Spacer()
                Text("-\(max(player.duration - player.currentTime, 0).formattedPlaybackTime)")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.68))
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 48) {
            Button { player.playPrevious() } label: {
                Image(systemName: "backward.fill").font(.system(size: 34))
            }
            Button { player.togglePlayback() } label: {
                Group {
                    if player.isPreparing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                }
                .font(.system(size: 46, weight: .bold))
                .frame(width: 64, height: 64)
            }
            Button { player.playNext() } label: {
                Image(systemName: "forward.fill").font(.system(size: 34))
            }
        }
        .buttonStyle(.plain)
    }

    private var optionsMenu: some View {
        Menu {
            ShareLink(item: activeItem.url) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            Button { player.toggleShuffle() } label: {
                Label(
                    AppLocalization.string(player.isShuffleEnabled ? "关闭随机播放" : "随机播放"),
                    systemImage: "shuffle"
                )
            }
            Button { player.cycleRepeatMode() } label: {
                Label(player.repeatMode.title, systemImage: player.repeatMode.symbol)
            }
            Menu("播放速度") {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2, 3], id: \.self) { rate in
                    Button {
                        player.setPlaybackRate(Float(rate))
                    } label: {
                        if player.playbackRate == Float(rate) {
                            Label("\(rate.formatted())x", systemImage: "checkmark")
                        } else {
                            Text("\(rate.formatted())x")
                        }
                    }
                }
            }
            Button { showsSleepTimer = true } label: {
                Label("定时关闭", systemImage: "timer")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.12), in: Circle())
        }
    }

    @ViewBuilder
    private var volumePanel: some View {
        #if os(iOS)
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption)
            SystemVolumeSlider()
                .frame(height: 24)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.68))
        #else
        EmptyView()
        #endif
    }

    private var secondaryControls: some View {
        HStack {
            Button { showsLyrics.toggle() } label: {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(showsLyrics ? .white : .white.opacity(0.62))
                    .frame(width: 44, height: 36)
            }
            .accessibilityLabel("歌词")
            Spacer()
            #if os(iOS)
            AirPlayRouteButton()
                .frame(width: 44, height: 36)
                .accessibilityLabel("AirPlay")
            #else
            Image(systemName: "airplayaudio")
                .frame(width: 44, height: 36)
            #endif
            Spacer()
            Button { showsQueue = true } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 36)
            }
            .accessibilityLabel("播放队列")
        }
        .font(.title3)
        .buttonStyle(.plain)
    }
}

private struct PlaybackQueueView: View {
    @EnvironmentObject private var player: AudioPlayerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(player.queue) { item in
                Button {
                    player.play(item, in: player.queue)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AudioArtwork(
                            data: player.metadataByPath[item.relativePath]?.artworkData,
                            fallbackSymbol: "music.note"
                        )
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(player.metadataByPath[item.relativePath]?.title ?? item.displayName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(player.metadataByPath[item.relativePath]?.artist ?? AppLocalization.string("未知艺人"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if player.currentItem == item {
                            Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("播放队列")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#if os(iOS)
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.tintColor = UIColor.white.withAlphaComponent(0.72)
        view.activeTintColor = .white
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

private struct SyncedLyricsView: View {
    @EnvironmentObject private var player: AudioPlayerController
    let lyrics: TimedLyrics?

    private var activeIndex: Int? { lyrics?.lineIndex(at: player.currentTime) }

    var body: some View {
        Group {
            if let lyrics, !lyrics.lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                                lyricText(line, index: index)
                                    .font(index == activeIndex ? .title.weight(.bold) : .title2.weight(.bold))
                                    .opacity(index == activeIndex ? 1 : 0.34)
                                    .blur(radius: index == activeIndex ? 0 : 1.1)
                                    .id(line.id)
                                    .onTapGesture { player.seek(to: line.time) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 90)
                    }
                    .onChange(of: activeIndex) { _, newIndex in
                        guard let newIndex, lyrics.lines.indices.contains(newIndex) else { return }
                        withAnimation(.easeOut(duration: 0.35)) {
                            proxy.scrollTo(lyrics.lines[newIndex].id, anchor: .center)
                        }
                    }
                }
            } else if let text = lyrics?.untimedText {
                ScrollView { Text(text).font(.title3).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                ContentUnavailableView("没有歌词", systemImage: "quote.bubble", description: Text("导入同名 LRC 文件，或使用带内嵌歌词的音频。"))
                    .foregroundStyle(.white)
            }
        }
    }

    private func lyricText(_ line: TimedLyricLine, index: Int) -> Text {
        guard !line.words.isEmpty else {
            let activeCharacters = activeIndex == index ? (lyrics?.activeCharacterCount(in: index, at: player.currentTime) ?? 0) : 0
            return line.text.enumerated().reduce(Text("")) { partial, entry in
                partial + Text(String(entry.element))
                    .foregroundColor(entry.offset < activeCharacters ? .white : .white.opacity(0.42))
            }
        }
        let activeWord = activeIndex == index ? player.currentMetadata.lyrics?.activeWordIndex(in: index, at: player.currentTime) : nil
        return line.words.enumerated().reduce(Text("")) { partial, entry in
            partial + Text(entry.element.text)
                .foregroundColor(entry.offset <= (activeWord ?? -1) ? .white : .white.opacity(0.42))
        }
    }
}

private struct AudioGradientBackground: View {
    let artworkData: Data?

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.10, blue: 0.12)
            if let image = platformAudioImage(data: artworkData) {
                platformAudioImageView(image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 58)
                    .scaleEffect(1.30)
                    .opacity(0.94)
            }
            Rectangle().fill(.ultraThinMaterial).opacity(0.18)
            Color.black.opacity(0.24)
        }
        .ignoresSafeArea()
    }
}

private struct AudioArtwork: View {
    let data: Data?
    let fallbackSymbol: String

    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.12))
            if let image = platformAudioImage(data: data) {
                platformAudioImageView(image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.10)
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .clipped()
    }
}

private func platformAudioImage(data: Data?) -> AudioPlatformImage? {
    guard let data else { return nil }
    #if os(macOS)
    return NSImage(data: data)
    #else
    return UIImage(data: data)
    #endif
}

@ViewBuilder
private func platformAudioImageView(_ image: AudioPlatformImage) -> Image {
    #if os(macOS)
    Image(nsImage: image)
    #else
    Image(uiImage: image)
    #endif
}
