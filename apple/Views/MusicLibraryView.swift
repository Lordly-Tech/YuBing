import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// Album and playlist presentation adapted from youshen2/MeloX (GPL-3.0).

struct MusicAlbum: Identifiable {
    let id: String
    let title: String
    let artist: String
    let year: String?
    let genre: String?
    let artworkData: Data?
    let tracks: [LibraryItem]

    var detailText: String {
        [artist, year, genre]
            .compactMap(musicCleaned)
            .joined(separator: " · ")
    }
}
struct MusicLibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @State private var query = ""
    @State private var showsCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var addToPlaylistItem: LibraryItem?
    @State private var deletingTrack: LibraryItem?

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
                  let albumTitle = musicCleaned(metadata.album) else { continue }
            let artist = musicCleaned(metadata.albumArtist)
                ?? musicCleaned(metadata.artist)
                ?? AppLocalization.string("未知艺人")
            grouped["\(albumTitle)|\(artist)", default: []].append(track)
        }

        return grouped.compactMap { key, tracks in
            guard let first = tracks.first,
                  let metadata = player.metadataByPath[first.relativePath],
                  let title = musicCleaned(metadata.album) else { return nil }
            return MusicAlbum(
                id: key,
                title: title,
                artist: musicCleaned(metadata.albumArtist)
                    ?? musicCleaned(metadata.artist)
                    ?? AppLocalization.string("未知艺人"),
                year: musicCleaned(metadata.year),
                genre: musicCleaned(metadata.genre),
                artworkData: metadata.artworkData,
                tracks: tracks.sorted(byMusicMetadataFrom: player.metadataByPath)
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Group {
            if audioTracks.isEmpty {
                ContentUnavailablePanel(
                    title: "还没有音乐",
                    message: "支持 MP3、FLAC、WAV、AAC、AIFF、M4A、DSD、DSF、APE、OGG、Opus 与 WMA。请从首页添加音乐。",
                    symbol: "music.note.list",
                    action: nil
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        libraryHeader
                        playlistSection
                        if !albums.isEmpty { albumSection }
                        trackSection
                    }
                    .frame(maxWidth: YuBingMetrics.contentMaxWidth, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                    .padding(.bottom, 84)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("音乐")
        .searchable(text: $query, prompt: "搜索歌曲、艺人或专辑")
        .task(id: audioTracks.map(\.relativePath).joined(separator: "|")) {
            for track in audioTracks where player.metadataByPath[track.relativePath] == nil {
                _ = await player.loadMetadata(for: track)
            }
        }
        #if os(iOS)
        .task { _ = await SystemMusicLibraryAccess.requestAuthorizationIfNeeded() }
        #endif
        .sheet(item: $addToPlaylistItem) { item in
            AddToLocalPlaylistSheet(item: item)
        }
        .confirmationDialog(
            deleteTrackDialogTitle,
            isPresented: deleteTrackPresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let deletingTrack { store.delete(deletingTrack) }
                deletingTrack = nil
            }
            Button("取消", role: .cancel) { deletingTrack = nil }
        } message: {
            Text("此操作会从本地资料库中删除歌曲文件，并自动从歌单中移除。")
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

    private var deleteTrackPresented: Binding<Bool> {
        Binding(
            get: { deletingTrack != nil },
            set: { if !$0 { deletingTrack = nil } }
        )
    }

    private var deleteTrackDialogTitle: String {
        guard let deletingTrack else { return "删除歌曲？" }
        return "删除“\(deletingTrack.displayName)”？"
    }

    private var libraryHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("本地音乐").font(.largeTitle.bold())
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
                .tint(.pink)
            }
        }
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MusicSectionTitle(text: "歌单")
                Button { showsCreatePlaylist = true } label: {
                    Image(systemName: "plus").frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("新建歌单")
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(store.orderedMusicPlaylists) { playlist in
                        NavigationLink {
                            LocalPlaylistDetailView(playlist: playlist)
                        } label: {
                            LocalPlaylistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MusicSectionTitle(text: "专辑")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink {
                            LocalAlbumDetailView(album: album)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                AudioArtwork(data: album.artworkData, fallbackSymbol: "square.stack.fill")
                                    .frame(width: 156, height: 156)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(album.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
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
            }
            .scrollIndicators(.hidden)
        }
    }

    private var trackSection: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            MusicSectionTitle(text: "歌曲").padding(.bottom, 4)
            ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, item in
                Button {
                    player.play(item, in: filteredTracks)
                    store.markOpened(item)
                } label: {
                    LocalTrackRow(item: item, index: index, showsArtwork: true)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    LocalTrackContextActions(
                        item: item,
                        addToPlaylistItem: $addToPlaylistItem,
                        onDelete: { deletingTrack = item }
                    )
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deletingTrack = item
                    } label: {
                        Label("删除歌曲", systemImage: "trash")
                    }
                }
                if index < filteredTracks.count - 1 {
                    Divider().padding(.leading, 62)
                }
            }
        }
    }

}

struct MusicSectionTitle: View {
    let text: String

    var body: some View {
        Text(AppLocalization.string(text))
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LocalTrackRow: View {
    @EnvironmentObject private var player: AudioPlayerController
    let item: LibraryItem
    var index: Int?
    var showsArtwork = false

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
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(metadata?.title ?? item.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(
                        player.currentItem == item
                            ? AnyShapeStyle(Color.pink)
                            : AnyShapeStyle(Color.primary)
                    )
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.pink)
                    .accessibilityLabel("当前歌曲")
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var detailText: String {
        let values = [metadata?.artist, metadata?.album].compactMap(musicCleaned)
        if !values.isEmpty { return values.joined(separator: " · ") }
        return musicCleaned(metadata?.qualityDescription)
            ?? "\(item.fileExtension.uppercased()) · \(item.byteCount.formattedFileSize)"
    }
}

private struct LocalPlaylistCard: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let playlist: MusicPlaylist

    private var tracks: [LibraryItem] { store.tracks(in: playlist) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            playlistArtwork
            .frame(width: 156, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if store.isFavorite(playlist) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(7)
                        .background(.thinMaterial, in: Circle())
                        .padding(7)
                }
            }

            Text(store.displayName(for: playlist))
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(tracks.count) 首歌曲").font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 156, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button { store.toggleFavorite(playlist) } label: {
                Label(
                    store.isFavorite(playlist) ? "取消收藏歌单" : "收藏歌单",
                    systemImage: store.isFavorite(playlist) ? "star.slash" : "star"
                )
            }
        }
    }
    @ViewBuilder
    private var playlistArtwork: some View {
        if store.isLikedPlaylist(playlist), playlist.artworkData == nil {
            Rectangle()
                .fill(.pink.gradient)
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 58, weight: .semibold))
                        .foregroundStyle(.white)
                }
        } else {
            AudioArtwork(
                data: playlist.artworkData ?? tracks.compactMap { player.metadataByPath[$0.relativePath]?.artworkData }.first,
                fallbackSymbol: store.isLikedPlaylist(playlist) ? "heart.fill" : "music.note.list"
            )
        }
    }
}

private struct LocalPlaylistDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @Environment(\.dismiss) private var dismiss
    let playlist: MusicPlaylist
    @State private var addToPlaylistItem: LibraryItem?
    @State private var renameText = ""
    @State private var showsRename = false
    @State private var showsEditDetails = false
    @State private var deletingTrack: LibraryItem?
    @State private var showsDeletePlaylistConfirmation = false

    private var currentPlaylist: MusicPlaylist {
        store.musicPlaylists.first(where: { $0.id == playlist.id }) ?? playlist
    }

    private var tracks: [LibraryItem] { store.tracks(in: currentPlaylist) }

    var body: some View {
        List {
            Section {
                HStack {
                    LocalPlaylistArtworkView(playlist: currentPlaylist, side: 72)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.displayName(for: currentPlaylist)).font(.title2.bold())
                        Text("\(tracks.count) 首歌曲").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        guard let first = tracks.first else { return }
                        player.play(first, in: tracks)
                    } label: {
                        Image(systemName: "play.fill").frame(width: 38, height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tracks.isEmpty)
                }
                .padding(.vertical, 8)
            }

            Section("歌曲") {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, item in
                    Button { player.play(item, in: tracks) } label: {
                        LocalTrackRow(item: item, index: index)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.remove(item, from: currentPlaylist)
                        } label: {
                            Label("从歌单移除", systemImage: "minus.circle")
                        }
                        Button { store.toggleFavorite(item) } label: {
                            Label(
                                store.isFavorite(item) ? "取消收藏" : "收藏",
                                systemImage: store.isFavorite(item) ? "star.slash" : "star"
                            )
                        }
                        Button { addToPlaylistItem = item } label: {
                            Label("添加到歌单", systemImage: "text.badge.plus")
                        }
                        ShareLink(item: item.url) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        Divider()
                        Button(role: .destructive) {
                            deletingTrack = item
                        } label: {
                            Label("删除歌曲", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deletingTrack = item
                        } label: {
                            Label("删除歌曲", systemImage: "trash")
                        }
                        Button(role: .destructive) {
                            store.remove(item, from: currentPlaylist)
                        } label: {
                            Label("从歌单移除", systemImage: "minus.circle")
                        }
                    }
                }
            }
        }
        .navigationTitle(store.displayName(for: currentPlaylist))
        .toolbar {
            ToolbarItem {
                Menu {
                    Button { store.toggleFavorite(currentPlaylist) } label: {
                        Label(
                            store.isFavorite(currentPlaylist) ? "取消收藏歌单" : "收藏歌单",
                            systemImage: store.isFavorite(currentPlaylist) ? "star.slash" : "star"
                        )
                    }
                    Button {
                        showsEditDetails = true
                    } label: {
                        Label("编辑歌单资料", systemImage: "slider.horizontal.3")
                    }
                    if !store.isLikedPlaylist(currentPlaylist) {
                        Button {
                            renameText = currentPlaylist.name
                            showsRename = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showsDeletePlaylistConfirmation = true
                        } label: {
                            Label("删除歌单", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(item: $addToPlaylistItem) { AddToLocalPlaylistSheet(item: $0) }
        .sheet(isPresented: $showsEditDetails) {
            PlaylistDetailsEditor(playlist: currentPlaylist)
        }
        .confirmationDialog(
            deleteTrackDialogTitle,
            isPresented: deleteTrackPresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let deletingTrack { store.delete(deletingTrack) }
                deletingTrack = nil
            }
            Button("取消", role: .cancel) { deletingTrack = nil }
        } message: {
            Text("此操作会从本地资料库中删除歌曲文件，并自动从歌单中移除。")
        }
        .confirmationDialog(
            deletePlaylistDialogTitle,
            isPresented: $showsDeletePlaylistConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除歌单", role: .destructive) {
                store.delete(currentPlaylist)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅删除歌单列表，不会删除歌单内的歌曲文件。")
        }
        .alert("重命名歌单", isPresented: $showsRename) {
            TextField("歌单名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { store.rename(currentPlaylist, to: renameText) }
        }
    }

    private var deleteTrackPresented: Binding<Bool> {
        Binding(
            get: { deletingTrack != nil },
            set: { if !$0 { deletingTrack = nil } }
        )
    }

    private var deleteTrackDialogTitle: String {
        guard let deletingTrack else { return "删除歌曲？" }
        return "删除“\(deletingTrack.displayName)”？"
    }

    private var deletePlaylistDialogTitle: String {
        "删除歌单“\(store.displayName(for: currentPlaylist))”？"
    }
}

private struct LocalPlaylistArtworkView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let playlist: MusicPlaylist
    let side: CGFloat

    private var tracks: [LibraryItem] { store.tracks(in: playlist) }

    var body: some View {
        Group {
            if store.isLikedPlaylist(playlist), playlist.artworkData == nil {
                Rectangle()
                    .fill(.pink.gradient)
                    .overlay {
                        Image(systemName: "heart.fill")
                            .font(.system(size: side * 0.38, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            } else {
                AudioArtwork(
                    data: playlist.artworkData ?? tracks.compactMap { player.metadataByPath[$0.relativePath]?.artworkData }.first,
                    fallbackSymbol: store.isLikedPlaylist(playlist) ? "heart.fill" : "music.note.list"
                )
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

}

private struct PlaylistDetailsEditor: View {    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let playlist: MusicPlaylist
    @State private var name: String
    @State private var isImporterPresented = false
    @State private var photoSelection: PhotosPickerItem?

    init(playlist: MusicPlaylist) {
        self.playlist = playlist
        _name = State(initialValue: playlist.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("歌单名称") {
                    TextField("名称", text: $name)
                }
                Section("歌单图片") {
                    HStack(spacing: 14) {
                        LocalPlaylistArtworkView(playlist: playlist, side: 88)
                        VStack(alignment: .leading, spacing: 10) {
                            Button { isImporterPresented = true } label: {
                                Label("从文件选择图片", systemImage: "folder")
                            }
                            PhotosPicker(selection: $photoSelection, matching: .images) {
                                Label("从相册选择图片", systemImage: "photo")
                            }
                            if playlist.artworkData != nil {
                                Button(role: .destructive) {
                                    store.updateArtwork(nil, for: playlist)
                                } label: {
                                    Label("移除图片", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("编辑歌单资料")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.rename(playlist, to: name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { store.updateArtwork(data, for: playlist) }
            }
            .onChange(of: photoSelection) { _, selection in
                guard let selection else { return }
                Task { @MainActor in
                    if let data = try? await selection.loadTransferable(type: Data.self) {
                        store.updateArtwork(data, for: playlist)
                    }
                    photoSelection = nil
                }
            }
        }
    }
}

struct LocalTrackContextActions: View {
    @EnvironmentObject private var store: LibraryStore
    let item: LibraryItem
    @Binding var addToPlaylistItem: LibraryItem?
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Button { store.toggleFavorite(item) } label: {
            Label(
                store.isFavorite(item) ? "取消收藏" : "收藏",
                systemImage: store.isFavorite(item) ? "star.slash" : "star"
            )
        }
        Button { addToPlaylistItem = item } label: {
            Label("添加到歌单", systemImage: "text.badge.plus")
        }
        ShareLink(item: item.url) {
            Label("分享", systemImage: "square.and.arrow.up")
        }
        if let onDelete {
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("删除歌曲", systemImage: "trash")
            }
        }
    }
}

struct AddToLocalPlaylistSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.orderedMusicPlaylists) { playlist in
                    Button {
                        store.add(item, to: playlist)
                        dismiss()
                    } label: {
                        HStack {
                            Label(
                                store.displayName(for: playlist),
                                systemImage: store.isLikedPlaylist(playlist) ? "heart.fill" : "music.note.list"
                            )
                            Spacer()
                            if store.contains(item, in: playlist) {
                                Image(systemName: "checkmark").foregroundStyle(.pink)
                            }
                        }
                    }
                    .disabled(store.contains(item, in: playlist))
                }

                Section("新建歌单") {
                    TextField("歌单名称", text: $newName)
                    Button("创建并添加") {
                        store.createMusicPlaylist(named: newName, initialTrack: item)
                        dismiss()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("添加到歌单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

func musicCleaned(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func musicTrackIndex(_ value: String?) -> Int {
    guard let value else { return Int.max }
    return Int(value.split(separator: "/").first ?? "") ?? Int.max
}

private extension Array where Element == LibraryItem {
    func sorted(byMusicMetadataFrom metadata: [String: EmbeddedAudioMetadata]) -> [LibraryItem] {
        sorted { lhs, rhs in
            let left = metadata[lhs.relativePath]
            let right = metadata[rhs.relativePath]
            let leftDisc = musicTrackIndex(left?.discNumber)
            let rightDisc = musicTrackIndex(right?.discNumber)
            if leftDisc != rightDisc { return leftDisc < rightDisc }
            let leftTrack = musicTrackIndex(left?.trackNumber)
            let rightTrack = musicTrackIndex(right?.trackNumber)
            if leftTrack != rightTrack { return leftTrack < rightTrack }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
