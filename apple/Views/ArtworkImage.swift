import CoreGraphics
import SwiftUI

struct ArtworkImage: View {
    let data: Data?
    var cornerRadius: CGFloat = 8
    var fallbackSymbol = "music.note"
    var aspectRatio: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        AudioArtwork(data: data, fallbackSymbol: fallbackSymbol)
            .transition(.opacity)
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.18),
                value: data
            )
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}

struct AudioArtwork: View {
    let data: Data?
    var fallbackSymbol = "music.note"

    @State private var decoded: CGImage?

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            let request = ArtworkDecodeRequest(data: data, side: side)

            Group {
                if let image = resolvedImage(for: request) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: request.cacheKey) {
                await decodeIfNeeded(request)
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .overlay {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
    }

    /// Prefers an already-cached decode so freshly recycled list rows render on the
    /// first frame instead of flashing the placeholder while the task starts.
    private func resolvedImage(for request: ArtworkDecodeRequest) -> CGImage? {
        guard let cacheKey = request.cacheKey else { return nil }
        if let cached = ArtworkImageCache.shared.cachedImage(forKey: cacheKey) {
            return cached
        }
        return decoded
    }

    private func decodeIfNeeded(_ request: ArtworkDecodeRequest) async {
        guard let payload = request.data,
              let cacheKey = request.cacheKey else {
            decoded = nil
            return
        }
        if let cached = ArtworkImageCache.shared.cachedImage(forKey: cacheKey) {
            decoded = cached
            return
        }
        let side = request.side
        let image = await Task.detached(priority: .userInitiated) {
            ArtworkImageCache.shared.image(for: payload, side: side)
        }.value
        guard !Task.isCancelled else { return }
        decoded = image
    }
}

/// Identity for a decode job. `cacheKey` folds the content fingerprint and the size
/// bucket into one string, so `task(id:)` compares a short key instead of multi-megabyte
/// `Data`, and resizing within a single bucket does not retrigger a decode.
private struct ArtworkDecodeRequest {
    let data: Data?
    let side: CGFloat
    let cacheKey: String?

    init(data: Data?, side: CGFloat) {
        self.data = data
        self.side = side
        if let data, side > 0 {
            cacheKey = ArtworkImageCache.shared.key(for: data, side: side)
        } else {
            cacheKey = nil
        }
    }
}
