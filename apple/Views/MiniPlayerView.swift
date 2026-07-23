import SwiftUI

struct MiniPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject private var player: AudioPlayerController

    let onExpand: () -> Void
    var isInline = false

    var body: some View {
        if let item = player.currentItem {
            HStack(spacing: isInline ? 8 : 10) {
                Button(action: onExpand) {
                    HStack(spacing: isInline ? 8 : 10) {
                        AudioArtwork(
                            data: player.currentMetadata.artworkData,
                            fallbackSymbol: "music.note"
                        )
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(player.currentMetadata.title ?? item.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if !isInline {
                                Text(player.currentMetadata.artist ?? "本地音乐")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if player.isPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 36, height: 36)
                } else {
                    Button {
                        player.togglePlayback()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .symbolEffect(
                                        .replace.downUp.wholeSymbol,
                                        options: .speed(1.25)
                                    )
                            )
                            .animation(
                                accessibilityReduceMotion
                                    ? nil
                                    : .snappy(duration: 0.28, extraBounce: 0),
                                value: player.isPlaying
                            )
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                }

                if !isInline {
                    Button {
                        player.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下一首")
                }
            }
            .padding(.horizontal, isInline ? 8 : 12)
            .padding(.vertical, isInline ? 3 : 6)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .simultaneousGesture(trackSwipeGesture)
            .accessibilityAction(named: "上一首") {
                player.playPrevious()
            }
            .accessibilityAction(named: "下一首") {
                player.playNext()
            }
        }
    }

    private var artworkSize: CGFloat {
        isInline ? 30 : 40
    }

    private var trackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 {
                    player.playNext()
                } else {
                    player.playPrevious()
                }
            }
    }
}

#if os(iOS)
@available(iOS 26.0, *)
struct MeloXMiniPlayerAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let onExpand: () -> Void

    var body: some View {
        MiniPlayerView(onExpand: onExpand, isInline: placement == .inline)
    }
}
#endif
