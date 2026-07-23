import SwiftUI

struct NowPlayingLandscapeView: View {
    @EnvironmentObject private var player: AudioPlayerController

    @Binding var showsSleepTimer: Bool

    let song: NowPlayingSong
    let lyrics: [LyricLine]
    let lyricError: String?
    let highlightedLyricID: LyricLine.ID?
    let artworkNamespace: Namespace.ID

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .safeAreaPadding(.vertical, 8)
    }
}
