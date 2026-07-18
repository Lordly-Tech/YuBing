import Foundation

enum WatchLibraryKind: String, Codable, CaseIterable {
    case novel
    case comic
    case music
    case photo
    case folder
    case file

    var title: String {
        switch self {
        case .novel: "小说"
        case .comic: "漫画"
        case .music: "音乐"
        case .photo: "图片"
        case .folder: "文件夹"
        case .file: "文件"
        }
    }

    var symbol: String {
        switch self {
        case .novel: "text.book.closed"
        case .comic: "rectangle.stack"
        case .music: "waveform"
        case .photo: "photo"
        case .folder: "folder.fill"
        case .file: "doc"
        }
    }
}

struct WatchLibraryItem: Identifiable, Codable, Hashable {
    let url: URL
    let name: String
    let kind: WatchLibraryKind
    let byteCount: Int64
    let modifiedAt: Date
    let isDirectory: Bool
    let relativePath: String

    var id: String { relativePath }
    var fileExtension: String { url.pathExtension.lowercased() }
    var displayName: String { isDirectory ? name : url.deletingPathExtension().lastPathComponent }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "webp"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "alac"]

    static func classify(url: URL, isDirectory: Bool) -> WatchLibraryKind {
        guard !isDirectory else { return .folder }
        let ext = url.pathExtension.lowercased()
        if ["txt", "md", "markdown", WatchBookPackage.fileExtension].contains(ext) { return .novel }
        if ext == "pdf" { return .comic }
        if audioExtensions.contains(ext) { return .music }
        if imageExtensions.contains(ext) { return .photo }
        return .file
    }
}

struct WatchManifestRecord: Codable {
    let id: String
    let name: String
    let kind: String
    let byteCount: Int64
}

extension Int64 {
    var watchFormattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension TimeInterval {
    var watchPlaybackTime: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
