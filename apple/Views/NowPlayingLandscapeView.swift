import SwiftUI

struct NowPlayingLandscapeView: View {
    @EnvironmentObject private var player: AudioPlayerController

    @Binding var showsSleepTimer: Bool

    let song: NowPlayingSong
    let lyrics: [LyricLine]
    let lyricError: String?
    let highlightedLyricID: LyricLine.ID?
    let artworkNamespace: Namespace.ID
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let spacing = min(max(proxy.size.width * 0.035, 24), 44)
            let artworkSide = min(
                proxy.size.height * 0.68,
                proxy.size.width * 0.34,
                430
            )

            HStack(spacing: spacing) {
                albumPage(side: artworkSide)
                    .frame(width: min(proxy.size.width * 0.4, 470))

                lyricsPage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 1_180, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .safeAreaPadding(.vertical, 12)
        .contentShape(.rect)
        .simultaneousGesture(dismissalDragGesture)
        .accessibilityAction(named: "收起播放器") {
            onDismiss()
        }
    }

    private func albumPage(side: CGFloat) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            ArtworkImage(data: song.artworkData, cornerRadius: 12)
                .frame(width: side, height: side)
                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)

            VStack(spacing: 4) {
                Text(song.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Text(song.artistText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(maxWidth: side)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lyricsPage: some View {
        NowPlayingLyricsPage(
            song: song,
            lyrics: lyrics,
            untimedText: player.currentMetadata.lyrics?.untimedText,
            errorMessage: lyricError,
            highlightedLyricID: highlightedLyricID,
            presentation: .landscape,
            isInterfaceHidden: true,
            artworkNamespace: artworkNamespace,
            showsSleepTimer: $showsSleepTimer
        )
    }

    private var dismissalDragGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let verticalDistance = value.translation.height
                let predictedDistance = value.predictedEndTranslation.height
                guard verticalDistance > 90,
                      predictedDistance > 150,
                      abs(verticalDistance) > abs(value.translation.width) * 1.25 else {
                    return
                }
                onDismiss()
            }
    }
}
