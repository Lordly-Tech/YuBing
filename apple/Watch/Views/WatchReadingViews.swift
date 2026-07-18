import Combine
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
                ContentUnavailableView(
                    "还没有书",
                    systemImage: "books.vertical",
                    description: Text("从 iPhone 传入电子书、PDF 或图片。")
                )
            } else {
                List(books) { item in
                    NavigationLink {
                        WatchItemDestination(item: item)
                    } label: {
                        if item.kind == .novel {
                            WatchBookRow(item: item)
                        } else {
                            WatchFileRow(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle("阅读")
        .searchable(text: $query, prompt: "搜索")
    }
}

private struct WatchBookRow: View {
    let item: WatchLibraryItem
    @State private var package: WatchBookPackage?
    @State private var cover: CGImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let cover {
                    Image(decorative: cover, scale: 2)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "text.book.closed")
                        .font(.title3)
                        .foregroundStyle(.cyan)
                }
            }
            .frame(width: 34, height: 44)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(package?.title ?? item.displayName)
                    .lineLimit(2)
                if let package {
                    Text("\(package.chapters.count) 章 · \(package.format.uppercased())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            package = try? WatchBookLoader.load(item)
            if let data = package?.coverData,
               let source = CGImageSourceCreateWithData(data as CFData, nil) {
                cover = CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
        }
    }
}

struct WatchBookDetailView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    let item: WatchLibraryItem
    @State private var package: WatchBookPackage?
    @State private var cover: CGImage?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("无法打开", systemImage: "book.closed", description: Text(loadError))
            } else if let package {
                ScrollView {
                    VStack(spacing: 10) {
                        Group {
                            if let cover {
                                Image(decorative: cover, scale: 2)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(systemName: "text.book.closed.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .frame(width: 92, height: 118)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text(package.title)
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        let record = store.readingRecord(
                            bookID: package.sourceID,
                            initialChapterIndex: package.initialChapterIndex,
                            initialChapterProgress: package.initialChapterProgress
                        )
                        Text("\(package.format.uppercased()) · \(package.chapters.count) 章")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("已阅读 \(record.readingTime.watchReadingDuration)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        NavigationLink {
                            WatchNovelReaderView(item: item, package: package)
                        } label: {
                            Label("继续阅读", systemImage: "book.pages")
                        }
                        .buttonStyle(.borderedProminent)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("章节")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(package.chapters) { chapter in
                                NavigationLink {
                                    WatchNovelReaderView(item: item, package: package, startingChapter: chapter.index)
                                } label: {
                                    HStack {
                                        Text(chapter.title)
                                            .lineLimit(2)
                                        Spacer(minLength: 4)
                                        if chapter.index == record.chapterIndex {
                                            Image(systemName: "bookmark.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.cyan)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("书籍详情")
        .task {
            do {
                let loaded = try WatchBookLoader.load(item)
                package = loaded
                if let data = loaded.coverData,
                   let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    cover = CGImageSourceCreateImageAtIndex(source, 0, nil)
                }
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

struct WatchNovelReaderView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    let item: WatchLibraryItem
    let package: WatchBookPackage
    let startingChapter: Int?

    @State private var chapterIndex = 0
    @State private var progress = 0.0
    @State private var lastPersistedProgress = -1.0
    @State private var scrollRequest = WatchReaderScrollRequest(progress: 0)
    @State private var autoTurnPulse = UUID()
    @State private var nextAutoTurn = Date.distantFuture
    @State private var lastReadingTick = Date()
    @State private var isSettingsPresented = false
    @State private var isChapterListPresented = false
    @State private var areReaderControlsVisible = false

    @AppStorage("watch.reader.fontSize") private var fontSize = 15.0
    @AppStorage("watch.reader.verticalMargin") private var verticalMargin = 8.0
    @AppStorage("watch.reader.autoTurnEnabled") private var autoTurnEnabled = false
    @AppStorage("watch.reader.autoTurnInterval") private var autoTurnInterval = 8.0
    @AppStorage("watch.reader.autoTurnDistance") private var autoTurnDistance = 80.0

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(item: WatchLibraryItem, package: WatchBookPackage, startingChapter: Int? = nil) {
        self.item = item
        self.package = package
        self.startingChapter = startingChapter
    }

    private var chapter: WatchBookChapter {
        package.chapters[min(max(chapterIndex, 0), max(package.chapters.count - 1, 0))]
    }

    var body: some View {
        WatchReaderChapterContent(
            chapter: chapter,
            chapterIndex: chapterIndex,
            chapterCount: package.chapters.count,
            fontSize: fontSize,
            verticalMargin: verticalMargin,
            progress: $progress,
            scrollRequest: scrollRequest,
            autoTurnPulse: autoTurnPulse,
            autoTurnDistance: autoTurnDistance,
            onPreviousChapter: { switchChapter(to: chapterIndex - 1, progress: 0.98) },
            onNextChapter: { switchChapter(to: chapterIndex + 1, progress: 0) }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) {
                areReaderControlsVisible.toggle()
            }
        }
        .overlay(alignment: .bottom) {
            if areReaderControlsVisible {
                watchReaderControls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(chapter.title)
        .toolbar {
            Button { isSettingsPresented = true } label: {
                Label("阅读菜单", systemImage: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $isSettingsPresented) { settings }
        .sheet(isPresented: $isChapterListPresented) {
            NavigationStack {
                WatchChapterPicker(package: package, currentIndex: chapterIndex) { index in
                    switchChapter(to: index, progress: 0)
                    isChapterListPresented = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { isChapterListPresented = false }
                    }
                }
            }
        }
        .onAppear {
            let record = store.readingRecord(
                bookID: package.sourceID,
                initialChapterIndex: package.initialChapterIndex,
                initialChapterProgress: package.initialChapterProgress
            )
            chapterIndex = min(max(startingChapter ?? record.chapterIndex, 0), max(package.chapters.count - 1, 0))
            progress = startingChapter == nil ? record.chapterProgress : 0
            lastPersistedProgress = progress
            scrollRequest = WatchReaderScrollRequest(progress: progress)
            lastReadingTick = .now
            nextAutoTurn = autoTurnEnabled ? Date().addingTimeInterval(autoTurnInterval) : .distantFuture
        }
        .onDisappear {
            commitReadingTime()
            store.updateReadingProgress(bookID: package.sourceID, chapterIndex: chapterIndex, progress: progress)
        }
        .onChange(of: progress) { _, value in
            if abs(value - lastPersistedProgress) >= 0.02 {
                lastPersistedProgress = value
                store.updateReadingProgress(bookID: package.sourceID, chapterIndex: chapterIndex, progress: value)
            }
        }
        .onChange(of: autoTurnEnabled) { _, enabled in
            nextAutoTurn = enabled ? Date().addingTimeInterval(autoTurnInterval) : .distantFuture
        }
        .onChange(of: autoTurnInterval) { _, value in
            if autoTurnEnabled { nextAutoTurn = Date().addingTimeInterval(value) }
        }
        .onReceive(clock) { now in
            if now.timeIntervalSince(lastReadingTick) >= 30 { commitReadingTime(now: now) }
            if autoTurnEnabled, now >= nextAutoTurn {
                autoTurnPulse = UUID()
                nextAutoTurn = now.addingTimeInterval(autoTurnInterval)
            }
        }
    }

    private var watchReaderControls: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Button {
                    isChapterListPresented = true
                } label: {
                    Label("目录", systemImage: "list.bullet")
                        .labelStyle(.iconOnly)
                }
                Button { addBookmark() } label: {
                    Label("书签", systemImage: "bookmark")
                        .labelStyle(.iconOnly)
                }
                Button {
                    areReaderControlsVisible = false
                } label: {
                    Label("隐藏", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.plain)

            ProgressView(value: progress)
            Text("\(chapter.title) · \(Int(progress * 100))%")
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .watchGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 4)
        .padding(.bottom, 3)
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("阅读") {
                    NavigationLink {
                        WatchChapterPicker(package: package, currentIndex: chapterIndex) { index in
                            switchChapter(to: index, progress: 0)
                        }
                    } label: {
                        Label("章节", systemImage: "list.number")
                    }
                    Button { addBookmark() } label: {
                        Label("添加书签", systemImage: "bookmark.badge.plus")
                    }
                    NavigationLink {
                        WatchBookmarkList(bookID: package.sourceID) { bookmark in
                            chapterIndex = bookmark.chapterIndex
                            progress = bookmark.chapterProgress
                            scrollRequest = WatchReaderScrollRequest(progress: bookmark.chapterProgress)
                        }
                        .environmentObject(store)
                    } label: {
                        Label("书签管理", systemImage: "bookmark.square")
                    }
                }
                Section("文字") {
                    WatchValueSlider(title: "字号", value: $fontSize, range: 12...24, step: 1, suffix: "")
                    WatchValueSlider(title: "上下边距", value: $verticalMargin, range: 2...30, step: 2, suffix: "")
                }
                Section("自动翻页") {
                    Toggle("开启", isOn: $autoTurnEnabled)
                    WatchValueSlider(title: "间隔", value: $autoTurnInterval, range: 2...30, step: 1, suffix: " 秒")
                    WatchValueSlider(title: "距离", value: $autoTurnDistance, range: 20...100, step: 10, suffix: "%")
                }
                Section("屏幕") {
                    Text("熄屏时长与屏幕亮度由 watchOS 控制。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("阅读设置")
            .toolbar { Button("完成") { isSettingsPresented = false } }
        }
    }

    private func switchChapter(to index: Int, progress newProgress: Double) {
        guard package.chapters.indices.contains(index) else { return }
        store.updateReadingProgress(bookID: package.sourceID, chapterIndex: chapterIndex, progress: progress)
        chapterIndex = index
        progress = min(max(newProgress, 0), 1)
        lastPersistedProgress = progress
        scrollRequest = WatchReaderScrollRequest(progress: progress)
    }

    private func addBookmark() {
        store.addBookmark(
            bookID: package.sourceID,
            chapterIndex: chapterIndex,
            chapterTitle: chapter.title,
            progress: progress
        )
    }

    private func commitReadingTime(now: Date = .now) {
        let elapsed = now.timeIntervalSince(lastReadingTick)
        if elapsed > 0 { store.addReadingTime(elapsed, bookID: package.sourceID) }
        lastReadingTick = now
    }

}

private struct WatchReaderScrollRequest: Equatable {
    let id = UUID()
    let progress: Double
}

private struct WatchReaderChapterContent: View {
    let chapter: WatchBookChapter
    let chapterIndex: Int
    let chapterCount: Int
    let fontSize: Double
    let verticalMargin: Double
    @Binding var progress: Double
    let scrollRequest: WatchReaderScrollRequest
    let autoTurnPulse: UUID
    let autoTurnDistance: Double
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    @State private var contentHeight = 1.0

    private var paragraphs: [String] {
        let values = chapter.text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? [chapter.text] : values
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: WatchReaderTopOffsetKey.self,
                                value: geometry.frame(in: .named("watch-reader-scroll")).minY
                            )
                        }
                        .frame(height: 0)

                        if chapterIndex > 0 {
                            Button(action: onPreviousChapter) { Label("上一章", systemImage: "arrow.up") }
                                .id("watch-chapter-top")
                        }

                        Text(chapter.title)
                            .font(.headline)

                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                            Text(paragraph)
                                .font(.system(size: fontSize, design: .serif))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("watch-paragraph-\(index)")
                        }

                        if chapterIndex + 1 < chapterCount {
                            Button(action: onNextChapter) { Label("下一章", systemImage: "arrow.down") }
                                .id("watch-chapter-bottom")
                        } else {
                            Label("全书已读完", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, verticalMargin)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: WatchReaderContentHeightKey.self, value: geometry.size.height)
                        }
                    }
                }
                .coordinateSpace(name: "watch-reader-scroll")
                .onPreferenceChange(WatchReaderContentHeightKey.self) { contentHeight = max($0, 1) }
                .onPreferenceChange(WatchReaderTopOffsetKey.self) { offset in
                    let scrollable = max(contentHeight - viewport.size.height, 1)
                    progress = min(max(-offset / scrollable, 0), 1)
                }
                .onChange(of: scrollRequest) { _, request in
                    scroll(to: request.progress, proxy: proxy)
                }
                .onChange(of: autoTurnPulse) { _, _ in
                    let visible = min(max(viewport.size.height / max(contentHeight, 1), 0.02), 1)
                    let target = progress + visible * autoTurnDistance / 100
                    if target >= 0.985 {
                        if chapterIndex + 1 < chapterCount { onNextChapter() }
                    } else {
                        scroll(to: target, proxy: proxy, animated: true)
                    }
                }
                .onAppear {
                    DispatchQueue.main.async { scroll(to: scrollRequest.progress, proxy: proxy) }
                }
            }
        }
    }

    private func scroll(to target: Double, proxy: ScrollViewProxy, animated: Bool = false) {
        let index = min(max(Int(Double(max(paragraphs.count - 1, 0)) * target), 0), max(paragraphs.count - 1, 0))
        let action = { proxy.scrollTo("watch-paragraph-\(index)", anchor: .top) }
        if animated { withAnimation(.easeInOut(duration: 0.4), action) } else { action() }
    }
}

private struct WatchReaderContentHeightKey: PreferenceKey {
    static var defaultValue = 1.0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = max(value, nextValue()) }
}

private struct WatchReaderTopOffsetKey: PreferenceKey {
    static var defaultValue = 0.0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
}

private struct WatchChapterPicker: View {
    @Environment(\.dismiss) private var dismiss
    let package: WatchBookPackage
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(package.chapters) { chapter in
                Button {
                    onSelect(chapter.index)
                    dismiss()
                } label: {
                    HStack {
                        Text(chapter.title)
                        Spacer()
                        if chapter.index == currentIndex { Image(systemName: "checkmark") }
                    }
                }
            }
            .navigationTitle("章节")
        }
    }
}

private struct WatchBookmarkList: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @Environment(\.dismiss) private var dismiss
    let bookID: String
    let onSelect: (WatchReaderBookmark) -> Void
    @State private var editingBookmark: WatchReaderBookmark?

    private var bookmarks: [WatchReaderBookmark] {
        store.readingRecord(bookID: bookID).bookmarks
    }

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    ContentUnavailableView("还没有书签", systemImage: "bookmark")
                } else {
                    List(bookmarks) { bookmark in
                        Button {
                            onSelect(bookmark)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(bookmark.name)
                                Text("第 \(bookmark.chapterIndex + 1) 章")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteBookmark(bookmark, bookID: bookID)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button { editingBookmark = bookmark } label: {
                                Label("编辑名称", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
            .navigationTitle("书签")
            .sheet(item: $editingBookmark) { bookmark in
                WatchBookmarkEditor(bookID: bookID, bookmark: bookmark)
                    .environmentObject(store)
            }
        }
    }
}

private struct WatchBookmarkEditor: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @Environment(\.dismiss) private var dismiss
    let bookID: String
    let bookmark: WatchReaderBookmark
    @State private var name: String

    init(bookID: String, bookmark: WatchReaderBookmark) {
        self.bookID = bookID
        self.bookmark = bookmark
        _name = State(initialValue: bookmark.name)
    }

    var body: some View {
        Form {
            TextField("名称", text: $name)
            Button("保存") {
                store.renameBookmark(bookmark, to: name, bookID: bookID)
                dismiss()
            }
        }
        .navigationTitle("书签名称")
    }
}

private struct WatchValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) \(Int(value))\(suffix)")
                .font(.caption)
            Slider(value: $value, in: range, step: step)
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
