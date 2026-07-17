import QuickLookThumbnailing
import SwiftUI

#if os(macOS)
import AppKit
private typealias YuBingPlatformImage = NSImage
#else
import UIKit
private typealias YuBingPlatformImage = UIImage
#endif

struct FileThumbnailView: View {
    let item: LibraryItem
    var size: CGSize = CGSize(width: 160, height: 160)

    @State private var image: YuBingPlatformImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(item.kind.tint.opacity(0.12))

            if let image {
                platformImage(image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: min(size.width, size.height) * 0.28, weight: .medium))
                    .foregroundStyle(item.kind.tint)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .clipped()
        .task(id: item.url) {
            guard !item.isDirectory else { return }
            let scale: CGFloat
            #if os(macOS)
            scale = NSScreen.main?.backingScaleFactor ?? 2
            #else
            scale = UIScreen.main.scale
            #endif
            let request = QLThumbnailGenerator.Request(
                fileAt: item.url,
                size: size,
                scale: scale,
                representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                guard let thumbnail else { return }
                Task { @MainActor in
                    #if os(macOS)
                    image = thumbnail.nsImage
                    #else
                    image = thumbnail.uiImage
                    #endif
                }
            }
        }
    }

    @ViewBuilder
    private func platformImage(_ image: YuBingPlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: image)
        #else
        Image(uiImage: image)
        #endif
    }
}

