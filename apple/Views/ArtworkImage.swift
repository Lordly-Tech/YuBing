import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ArtworkImage: View {
    let data: Data?
    var cornerRadius: CGFloat = 8
    var fallbackSymbol = "music.note"
    var aspectRatio: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        GeometryReader { proxy in
            AudioArtwork(data: data, fallbackSymbol: fallbackSymbol)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .transition(.opacity)
                .animation(
                    accessibilityReduceMotion ? nil : .easeOut(duration: 0.18),
                    value: data
                )
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}

struct AudioArtwork: View {
    let data: Data?
    var fallbackSymbol = "music.note"

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .overlay {
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
            }
        }
        .clipped()
    }

    private var image: Image? {
        guard let data else { return nil }
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}
