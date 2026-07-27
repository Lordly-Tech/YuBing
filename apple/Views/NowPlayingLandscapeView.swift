import SwiftUI

struct NowPlayingLandscapeView: View {
    @Environment(AudioPlayerController.self) private var player

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
            let isCompactHeight = proxy.size.height < 480
            let reservedControlHeight: CGFloat = isCompactHeight ? 194 : 220
            let artworkSide = min(
                max(proxy.size.height - reservedControlHeight, 132),
                proxy.size.width * 0.34,
                430
            )

            HStack(spacing: spacing) {
                albumPage(side: artworkSide, isCompactHeight: isCompactHeight)
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

    private func albumPage(side: CGFloat, isCompactHeight: Bool) -> some View {
        VStack(spacing: isCompactHeight ? 10 : 16) {
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

            playbackControls(width: side, isCompactHeight: isCompactHeight)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playbackControls(width: CGFloat, isCompactHeight: Bool) -> some View {
        VStack(spacing: isCompactHeight ? 0 : 6) {
            NowPlayingProgressControl(song: song)

            NowPlayingTransportControls(isCompact: isCompactHeight)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: max(width, 240))
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
