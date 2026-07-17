import CoreGraphics
import ImageIO
import SwiftUI

struct WatchReadingLibraryView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @State private var query = ""

    private var books: [WatchLibraryItem] {
        store.items(of: [.novel, .comic, .photo])
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if books.isEmpty {
                ContentUnavailableView("还没有书", systemImage: "books.vertical", description: Text("从 iPhone 传入 TXT、PDF 或图片。"))
            } else {
                List(books) { item in
                    NavigationLink {
                        WatchItemDestination(item: item)
                    } label: {
                        WatchFileRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("阅读")
        .searchable(text: $query, prompt: "搜索")
    }
}

struct WatchNovelReaderView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    let item: WatchLibraryItem
    @State private var content = ""
    @State private var loadError: String?
    @State private var fontSize = 15.0

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("无法读取", systemImage: "text.badge.xmark", description: Text(loadError))
            } else if content.isEmpty {
                ProgressView()
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(size: fontSize, design: .serif))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 3)
                }
            }
        }
        .navigationTitle(item.displayName)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    fontSize = fontSize >= 21 ? 13 : fontSize + 2
                } label: {
                    Label("调整字号", systemImage: "textformat.size")
                }
                Button {
                    store.toggleFavorite(item)
                } label: {
                    Label("收藏", systemImage: store.isFavorite(item) ? "star.fill" : "star")
                }
            }
        }
        .task {
            do {
                var encoding = String.Encoding.utf8
                content = try String(contentsOf: item.url, usedEncoding: &encoding)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

struct WatchImageReaderView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    let item: WatchLibraryItem
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(item.displayName)
        .toolbar {
            Button { store.toggleFavorite(item) } label: {
                Label("收藏", systemImage: store.isFavorite(item) ? "star.fill" : "star")
            }
        }
        .task {
            guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) else { return }
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }
}

struct WatchPDFReaderView: View {
    let item: WatchLibraryItem
    @State private var pageIndex = 0

    private var pageCount: Int {
        CGPDFDocument(item.url as CFURL)?.numberOfPages ?? 0
    }

    var body: some View {
        Group {
            if pageCount == 0 {
                ContentUnavailableView("无法打开 PDF", systemImage: "doc.badge.xmark")
            } else {
                TabView(selection: $pageIndex) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        WatchPDFPage(url: item.url, pageNumber: index + 1)
                            .tag(index)
                    }
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .navigationTitle("\(pageIndex + 1) / \(max(pageCount, 1))")
    }
}

private struct WatchPDFPage: View {
    let url: URL
    let pageNumber: Int
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFit()
                    .background(.white)
            } else {
                ProgressView()
            }
        }
        .task(id: pageNumber) {
            image = renderPDFPage(url: url, pageNumber: pageNumber)
        }
    }

    private func renderPDFPage(url: URL, pageNumber: Int) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: pageNumber) else { return nil }

        let bounds = page.getBoxRect(.mediaBox)
        let targetWidth: CGFloat = 360
        let scale = targetWidth / max(bounds.width, 1)
        let width = max(Int(bounds.width * scale), 1)
        let height = max(Int(bounds.height * scale), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.drawPDFPage(page)
        return context.makeImage()
    }
}

