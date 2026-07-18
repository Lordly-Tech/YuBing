import Foundation

struct WatchBookChapter: Codable, Hashable, Identifiable, Sendable {
    let index: Int
    let title: String
    let text: String
    let startOffset: Int
    let length: Int

    var id: Int { index }
}

struct WatchBookPackage: Codable, Sendable {
    static let fileExtension = "ybbook"

    let version: Int
    let sourceID: String
    let title: String
    let originalFileName: String
    let format: String
    let chapters: [WatchBookChapter]
    let totalLength: Int
    let coverData: Data?
    let initialChapterIndex: Int
    let initialChapterProgress: Double
}

struct WatchReaderBookmark: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let chapterIndex: Int
    let chapterProgress: Double
    let createdAt: Date
}

struct WatchReaderRecord: Codable, Hashable, Sendable {
    var chapterIndex: Int = 0
    var chapterProgress: Double = 0
    var readingTime: TimeInterval = 0
    var bookmarks: [WatchReaderBookmark] = []
    var updatedAt: Date = .now
}

struct WatchReadingStatPayload: Codable, Hashable, Sendable {
    let bookID: String
    let readingTime: TimeInterval
    let chapterIndex: Int
    let chapterProgress: Double
    let updatedAt: Date
}

enum WatchBookLoader {
    static func load(_ item: WatchLibraryItem) throws -> WatchBookPackage {
        if item.fileExtension == WatchBookPackage.fileExtension {
            let data = try Data(contentsOf: item.url)
            return try PropertyListDecoder().decode(WatchBookPackage.self, from: data)
        }

        var encoding = String.Encoding.utf8
        let text = try String(contentsOf: item.url, usedEncoding: &encoding)
        let length = max((text as NSString).length, 1)
        return WatchBookPackage(
            version: 1,
            sourceID: item.relativePath,
            title: item.displayName,
            originalFileName: item.name,
            format: item.fileExtension,
            chapters: [
                WatchBookChapter(index: 0, title: "全文", text: text, startOffset: 0, length: length)
            ],
            totalLength: length,
            coverData: nil,
            initialChapterIndex: 0,
            initialChapterProgress: 0
        )
    }
}

extension TimeInterval {
    var watchReadingDuration: String {
        let minutes = max(Int(self / 60), 0)
        if minutes < 1 { return "< 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) 小时" : "\(hours) 小时 \(remainder) 分钟"
    }
}
