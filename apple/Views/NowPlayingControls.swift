#if os(iOS)
import AVKit
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

            HStack(spacing: 12) {
                Text(formatMusicTime(player.progress))
                    .frame(minWidth: 40, alignment: .leading)

                Spacer(minLength: 0)

                Text("−\(formatMusicTime(max(player.duration - player.progress, 0)))")
                    .frame(minWidth: 40, alignment: .trailing)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
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
        .tint(Color.primary)
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

    var isCompact = false

    private var skipSymbolSize: CGFloat { isCompact ? 26 : 34 }
    private var playSymbolSize: CGFloat { isCompact ? 38 : 48 }
    private var buttonSide: CGFloat { isCompact ? 52 : 64 }
    private var rowHeight: CGFloat { isCompact ? 62 : 82 }

    var body: some View {
        HStack {
            Spacer()

            Button {
                player.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: skipSymbolSize, weight: .medium))
                    .frame(width: buttonSide, height: buttonSide)
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
                            .controlSize(isCompact ? .regular : .large)
                            .tint(Color.primary)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: playSymbolSize, weight: .medium))
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
                .frame(width: buttonSide, height: buttonSide)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Spacer()

            Button {
                player.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: skipSymbolSize, weight: .medium))
                    .frame(width: buttonSide, height: buttonSide)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一首")

            Spacer()
        }
        .frame(height: rowHeight)
    }
}

struct NowPlayingVolumeControl: View {
    @EnvironmentObject private var player: AudioPlayerController
    @State private var isAdjustingVolume = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11, weight: .semibold))

            AppleMusicVolumeSlider(
                value: Binding(
                    get: { player.volume },
                    set: { player.setVolume($0) }
                ),
                isAdjusting: $isAdjustingVolume
            )

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Color.primary.opacity(isAdjustingVolume ? 0.86 : 0.62))
        .frame(height: 38)
        .animation(.easeOut(duration: 0.16), value: isAdjustingVolume)
    }
}

private struct AppleMusicVolumeSlider: View {
    @Binding var value: Double
    @Binding var isAdjusting: Bool

    private let trackHeight: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let clampedValue = min(max(value, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.primary.opacity(0.82))
                    .frame(width: width * clampedValue, height: trackHeight)

                Circle()
                    .fill(Color.primary)
                    .frame(
                        width: isAdjusting ? 17 : 13,
                        height: isAdjusting ? 17 : 13
                    )
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(
                        x: min(
                            max(width * clampedValue - (isAdjusting ? 8.5 : 6.5), 0),
                            width - (isAdjusting ? 17 : 13)
                        )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isAdjusting { isAdjusting = true }
                        value = min(max(gesture.location.x / width, 0), 1)
                    }
                    .onEnded { gesture in
                        value = min(max(gesture.location.x / width, 0), 1)
                        withAnimation(.easeOut(duration: 0.16)) {
                            isAdjusting = false
                        }
                    }
            )
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel("播放器音量")
        .accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + 0.05, 1)
            case .decrement:
                value = max(value - 0.05, 0)
            @unknown default:
                break
            }
        }
        .animation(.easeOut(duration: 0.16), value: isAdjusting)
    }
}

struct NowPlayingPageSelector: View {
    @Binding var page: NowPlayingPage

    var body: some View {
        HStack(spacing: 0) {
            pageButton(
                page: .lyrics,
                systemImage: "quote.bubble",
                accessibilityLabel: "歌词"
            )

            #if os(iOS)
            AirPlayRouteButton()
                .frame(width: 48, height: 44)
                .accessibilityLabel("AirPlay")
                .frame(maxWidth: .infinity)
            #endif

            pageButton(
                page: .queue,
                systemImage: "list.bullet",
                accessibilityLabel: "播放队列"
            )
        }
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
                .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(Color.primary.opacity(isSelected ? 0.95 : 0.62))
                .frame(width: 48, height: 44)
                .background(Color.primary.opacity(isSelected ? 0.18 : 0), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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
private struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView(frame: .zero)
        routePicker.prioritizesVideoDevices = false
        routePicker.tintColor = .label
        routePicker.activeTintColor = .systemPink
        return routePicker
    }

    func updateUIView(_ routePicker: AVRoutePickerView, context: Context) {
        routePicker.prioritizesVideoDevices = false
        routePicker.tintColor = .label
        routePicker.activeTintColor = .systemPink
    }
}
#endif
