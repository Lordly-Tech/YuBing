import Foundation
import SwiftUI

struct AlbumDetailContent: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController

    let album: MusicAlbum
    let tracks: [LibraryItem]
    let palette: ArtworkDetailPalette
    let blurredBackdropImage: CGImage?
    let searchQuery: String
    @Binding var addToPlaylistItem: LibraryItem?

    var body: some View {
        ZStack {
            MusicCollectionArtworkBackdrop(
                blurredArtworkImage: blurredBackdropImage,
                palette: palette
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    StandardMusicCollectionDetailHero(
                        artworkData: album.artworkData,
                        title: album.title,
                        subtitle: album.artist,
                        metadataText: metadataText,
                        tracks: album.tracks,
                        isSaved: isSaved,
                        onToggleSaved: toggleSaved
                    )

                    MusicCollectionTrackContent(
                        tracks: filteredTracks,
                        queue: album.tracks,
                        addToPlaylistItem: $addToPlaylistItem
                    )
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.primary)
    }

    private var metadataText: String {
        var components = ["专辑"]
        if let year = musicCleaned(album.year) {
            components.append("\(year)年")
        }
        components.append("\(tracks.count) 首歌曲")
        return components.joined(separator: " · ")
    }

    private var filteredTracks: [LibraryItem] {
        let keywords = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keywords.isEmpty else { return tracks }
        return tracks.filter { item in
            let metadata = player.metadataByPath[item.relativePath]
            return [
                item.displayName,
                metadata?.title,
                metadata?.artist,
                metadata?.album,
            ]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(keywords) }
        }
    }

    private var isSaved: Bool {
        !tracks.isEmpty && tracks.allSatisfy { store.isFavorite($0) }
    }

    private func toggleSaved() {
        let targetState = !isSaved
        for track in tracks where store.isFavorite(track) != targetState {
            store.toggleFavorite(track)
        }
    }
}

struct MusicCollectionTrackContent: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController

    let tracks: [LibraryItem]
    let queue: [LibraryItem]
    @Binding var addToPlaylistItem: LibraryItem?

    var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView("暂无歌曲", systemImage: "music.note")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 4) {
                            Button {
                                if player.currentItem == track {
                                    player.togglePlayback()
                                } else {
                                    player.play(track, in: queue)
                                }
                                store.markOpened(track)
                            } label: {
                                LocalTrackRow(
                                    item: track,
                                    index: queue.firstIndex(of: track)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                LocalTrackContextActions(
                                    item: track,
                                    addToPlaylistItem: $addToPlaylistItem
                                )
                            }

                            Menu {
                                Button {
                                    store.toggleFavorite(track)
                                } label: {
                                    Label(
                                        store.isFavorite(track) ? "取消收藏" : "收藏歌曲",
                                        systemImage: store.isFavorite(track) ? "star.slash" : "star"
                                    )
                                }

                                Button {
                                    addToPlaylistItem = track
                                } label: {
                                    Label("添加到歌单", systemImage: "text.badge.plus")
                                }

                                ShareLink(item: track.url) {
                                    Label("分享", systemImage: "square.and.arrow.up")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 42, height: 44)
                                    .contentShape(.rect)
                            }
                            .accessibilityLabel("\(track.displayName)的更多操作")
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 8)
                        .background(
                            player.currentItem == track
                                ? Color.primary.opacity(0.10)
                                : .clear
                        )

                        if index < tracks.count - 1 {
                            Divider()
                                .overlay(Color.primary.opacity(0.12))
                                .padding(.leading, 58)
                                .padding(.trailing, 20)
                        }
                    }
                }
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: tracks)
    }
}

struct StandardMusicCollectionDetailHero: View {
    @EnvironmentObject private var player: AudioPlayerController
    @Environment(\.colorScheme) private var colorScheme

    let artworkData: Data?
    let title: String
    let subtitle: String
    let metadataText: String
    let tracks: [LibraryItem]
    let isSaved: Bool
    let onToggleSaved: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ArtworkImage(
                data: artworkData,
                cornerRadius: 12,
                fallbackSymbol: "square.stack.fill"
            )
            .containerRelativeFrame(.horizontal) { width, _ in
                min(width * 0.68, 300)
            }
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)

            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 24)
                .padding(.horizontal, 24)

            Text(subtitle)
                .font(.title3)
                .lineLimit(1)
                .padding(.top, 8)

            Text(metadataText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 7)

            primaryActions
                .padding(.top, 17)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.bottom, 22)
    }

    private var primaryActions: some View {
        AdaptiveGlassGroup {
            HStack(spacing: 14) {
                Button {
                    guard let first = tracks.shuffled().first else { return }
                    player.play(first, in: tracks)
                    if !player.isShuffleEnabled {
                        player.toggleShuffle()
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.title2.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .adaptiveGlassButton()
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(tracks.isEmpty)
                .accessibilityLabel("随机播放")

                Button {
                    guard let first = tracks.first else { return }
                    player.play(first, in: tracks)
                } label: {
                    Label("播放", systemImage: "play.fill")
                        .font(.title3.weight(.bold))
                        .frame(minWidth: 116)
                }
                .adaptiveGlassButton(prominent: true)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(colorScheme == .dark ? .white : .black)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .disabled(tracks.isEmpty)

                Button(action: onToggleSaved) {
                    Image(systemName: isSaved ? "checkmark" : "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .adaptiveGlassButton()
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel(isSaved ? "取消收藏" : "收藏")
            }
        }
    }
}

struct MusicCollectionArtworkBackdrop: View {
    let blurredArtworkImage: CGImage?
    let palette: ArtworkDetailPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                palette.backgroundColor

                if let blurredArtworkImage {
                    Image(decorative: blurredArtworkImage, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(0.22)
                        .transition(.opacity)
                }

                LinearGradient(
                    colors: backdropOverlayColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var backdropOverlayColors: [Color] {
        if palette.prefersDarkAppearance {
            return [
                .black.opacity(0.08),
                .black.opacity(0.24),
                .black.opacity(0.40),
            ]
        }
        return [
            .white.opacity(0.06),
            .white.opacity(0.16),
            .white.opacity(0.30),
        ]
    }
}
