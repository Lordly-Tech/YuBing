import SwiftUI

// Playlist and album detail flows adapted from youshen2/MeloX (GPL-3.0).

private enum MeloXCollectionPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}

struct MeloXPlaylistDetailView: View {
    @EnvironmentObject private var service: MeloXMusicService
    let initialPlaylist: MeloXPlaylist

    @State private var playlist: MeloXPlaylist?
    @State private var phase: MeloXCollectionPhase = .loading
    @State private var query = ""
    @State private var reloadToken = 0

    private var displayedPlaylist: MeloXPlaylist { playlist ?? initialPlaylist }

    var body: some View {
        MeloXCollectionDetailView(
            artworkURL: displayedPlaylist.artworkURL,
            title: displayedPlaylist.name,
            subtitle: displayedPlaylist.creator?.nickname ?? "网易云音乐",
            metadata: playlistMetadata,
            description: displayedPlaylist.playlistDescription,
            songs: filteredSongs,
            isLoading: playlist == nil && phase == .loading,
            failureMessage: failureMessage
        ) {
            await service.play($0, in: displayedPlaylist.tracks)
        } playAll: {
            guard let first = displayedPlaylist.tracks.first else { return }
            Task { await service.play(first, in: displayedPlaylist.tracks) }
        } retry: {
            reloadToken += 1
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $query, prompt: "在歌单中搜索")
        .task(id: reloadToken) { await load() }
        .refreshable { await load(force: true) }
    }

    private var filteredSongs: [MeloXSong] {
        guard !query.isEmpty else { return displayedPlaylist.tracks }
        return displayedPlaylist.tracks.filter { song in
            [song.name, song.artistText, song.album?.name]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var playlistMetadata: String {
        var values = ["\(displayedPlaylist.trackCount) 首歌曲"]
        if displayedPlaylist.playCount > 0 {
            values.append("\(meloXPlayCountText(displayedPlaylist.playCount)) 次播放")
        }
        if let update = displayedPlaylist.updateFrequency, !update.isEmpty {
            values.append(update)
        }
        return values.joined(separator: " · ")
    }

    private var failureMessage: String? {
        if case .failed(let message) = phase, playlist == nil { return message }
        return nil
    }

    private func load(force: Bool = false) async {
        guard force || playlist == nil else { return }
        phase = .loading
        do {
            playlist = try await service.playlist(id: initialPlaylist.id)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

struct MeloXAlbumDetailView: View {
    @EnvironmentObject private var service: MeloXMusicService
    let initialAlbum: MeloXAlbum

    @State private var album: MeloXAlbum?
    @State private var songs: [MeloXSong] = []
    @State private var phase: MeloXCollectionPhase = .loading
    @State private var query = ""
    @State private var reloadToken = 0

    private var displayedAlbum: MeloXAlbum { album ?? initialAlbum }

    var body: some View {
        MeloXCollectionDetailView(
            artworkURL: displayedAlbum.artworkURL,
            title: displayedAlbum.name,
            subtitle: displayedAlbum.artistText,
            metadata: albumMetadata,
            description: displayedAlbum.albumDescription,
            songs: filteredSongs,
            isLoading: album == nil && phase == .loading,
            failureMessage: failureMessage
        ) { song in
            await service.play(song, in: songs)
        } playAll: {
            guard let first = songs.first else { return }
            Task { await service.play(first, in: songs) }
        } retry: {
            reloadToken += 1
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $query, prompt: "在专辑中搜索")
        .task(id: reloadToken) { await load() }
        .refreshable { await load(force: true) }
    }

    private var filteredSongs: [MeloXSong] {
        guard !query.isEmpty else { return songs }
        return songs.filter { song in
            [song.name, song.artistText]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var albumMetadata: String {
        var values = [displayedAlbum.type?.nilIfBlank ?? "专辑"]
        if let timestamp = displayedAlbum.publishTime {
            let date = Date(timeIntervalSince1970: timestamp / 1_000)
            values.append("\(Calendar.current.component(.year, from: date))年")
        }
        values.append("\(songs.isEmpty ? (displayedAlbum.size ?? 0) : songs.count) 首歌曲")
        return values.joined(separator: " · ")
    }

    private var failureMessage: String? {
        if case .failed(let message) = phase, album == nil { return message }
        return nil
    }

    private func load(force: Bool = false) async {
        guard force || album == nil else { return }
        phase = .loading
        do {
            let result = try await service.album(id: initialAlbum.id)
            album = result.0
            songs = result.1
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct MeloXCollectionDetailView: View {
    @EnvironmentObject private var player: AudioPlayerController

    let artworkURL: URL?
    let title: String
    let subtitle: String
    let metadata: String
    let description: String?
    let songs: [MeloXSong]
    let isLoading: Bool
    let failureMessage: String?
    let play: (MeloXSong) async -> Void
    let playAll: () -> Void
    let retry: () -> Void

    var body: some View {
        ZStack {
            backdrop

            ScrollView {
                LazyVStack(spacing: 0) {
                    hero
                    trackContent
                }
                .frame(maxWidth: 920)
                .padding(.horizontal, 18)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var backdrop: some View {
        ZStack {
            Color.primary.opacity(0.035)
            AsyncImage(url: artworkURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 64)
                        .saturation(1.15)
                        .opacity(0.34)
                }
            }
            LinearGradient(
                colors: [.clear, Color.primary.opacity(0.035), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) {
                heroArtwork(size: 210)
                heroText
            }
            .frame(minWidth: 620)
            .padding(.top, 26)
            .padding(.bottom, 30)

            VStack(alignment: .leading, spacing: 18) {
                heroArtwork(size: 220)
                    .frame(maxWidth: .infinity)
                heroText
            }
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
    }

    private func heroArtwork(size: CGFloat) -> some View {
        MeloXArtworkView(url: artworkURL)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(metadata)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let description = description?.nilIfBlank {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Button(action: playAll) {
                Label("播放全部", systemImage: "play.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .disabled(songs.isEmpty)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trackContent: some View {
        if songs.isEmpty {
            if isLoading {
                ProgressView("正在载入歌曲")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if let failureMessage {
                ContentUnavailableView {
                    Label("无法载入歌曲", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(failureMessage)
                } actions: {
                    Button("重试", action: retry)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ContentUnavailableView("暂无歌曲", systemImage: "music.note")
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 6) {
                        Button {
                            Task { await play(song) }
                        } label: {
                            MeloXOnlineTrackRow(
                                song: song,
                                index: index,
                                isCurrent: player.currentItem?.relativePath == "MeloX/\(song.id).mp3"
                            )
                        }
                        .buttonStyle(.plain)

                        if let album = song.album {
                            NavigationLink {
                                MeloXAlbumDetailView(initialAlbum: album)
                            } label: {
                                Image(systemName: "square.stack")
                                    .frame(width: 36, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("查看专辑")
                        }
                    }

                    if index < songs.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }
}

private struct MeloXOnlineTrackRow: View {
    let song: MeloXSong
    let index: Int
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(
                        isCurrent ? AnyShapeStyle(Color.pink) : AnyShapeStyle(Color.primary)
                    )
                    .lineLimit(1)
                Text(song.artistText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(song.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.pink)
                    .accessibilityLabel("当前歌曲")
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
