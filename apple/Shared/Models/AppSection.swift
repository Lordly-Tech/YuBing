import Foundation
import SwiftUI

extension Notification.Name {
    static let yuBingNavigateToSection = Notification.Name("YuBingNavigateToSection")
}

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case reading
    case music
    case gallery
    case files
    case favorites
    case watch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .reading: "阅读"
        case .music: "影音"
        case .gallery: "图库"
        case .files: "文件"
        case .favorites: "收藏"
        case .watch: "传到 Watch"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .reading: "books.vertical"
        case .music: "play.rectangle"
        case .gallery: "photo.on.rectangle.angled"
        case .files: "folder"
        case .favorites: "star"
        case .watch: "applewatch.radiowaves.left.and.right"
        }
    }
}
