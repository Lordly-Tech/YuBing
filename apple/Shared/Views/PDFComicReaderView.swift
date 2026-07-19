import PDFKit
import SwiftUI

private enum ComicDisplayMode: String, CaseIterable, Identifiable {
    case pages
    case continuous

    var id: String { rawValue }
    var title: String { AppLocalization.string(self == .pages ? "单页" : "连续") }
}

struct PDFComicReaderView: View {
    @EnvironmentObject private var store: LibraryStore
    #if os(iOS)
    @EnvironmentObject private var watchTransfer: WatchTransferService
    #endif
    let item: LibraryItem

    @State private var mode: ComicDisplayMode = .pages
    @State private var areControlsVisible = false
    private var pageCount: Int { PDFDocument(url: item.url)?.pageCount ?? 0 }

    var body: some View {
        PDFKitView(url: item.url, displayMode: mode)
            .ignoresSafeArea(edges: .bottom)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy(duration: 0.22)) { areControlsVisible.toggle() }
            }
            .navigationTitle(item.displayName)
            #if os(iOS)
            .toolbar(areControlsVisible ? .visible : .hidden, for: .navigationBar)
            .toolbar(areControlsVisible ? .visible : .hidden, for: .tabBar)
            .statusBarHidden(!areControlsVisible)
            #endif
            .toolbar {
                ToolbarItemGroup {
                    Text("\(pageCount) \(AppLocalization.string("页"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("阅读方式", selection: $mode) {
                        ForEach(ComicDisplayMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
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
                }
            }
    }
}

private struct PDFKitView {
    let url: URL
    let displayMode: ComicDisplayMode

    private func configure(_ view: PDFView) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        view.autoScales = true
        view.backgroundColor = .clear
        view.displaysPageBreaks = true
        view.displayDirection = displayMode == .pages ? .horizontal : .vertical
        view.displayMode = displayMode == .pages ? .singlePage : .singlePageContinuous
        view.usePageViewController(displayMode == .pages, withViewOptions: nil)
    }
}

#if os(macOS)
extension PDFKitView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        configure(nsView)
    }
}
#else
extension PDFKitView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        configure(uiView)
    }
}
#endif
