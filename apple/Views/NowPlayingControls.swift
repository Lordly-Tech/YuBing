#if os(iOS)
import AVKit
import MediaPlayer
import UIKit
#endif
import Foundation
import SwiftUI

struct NowPlayingProgressControl: View {
    @EnvironmentObject private var player: AudioPlayerController

    let song: NowPlayingSong

    var body: some View {
        VStack(spacing: 2) {
            progressSlider

            HStack {
                Text(formatMusicTime(player.progress))

                Spacer()

                Text("−\(formatMusicTime(max(player.duration - player.progress, 0)))")
            }
            .overlay {
                Text(
                    song.metadata.qualityDescription.isEmpty
                        ? song.item.fileExtension.uppercased()
                        : song.metadata.qualityDescription
                )
                    .lineLimit(1)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
        .frame(height: 52)
    }

    @ViewBuilder
    private var progressSlider: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            slider
                .sliderThumbVisibility(.hidden)
        } else {
            slider
        }
        #else
        slider
        #endif
    }

    private var slider: some View {
        Slider(
            value: Binding(
                get: { min(player.progress, progressMaximum) },
                set: { player.seek(to: $0) }
            ),
            in: 0...progressMaximum
        )
        .tint(.white)
        .accessibilityLabel("播放进度")
        .accessibilityValue(
            "已播放 \(formatMusicTime(player.progress))，总时长 \(formatMusicTime(progressMaximum))"
        )
    }

    private var progressMaximum: TimeInterval {
        max(player.duration, TimeInterval(song.durationMS) / 1_000, 1)
    }
}

struct NowPlayingTransportControls: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject private var player: AudioPlayerController

    var body: some View {
        HStack {
            Spacer()

            Button {
                player.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: 64, height: 64)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一首")

            Spacer()

            Button {
                player.togglePlayback()
            } label: {
                Group {
                    if player.isPreparing {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 48, weight: .medium))
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
                    }
                }
                .frame(width: 64, height: 64)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Spacer()

            Button {
                player.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: 64, height: 64)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一首")

            Spacer()
        }
        .frame(height: 82)
    }
}

struct NowPlayingVolumeControl: View {
    @EnvironmentObject private var player: AudioPlayerController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption2)

            volumeSlider

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.62))
        .frame(height: 42)
    }

    @ViewBuilder
    private var volumeSlider: some View {
        #if os(iOS)
        SystemVolumeSlider()
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .layoutPriority(1)
            .accessibilityLabel("系统音量")
        #else
        Slider(
            value: Binding(
                get: { player.volume },
                set: { player.setVolume($0) }
            ),
            in: 0...1
        )
        .tint(.white)
        .accessibilityLabel("播放器音量")
        #endif
    }
}

struct NowPlayingPageSelector: View {
    @Binding var page: NowPlayingPage

    var body: some View {
        HStack {
            Spacer()

            pageButton(
                page: .lyrics,
                systemImage: "quote.bubble",
                accessibilityLabel: "歌词"
            )

            Spacer()

            #if os(iOS)
            AirPlayRouteButton()
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay")

            Spacer()
            #endif

            pageButton(
                page: .queue,
                systemImage: "list.bullet",
                accessibilityLabel: "播放队列"
            )

            Spacer()
        }
        .foregroundStyle(.white.opacity(0.72))
        .frame(height: 50)
    }

    private func pageButton(
        page destination: NowPlayingPage,
        systemImage: String,
        accessibilityLabel: String
    ) -> some View {
        let isSelected = page == destination

        return Button {
            withAnimation(.smooth(duration: 0.4)) {
                page = isSelected ? .artwork : destination
            }
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.white.opacity(isSelected ? 0.2 : 0), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

func formatMusicTime(_ value: TimeInterval) -> String {
    guard value.isFinite else { return "0:00" }
    let seconds = max(0, Int(value))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

#if os(iOS)
private struct SystemVolumeSlider: UIViewRepresentable {
    final class Coordinator {
        let volumeView = MPVolumeView(
            frame: CGRect(x: 0, y: 0, width: 200, height: 32)
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: 200, height: 32)
        )
        container.backgroundColor = .clear

        let volumeView = context.coordinator.volumeView
        volumeView.showsVolumeSlider = true
        volumeView.showsRouteButton = false
        volumeView.tintColor = .white
        volumeView.frame = container.bounds
        volumeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(volumeView)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        let volumeView = context.coordinator.volumeView
        volumeView.showsVolumeSlider = true
        volumeView.showsRouteButton = false
        volumeView.tintColor = .white
        volumeView.frame = container.bounds
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? 200,
            height: proposal.height ?? 32
        )
    }
}

private struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView(frame: .zero)
        routePicker.prioritizesVideoDevices = false
        routePicker.tintColor = .white
        routePicker.activeTintColor = .systemPink
        return routePicker
    }

    func updateUIView(_ routePicker: AVRoutePickerView, context: Context) {
        routePicker.prioritizesVideoDevices = false
        routePicker.tintColor = .white
        routePicker.activeTintColor = .systemPink
    }
}
#endif
