import Combine
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

private enum ReaderAppearance: String, CaseIterable, Identifiable {
    case system
    case paper
    case night

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "自动"
        case .paper: "纸张"
        case .night: "夜间"
        }
    }

    var background: Color {
        switch self {
        case .system:
            #if os(macOS)
            Color(nsColor: .textBackgroundColor)
            #else
            Color(uiColor: .systemBackground)
            #endif
        case .paper: Color(red: 0.94, green: 0.91, blue: 0.82)
        case .night: Color(red: 0.06, green: 0.065, blue: 0.075)
        }
    }

    var foreground: Color {
        switch self {
        case .system: .primary
        case .paper: Color(red: 0.18, green: 0.16, blue: 0.12)
        case .night: Color(white: 0.88)
        }
    }
}

struct NovelReaderView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var readingStore: ReadingStore
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @EnvironmentObject private var watchTransfer: WatchTransferService
    #endif

    let item: LibraryItem

    @State private var book: ParsedBook?
    @State private var loadError: String?
    @State private var chapterIndex = 0
    @State private var chapterProgress = 0.0
    @State private var lastPersistedProgress = -1.0
    @State private var scrollRequest = ReaderScrollRequest(progress: 0)
    @State private var autoTurnPulse = UUID()
    @State private var nextAutoTurn = Date.distantFuture
    @State private var lastReadingTick = Date()
    @State private var isChapterListPresented = false
    @State private var isBookmarkManagerPresented = false
    @State private var isSettingsPresented = false
    @State private var isCoverImporterPresented = false
    @State private var bookmarkConfirmation: ReaderBookmark?
    #if os(iOS)
    @State private var originalBrightness: CGFloat?
    #endif

    @AppStorage("reader.fontSize") private var fontSize = 19.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = 8.0
    @AppStorage("reader.verticalMargin") private var verticalMargin = 34.0
    @AppStorage("reader.appearance") private var appearanceRaw = ReaderAppearance.system.rawValue
    @AppStorage("reader.autoTurnEnabled") private var autoTurnEnabled = false
    @AppStorage("reader.autoTurnInterval") private var autoTurnInterval = 8.0
    @AppStorage("reader.autoTurnDistance") private var autoTurnDistance = 80.0
    @AppStorage("reader.keepAwake") private var keepAwake = false
    @AppStorage("reader.followSystemBrightness") private var followsSystemBrightness = true
    @AppStorage("reader.brightness") private var customBrightness = 0.55

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var appearance: ReaderAppearance {
        ReaderAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var currentChapter: BookChapter? {
        guard let book, book.chapters.indices.contains(chapterIndex) else { return nil }
        return book.chapters[chapterIndex]
    }

    private var currentFileOffset: Int {
        guard let chapter = currentChapter else { return 0 }
        return chapter.startOffset + Int(Double(chapter.length) * chapterProgress)
    }

    var body: some View {
        ZStack {
            appearance.background.ignoresSafeArea()
            if let loadError {
                ContentUnavailableView(
                    "无法读取这本书",
                    systemImage: "text.badge.xmark",
                    description: Text(loadError)
                )
            } else if let book, let chapter = currentChapter {
                ReaderChapterContent(
                    chapter: chapter,
                    chapterIndex: chapterIndex,
                    chapterCount: book.chapters.count,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    verticalMargin: verticalMargin,
                    foreground: appearance.foreground,
                    progress: $chapterProgress,
                    scrollRequest: scrollRequest,
                    autoTurnPulse: autoTurnPulse,
                    autoTurnDistance: autoTurnDistance,
                    onPreviousChapter: { switchChapter(to: chapterIndex - 1, progress: 0.98) },
                    onNextChapter: { switchChapter(to: chapterIndex + 1, progress: 0) }
                )
            } else {
                ProgressView("正在分析格式与章节")
            }
        }
        .navigationTitle(currentChapter?.title ?? item.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { readerToolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) { progressFooter }
        .sheet(isPresented: $isChapterListPresented) {
            if let book {
                ReaderChapterPicker(
                    bookTitle: book.title,
                    chapters: book.chapters,
                    currentIndex: chapterIndex,
                    onSelect: { switchChapter(to: $0, progress: 0) }
                )
            }
        }
        .sheet(isPresented: $isBookmarkManagerPresented) {
            ReaderBookmarkManager(item: item) { bookmark in
                jump(to: bookmark)
            }
            .environmentObject(readingStore)
        }
        .sheet(isPresented: $isSettingsPresented) { settingsSheet }
        .fileImporter(
            isPresented: $isCoverImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            importCover(result)
        }
        .alert(item: $bookmarkConfirmation) { bookmark in
            Alert(
                title: Text("已添加书签"),
                message: Text(bookmark.name),
                dismissButton: .default(Text("好"))
            )
        }
        .task(id: item.url) { await loadBook() }
        .onChange(of: chapterProgress) { _, value in persistProgressIfNeeded(value) }
        .onChange(of: autoTurnEnabled) { _, enabled in
            nextAutoTurn = enabled ? Date().addingTimeInterval(autoTurnInterval) : .distantFuture
        }
        .onChange(of: autoTurnInterval) { _, value in
            if autoTurnEnabled { nextAutoTurn = Date().addingTimeInterval(value) }
        }
        .onChange(of: keepAwake) { _, _ in applyKeepAwake() }
        .onChange(of: followsSystemBrightness) { _, _ in applyBrightness() }
        .onChange(of: customBrightness) { _, _ in applyBrightness() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                lastReadingTick = .now
                applyKeepAwake()
                applyBrightness()
            } else {
                commitReadingTime()
            }
        }
        .onReceive(clock) { now in handleClock(now) }
        .onAppear {
            lastReadingTick = .now
            #if os(iOS)
            originalBrightness = UIScreen.main.brightness
            #endif
            applyKeepAwake()
            applyBrightness()
        }
        .onDisappear {
            commitReadingTime()
            readingStore.updateProgress(for: item, chapterIndex: chapterIndex, progress: chapterProgress)
            restoreDisplaySettings()
        }
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                addBookmark()
            } label: {
                Label("添加书签", systemImage: "bookmark")
            }
            .contextMenu {
                Button { isBookmarkManagerPresented = true } label: {
                    Label("书签管理", systemImage: "bookmark.square")
                }
            }

            Menu {
                Button { isChapterListPresented = true } label: {
                    Label("章节", systemImage: "list.number")
                }
                Toggle(isOn: $autoTurnEnabled) {
                    Label("自动翻页", systemImage: "timer")
                }
                Toggle(isOn: $keepAwake) {
                    Label("常驻亮屏", systemImage: "sun.max")
                }

                Divider()
                Button { addBookmark() } label: {
                    Label("在当前位置添加书签", systemImage: "bookmark.badge.plus")
                }
                Button { isBookmarkManagerPresented = true } label: {
                    Label("书签管理", systemImage: "bookmark.square")
                }

                Divider()
                Button { isSettingsPresented = true } label: {
                    Label("阅读与显示设置", systemImage: "textformat.size")
                }
                Button { isCoverImporterPresented = true } label: {
                    Label(readingStore.hasCover(for: item) ? "更换书籍封面" : "设置书籍封面", systemImage: "photo.badge.plus")
                }

                Divider()
                Button {} label: {
                    Label(
                        "已阅读 \(readingStore.record(for: item).totalReadingTime.formattedReadingDuration)",
                        systemImage: "clock"
                    )
                }
                .disabled(true)

                #if os(iOS)
                Divider()
                Button {
                    readingStore.updateProgress(for: item, chapterIndex: chapterIndex, progress: chapterProgress)
                    watchTransfer.send([item])
                } label: {
                    Label("同步到 Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                }
                #endif
            } label: {
                Label("阅读菜单", systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var progressFooter: some View {
        if let chapter = currentChapter, let book {
            VStack(spacing: 5) {
                ProgressView(value: chapterProgress)
                    .progressViewStyle(.linear)
                HStack(spacing: 8) {
                    Text(chapter.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(Int(chapterProgress * 100))% · \(currentFileOffset.formatted()) / \(book.totalLength.formatted())")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 5)
            .background(.bar)
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("文字") {
                    Picker("外观", selection: $appearanceRaw) {
                        ForEach(ReaderAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    ReaderValueSlider(title: "字号", value: $fontSize, range: 14...32, step: 1, suffix: "")
                    ReaderValueSlider(title: "行距", value: $lineSpacing, range: 2...16, step: 1, suffix: "")
                    ReaderValueSlider(title: "上下边距", value: $verticalMargin, range: 12...100, step: 2, suffix: " pt")
                }

                Section("自动翻页") {
                    Toggle("开启自动翻页", isOn: $autoTurnEnabled)
                    ReaderValueSlider(title: "间隔", value: $autoTurnInterval, range: 2...30, step: 1, suffix: " 秒")
                    ReaderValueSlider(title: "每次移动", value: $autoTurnDistance, range: 20...100, step: 10, suffix: "% 屏")
                    Text("到达章节末尾后会自动进入下一章。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("屏幕") {
                    Toggle("常驻亮屏", isOn: $keepAwake)
                    #if os(iOS)
                    Toggle("亮度跟随系统", isOn: $followsSystemBrightness)
                    if !followsSystemBrightness {
                        ReaderValueSlider(title: "阅读亮度", value: $customBrightness, range: 0.05...1, step: 0.05, suffix: "")
                    }
                    #else
                    Text("Mac 的亮度继续由系统控制。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #endif
                }
            }
            .navigationTitle("阅读设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { isSettingsPresented = false }
                }
            }
        }
    }

    private func loadBook() async {
        loadError = nil
        do {
            let url = item.url
            let parsed = try await Task.detached(priority: .userInitiated) {
                try BookParser.parse(url: url)
            }.value
            if let cover = parsed.coverData, !readingStore.hasCover(for: item) {
                readingStore.saveCover(cover, for: item)
            }
            let record = readingStore.record(for: item)
            let index = min(max(record.chapterIndex, 0), max(parsed.chapters.count - 1, 0))
            book = parsed
            chapterIndex = index
            chapterProgress = min(max(record.chapterProgress, 0), 1)
            lastPersistedProgress = chapterProgress
            scrollRequest = ReaderScrollRequest(progress: chapterProgress)
            nextAutoTurn = autoTurnEnabled ? Date().addingTimeInterval(autoTurnInterval) : .distantFuture
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func switchChapter(to index: Int, progress: Double) {
        guard let book, book.chapters.indices.contains(index) else { return }
        readingStore.updateProgress(for: item, chapterIndex: chapterIndex, progress: chapterProgress)
        chapterIndex = index
        chapterProgress = min(max(progress, 0), 1)
        lastPersistedProgress = chapterProgress
        scrollRequest = ReaderScrollRequest(progress: chapterProgress)
        nextAutoTurn = autoTurnEnabled ? Date().addingTimeInterval(autoTurnInterval) : .distantFuture
    }

    private func jump(to bookmark: ReaderBookmark) {
        isBookmarkManagerPresented = false
        guard let book, book.chapters.indices.contains(bookmark.chapterIndex) else { return }
        chapterIndex = bookmark.chapterIndex
        chapterProgress = bookmark.chapterProgress
        scrollRequest = ReaderScrollRequest(progress: bookmark.chapterProgress)
    }

    private func addBookmark() {
        guard let chapter = currentChapter else { return }
        bookmarkConfirmation = readingStore.addBookmark(
            for: item,
            chapterIndex: chapterIndex,
            chapterTitle: chapter.title,
            chapterProgress: chapterProgress,
            fileOffset: currentFileOffset
        )
    }

    private func persistProgressIfNeeded(_ value: Double) {
        guard abs(value - lastPersistedProgress) >= 0.015 else { return }
        lastPersistedProgress = value
        readingStore.updateProgress(for: item, chapterIndex: chapterIndex, progress: value)
    }

    private func handleClock(_ now: Date) {
        if now.timeIntervalSince(lastReadingTick) >= 30 { commitReadingTime(now: now) }
        guard autoTurnEnabled, now >= nextAutoTurn else { return }
        autoTurnPulse = UUID()
        nextAutoTurn = now.addingTimeInterval(autoTurnInterval)
    }

    private func commitReadingTime(now: Date = .now) {
        let elapsed = now.timeIntervalSince(lastReadingTick)
        if elapsed > 0 { readingStore.addReadingTime(elapsed, for: item) }
        lastReadingTick = now
    }

    private func applyKeepAwake() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = keepAwake
        #endif
    }

    private func applyBrightness() {
        #if os(iOS)
        guard !followsSystemBrightness else {
            if let originalBrightness { UIScreen.main.brightness = originalBrightness }
            return
        }
        UIScreen.main.brightness = CGFloat(customBrightness)
        #endif
    }

    private func restoreDisplaySettings() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        if let originalBrightness { UIScreen.main.brightness = originalBrightness }
        #endif
    }

    private func importCover(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        readingStore.saveCover(data, for: item)
    }
}

private struct ReaderScrollRequest: Equatable {
    let id = UUID()
    let progress: Double
}

private struct ReaderChapterContent: View {
    let chapter: BookChapter
    let chapterIndex: Int
    let chapterCount: Int
    let fontSize: Double
    let lineSpacing: Double
    let verticalMargin: Double
    let foreground: Color
    @Binding var progress: Double
    let scrollRequest: ReaderScrollRequest
    let autoTurnPulse: UUID
    let autoTurnDistance: Double
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void

    @State private var contentHeight = 1.0

    private var paragraphs: [String] {
        let values = chapter.text
            .components(separatedBy: #"\n\s*\n"#)
            .flatMap { $0.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? [chapter.text] : values
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ReaderTopOffsetKey.self,
                                value: geometry.frame(in: .named("reader-scroll")).minY
                            )
                        }
                        .frame(height: 0)

                        if chapterIndex > 0 {
                            chapterButton("上一章", symbol: "arrow.up", action: onPreviousChapter)
                                .id("chapter-top")
                        }

                        Text(chapter.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(foreground)
                            .frame(maxWidth: 720, alignment: .leading)
                            .padding(.bottom, 8)

                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                            Text(paragraph)
                                .font(.system(size: fontSize, design: .serif))
                                .foregroundStyle(foreground)
                                .lineSpacing(lineSpacing)
                                .textSelection(.enabled)
                                .frame(maxWidth: 720, alignment: .leading)
                                .id("paragraph-\(index)")
                        }

                        if chapterIndex + 1 < chapterCount {
                            chapterButton("下一章", symbol: "arrow.down", action: onNextChapter)
                                .id("chapter-bottom")
                        } else {
                            Label("全书已读完", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 720)
                                .padding(.vertical, 22)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, verticalMargin)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: ReaderContentHeightKey.self, value: geometry.size.height)
                        }
                    }
                }
                .coordinateSpace(name: "reader-scroll")
                .onPreferenceChange(ReaderContentHeightKey.self) { contentHeight = max($0, 1) }
                .onPreferenceChange(ReaderTopOffsetKey.self) { offset in
                    let scrollable = max(contentHeight - viewport.size.height, 1)
                    progress = min(max(-offset / scrollable, 0), 1)
                }
                .onChange(of: scrollRequest) { _, request in
                    scroll(to: request.progress, using: proxy)
                }
                .onChange(of: autoTurnPulse) { _, _ in
                    let visibleFraction = min(max(viewport.size.height / max(contentHeight, 1), 0.01), 1)
                    let target = progress + visibleFraction * autoTurnDistance / 100
                    if target >= 0.985 {
                        if chapterIndex + 1 < chapterCount { onNextChapter() }
                    } else {
                        scroll(to: target, using: proxy, animated: true)
                    }
                }
                .onAppear {
                    DispatchQueue.main.async { scroll(to: scrollRequest.progress, using: proxy) }
                }
            }
        }
    }

    private func scroll(to targetProgress: Double, using proxy: ScrollViewProxy, animated: Bool = false) {
        let index = min(max(Int(Double(max(paragraphs.count - 1, 0)) * targetProgress), 0), max(paragraphs.count - 1, 0))
        let action = { proxy.scrollTo("paragraph-\(index)", anchor: .top) }
        if animated {
            withAnimation(.easeInOut(duration: 0.45), action)
        } else {
            action()
        }
    }

    private func chapterButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: 720)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
    }
}

private struct ReaderContentHeightKey: PreferenceKey {
    static var defaultValue = 1.0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = max(value, nextValue()) }
}

private struct ReaderTopOffsetKey: PreferenceKey {
    static var defaultValue = 0.0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
}

private struct ReaderChapterPicker: View {
    @Environment(\.dismiss) private var dismiss
    let bookTitle: String
    let chapters: [BookChapter]
    let currentIndex: Int
    let onSelect: (Int) -> Void
    @State private var query = ""

    private var filtered: [BookChapter] {
        chapters.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { chapter in
                Button {
                    onSelect(chapter.index)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chapter.title)
                                .foregroundStyle(.primary)
                            Text("文本偏移 \(chapter.startOffset.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if chapter.index == currentIndex {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .navigationTitle(bookTitle)
            .searchable(text: $query, prompt: "搜索章节")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct ReaderBookmarkManager: View {
    @EnvironmentObject private var readingStore: ReadingStore
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    let onSelect: (ReaderBookmark) -> Void
    @State private var editingBookmark: ReaderBookmark?
    @State private var bookmarkName = ""

    private var bookmarks: [ReaderBookmark] {
        readingStore.record(for: item).bookmarks.sorted { $0.fileOffset < $1.fileOffset }
    }

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    ContentUnavailableView("还没有书签", systemImage: "bookmark", description: Text("在阅读器中点击书签按钮即可添加。"))
                } else {
                    List {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                onSelect(bookmark)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bookmark.name)
                                        .foregroundStyle(.primary)
                                    Text("第 \(bookmark.chapterIndex + 1) 章 · \(Int(bookmark.chapterProgress * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingBookmark = bookmark
                                    bookmarkName = bookmark.name
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    readingStore.deleteBookmark(bookmark, for: item)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    editingBookmark = bookmark
                                    bookmarkName = bookmark.name
                                } label: {
                                    Label("编辑名称", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    readingStore.deleteBookmark(bookmark, for: item)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("书签")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("编辑书签名称", isPresented: editPresented) {
                TextField("名称", text: $bookmarkName)
                Button("取消", role: .cancel) { editingBookmark = nil }
                Button("保存") {
                    if let editingBookmark {
                        readingStore.renameBookmark(editingBookmark, to: bookmarkName, for: item)
                    }
                    editingBookmark = nil
                }
            }
        }
    }

    private var editPresented: Binding<Bool> {
        Binding(get: { editingBookmark != nil }, set: { if !$0 { editingBookmark = nil } })
    }
}

private struct ReaderValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value))\(suffix)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
