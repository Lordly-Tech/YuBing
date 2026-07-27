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
                min(proxy.size.width, proxy.size.height - 104)
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
                            .foregroundStyle(.secondary)
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
    @State private var showsLyricsEffects = false

    var body: some View {
        HStack(spacing: 9) {
            Button {
                store.toggleFavorite(song.item)
            } label: {
                actionIcon(
                    store.isFavorite(song.item) ? "star.fill" : "star",
                    isActive: store.isFavorite(song.item)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isFavorite(song.item) ? "取消收藏" : "收藏")

            Menu {
                Button {
                    onToggleDetails()
                } label: {
                    Label(
                        isShowingDetails ? "返回封面" : "歌曲资料",
                        systemImage: isShowingDetails ? "rectangle.portrait" : "info.circle"
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
                    Label("歌词动效", systemImage: "sparkles")
                }

                ShareLink(item: song.item.url) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            } label: {
                actionIcon("ellipsis")
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("更多")
        }
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

    private func actionIcon(_ systemImage: String, isActive: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(isActive ? 0.98 : 0.86))
            .frame(width: 42, height: 42)
            .background(Color.primary.opacity(isActive ? 0.2 : 0.13), in: .circle)
            .contentShape(.circle)
    }
}
