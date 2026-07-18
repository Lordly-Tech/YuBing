import SwiftUI
import ImageIO
import WatchKit

struct WatchMusicLibraryView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer
    @State private var query = ""

    private var mediaItems: [WatchLibraryItem] {
        store.items(of: [.music])
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var audioTracks: [WatchLibraryItem] {
        store.items(of: [.music])
    }

    var body: some View {
        Group {
            if mediaItems.isEmpty {
                ContentUnavailableView("还没有音乐", systemImage: "music.note.list", description: Text("从 iPhone 传入音乐后可离线播放。"))
            } else {
                List(mediaItems) { item in
                    Button {
                        player.play(item, queue: audioTracks)
                        store.markOpened(item)
                    } label: {
                        HStack(spacing: 8) {
                            WatchAudioArtwork(
                                data: player.metadataByPath[item.relativePath]?.artworkData,
                                size: 42
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.metadataByPath[item.relativePath]?.title ?? item.displayName)
                                    .lineLimit(1)
                                Text(audioDetail(for: item))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: player.currentItem == item && player.isPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                                .foregroundStyle(.pink)
                        }
                    }
                    .task { _ = await player.loadMetadata(for: item) }
                }
            }
        }
        .navigationTitle("音乐")
        .searchable(text: $query, prompt: "搜索")
        .toolbar {
            if let item = player.currentItem {
                NavigationLink {
                    WatchNowPlayingView(startingItem: item)
                } label: {
                    Label("正在播放", systemImage: "waveform")
                }
            }
        }
    }
}

struct WatchNowPlayingView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer
    let startingItem: WatchLibraryItem

    private var tracks: [WatchLibraryItem] { store.items(of: [.music]) }
    var body: some View {
        NowPlayingView()
            .onAppear {
                if player.currentItem != startingItem {
                    player.play(startingItem, queue: tracks)
                }
                store.markOpened(startingItem)
            }
            .toolbar(.hidden, for: .navigationBar)
    }
}

struct WatchGalleryView: View {
    @EnvironmentObject private var store: WatchLibraryStore

    private var mediaItems: [WatchLibraryItem] {
        store.items(of: [.photo, .video])
    }

    var body: some View {
        Group {
            if mediaItems.isEmpty {
                ContentUnavailableView(
                    "图库是空的",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("从 iPhone 传入照片或视频后可离线查看。")
                )
            } else {
                List(mediaItems) { item in
                    NavigationLink {
                        WatchItemDestination(item: item)
                    } label: {
                        WatchFileRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("图库")
    }
}

private extension WatchMusicLibraryView {
    func audioDetail(for item: WatchLibraryItem) -> String {
        let metadata = player.metadataByPath[item.relativePath]
        let details = [metadata?.artist, metadata?.album]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return details.isEmpty ? item.byteCount.watchFormattedFileSize : details.joined(separator: " · ")
    }
}

private struct WatchAudioArtwork: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.pink.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WatchVideoPlayerView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    let item: WatchLibraryItem
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.purple)

                VStack(spacing: 2) {
                    Text(item.displayName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(item.byteCount.watchFormattedFileSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    playVideo()
                } label: {
                    Label("播放视频", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .watchGlassButton(prominent: true)

                if let message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(item.displayName)
        .onAppear {
            store.markOpened(item)
        }
    }

    private func playVideo() {
        guard let controller = WKExtension.shared().rootInterfaceController else {
            message = "暂时无法打开系统播放器。"
            return
        }
        let options: [AnyHashable: Any] = [
            WKMediaPlayerControllerOptionsAutoplayKey: true
        ]
        controller.presentMediaPlayerController(with: item.url, options: options) { didPlayToEnd, _, error in
            Task { @MainActor in
                if let error {
                    message = error.localizedDescription
                } else {
                    message = didPlayToEnd ? "播放完成" : "已关闭播放器"
                }
            }
        }
    }
}
