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
    @EnvironmentObject private var readingStore: ReadingStore
    @EnvironmentObject private var player: AudioPlayerController
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
            } else if item.kind == .novel {
                GeneratedBookCoverView(title: item.displayName)
            } else {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: min(size.width, size.height) * 0.28, weight: .medium))
                    .foregroundStyle(item.kind.tint)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .clipped()
        .task(id: "\(item.url.path)-\(readingStore.coverRevision)") {
            guard !item.isDirectory else { return }
            if item.kind == .music {
                let metadata = await player.loadMetadata(for: item)
                if let artworkData = metadata.artworkData,
                   let artwork = platformImage(data: artworkData) {
                    image = artwork
                }
                return
            }
            if (item.kind == .novel || item.kind == .comic),
               let data = await readingStore.coverData(for: item),
               let cover = platformImage(data: data) {
                image = cover
                return
            }
            if item.kind == .novel { return }
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

    private func platformImage(data: Data) -> YuBingPlatformImage? {
        #if os(macOS)
        NSImage(data: data)
        #else
        UIImage(data: data)
        #endif
    }
}

private struct GeneratedBookCoverView: View {
    let title: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.92),
                    Color.cyan.opacity(0.68),
                    Color.indigo.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.88))
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.62)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                Spacer(minLength: 0)
                Text("鱼饼")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.vertical, 16)
        }
    }
}
