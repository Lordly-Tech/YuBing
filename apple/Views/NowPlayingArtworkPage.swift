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
                    .matchedGeometryEffect(
                        id: song.id,
                        in: artworkNamespace,
                        properties: .frame
                    )
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

struct NowPlayingSongActions: View {
    @EnvironmentObject private var store: LibraryStore

    let song: NowPlayingSong
    @Binding var showsSleepTimer: Bool
    let isShowingDetails: Bool
    let onToggleDetails: () -> Void

    @State private var addToPlaylistItem: LibraryItem?

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
                Button(action: onToggleDetails) {
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
            .accessibilityLabel("更多")
        }
        .sheet(item: $addToPlaylistItem) { item in
            AddToLocalPlaylistSheet(item: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
