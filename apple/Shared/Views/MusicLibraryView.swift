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

// Music playback and album surfaces are adapted from MeloX (GPL-3.0) for YuBing's local file library.
private struct MusicAlbum: Identifiable {
    let id: String
    let title: String
    let artist: String
    let year: String?
    let genre: String?
    let artworkData: Data?
    let tracks: [LibraryItem]

    var detailText: String {
        [artist, year, genre]
            .compactMap { value in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }
}

private enum NowPlayingPage: String, Equatable {
    case artwork
    case lyrics
    case queue
}

struct MusicLibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @State private var query = ""
    @State private var showsCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var addToPlaylistItem: LibraryItem?

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
                  let albumTitle = cleaned(metadata.album) else { continue }
            let artist = cleaned(metadata.albumArtist) ?? cleaned(metadata.artist) ?? AppLocalization.string("未知艺人")
            grouped["\(albumTitle)|\(artist)", default: []].append(track)
        }

        return grouped.compactMap { key, tracks -> MusicAlbum? in
            guard let first = tracks.first,
                  let metadata = player.metadataByPath[first.relativePath],
                  let title = cleaned(metadata.album) else { return nil }
            return MusicAlbum(
                id: key,
                title: title,
                artist: cleaned(metadata.albumArtist) ?? cleaned(metadata.artist) ?? AppLocalization.string("未知艺人"),
                year: cleaned(metadata.year),
                genre: cleaned(metadata.genre),
                artworkData: metadata.artworkData,
                tracks: tracks.sorted { lhs, rhs in
                    let lhsMetadata = player.metadataByPath[lhs.relativePath]
                    let rhsMetadata = player.metadataByPath[rhs.relativePath]
                    let lhsDisc = trackIndex(lhsMetadata?.discNumber)
                    let rhsDisc = trackIndex(rhsMetadata?.discNumber)
                    if lhsDisc != rhsDisc { return lhsDisc < rhsDisc }
                    let lhsTrack = trackIndex(lhsMetadata?.trackNumber)
                    let rhsTrack = trackIndex(rhsMetadata?.trackNumber)
                    if lhsTrack != rhsTrack { return lhsTrack < rhsTrack }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
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
                    LazyVStack(alignment: .leading, spacing: 28) {
                        libraryHeader
                        playlistSection
                        if !albums.isEmpty {
                            albumSection
                        }
                        trackSection
                    }
                    .frame(maxWidth: YuBingMetrics.contentMaxWidth, alignment: .leading)
                    .padding(.horizontal, 18)
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
        .sheet(item: $addToPlaylistItem) { item in
            AddToPlaylistSheet(item: item)
        }
        .alert("新建歌单", isPresented: $showsCreatePlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("取消", role: .cancel) { newPlaylistName = "" }
            Button("创建") {
                store.createMusicPlaylist(named: newPlaylistName)
                newPlaylistName = ""
            }
        } message: {
            Text("创建一个本地音乐歌单。")
        }
    }

    private var libraryHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("本地音乐")
                    .font(.largeTitle.bold())
                Text("\(filteredTracks.count) 首歌曲 · \(albums.count) 张专辑")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let first = filteredTracks.first {
                Button {
                    player.play(first, in: filteredTracks)
                    store.markOpened(first)
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "专辑")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 18)
            }
        }
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: "歌单")
                Button {
                    showsCreatePlaylist = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("新建歌单")
            }

            if store.musicPlaylists.isEmpty {
                Button {
                    showsCreatePlaylist = true
                } label: {
                    Label("新建歌单", systemImage: "music.note.list")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(store.musicPlaylists) { playlist in
                            NavigationLink {
                                MusicPlaylistDetailView(playlist: playlist)
                            } label: {
                                MusicPlaylistCard(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 18)
                }
            }
        }
    }

    private var trackSection: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: "歌曲")
                .padding(.bottom, 4)
            ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, item in
                Button {
                    player.play(item, in: filteredTracks)
                    store.markOpened(item)
                } label: {
                    LocalTrackRow(item: item, index: index, showsArtwork: true)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    MusicTrackContextActions(item: item, addToPlaylistItem: $addToPlaylistItem)
                }
                if index < filteredTracks.count - 1 {
                    Divider().padding(.leading, 62)
                }
            }
        }
    }

    private var playbackErrorPresented: Binding<Bool> {
        Binding(
            get: { player.playbackError != nil },
            set: { if !$0 { player.playbackError = nil } }
        )
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(AppLocalization.string(text))
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LocalTrackRow: View {
    @EnvironmentObject private var player: AudioPlayerController
    let item: LibraryItem
    var index: Int? = nil
    var showsArtwork = false
    var foregroundStyle: AnyShapeStyle = AnyShapeStyle(.primary)
    var secondaryStyle: AnyShapeStyle = AnyShapeStyle(.secondary)

    private var metadata: EmbeddedAudioMetadata? {
        player.metadataByPath[item.relativePath]
    }

    var body: some View {
        HStack(spacing: 12) {
            if showsArtwork {
                AudioArtwork(data: metadata?.artworkData, fallbackSymbol: "music.note")
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else if let index {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondaryStyle)
                    .frame(width: 28, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(metadata?.title ?? item.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(foregroundStyle)
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(secondaryStyle)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if metadata?.isLossless == true {
                Text("Lossless")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.pink)
            }
            if player.currentItem == item {
                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .foregroundStyle(secondaryStyle)
                    .accessibilityLabel("当前歌曲")
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        let values = [metadata?.artist, metadata?.album]
            .compactMap(cleaned)
        if !values.isEmpty { return values.joined(separator: " · ") }
        let quality = cleaned(metadata?.qualityDescription)
        return quality ?? "\(item.fileExtension.uppercased()) · \(item.byteCount.formattedFileSize)"
    }
}

private struct MusicPlaylistCard: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let playlist: MusicPlaylist

    private var tracks: [LibraryItem] {
        store.tracks(in: playlist)
    }

    private var firstArtworkData: Data? {
        tracks.compactMap { player.metadataByPath[$0.relativePath]?.artworkData }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AudioArtwork(data: firstArtworkData, fallbackSymbol: "music.note.list")
                    .frame(width: 156, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if store.isFavorite(playlist) {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .padding(7)
                        .background(.thinMaterial, in: Circle())
                        .padding(7)
                }
            }

            Text(playlist.name)
                .font(.headline)
                .lineLimit(1)
            Text("\(tracks.count) 首歌曲")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 156, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                store.toggleFavorite(playlist)
            } label: {
                Label(store.isFavorite(playlist) ? "取消收藏歌单" : "收藏歌单", systemImage: store.isFavorite(playlist) ? "star.slash" : "star")
            }
        }
    }
}

private struct AlbumDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let album: MusicAlbum
    @State private var addToPlaylistItem: LibraryItem?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        AudioArtwork(data: album.artworkData, fallbackSymbol: "square.stack.fill")
                            .frame(width: 132, height: 132)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(album.title)
                                .font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            Text(album.artist)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            if !album.detailText.isEmpty {
                                Text(album.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }

                    Button {
                        guard let first = album.tracks.first else { return }
                        player.play(first, in: album.tracks)
                        store.markOpened(first)
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(album.tracks.isEmpty)
                }
                .padding(.vertical, 8)
            }

            Section("歌曲") {
                ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        player.play(track, in: album.tracks)
                        store.markOpened(track)
                    } label: {
                        LocalTrackRow(item: track, index: index, showsArtwork: false)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button {
                            store.toggleFavorite(track)
                        } label: {
                            Label(store.isFavorite(track) ? "取消收藏" : "收藏", systemImage: store.isFavorite(track) ? "star.slash" : "star")
                        }
                        .tint(.pink)
                    }
                    .contextMenu {
                        MusicTrackContextActions(item: track, addToPlaylistItem: $addToPlaylistItem)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(album.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $addToPlaylistItem) { item in
            AddToPlaylistSheet(item: item)
        }
    }
}

private struct MusicPlaylistDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let playlist: MusicPlaylist

    @State private var renameText = ""
    @State private var showsRename = false
    @State private var showsDeleteConfirmation = false
    @State private var addToPlaylistItem: LibraryItem?

    private var currentPlaylist: MusicPlaylist {
        store.musicPlaylists.first { $0.id == playlist.id } ?? playlist
    }

    private var tracks: [LibraryItem] {
        store.tracks(in: currentPlaylist)
    }

    private var artworkData: Data? {
        tracks.compactMap { player.metadataByPath[$0.relativePath]?.artworkData }.first
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        AudioArtwork(data: artworkData, fallbackSymbol: "music.note.list")
                            .frame(width: 132, height: 132)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(currentPlaylist.name)
                                .font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(tracks.count) 首歌曲")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text(currentPlaylist.updatedAt, format: .dateTime.year().month().day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            guard let first = tracks.first else { return }
                            player.play(first, in: tracks)
                            store.markOpened(first)
                        } label: {
                            Label("播放全部", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(tracks.isEmpty)

                        Button {
                            store.toggleFavorite(currentPlaylist)
                        } label: {
                            Image(systemName: store.isFavorite(currentPlaylist) ? "star.fill" : "star")
                                .frame(width: 44, height: 36)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(store.isFavorite(currentPlaylist) ? "取消收藏歌单" : "收藏歌单")
                    }
                }
                .padding(.vertical, 8)
            }

            Section("歌曲") {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        player.play(track, in: tracks)
                        store.markOpened(track)
                    } label: {
                        LocalTrackRow(item: track, index: index, showsArtwork: true)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.remove(track, from: currentPlaylist)
                        } label: {
                            Label("移出歌单", systemImage: "minus.circle")
                        }
                    }
                    .contextMenu {
                        MusicTrackContextActions(item: track, addToPlaylistItem: $addToPlaylistItem)
                        Button(role: .destructive) {
                            store.remove(track, from: currentPlaylist)
                        } label: {
                            Label("移出歌单", systemImage: "minus.circle")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(currentPlaylist.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        renameText = currentPlaylist.name
                        showsRename = true
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label("删除歌单", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(item: $addToPlaylistItem) { item in
            AddToPlaylistSheet(item: item)
        }
        .alert("重命名歌单", isPresented: $showsRename) {
            TextField("歌单名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { store.rename(currentPlaylist, to: renameText) }
        }
        .confirmationDialog("删除歌单", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("删除歌单", role: .destructive) {
                store.delete(currentPlaylist)
            }
        } message: {
            Text("歌单会被删除，歌曲文件仍会保留。")
        }
    }
}

private struct MusicTrackContextActions: View {
    @EnvironmentObject private var store: LibraryStore
    let item: LibraryItem
    @Binding var addToPlaylistItem: LibraryItem?

    var body: some View {
        Button {
            store.toggleFavorite(item)
        } label: {
            Label(store.isFavorite(item) ? "取消收藏歌曲" : "收藏歌曲", systemImage: store.isFavorite(item) ? "star.slash" : "star")
        }
        Button {
            addToPlaylistItem = item
        } label: {
            Label("添加到歌单", systemImage: "text.badge.plus")
        }
        ShareLink(item: item.url) {
            Label("分享", systemImage: "square.and.arrow.up")
        }
    }
}

private struct AddToPlaylistSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem

    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("新歌单名称", text: $newPlaylistName)
                        Button("创建并添加") {
                            store.createMusicPlaylist(named: newPlaylistName, initialTrack: item)
                            dismiss()
                        }
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("已有歌单") {
                    if store.musicPlaylists.isEmpty {
                        ContentUnavailableView("还没有歌单", systemImage: "music.note.list")
                    } else {
                        ForEach(store.musicPlaylists) { playlist in
                            let contains = store.contains(item, in: playlist)
                            Button {
                                if contains {
                                    store.remove(item, from: playlist)
                                } else {
                                    store.add(item, to: playlist)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.name)
                                            .foregroundStyle(.primary)
                                        Text("\(store.tracks(in: playlist).count) 首歌曲")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: contains ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(contains ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("添加到歌单")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerController
    let openPlayer: (LibraryItem) -> Void

    var body: some View {
        if let item = player.currentItem {
            HStack(spacing: 10) {
                Button { openPlayer(item) } label: {
                    HStack(spacing: 10) {
                        AudioArtwork(data: player.currentMetadata.artworkData, fallbackSymbol: "music.note")
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentMetadata.title ?? item.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(player.currentMetadata.artist ?? player.currentMetadata.album ?? AppLocalization.string("本地音乐"))
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
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 36, height: 36)
                } else {
                    Button {
                        player.togglePlayback()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                }

                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一首")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 58)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 29, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 29, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            .simultaneousGesture(trackSwipeGesture)
        }
    }

    private var trackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 {
                    player.playNext()
                } else {
                    player.playPrevious()
                }
            }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @Environment(\.dismiss) private var dismiss

    let startingItem: LibraryItem
    var queueItems: [LibraryItem]? = nil

    @State private var page: NowPlayingPage = .artwork
    @State private var showsSleepTimer = false
    @State private var showsSkylineLyrics = false

    private var tracks: [LibraryItem] {
        (queueItems ?? store.items(of: .music).sorted(by: .name)).filter { $0.kind == .music }
    }

    private var activeItem: LibraryItem {
        player.currentItem ?? startingItem
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscapePlayer = proxy.size.width > proxy.size.height
                && proxy.size.width >= 720
                && proxy.size.height >= 520

            ZStack {
                NowPlayingBackground(artworkData: player.currentMetadata.artworkData)

                if isLandscapePlayer {
                    landscapeContent
                } else {
                    portraitContent
                }

                if showsSkylineLyrics, page == .lyrics, isLandscapePlayer {
                    SkylineLyricsView(
                        lyrics: player.currentMetadata.lyrics,
                        onExit: { showsSkylineLyrics = false }
                    )
                    .zIndex(1)
                }
            }
            .foregroundStyle(.white)
            .simultaneousGesture(dismissDragGesture)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            player.isNowPlayingVisible = true
            if let queueItems {
                player.setQueue(queueItems)
            } else if player.queue.isEmpty {
                player.setQueue(tracks)
            }
            if player.currentItem != startingItem {
                player.play(startingItem, in: tracks)
            }
            store.markOpened(startingItem)
        }
        .onDisappear {
            player.isNowPlayingVisible = false
        }
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
        .animation(.smooth(duration: 0.32), value: page)
        .onChange(of: page) { _, newPage in
            if newPage != .lyrics {
                showsSkylineLyrics = false
            }
        }
    }

    private var portraitContent: some View {
        VStack(spacing: 0) {
            dismissalHandle

            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            NowPlayingProgressControl()
            NowPlayingTransportControls()
            NowPlayingVolumeControl()
            NowPlayingPageSelector(page: $page)
        }
        .padding(.horizontal, 28)
        .safeAreaPadding(.top, 4)
        .safeAreaPadding(.bottom, 8)
    }

    private var landscapeContent: some View {
        GeometryReader { proxy in
            let controlWidth = min(max(proxy.size.width * 0.34, 320), 430)
            let artworkSide = min(max(proxy.size.height * 0.28, 150), 240)
            let spacing = min(max(proxy.size.width * 0.035, 18), 38)

            HStack(spacing: spacing) {
                landscapeControlPanel(artworkSide: artworkSide)
                    .frame(width: controlWidth)
                    .frame(maxHeight: .infinity)

                landscapePagePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 1_180, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 32)
        .safeAreaPadding(.vertical, 18)
    }

    private func landscapeControlPanel(artworkSide: CGFloat) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                dismissalHandle
                    .frame(height: 44)

                if page == .lyrics, player.currentMetadata.lyrics?.lines.isEmpty == false {
                    Button {
                        showsSkylineLyrics = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.title3.weight(.medium))
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.13), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开全屏天际歌词")
                }
            }

            Spacer(minLength: 0)

            AudioArtwork(data: player.currentMetadata.artworkData, fallbackSymbol: "music.note")
                .frame(width: artworkSide, height: artworkSide)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.24), radius: 22, y: 12)

            NowPlayingArtworkSummary(
                item: activeItem,
                showsSleepTimer: $showsSleepTimer
            )

            NowPlayingProgressControl()
            NowPlayingTransportControls()
            NowPlayingVolumeControl()
            NowPlayingPageSelector(page: $page)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var landscapePagePanel: some View {
        switch page {
        case .artwork:
            NowPlayingArtworkPage(item: activeItem, showsSleepTimer: $showsSleepTimer)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .lyrics:
            NowPlayingLyricsPage(lyrics: player.currentMetadata.lyrics)
                .transition(.opacity)
        case .queue:
            NowPlayingQueuePage()
                .transition(.opacity)
        }
    }

    private var dismissalHandle: some View {
        Capsule()
            .fill(.white.opacity(0.52))
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .accessibilityLabel("收起播放器")
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                guard value.translation.height > 90,
                      value.translation.height > abs(value.translation.width) * 1.4 else {
                    return
                }
                dismiss()
            }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .artwork:
            NowPlayingArtworkPage(item: activeItem, showsSleepTimer: $showsSleepTimer)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .lyrics:
            NowPlayingLyricsPage(lyrics: player.currentMetadata.lyrics)
                .transition(.opacity)
        case .queue:
            NowPlayingQueuePage()
                .transition(.opacity)
        }
    }
}

private struct NowPlayingArtworkPage: View {
    let item: LibraryItem
    @Binding var showsSleepTimer: Bool

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = max(170, min(proxy.size.width - 28, proxy.size.height - 104))

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                AudioArtwork(data: metadata.artworkData, fallbackSymbol: "music.note")
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: 22, y: 12)

                Spacer(minLength: 22)

                NowPlayingArtworkSummary(item: item, showsSleepTimer: $showsSleepTimer)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @EnvironmentObject private var player: AudioPlayerController
    private var metadata: EmbeddedAudioMetadata { player.currentMetadata }
}

private struct NowPlayingArtworkSummary: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let item: LibraryItem
    @Binding var showsSleepTimer: Bool
    @State private var addToPlaylistItem: LibraryItem?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentMetadata.title ?? item.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(player.currentMetadata.artist ?? player.currentMetadata.album ?? AppLocalization.string("本地音乐"))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.toggleFavorite(item)
            } label: {
                Image(systemName: store.isFavorite(item) ? "star.fill" : "star")
                    .font(.title3.weight(.medium))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.13), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isFavorite(item) ? "取消收藏" : "收藏")

            Menu {
                Button {
                    addToPlaylistItem = item
                } label: {
                    Label("添加到歌单", systemImage: "text.badge.plus")
                }
                ShareLink(item: item.url) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                Button { player.toggleShuffle() } label: {
                    Label(player.isShuffleEnabled ? "关闭随机播放" : "随机播放", systemImage: "shuffle")
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
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.13), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("更多")
            .sheet(item: $addToPlaylistItem) { item in
                AddToPlaylistSheet(item: item)
            }
        }
    }
}

private struct NowPlayingProgressControl: View {
    @EnvironmentObject private var player: AudioPlayerController

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { min(player.currentTime, progressMaximum) },
                    set: { player.seek(to: $0) }
                ),
                in: 0...progressMaximum
            )
            .tint(.white)
            .accessibilityLabel("播放进度")

            HStack {
                Text(player.currentTime.formattedPlaybackTime)
                Spacer()
                Text("-\(max(player.duration - player.currentTime, 0).formattedPlaybackTime)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
        .frame(height: 52)
    }

    private var progressMaximum: TimeInterval {
        max(player.duration, 1)
    }
}

private struct NowPlayingTransportControls: View {
    @EnvironmentObject private var player: AudioPlayerController

    var body: some View {
        HStack {
            Spacer()
            Button { player.playPrevious() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一首")

            Spacer()
            Button { player.togglePlayback() } label: {
                Group {
                    if player.isPreparing {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 48, weight: .medium))
                    }
                }
                .frame(width: 64, height: 64)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Spacer()
            Button { player.playNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一首")
            Spacer()
        }
        .frame(height: 82)
    }
}

private struct NowPlayingVolumeControl: View {
    @EnvironmentObject private var player: AudioPlayerController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption2)
            Slider(
                value: Binding(
                    get: { player.volume },
                    set: { player.setVolume($0) }
                ),
                in: 0...1
            )
            .tint(.white)
            .accessibilityLabel("音量")
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.62))
        .frame(height: 42)
    }
}

private struct NowPlayingPageSelector: View {
    @Binding var page: NowPlayingPage

    var body: some View {
        HStack {
            Spacer()
            pageButton(page: .lyrics, systemImage: "quote.bubble", label: "歌词")
            Spacer()
            #if os(iOS)
            AirPlayRouteButton()
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay")
            #else
            Image(systemName: "airplayaudio")
                .font(.title3)
                .frame(width: 44, height: 44)
            #endif
            Spacer()
            pageButton(page: .queue, systemImage: "list.bullet", label: "播放队列")
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.72))
        .frame(height: 50)
    }

    private func pageButton(page destination: NowPlayingPage, systemImage: String, label: String) -> some View {
        let isSelected = page == destination
        return Button {
            withAnimation(.smooth(duration: 0.32)) {
                page = isSelected ? .artwork : destination
            }
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.white.opacity(isSelected ? 0.2 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NowPlayingLyricsPage: View {
    @EnvironmentObject private var player: AudioPlayerController
    let lyrics: TimedLyrics?

    @AppStorage("yubing.lyrics.translationEnabled") private var translationEnabled = true
    @AppStorage("yubing.lyrics.wordByWord") private var wordByWordEnabled = true
    @AppStorage("yubing.lyrics.pseudoWordByWord") private var pseudoWordByWordEnabled = true
    @AppStorage("yubing.lyrics.glowEnabled") private var glowEnabled = true
    @State private var isBrowsingLyrics = false
    @State private var browsingGeneration = 0

    private var activeIndex: Int? {
        lyrics?.lineIndex(at: player.currentTime)
    }

    var body: some View {
        Group {
            if let lyrics, !lyrics.lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                                SynchronizedLyricLineView(
                                    lyrics: lyrics,
                                    line: line,
                                    lineIndex: index,
                                    isActive: index == activeIndex,
                                    translationEnabled: translationEnabled,
                                    wordByWordEnabled: wordByWordEnabled,
                                    pseudoWordByWordEnabled: pseudoWordByWordEnabled,
                                    glowEnabled: glowEnabled,
                                    alignment: .leading,
                                    fontSize: index == activeIndex ? 31 : 26
                                )
                                    .id(line.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) {
                                        player.seek(to: line.time)
                                        isBrowsingLyrics = false
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 96)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { _ in
                                browsingGeneration += 1
                                isBrowsingLyrics = true
                            }
                            .onEnded { _ in
                                schedulePlaybackFollowing()
                            }
                    )
                    .onChange(of: activeIndex) { _, newIndex in
                        guard !isBrowsingLyrics,
                              let newIndex,
                              lyrics.lines.indices.contains(newIndex) else { return }
                        withAnimation(.smooth(duration: 0.24)) {
                            proxy.scrollTo(lyrics.lines[newIndex].id, anchor: .center)
                        }
                    }
                }
            } else if let text = lyrics?.untimedText, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 32)
                }
            } else {
                ContentUnavailableView("没有歌词", systemImage: "quote.bubble", description: Text("导入同名 LRC 文件，或使用带内嵌歌词的音频。"))
                    .foregroundStyle(.white)
            }
        }
    }

    private func schedulePlaybackFollowing() {
        let generation = browsingGeneration
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2.5))
            } catch {
                return
            }
            guard generation == browsingGeneration else { return }
            isBrowsingLyrics = false
        }
    }
}

private enum LyricTextAlignment: Equatable {
    case leading
    case center

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        }
    }
}

private struct SynchronizedLyricLineView: View {
    @EnvironmentObject private var player: AudioPlayerController
    let lyrics: TimedLyrics
    let line: TimedLyricLine
    let lineIndex: Int
    let isActive: Bool
    let translationEnabled: Bool
    let wordByWordEnabled: Bool
    let pseudoWordByWordEnabled: Bool
    let glowEnabled: Bool
    var alignment: LyricTextAlignment = .leading
    var fontSize: CGFloat = 28
    var primaryColor: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !player.isPlaying)) { _ in
            let progress = highlightProgress
            VStack(alignment: alignment.horizontalAlignment, spacing: translationSpacing) {
                lyricText(progress: progress)
                if translationEnabled, let translation = cleaned(line.translation) {
                    Text(translation)
                        .font(.system(size: max(fontSize * 0.56, 13), weight: .semibold))
                        .foregroundStyle(.white.opacity(isActive ? 0.68 : 0.36))
                        .multilineTextAlignment(alignment.textAlignment)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
            .opacity(isActive ? 1 : 0.45)
            .animation(.smooth(duration: 0.26), value: isActive)
        }
    }

    private func lyricText(progress: Double) -> some View {
        Text(line.text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white.opacity(isActive ? 0.30 : 0.58))
            .multilineTextAlignment(alignment.textAlignment)
            .overlay(alignment: .leading) {
                if isActive {
                    Text(line.text)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundStyle(primaryColor)
                        .multilineTextAlignment(alignment.textAlignment)
                        .mask(alignment: .leading) {
                            GeometryReader { geometry in
                                Rectangle()
                                    .frame(width: max(0, geometry.size.width * progress))
                            }
                        }
                        .shadow(color: glowEnabled ? primaryColor.opacity(0.72) : .clear, radius: glowEnabled ? 10 : 0)
                        .shadow(color: glowEnabled ? primaryColor.opacity(0.36) : .clear, radius: glowEnabled ? 22 : 0)
                }
            }
    }

    private var highlightProgress: Double {
        guard isActive else { return 0 }
        let playbackTime = player.isPlaying ? player.playbackPosition() : player.currentTime
        if wordByWordEnabled, line.isWordSynced {
            return lyrics.highlightProgress(in: lineIndex, at: playbackTime)
        }
        if pseudoWordByWordEnabled {
            return lyrics.lineProgress(in: lineIndex, at: playbackTime)
        }
        return 1
    }

    private var translationSpacing: CGFloat {
        translationEnabled && line.translation != nil ? 6 : 0
    }
}

private struct SkylineLyricsView: View {
    @EnvironmentObject private var player: AudioPlayerController
    let lyrics: TimedLyrics?
    let onExit: () -> Void

    @AppStorage("yubing.lyrics.translationEnabled") private var translationEnabled = true
    @AppStorage("yubing.lyrics.wordByWord") private var wordByWordEnabled = true
    @AppStorage("yubing.lyrics.pseudoWordByWord") private var pseudoWordByWordEnabled = true
    @AppStorage("yubing.lyrics.glowEnabled") private var glowEnabled = true
    @AppStorage("yubing.skyline.currentFontSize") private var currentFontSize = 54.0
    @AppStorage("yubing.skyline.nextFontSize") private var nextFontSize = 24.0
    @AppStorage("yubing.skyline.ambientFontSize") private var ambientFontSize = 44.0
    @AppStorage("yubing.skyline.ambientOpacity") private var ambientOpacity = 1.0
    @AppStorage("yubing.skyline.ambientDrift") private var ambientDrift = 1.0

    @State private var controlsAreVisible = true
    @State private var showsSettings = false
    @State private var ambientFieldIsDrifting = false

    private static let ambientSlots: [SkylineLyricSlot] = [
        .init(id: 0, x: 0.02, y: 0.14, scale: 1.24, blur: 1.8, opacity: 0.22, driftX: 12, driftY: -3),
        .init(id: 1, x: 0.10, y: 0.72, scale: 1.52, blur: 8.5, opacity: 0.25, driftX: 18, driftY: 4),
        .init(id: 2, x: 0.20, y: 0.32, scale: 1.08, blur: 1.2, opacity: 0.20, driftX: 10, driftY: -5),
        .init(id: 3, x: 0.30, y: 0.88, scale: 0.68, blur: 2.4, opacity: 0.17, driftX: 8, driftY: 2),
        .init(id: 4, x: 0.38, y: 0.60, scale: 0.58, blur: 0.8, opacity: 0.13, driftX: 6, driftY: -2),
        .init(id: 5, x: 0.47, y: 0.18, scale: 0.42, blur: 5.5, opacity: 0.12, driftX: 4, driftY: 2),
        .init(id: 6, x: 0.56, y: 0.82, scale: 0.42, blur: 4.0, opacity: 0.11, driftX: -4, driftY: -2),
        .init(id: 7, x: 0.66, y: 0.64, scale: 0.56, blur: 0.9, opacity: 0.13, driftX: -6, driftY: 3),
        .init(id: 8, x: 0.75, y: 0.35, scale: 0.78, blur: 1.6, opacity: 0.17, driftX: -8, driftY: -4),
        .init(id: 9, x: 0.84, y: 0.90, scale: 1.02, blur: 2.4, opacity: 0.20, driftX: -10, driftY: 3),
        .init(id: 10, x: 0.92, y: 0.70, scale: 1.46, blur: 8.0, opacity: 0.24, driftX: -16, driftY: -3),
        .init(id: 11, x: 0.98, y: 0.22, scale: 1.30, blur: 1.6, opacity: 0.21, driftX: -12, driftY: 4)
    ]

    var body: some View {
        GeometryReader { proxy in
            let lines = lyrics?.lines ?? []
            let activeIndex = activeLyricIndex(in: lines)
            let ambientTexts = ambientTexts(around: activeIndex, in: lines)

            ZStack {
                Color.black.opacity(0.92)
                LinearGradient(
                    colors: [.black.opacity(0.10), .clear, .black.opacity(0.58)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let activeIndex, lines.indices.contains(activeIndex) {
                    ambientField(texts: ambientTexts, activeIndex: activeIndex, size: proxy.size)
                    currentLyrics(lines: lines, activeIndex: activeIndex, size: proxy.size)
                } else {
                    ContentUnavailableView("暂无歌词", systemImage: "quote.bubble")
                        .foregroundStyle(.white)
                }

                if controlsAreVisible {
                    skylineControls
                        .transition(.opacity)
                }

                if showsSettings {
                    skylineSettings
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .clipped()
            .onTapGesture {
                withAnimation(.smooth(duration: 0.25)) {
                    controlsAreVisible.toggle()
                    if !controlsAreVisible { showsSettings = false }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                ambientFieldIsDrifting = true
            }
        }
    }

    private func ambientField(texts: [String], activeIndex: Int, size: CGSize) -> some View {
        ZStack {
            ForEach(Self.ambientSlots) { slot in
                let text = texts[slot.id]
                Text(verbatim: text)
                    .font(.system(size: CGFloat(ambientFontSize) * slot.scale, weight: .bold))
                    .foregroundStyle(.white.opacity(slot.opacity * ambientOpacity))
                    .blur(radius: slot.blur)
                    .position(
                        x: size.width * slot.x + driftOffset(slot.driftX),
                        y: size.height * slot.y + driftOffset(slot.driftY)
                    )
                    .id("\(activeIndex)-\(slot.id)-\(text)")
                    .animation(.easeInOut(duration: 1.2), value: text)
            }
        }
        .accessibilityHidden(true)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func currentLyrics(lines: [TimedLyricLine], activeIndex: Int, size: CGSize) -> some View {
        let line = lines[activeIndex]
        let nextLine = lines.indices.contains(activeIndex + 1) ? lines[activeIndex + 1] : nil

        return VStack(spacing: 14) {
            SynchronizedLyricLineView(
                lyrics: TimedLyrics(lines: lines, untimedText: nil),
                line: line,
                lineIndex: activeIndex,
                isActive: true,
                translationEnabled: translationEnabled,
                wordByWordEnabled: wordByWordEnabled,
                pseudoWordByWordEnabled: pseudoWordByWordEnabled,
                glowEnabled: glowEnabled,
                alignment: .center,
                fontSize: CGFloat(currentFontSize),
                primaryColor: .white
            )

            if let nextLine {
                Text(nextLine.text)
                    .font(.system(size: CGFloat(nextFontSize), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(width: size.width * 0.66)
        .position(x: size.width * 0.5, y: size.height * 0.5)
        .id(line.id)
        .animation(.smooth(duration: 0.45), value: line.id)
    }

    private var skylineControls: some View {
        VStack {
            HStack(spacing: 12) {
                Spacer()
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        showsSettings.toggle()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("调整天际歌词")

                Button(action: onExit) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回播放器")
            }
            Spacer()
        }
        .safeAreaPadding(12)
    }

    private var skylineSettings: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                SkylineSlider(systemImage: "textformat.size", value: $currentFontSize, range: 36...82, accessibilityLabel: "当前歌词大小")
                SkylineSlider(systemImage: "textformat", value: $nextFontSize, range: 16...38, accessibilityLabel: "后续歌词大小")
                SkylineSlider(systemImage: "text.word.spacing", value: $ambientFontSize, range: 24...64, accessibilityLabel: "环境文字大小")
                SkylineSlider(systemImage: "circle.lefthalf.filled", value: $ambientOpacity, range: 0.2...1.4, accessibilityLabel: "环境文字透明度")
                SkylineSlider(systemImage: "arrow.left.and.right", value: $ambientDrift, range: 0...2, accessibilityLabel: "环境文字动态幅度")
            }
            .padding(16)
            .frame(width: 280)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .padding(.trailing, 16)
        }
    }

    private func activeLyricIndex(in lines: [TimedLyricLine]) -> Int? {
        TimedLyrics(lines: lines, untimedText: nil).lineIndex(at: player.currentTime)
    }

    private func ambientTexts(around activeIndex: Int?, in lines: [TimedLyricLine]) -> [String] {
        guard let activeIndex, lines.indices.contains(activeIndex) else {
            return Array(repeating: "", count: Self.ambientSlots.count)
        }

        let neighborOffsets = [-3, 3, -2, 2, -1, 1]
        var fragments = neighborOffsets.flatMap { offset -> [String] in
            let index = activeIndex + offset
            guard lines.indices.contains(index) else { return [] }
            return lyricFragments(from: lines[index].text)
        }
        if fragments.isEmpty {
            fragments = lyricFragments(from: lines[activeIndex].text)
        }
        guard !fragments.isEmpty else {
            return Array(repeating: "", count: Self.ambientSlots.count)
        }
        return Self.ambientSlots.map { slot in
            fragments[(slot.id * 5 + activeIndex * 3) % fragments.count]
        }
    }

    private func lyricFragments(from text: String) -> [String] {
        let characters = Array(text.filter { !$0.isWhitespace && !$0.isPunctuation })
        guard !characters.isEmpty else { return [] }
        return stride(from: characters.startIndex, to: characters.endIndex, by: 2).map { startIndex in
            let endIndex = min(startIndex + 2, characters.endIndex)
            return String(characters[startIndex..<endIndex])
        }
    }

    private func driftOffset(_ offset: CGFloat) -> CGFloat {
        let direction: CGFloat = ambientFieldIsDrifting ? 1 : -1
        return offset * direction * CGFloat(ambientDrift)
    }
}

private struct SkylineSlider: View {
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 28)
            Slider(value: $value, in: range)
        }
        .foregroundStyle(.white)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SkylineLyricSlot: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double
    let driftX: CGFloat
    let driftY: CGFloat
}

private struct NowPlayingQueuePage: View {
    @EnvironmentObject private var player: AudioPlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("接下来播放")
                    .font(.title2.bold())
                Spacer()
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(player.isShuffleEnabled ? 0.24 : 0.1), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isShuffleEnabled ? "关闭随机播放" : "开启随机播放")

                Button { player.cycleRepeatMode() } label: {
                    Image(systemName: player.repeatMode.symbol)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(player.repeatMode == .off ? 0.1 : 0.24), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.repeatMode.title)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, item in
                        Button {
                            player.playFromQueue(at: index)
                        } label: {
                            LocalTrackRow(
                                item: item,
                                showsArtwork: true,
                                foregroundStyle: AnyShapeStyle(.white),
                                secondaryStyle: AnyShapeStyle(.white.opacity(0.58))
                            )
                        }
                        .buttonStyle(.plain)

                        if index < player.queue.count - 1 {
                            Divider()
                                .overlay(.white.opacity(0.12))
                                .padding(.leading, 62)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .overlay {
                if player.queue.isEmpty {
                    ContentUnavailableView("播放队列为空", systemImage: "list.bullet")
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

private struct NowPlayingBackground: View {
    let artworkData: Data?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if let image = platformAudioImage(data: artworkData) {
                    platformAudioImageView(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .scaleEffect(1.35)
                        .blur(radius: 42)
                        .saturation(1.18)
                }

                Color.black.opacity(0.18)
                LinearGradient(
                    colors: [.black.opacity(0.04), .black.opacity(0.14), .black.opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct AudioArtwork: View {
    let data: Data?
    let fallbackSymbol: String

    var body: some View {
        ZStack {
            Rectangle().fill(.secondary.opacity(0.14))
            if let image = platformAudioImage(data: data) {
                platformAudioImageView(image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

#if os(iOS)
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

private func cleaned(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func trackIndex(_ value: String?) -> Int {
    Int(value?.split(separator: "/").first ?? "") ?? Int.max
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
