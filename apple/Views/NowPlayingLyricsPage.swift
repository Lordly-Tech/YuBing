import Foundation
import SwiftUI

enum NowPlayingLyricsPresentation: Equatable {
    case portrait
    case landscape
}

struct NowPlayingLyricsPage: View {
    let song: NowPlayingSong
    let lyrics: [LyricLine]
    let untimedText: String?
    let errorMessage: String?
    let highlightedLyricID: LyricLine.ID?
    let presentation: NowPlayingLyricsPresentation
    let isInterfaceHidden: Bool
    let bottomOverlayHeight: CGFloat?
    let artworkNamespace: Namespace.ID
    let isArtworkGeometrySource: Bool
    @Binding var showsSleepTimer: Bool
    let onToggleInterface: (() -> Void)?
    let onShowDetails: (() -> Void)?

    init(
        song: NowPlayingSong,
        lyrics: [LyricLine],
        untimedText: String? = nil,
        errorMessage: String?,
        highlightedLyricID: LyricLine.ID?,
        presentation: NowPlayingLyricsPresentation = .portrait,
        isInterfaceHidden: Bool = false,
        bottomOverlayHeight: CGFloat? = nil,
        artworkNamespace: Namespace.ID,
        isArtworkGeometrySource: Bool = true,
        showsSleepTimer: Binding<Bool>,
        onToggleInterface: (() -> Void)? = nil,
        onShowDetails: (() -> Void)? = nil
    ) {
        self.song = song
        self.lyrics = lyrics
        self.untimedText = untimedText
        self.errorMessage = errorMessage
        self.highlightedLyricID = highlightedLyricID
        self.presentation = presentation
        self.isInterfaceHidden = isInterfaceHidden
        self.bottomOverlayHeight = bottomOverlayHeight
        self.artworkNamespace = artworkNamespace
        self.isArtworkGeometrySource = isArtworkGeometrySource
        _showsSleepTimer = showsSleepTimer
        self.onToggleInterface = onToggleInterface
        self.onShowDetails = onShowDetails
    }

    var body: some View {
        VStack(spacing: presentation == .portrait ? 18 : 0) {
            if presentation == .portrait {
                songHeader
            }

            if lyrics.isEmpty, let untimedText = normalizedUntimedText {
                ScrollView {
                    Text(verbatim: untimedText)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                        .padding(.bottom, appleMusicBottomOverlayHeight)
                }
                .scrollIndicators(.hidden)
                .contentShape(.rect)
                .onTapGesture {
                    onToggleInterface?()
                }
            } else {
                AppleMusicLyricsView(
                    lyrics: lyrics,
                    errorMessage: errorMessage,
                    highlightedLyricID: highlightedLyricID,
                    isInterfaceHidden: isInterfaceHidden,
                    bottomOverlayHeight: appleMusicBottomOverlayHeight,
                    onToggleInterface: onToggleInterface
                )
            }
        }
        .padding(.bottom, presentation == .portrait ? 12 : 0)
        .resolvedLyricsRefreshRate()
    }

    private var songHeader: some View {
        HStack(spacing: 12) {
            ArtworkImage(data: song.artworkData, cornerRadius: 10)
                .matchedGeometryEffect(
                    id: song.id,
                    in: artworkNamespace,
                    properties: .frame,
                    isSource: isArtworkGeometrySource
                )
                .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(song.artistText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NowPlayingSongActions(
                song: song,
                showsSleepTimer: $showsSleepTimer,
                isShowingDetails: false,
                onToggleDetails: { onShowDetails?() }
            )
        }
    }

    private var appleMusicBottomOverlayHeight: CGFloat {
        if let bottomOverlayHeight { return max(bottomOverlayHeight, 0) }
        switch presentation {
        case .portrait:
            226
        case .landscape:
            0
        }
    }

    private var normalizedUntimedText: String? {
        guard let untimedText else { return nil }
        let value = untimedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
