import ImageIO
import SwiftUI

struct PhotoViewer: View {
    @EnvironmentObject private var store: LibraryStore
    #if os(iOS)
    @EnvironmentObject private var watchTransfer: WatchTransferService
    #endif
    let item: LibraryItem

    @State private var image: CGImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var loadFailed = false
    @State private var areControlsVisible = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in scale = min(max(1, lastScale * value.magnification), 6) }
                            .onEnded { _ in lastScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) {
                            scale = scale > 1 ? 1 : 2
                            lastScale = scale
                        }
                    }
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.22)) { areControlsVisible.toggle() }
                    }
            } else if loadFailed {
                ContentUnavailableView("无法显示图片", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .navigationTitle(item.displayName)
        #if os(iOS)
        .toolbar(areControlsVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar(areControlsVisible ? .visible : .hidden, for: .tabBar)
        .statusBarHidden(!areControlsVisible)
        #endif
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.toggleFavorite(item)
                } label: {
                    Label("收藏", systemImage: store.isFavorite(item) ? "star.fill" : "star")
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
        .task { loadImage() }
    }

    private func loadImage() {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            loadFailed = true
            return
        }
        image = cgImage
    }
}
