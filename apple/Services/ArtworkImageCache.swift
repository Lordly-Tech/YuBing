import CoreGraphics
import Foundation
import ImageIO

/// Decodes and caches downsampled artwork so list rows never decode full-resolution
/// images during scrolling. Keys combine a cheap content fingerprint with a size bucket.
final class ArtworkImageCache: @unchecked Sendable {
    static let shared = ArtworkImageCache()

    private final class Entry {
        let image: CGImage

        init(_ image: CGImage) {
            self.image = image
        }
    }

    /// Assumed upper bound for display scale. Overshooting only costs a slightly
    /// larger thumbnail; reading UIScreen here would require main-actor isolation.
    private static let assumedScale: CGFloat = 3

    private let cache = NSCache<NSString, Entry>()

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 48 * 1_024 * 1_024
    }

    func key(for data: Data, side: CGFloat) -> String {
        "\(Self.fingerprint(data))@\(Self.bucket(for: side))"
    }

    func cachedImage(forKey key: String) -> CGImage? {
        cache.object(forKey: key as NSString)?.image
    }

    func image(for data: Data, side: CGFloat) -> CGImage? {
        let cacheKey = key(for: data, side: side)
        if let existing = cachedImage(forKey: cacheKey) { return existing }
        guard let image = Self.decode(data, maximumPixelSize: Self.bucket(for: side)) else {
            return nil
        }
        cache.setObject(
            Entry(image),
            forKey: cacheKey as NSString,
            cost: max(image.bytesPerRow * image.height, 1)
        )
        return image
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    static func bucket(for side: CGFloat) -> Int {
        let pixels = Int((max(side, 1) * assumedScale).rounded(.up))
        for candidate in [64, 128, 256, 512, 1_024, 2_048] where pixels <= candidate {
            return candidate
        }
        return 2_048
    }

    private static func decode(_ data: Data, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return thumbnail
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Samples byte windows spread across the payload instead of only the edges, so
    /// two different covers of equal length cannot collide onto one cache entry.
    private static func fingerprint(_ data: Data) -> String {
        var hasher = Hasher()
        hasher.combine(data.count)
        guard !data.isEmpty else { return "empty" }

        let windowLength = 32
        let windowCount = 8
        let stride = max(data.count / windowCount, 1)
        var offset = 0
        while offset < data.count {
            let end = min(offset + windowLength, data.count)
            for index in offset..<end {
                hasher.combine(data[data.startIndex + index])
            }
            offset += stride
        }
        for byte in data.suffix(windowLength) { hasher.combine(byte) }
        return String(UInt(bitPattern: hasher.finalize()), radix: 16)
    }
}
