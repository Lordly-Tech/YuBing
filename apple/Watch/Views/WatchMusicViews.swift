import SwiftUI

struct WatchMusicLibraryView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer
    @State private var query = ""

    private var tracks: [WatchLibraryItem] {
        store.items(of: [.music])
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView("还没有音乐", systemImage: "music.note", description: Text("从 iPhone 传入音频后可离线播放。"))
            } else {
                List(tracks) { track in
                    Button {
                        player.play(track, queue: tracks)
                        store.markOpened(track)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: player.currentItem == track && player.isPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                                .foregroundStyle(.pink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.displayName).lineLimit(1)
                                Text(track.byteCount.watchFormattedFileSize)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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

