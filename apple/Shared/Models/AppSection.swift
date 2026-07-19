import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case music
    case reading
    case gallery
    case more

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "首页"
        case .music: "音乐"
        case .reading: "阅读"
        case .gallery: "图库"
        case .more: "更多"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .music: "music.note.list"
        case .reading: "books.vertical"
        case .gallery: "photo.on.rectangle.angled"
        case .more: "ellipsis.circle"
        }
    }
}
