import SwiftUI

struct NowPlayingArtworkPage: View {
    @EnvironmentObject private var player: AudioPlayerController
    @Environment(AppSettings.self) private var settings

    let song: NowPlayingSong
    @Binding var showsSleepTimer: Bool
    let artworkNamespace: Namespace.ID
    let onShowDetails: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = max(
                170,
                min(proxy.size.width - 28, proxy.size.height - 104)
            )

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                ArtworkImage(data: song.artworkData, cornerRadius: 10)
                    .frame(width: artworkSize, height: artworkSize)
                    .scaleEffect(player.isPlaying || !settings.shrinksPausedArtwork ? 1 : 0.9)
                    .shadow(color: .black.opacity(0.24), radius: 22, y: 12)
                    .animation(.smooth(duration: 0.45), value: player.isPlaying)
                    .contentShape(.rect)
                    .onTapGesture(perform: onShowDetails)
                    .accessibilityElement()
                    .accessibilityLabel("查看歌曲资料")
                    .accessibilityHint("轻点切换到歌曲资料")
                    .accessibilityAction {
                        onShowDetails()
                    }

                Spacer(minLength: 22)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)

                        Text(song.artistText)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    NowPlayingSongActions(
                        song: song,
                        showsSleepTimer: $showsSleepTimer,
                        isShowingDetails: false,
                        onToggleDetails: onShowDetails
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// Favourite plus overflow menu shown next to the track title.
///
/// The now playing view recomputes `song` every time playback progress is
/// republished (twice a second while a track plays). The action row only depends
/// on the track identity, so the real content is wrapped in an equatable view:
/// the closure stored in `onToggleDetails` can never compare equal, which would
/// otherwise force SwiftUI to rebuild the menu label on every tick and make the
/// icons flash.
struct NowPlayingSongActions: View {
    let song: NowPlayingSong
    @Binding var showsSleepTimer: Bool
    let isShowingDetails: Bool
    let onToggleDetails: () -> Void

    var body: some View {
        NowPlayingSongActionsContent(
            song: song,
            showsSleepTimer: $showsSleepTimer,
            isShowingDetails: isShowingDetails,
            onToggleDetails: onToggleDetails
        )
        .equatable()
    }
}

private struct NowPlayingSongActionsContent: View, Equatable {
    @EnvironmentObject private var store: LibraryStore

    let song: NowPlayingSong
    @Binding var showsSleepTimer: Bool
    let isShowingDetails: Bool
    let onToggleDetails: () -> Void

    @State private var addToPlaylistItem: LibraryItem?
    @State private var showsLyricsEffects = false

    static func == (
        lhs: NowPlayingSongActionsContent,
        rhs: NowPlayingSongActionsContent
    ) -> Bool {
        lhs.song.item == rhs.song.item
            && lhs.isShowingDetails == rhs.isShowingDetails
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.toggleFavorite(song.item)
            } label: {
                Image(systemName: store.isFavorite(song.item) ? "star.fill" : "star")
                    .font(.title3.weight(.medium))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.13), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isFavorite(song.item) ? "取消收藏" : "收藏")

            Menu {
                Button {
                    onToggleDetails()
                } label: {
                    Label(
                        isShowingDetails ? "返回封面" : "歌曲资料",
                        systemImage: isShowingDetails ? "music.note" : "info.circle"
                    )
                }

                Button {
                    addToPlaylistItem = song.item
                } label: {
                    Label("添加到歌单", systemImage: "text.badge.plus")
                }

                Button {
                    showsSleepTimer = true
                } label: {
                    Label("定时关闭", systemImage: "timer")
                }

                Button {
                    showsLyricsEffects = true
                } label: {
                    Label("歌词动效", systemImage: "wand.and.stars")
                }

                ShareLink(item: song.item.url) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.13), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .menuOrder(.fixed)
            .accessibilityLabel("更多")
        }
        // The enclosing page animates its own transitions; without this the
        // inherited animation is re-applied to the button styles on every
        // republish.
        .animation(nil, value: song.item)
        .sheet(item: $addToPlaylistItem) { item in
            AddToLocalPlaylistSheet(item: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsLyricsEffects) {
            NavigationStack {
                LyricsEffectsSettingsView()
            }
        }
    }
}
