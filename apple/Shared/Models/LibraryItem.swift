import Foundation

enum LibraryKind: String, Codable, CaseIterable, Sendable {
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
        case .photo: "图库"
        case .folder: "文件夹"
        case .file: "文件"
        }
    }
}

struct LibraryItem: Identifiable, Codable, Hashable, Sendable {
    let url: URL
    let name: String
    let kind: LibraryKind
    let byteCount: Int64
    let modifiedAt: Date
    let isDirectory: Bool
    let relativePath: String

    var id: String { relativePath }
    var fileExtension: String { url.pathExtension.lowercased() }
    var displayName: String { isDirectory ? name : url.deletingPathExtension().lastPathComponent }

    var isWatchCompatible: Bool {
        switch kind {
        case .novel:
            return Self.novelExtensions.contains(fileExtension)
        case .comic:
            return fileExtension == "pdf" || Self.imageExtensions.contains(fileExtension)
        case .music, .photo:
            return true
        case .folder, .file:
            return false
        }
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "webp"]
    static let musicExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "alac"]
    static let novelExtensions: Set<String> = ["txt", "md", "markdown", "epub", "mobi", "azw", "azw3", "doc", "docx"]
    static let comicExtensions: Set<String> = ["pdf", "cbz", "cbr"]

    static func classify(url: URL, isDirectory: Bool) -> LibraryKind {
        guard !isDirectory else { return .folder }
        let ext = url.pathExtension.lowercased()
        if novelExtensions.contains(ext) { return .novel }
        if comicExtensions.contains(ext) { return .comic }
        if musicExtensions.contains(ext) { return .music }
        if imageExtensions.contains(ext) { return .photo }
        return .file
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case name
    case date
    case size
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "名称"
        case .date: "最近修改"
        case .size: "大小"
        case .kind: "类型"
        }
    }
}

extension Array where Element == LibraryItem {
    func sorted(by option: LibrarySort, ascending: Bool = true) -> [LibraryItem] {
        let ordered = sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            switch option {
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .date:
                return lhs.modifiedAt > rhs.modifiedAt
            case .size:
                return lhs.byteCount > rhs.byteCount
            case .kind:
                if lhs.kind == rhs.kind {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.kind.title < rhs.kind.title
            }
        }
        return ascending ? ordered : Array(ordered.reversed())
    }
}
