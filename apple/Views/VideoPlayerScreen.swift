import AVKit
import SwiftUI

struct VideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LibraryStore
    #if os(iOS)
    @EnvironmentObject private var watchTransfer: WatchTransferService
    #endif

    let item: LibraryItem

    @State private var player: AVPlayer?
    @State private var showsDeleteConfirmation = false

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .background(.black)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(item.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.toggleFavorite(item)
                } label: {
                    Label(AppLocalization.string(store.isFavorite(item) ? "取消收藏" : "收藏"), systemImage: store.isFavorite(item) ? "star.fill" : "star")
                }
                #if os(iOS)
                Button {
                    watchTransfer.send([item])
                } label: {
                    Label("发送到 Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                }
                #endif
                ShareLink(item: item.url)
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "删除“\(item.displayName)”？",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                player?.pause()
                store.delete(item)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会从本地资料库中删除文件。")
        }
        .task(id: item.url) {
            player = AVPlayer(url: item.url)
            player?.play()
        }
        .onAppear {
            player?.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
