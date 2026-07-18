import SwiftUI

struct ItemDestinationView: View {
    @EnvironmentObject private var store: LibraryStore
    let item: LibraryItem

    @ViewBuilder
    var body: some View {
        Group {
            switch item.kind {
            case .folder:
                FileBrowserView(folderURL: item.url)
            case .novel:
                NovelReaderView(item: item)
            case .comic:
                if item.fileExtension == "pdf" {
                    PDFComicReaderView(item: item)
                } else if LibraryItem.imageExtensions.contains(item.fileExtension) {
                    PhotoViewer(item: item)
                } else {
                    DocumentPreviewScreen(item: item, message: "此漫画格式由系统预览打开。PDF 与图片可直接传到 Watch 阅读。")
                }
            case .music:
                NowPlayingView(startingItem: item)
            case .video:
                VideoPlayerScreen(item: item)
            case .photo:
                PhotoViewer(item: item)
            case .file:
                DocumentPreviewScreen(item: item, message: nil)
            }
        }
        .onAppear { store.markOpened(item) }
    }
}

private struct DocumentPreviewScreen: View {
    @EnvironmentObject private var store: LibraryStore
    #if os(iOS)
    @EnvironmentObject private var watchTransfer: WatchTransferService
    #endif

    let item: LibraryItem
    let message: String?

    var body: some View {
        VStack(spacing: 0) {
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.bar)
            }
            QuickLookPreview(url: item.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(item.displayName)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.toggleFavorite(item)
                } label: {
                    Label(store.isFavorite(item) ? "取消收藏" : "收藏", systemImage: store.isFavorite(item) ? "star.fill" : "star")
                }
                #if os(iOS)
                if item.isWatchCompatible {
                    Button {
                        watchTransfer.send([item])
                    } label: {
                        Label("发送到 Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                    }
                }
                #endif
                ShareLink(item: item.url)
            }
        }
    }
}
