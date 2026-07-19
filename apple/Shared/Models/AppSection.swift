import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case reading
    case music
    case gallery
    case files
    case favorites
    case watch
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .reading: "阅读"
        case .music: "音乐"
        case .gallery: "图库"
        case .files: "文件"
        case .favorites: "收藏"
        case .watch: "传到 Watch"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .reading: "books.vertical"
        case .music: "music.note.list"
        case .gallery: "photo.on.rectangle.angled"
        case .files: "folder"
        case .favorites: "star"
        case .watch: "applewatch.radiowaves.left.and.right"
        case .settings: "gear"
        }
    }
}
