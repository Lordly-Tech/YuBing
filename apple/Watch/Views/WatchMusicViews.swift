import SwiftUI
import WatchKit

struct WatchMusicLibraryView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer
    @State private var query = ""

    private var mediaItems: [WatchLibraryItem] {
        store.items(of: [.music, .video])
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var audioTracks: [WatchLibraryItem] {
        store.items(of: [.music])
    }

    var body: some View {
        Group {
            if mediaItems.isEmpty {
                ContentUnavailableView("还没有影音", systemImage: "play.rectangle", description: Text("从 iPhone 传入影音文件后可离线播放。"))
            } else {
                List(mediaItems) { item in
                    if item.kind == .music {
                        Button {
                            player.play(item, queue: audioTracks)
                            store.markOpened(item)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: player.currentItem == item && player.isPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                                    .foregroundStyle(.pink)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName).lineLimit(1)
                                    Text(item.byteCount.watchFormattedFileSize)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        NavigationLink {
                            WatchVideoPlayerView(item: item)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName).lineLimit(1)
                                    Text(item.byteCount.watchFormattedFileSize)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("影音")
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
    private var active: WatchLibraryItem { player.currentItem ?? startingItem }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.pink)
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)

                VStack(spacing: 2) {
                    Text(active.displayName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text("鱼饼 Watch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 3) {
                    Slider(
                        value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                        in: 0...max(player.duration, 1)
                    )
                    HStack {
                        Text(player.currentTime.watchPlaybackTime)
                        Spacer()
                        Text(player.duration.watchPlaybackTime)
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button { player.previous() } label: { Image(systemName: "backward.fill") }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 28, height: 28)
                    }
                    .watchGlassButton(prominent: true)
                    Button { player.next() } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("正在播放")
        .onAppear {
            if player.currentItem != startingItem {
                player.play(startingItem, queue: tracks)
            }
            store.markOpened(startingItem)
        }
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
