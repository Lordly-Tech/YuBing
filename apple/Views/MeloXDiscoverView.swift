import SwiftUI

// Discovery layout adapted from youshen2/MeloX (GPL-3.0).

struct MeloXArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    var aspectRatio: CGFloat = 1

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            case .failure:
                placeholder
            case .empty:
                ZStack {
                    placeholder
                    ProgressView().controlSize(.small)
                }
            @unknown default:
                placeholder
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }
}

private enum MeloXDiscoveryPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}

struct MeloXDiscoverView: View {
    @EnvironmentObject private var service: MeloXMusicService
    @State private var category = "推荐歌单"
    @State private var playlists: [MeloXPlaylist] = []
    @State private var playlistsByCategory: [String: [MeloXPlaylist]] = [:]
    @State private var newAlbums: [MeloXAlbum] = []
    @State private var phase: MeloXDiscoveryPhase = .loading
    @State private var reloadToken = 0

    private let categories = [
        "推荐歌单", "排行榜", "精品歌单", "全部", "华语", "欧美", "流行", "摇滚", "民谣", "电子"
    ]

    private let columns = [
        GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                categoryPicker

                if !newAlbums.isEmpty {
                    albumShelf
                }

                content
            }
            .frame(maxWidth: YuBingMetrics.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("发现")
        .refreshable { await load(force: true) }
        .task(id: MeloXDiscoverLoadRequest(category: category, token: reloadToken)) {
            await load()
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(categories, id: \.self) { value in
                    Button(shortTitle(for: value)) {
                        select(value)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(value == category ? .pink : Color.secondary.opacity(0.14))
                    .foregroundStyle(
                        value == category
                            ? AnyShapeStyle(Color.white)
                            : AnyShapeStyle(Color.primary)
                    )
                    .accessibilityAddTraits(value == category ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var albumShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新碟上架")
                .font(.title2.bold())

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(newAlbums) { album in
                        NavigationLink {
                            MeloXAlbumDetailView(initialAlbum: album)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                MeloXArtworkView(url: album.artworkURL)
                                    .frame(width: 146, height: 146)
                                Text(album.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(album.artistText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 146, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var content: some View {
        if playlists.isEmpty {
            switch phase {
            case .loading:
                ProgressView("正在发现好音乐")
                    .frame(maxWidth: .infinity, minHeight: 280)
            case .failed(let message):
                ContentUnavailableView {
                    Label("无法载入发现内容", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") { reloadToken += 1 }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            case .loaded:
                ContentUnavailableView("暂无歌单", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity, minHeight: 280)
            }
        } else {
            if let featured = playlists.first {
                NavigationLink {
                    MeloXPlaylistDetailView(initialPlaylist: featured)
                } label: {
                    featuredPlaylist(featured)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(collectionTitle).font(.title2.bold())
                    Spacer()
                    Text("\(playlists.count) 个歌单")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(playlists.dropFirst()) { playlist in
                        NavigationLink {
                            MeloXPlaylistDetailView(initialPlaylist: playlist)
                        } label: {
                            playlistCard(playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func featuredPlaylist(_ playlist: MeloXPlaylist) -> some View {
        ZStack(alignment: .bottomLeading) {
            MeloXArtworkView(url: playlist.artworkURL, aspectRatio: 1.55)
                .frame(maxWidth: .infinity)

            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(featuredBadge)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(playlist.name)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let subtitle = playlist.updateFrequency ?? playlist.creator?.nickname {
                        Text(subtitle).lineLimit(1)
                    }
                    if playlist.playCount > 0 {
                        Label(meloXPlayCountText(playlist.playCount), systemImage: "play.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.76))
            }
            .padding(18)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func playlistCard(_ playlist: MeloXPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MeloXArtworkView(url: playlist.artworkURL)
                .overlay(alignment: .topTrailing) {
                    if playlist.playCount > 0 {
                        Label(meloXPlayCountText(playlist.playCount), systemImage: "play.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding(7)
                    }
                }
            Text(playlist.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(playlist.updateFrequency ?? playlist.creator?.nickname ?? "\(playlist.trackCount) 首歌曲")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private var featuredBadge: String {
        switch category {
        case "推荐歌单": "今日推荐"
        case "排行榜": "热门榜单"
        case "精品歌单": "编辑精选"
        default: category
        }
    }

    private var collectionTitle: String {
        switch category {
        case "推荐歌单": "更多推荐"
        case "排行榜": "全部榜单"
        case "精品歌单": "更多精品"
        case "全部": "热门歌单"
        default: "\(category)歌单"
        }
    }

    private func shortTitle(for value: String) -> String {
        switch value {
        case "推荐歌单": "推荐"
        case "精品歌单": "精品"
        default: value
        }
    }

    private func select(_ value: String) {
        guard value != category else { return }
        category = value
        if let cached = playlistsByCategory[value] {
            playlists = cached
            phase = .loaded
        } else {
            playlists = []
            phase = .loading
        }
    }

    private func load(force: Bool = false) async {
        if !force, let cached = playlistsByCategory[category] {
            playlists = cached
            phase = .loaded
            return
        }

        let requestedCategory = category
        phase = .loading
        do {
            let loadedPlaylists = try await service.playlists(category: requestedCategory)
            let loadedAlbums: [MeloXAlbum]
            if newAlbums.isEmpty {
                loadedAlbums = (try? await service.newAlbums()) ?? []
            } else {
                loadedAlbums = newAlbums
            }
            try Task.checkCancellation()
            playlistsByCategory[requestedCategory] = loadedPlaylists
            if newAlbums.isEmpty { newAlbums = loadedAlbums }
            guard category == requestedCategory else { return }
            playlists = loadedPlaylists
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard category == requestedCategory else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct MeloXDiscoverLoadRequest: Hashable {
    let category: String
    let token: Int
}

func meloXPlayCountText(_ count: Int) -> String {
    switch count {
    case 100_000_000...:
        return "\(meloXFormattedCount(Double(count) / 100_000_000))亿"
    case 10_000...:
        return "\(meloXFormattedCount(Double(count) / 10_000))万"
    default:
        return "\(count)"
    }
}

private func meloXFormattedCount(_ value: Double) -> String {
    if value >= 10 || value.rounded() == value {
        return String(Int(value.rounded()))
    }
    return value.formatted(.number.precision(.fractionLength(1)))
}
