import SwiftUI

struct MusicLibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @State private var query = ""

    private var mediaItems: [LibraryItem] {
        store.items
            .filter { $0.kind == .music || $0.kind == .video }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted(by: .name)
    }

    private var audioTracks: [LibraryItem] {
        store.items(of: .music).sorted(by: .name)
    }

    var body: some View {
        Group {
            if mediaItems.isEmpty {
                ContentUnavailablePanel(
                    title: "还没有影音",
                    message: "导入 MP3、M4A、AAC、WAV、FLAC、MP4、M4V 或 MOV。",
                    symbol: "play.rectangle",
                    action: AnyView(LibraryImportMenu(title: "添加影音", photoScope: .videos, prominent: true))
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if player.currentItem != nil {
                            compactNowPlaying
                                .padding(.bottom, 18)
                        }

                        Text("影音 · \(mediaItems.count)")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                        ForEach(mediaItems) { item in
                            HStack(spacing: 10) {
                                if item.kind == .music {
                                    Button {
                                        player.play(item, in: audioTracks)
                                        store.markOpened(item)
                                    } label: {
                                        Image(systemName: player.currentItem == item && player.isPlaying ? "pause.fill" : "play.fill")
                                            .frame(width: 34, height: 34)
                                    }
                                    .adaptiveGlassButton()
                                } else {
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundStyle(.purple)
                                        .frame(width: 34, height: 34)
                                }

                                NavigationLink(value: item) {
                                    LibraryItemRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            Divider().padding(.leading, 76)
                        }
                    }
                    .frame(maxWidth: 880)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("影音")
        .searchable(text: $query, prompt: "搜索影音")
        .toolbar {
            LibraryImportMenu(title: "添加", photoScope: .videos)
                .labelStyle(.iconOnly)
        }
    }

    private var compactNowPlaying: some View {
        HStack(spacing: 16) {
            if let item = player.currentItem {
                FileThumbnailView(item: item, size: CGSize(width: 88, height: 88))
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: YuBingMetrics.compactCornerRadius))
                VStack(alignment: .leading, spacing: 7) {
                    Text("正在播放")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.pink)
                    Text(player.currentMetadata.title ?? item.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if let artist = player.currentMetadata.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ProgressView(value: player.currentTime, total: max(player.duration, 1))
                        .tint(.pink)
                }
                Spacer()
                Button { player.playPrevious() } label: { Image(systemName: "backward.fill") }
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 28, height: 28)
                }
                .adaptiveGlassButton(prominent: true)
                Button { player.playNext() } label: { Image(systemName: "forward.fill") }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: YuBingMetrics.compactCornerRadius))
        .padding(.horizontal, 16)
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerController
    @State private var isPlayerPresented = false

    var body: some View {
        AdaptiveGlassGroup {
            HStack(spacing: 10) {
                if let item = player.currentItem {
                    Button {
                        isPlayerPresented = true
                    } label: {
                        HStack(spacing: 10) {
                            FileThumbnailView(item: item, size: CGSize(width: 40, height: 40))
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(player.currentTime.formattedPlaybackTime) / \(player.duration.formattedPlaybackTime)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 8)
                    Button { player.playPrevious() } label: { Image(systemName: "backward.fill") }
                        .buttonStyle(.plain)
                    Button { player.togglePlayback() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 30, height: 30)
                    }
                    .adaptiveGlassButton(prominent: true)
                    Button { player.playNext() } label: { Image(systemName: "forward.fill") }
                        .buttonStyle(.plain)
                }
            }
            .padding(8)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sheet(isPresented: $isPlayerPresented) {
            if let item = player.currentItem {
                NavigationStack { NowPlayingView(startingItem: item) }
                    .frame(minWidth: 360, minHeight: 520)
            }
        }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let startingItem: LibraryItem

    private var tracks: [LibraryItem] { store.items(of: .music).sorted(by: .name) }
    private var activeItem: LibraryItem { player.currentItem ?? startingItem }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                FileThumbnailView(item: activeItem, size: CGSize(width: 420, height: 420))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 420)
                    .clipShape(RoundedRectangle(cornerRadius: YuBingMetrics.panelCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 18, y: 10)

                VStack(spacing: 5) {
                    Text(player.currentMetadata.title ?? activeItem.displayName)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    if let artist = player.currentMetadata.artist {
                        Text(artist)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    if let album = player.currentMetadata.album {
                        Text(album)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("鱼饼 资料库")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 7) {
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 1)
                    )
                    HStack {
                        Text(player.currentTime.formattedPlaybackTime)
                        Spacer()
                        Text(player.duration.formattedPlaybackTime)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 520)

                HStack(spacing: 28) {
                    Button { player.playPrevious() } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    Button { player.togglePlayback() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 50, height: 50)
                    }
                    .adaptiveGlassButton(prominent: true)
                    Button { player.playNext() } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("正在播放")
        .toolbar { ShareLink(item: activeItem.url) }
        .onAppear {
            if player.currentItem != startingItem {
                player.play(startingItem, in: tracks)
            }
            store.markOpened(startingItem)
        }
    }
}
