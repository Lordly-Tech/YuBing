import Foundation
import SwiftUI

struct NowPlayingBackground: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    let artworkData: Data?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                colorScheme.nowPlayingBase

                if artworkData != nil {
                    AudioArtwork(data: artworkData)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.35)
                        .blur(radius: CGFloat(settings.playerBackgroundBlur))
                        .saturation(settings.playerBackgroundSaturation)
                }

                colorScheme == .dark
                    ? Color.black.opacity(0.16)
                    : Color.white.opacity(0.34)

                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            .black.opacity(0.04),
                            .black.opacity(0.12),
                            .black.opacity(0.48),
                        ]
                        : [
                            .white.opacity(0.12),
                            .white.opacity(0.34),
                            .white.opacity(0.68),
                        ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension ColorScheme {
    var nowPlayingPrimary: Color { self == .dark ? .white : .black }

    var nowPlayingSecondary: Color { nowPlayingPrimary.opacity(0.62) }

    var nowPlayingTertiary: Color { nowPlayingPrimary.opacity(0.48) }

    var nowPlayingSurface: Color {
        nowPlayingPrimary.opacity(self == .dark ? 0.12 : 0.08)
    }

    var nowPlayingBase: Color {
        self == .dark
            ? .black
            : Color(red: 0.95, green: 0.95, blue: 0.96)
    }
}
