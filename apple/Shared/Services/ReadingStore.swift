import Combine
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ReadingStore: ObservableObject {
    @Published private(set) var records: [String: ReadingRecord] = [:]
    @Published private(set) var coverRevision = 0

    private let fileManager = FileManager.default
    private let stateURL: URL
    private let coverDirectory: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("YuBing", isDirectory: true)
        stateURL = support.appendingPathComponent("ReadingState.json")
        coverDirectory = support.appendingPathComponent("Book Covers", isDirectory: true)

        try? fileManager.createDirectory(at: coverDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: stateURL),
           let decoded = try? JSONDecoder().decode([String: ReadingRecord].self, from: data) {
            records = decoded
        }
    }

    func record(for item: LibraryItem) -> ReadingRecord {
        records[item.relativePath] ?? ReadingRecord()
    }

    func updateProgress(for item: LibraryItem, chapterIndex: Int, progress: Double) {
        var value = record(for: item)
        value.chapterIndex = max(chapterIndex, 0)
        value.chapterProgress = min(max(progress, 0), 1)
        value.updatedAt = .now
        records[item.relativePath] = value
        persist()
    }

    func addReadingTime(_ duration: TimeInterval, for item: LibraryItem) {
        guard duration.isFinite, duration > 0 else { return }
        var value = record(for: item)
        value.localReadingTime += min(duration, 90)
        value.updatedAt = .now
        records[item.relativePath] = value
        persist()
    }

    @discardableResult
    func addBookmark(
        for item: LibraryItem,
        chapterIndex: Int,
        chapterTitle: String,
        chapterProgress: Double,
        fileOffset: Int
    ) -> ReaderBookmark {
        var value = record(for: item)
        let defaultName = chapterProgress < 0.02
            ? chapterTitle
            : "\(chapterTitle) · \(Int(chapterProgress * 100))%"
        let bookmark = ReaderBookmark(
            id: UUID(),
            name: defaultName,
            chapterIndex: chapterIndex,
            chapterProgress: min(max(chapterProgress, 0), 1),
            fileOffset: max(fileOffset, 0),
            createdAt: .now
        )
        value.bookmarks.append(bookmark)
        value.updatedAt = .now
        records[item.relativePath] = value
        persist()
        return bookmark
    }

    func renameBookmark(_ bookmark: ReaderBookmark, to name: String, for item: LibraryItem) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var value = record(for: item)
        guard let index = value.bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        value.bookmarks[index].name = trimmed
        value.updatedAt = .now
        records[item.relativePath] = value
        persist()
    }

    func deleteBookmark(_ bookmark: ReaderBookmark, for item: LibraryItem) {
        var value = record(for: item)
        value.bookmarks.removeAll { $0.id == bookmark.id }
        value.updatedAt = .now
        records[item.relativePath] = value
        persist()
    }

    func mergeWatchStats(_ stats: [WatchReadingStatPayload]) {
        var didChange = false
        for stat in stats {
            var value = records[stat.bookID] ?? ReadingRecord()
            if stat.readingTime > value.watchReadingTime {
                value.watchReadingTime = stat.readingTime
                didChange = true
            }
            if stat.updatedAt > value.updatedAt {
                value.chapterIndex = max(stat.chapterIndex, 0)
                value.chapterProgress = min(max(stat.chapterProgress, 0), 1)
                value.updatedAt = stat.updatedAt
                didChange = true
            }
            records[stat.bookID] = value
        }
        if didChange { persist() }
    }

    func hasCover(for item: LibraryItem) -> Bool {
        fileManager.fileExists(atPath: coverURL(for: item).path)
    }

    func coverData(for item: LibraryItem, discoverIfNeeded: Bool = true) async -> Data? {
        let destination = coverURL(for: item)
        if let data = try? Data(contentsOf: destination) { return data }
        guard discoverIfNeeded, item.fileExtension == "epub" else { return nil }

        let sourceURL = item.url
        let discovered = try? await Task.detached(priority: .utility) {
            try BookParser.parse(url: sourceURL).coverData
        }.value
        guard let discovered else { return nil }
        return saveCover(discovered, for: item)
    }

    @discardableResult
    func saveCover(_ data: Data, for item: LibraryItem) -> Data? {
        guard let normalized = Self.normalizedCoverData(data) else { return nil }
        do {
            try normalized.write(to: coverURL(for: item), options: .atomic)
            coverRevision += 1
            return normalized
        } catch {
            return nil
        }
    }

    private func coverURL(for item: LibraryItem) -> URL {
        let digest = SHA256.hash(data: Data(item.relativePath.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return coverDirectory.appendingPathComponent("\(digest).jpg")
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(records).write(to: stateURL, options: .atomic)
        } catch {
            // Reading can continue even if a transient disk write fails.
        }
    }

    private nonisolated static func normalizedCoverData(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary
              ),
              let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
