import SwiftUI

struct WatchItemDestination: View {
    @EnvironmentObject private var store: WatchLibraryStore
    let item: WatchLibraryItem

    @ViewBuilder
    var body: some View {
        Group {
            switch item.kind {
            case .folder:
                WatchFileBrowserView(folderURL: item.url)
            case .novel:
                WatchBookDetailView(item: item)
            case .comic:
                WatchPDFReaderView(item: item)
            case .photo:
                WatchImageReaderView(item: item)
            case .music:
                WatchNowPlayingView(startingItem: item)
            case .file:
                ContentUnavailableView("无法打开", systemImage: "doc.badge.ellipsis", description: Text("请在 iPhone 或 Mac 上预览此格式。"))
                    .navigationTitle(item.displayName)
            }
        }
        .onAppear { store.markOpened(item) }
    }
}
