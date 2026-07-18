import Foundation

struct BookChapter: Codable, Hashable, Identifiable, Sendable {
    let index: Int
    let title: String
    let text: String
    let startOffset: Int
    let length: Int

    var id: Int { index }
}

struct ParsedBook: Sendable {
    let title: String
    let format: String
    let chapters: [BookChapter]
    let totalLength: Int
    let coverData: Data?
}

struct ReaderBookmark: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let chapterIndex: Int
    let chapterProgress: Double
    let fileOffset: Int
    let createdAt: Date
}

struct ReadingRecord: Codable, Hashable, Sendable {
    var chapterIndex: Int = 0
    var chapterProgress: Double = 0
    var localReadingTime: TimeInterval = 0
    var watchReadingTime: TimeInterval = 0
    var bookmarks: [ReaderBookmark] = []
    var updatedAt: Date = .now

    var totalReadingTime: TimeInterval {
        localReadingTime + watchReadingTime
    }
}

struct WatchBookPackage: Codable, Sendable {
    static let fileExtension = "ybbook"

    let version: Int
    let sourceID: String
    let title: String
    let originalFileName: String
    let format: String
    let chapters: [BookChapter]
    let totalLength: Int
    let coverData: Data?
    let initialChapterIndex: Int
    let initialChapterProgress: Double
}

struct WatchReadingStatPayload: Codable, Hashable, Sendable {
    let bookID: String
    let readingTime: TimeInterval
    let chapterIndex: Int
    let chapterProgress: Double
    let updatedAt: Date
}

extension TimeInterval {
    var formattedReadingDuration: String {
        let totalMinutes = max(Int(self / 60), 0)
        if totalMinutes < 1 { return "不到 1 分钟" }
        if totalMinutes < 60 { return "\(totalMinutes) 分钟" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分钟"
    }
}
