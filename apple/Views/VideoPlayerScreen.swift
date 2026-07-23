import AVKit
import SwiftUI

struct VideoPlayerScreen: View {
    @EnvironmentObject private var store: LibraryStore
    #if os(iOS)
    @EnvironmentObject private var watchTransfer: WatchTransferService
    #endif

    let item: LibraryItem

    @State private var player: AVPlayer?

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
            }
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
