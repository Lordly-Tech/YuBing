import Foundation
import SwiftUI

struct NowPlayingBackground: View {
    @Environment(AppSettings.self) private var settings

    let artworkData: Data?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if artworkData != nil {
                    AudioArtwork(data: artworkData)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.35)
                        .blur(radius: CGFloat(settings.playerBackgroundBlur))
                        .saturation(settings.playerBackgroundSaturation)
                }

                Color.black.opacity(0.16)

                LinearGradient(
                    colors: [
                        .black.opacity(0.04),
                        .black.opacity(0.12),
                        .black.opacity(0.48),
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
