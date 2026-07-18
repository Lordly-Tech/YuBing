import Combine
import SwiftUI

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

private enum ReaderTransitionMode: String, CaseIterable, Identifiable {
    case slide
    case curl
    case fade
    case scroll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slide: "滑动"
        case .curl: "卷页"
        case .fade: "快速淡入淡出"
        case .scroll: "滚动"
        }
    }

    var symbol: String {
        switch self {
        case .slide: "rectangle.portrait.on.rectangle.portrait"
        case .curl: "book.pages"
        case .fade: "square.stack.3d.up"
        case .scroll: "scroll"
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
    @State private var areReaderControlsVisible = false
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
    @AppStorage("reader.transitionMode") private var transitionModeRaw = ReaderTransitionMode.slide.rawValue

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var appearance: ReaderAppearance {
        ReaderAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var transitionMode: ReaderTransitionMode {
        ReaderTransitionMode(rawValue: transitionModeRaw) ?? .slide
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
                chapterContent(book: book, chapter: chapter)
            } else {
                ProgressView("正在分析格式与章节")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(iOS)
            if transitionMode == .scroll { toggleReaderControls() }
            #else
            toggleReaderControls()
            #endif
        }
        .overlay(alignment: .bottom) {
            if areReaderControlsVisible {
                readerControlOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(currentChapter?.title ?? item.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(areReaderControlsVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar(areReaderControlsVisible ? .visible : .hidden, for: .tabBar)
        .statusBarHidden(!areReaderControlsVisible)
        #endif
        .toolbar { readerToolbar }
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

    @ViewBuilder
    private func chapterContent(book: ParsedBook, chapter: BookChapter) -> some View {
        #if os(iOS)
        if transitionMode == .scroll {
            scrollingChapterContent(book: book, chapter: chapter)
        } else {
            ReaderPagedChapterContent(
                chapter: chapter,
                chapterIndex: chapterIndex,
                chapterCount: book.chapters.count,
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                verticalMargin: verticalMargin,
                appearance: appearance,
                mode: transitionMode,
                progress: $chapterProgress,
                scrollRequest: scrollRequest,
                autoTurnPulse: autoTurnPulse,
                onPreviousChapter: { switchChapter(to: chapterIndex - 1, progress: 0.98) },
                onNextChapter: { switchChapter(to: chapterIndex + 1, progress: 0) },
                onToggleControls: toggleReaderControls
            )
            .id("\(chapterIndex)-\(transitionMode.rawValue)")
        }
        #else
        scrollingChapterContent(book: book, chapter: chapter)
        #endif
    }

    private func scrollingChapterContent(book: ParsedBook, chapter: BookChapter) -> some View {
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
    }

    private func toggleReaderControls() {
        withAnimation(.snappy(duration: 0.22)) {
            areReaderControlsVisible.toggle()
        }
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
            ToolbarItemGroup {
            #if os(iOS)
            Button {
                readingStore.updateProgress(for: item, chapterIndex: chapterIndex, progress: chapterProgress)
                watchTransfer.send([item])
            } label: {
                Label("传输到 Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
            }
            #endif

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

                #if os(iOS)
                Picker("翻页效果", selection: $transitionModeRaw) {
                    ForEach(ReaderTransitionMode.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option.rawValue)
                    }
                }
                #endif

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
    private var readerControlOverlay: some View {
        if let chapter = currentChapter, let book {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        isChapterListPresented = true
                    } label: {
                        Label("目录 · \(Int(chapterProgress * 100))%", systemImage: "list.bullet")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button { addBookmark() } label: {
                        Image(systemName: "bookmark")
                            .frame(width: 36, height: 36)
                    }
                    .adaptiveGlassButton()

                    Button { isSettingsPresented = true } label: {
                        Image(systemName: "textformat.size")
                            .frame(width: 36, height: 36)
                    }
                    .adaptiveGlassButton()

                    ShareLink(item: item.url) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 36, height: 36)
                    }
                    .adaptiveGlassButton()
                }

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
            .padding(.vertical, 12)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
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

                #if os(iOS)
                Section("翻页效果") {
                    Picker("翻页方式", selection: $transitionModeRaw) {
                        ForEach(ReaderTransitionMode.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option.rawValue)
                        }
                    }
                    Text(transitionMode == .scroll ? "连续上下滚动阅读。" : "左右翻页，章节内容会自动排成适合当前屏幕的页面。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif

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

#if os(iOS)
private struct ReaderPagedChapterContent: UIViewControllerRepresentable {
    let chapter: BookChapter
    let chapterIndex: Int
    let chapterCount: Int
    let fontSize: Double
    let lineSpacing: Double
    let verticalMargin: Double
    let appearance: ReaderAppearance
    let mode: ReaderTransitionMode
    @Binding var progress: Double
    let scrollRequest: ReaderScrollRequest
    let autoTurnPulse: UUID
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onToggleControls: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> ReaderPagesViewController {
        let controller = ReaderPagesViewController(mode: mode)
        let coordinator = context.coordinator
        controller.onProgress = { value in coordinator.parent.progress = value }
        controller.onPreviousChapter = { coordinator.parent.onPreviousChapter() }
        controller.onNextChapter = { coordinator.parent.onNextChapter() }
        controller.onTap = { coordinator.parent.onToggleControls() }
        return controller
    }

    func updateUIViewController(_ controller: ReaderPagesViewController, context: Context) {
        context.coordinator.parent = self
        controller.configure(
            ReaderPagesConfiguration(
                chapter: chapter,
                chapterIndex: chapterIndex,
                chapterCount: chapterCount,
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                verticalMargin: verticalMargin,
                appearance: appearance
            ),
            targetProgress: scrollRequest.progress,
            requestID: scrollRequest.id,
            autoTurnPulse: autoTurnPulse
        )
    }

    final class Coordinator {
        var parent: ReaderPagedChapterContent
        init(parent: ReaderPagedChapterContent) { self.parent = parent }
    }
}

private struct ReaderPagesConfiguration {
    let chapter: BookChapter
    let chapterIndex: Int
    let chapterCount: Int
    let fontSize: Double
    let lineSpacing: Double
    let verticalMargin: Double
    let appearance: ReaderAppearance

    var key: String {
        "\(chapterIndex)|\(chapter.length)|\(fontSize)|\(lineSpacing)|\(verticalMargin)|\(appearance.rawValue)"
    }

    var hasPreviousChapter: Bool { chapterIndex > 0 }
    var hasNextChapter: Bool { chapterIndex + 1 < chapterCount }

    var backgroundColor: UIColor {
        switch appearance {
        case .system: .systemBackground
        case .paper: UIColor(red: 0.94, green: 0.91, blue: 0.82, alpha: 1)
        case .night: UIColor(red: 0.06, green: 0.065, blue: 0.075, alpha: 1)
        }
    }

    var foregroundColor: UIColor {
        switch appearance {
        case .system: .label
        case .paper: UIColor(red: 0.18, green: 0.16, blue: 0.12, alpha: 1)
        case .night: UIColor(white: 0.88, alpha: 1)
        }
    }
}

private enum ReaderPageContent {
    case text(NSAttributedString)
    case previousChapter
    case nextChapter
    case finished
}

private final class ReaderPagesViewController: UIViewController,
    UIPageViewControllerDataSource,
    UIPageViewControllerDelegate,
    UIGestureRecognizerDelegate {
    var onProgress: (Double) -> Void = { _ in }
    var onPreviousChapter: () -> Void = {}
    var onNextChapter: () -> Void = {}
    var onTap: () -> Void = {}

    private let mode: ReaderTransitionMode
    private var configuration: ReaderPagesConfiguration?
    private var configurationKey = ""
    private var pages: [ReaderPageContent] = []
    private var textPageCount = 0
    private var currentIndex = 0
    private var lastLayoutSize = CGSize.zero
    private var lastRequestID: UUID?
    private var lastAutoTurnPulse: UUID?
    private var pendingTargetProgress = 0.0
    private var pager: UIPageViewController?
    private var fadePageController: ReaderTextPageController?

    init(mode: ReaderTransitionMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)

        if mode == .fade {
            let forward = UISwipeGestureRecognizer(target: self, action: #selector(handleFadeSwipe(_:)))
            forward.direction = .left
            view.addGestureRecognizer(forward)
            let backward = UISwipeGestureRecognizer(target: self, action: #selector(handleFadeSwipe(_:)))
            backward.direction = .right
            view.addGestureRecognizer(backward)
        } else {
            let transitionStyle: UIPageViewController.TransitionStyle = mode == .curl ? .pageCurl : .scroll
            let pager = UIPageViewController(
                transitionStyle: transitionStyle,
                navigationOrientation: .horizontal
            )
            pager.dataSource = self
            pager.delegate = self
            pager.isDoubleSided = false
            addChild(pager)
            pager.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(pager.view)
            NSLayoutConstraint.activate([
                pager.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                pager.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                pager.view.topAnchor.constraint(equalTo: view.topAnchor),
                pager.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            pager.didMove(toParent: self)
            self.pager = pager
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 80, size.height > 120,
              abs(size.width - lastLayoutSize.width) > 1 || abs(size.height - lastLayoutSize.height) > 1 else { return }
        let target = pages.isEmpty ? pendingTargetProgress : currentProgress
        lastLayoutSize = size
        rebuildPages(targetProgress: target)
    }

    func configure(
        _ configuration: ReaderPagesConfiguration,
        targetProgress: Double,
        requestID: UUID,
        autoTurnPulse: UUID
    ) {
        self.configuration = configuration
        view.backgroundColor = configuration.backgroundColor

        if configuration.key != configurationKey {
            configurationKey = configuration.key
            pendingTargetProgress = targetProgress
            lastRequestID = requestID
            lastAutoTurnPulse = autoTurnPulse
            rebuildPages(targetProgress: targetProgress)
            return
        }

        if lastRequestID != requestID {
            lastRequestID = requestID
            pendingTargetProgress = targetProgress
            showPage(at: pageIndex(for: targetProgress), animated: false, direction: .forward)
        }

        if lastAutoTurnPulse != autoTurnPulse {
            if lastAutoTurnPulse != nil { advancePage() }
            lastAutoTurnPulse = autoTurnPulse
        }
    }

    private var textStartIndex: Int {
        configuration?.hasPreviousChapter == true ? 1 : 0
    }

    private var currentProgress: Double {
        guard textPageCount > 1 else { return currentIndex > textStartIndex ? 1 : 0 }
        let textIndex = min(max(currentIndex - textStartIndex, 0), textPageCount - 1)
        return Double(textIndex) / Double(textPageCount - 1)
    }

    private func pageIndex(for progress: Double) -> Int {
        guard textPageCount > 1 else { return textStartIndex }
        let offset = Int((min(max(progress, 0), 1) * Double(textPageCount - 1)).rounded())
        return textStartIndex + offset
    }

    private func rebuildPages(targetProgress: Double) {
        guard let configuration, view.bounds.width > 80, view.bounds.height > 120 else { return }
        let textPages = paginate(configuration: configuration, viewportSize: view.bounds.size)
        textPageCount = max(textPages.count, 1)
        var rebuilt: [ReaderPageContent] = []
        if configuration.hasPreviousChapter { rebuilt.append(.previousChapter) }
        rebuilt.append(contentsOf: textPages.map(ReaderPageContent.text))
        rebuilt.append(configuration.hasNextChapter ? .nextChapter : .finished)
        pages = rebuilt
        showPage(at: pageIndex(for: targetProgress), animated: false, direction: .forward)
    }

    private func paginate(
        configuration: ReaderPagesConfiguration,
        viewportSize: CGSize
    ) -> [NSAttributedString] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(configuration.lineSpacing)
        paragraphStyle.paragraphSpacing = 13
        paragraphStyle.lineBreakMode = .byWordWrapping

        let bodyFont = UIFont(name: "NewYork-Regular", size: CGFloat(configuration.fontSize))
            ?? UIFont.systemFont(ofSize: CGFloat(configuration.fontSize))
        let titleFont = UIFont.systemFont(ofSize: CGFloat(configuration.fontSize * 1.35), weight: .semibold)
        let fullText = "\(configuration.chapter.title)\n\n\(configuration.chapter.text)"
        let attributed = NSMutableAttributedString(
            string: fullText,
            attributes: [
                .font: bodyFont,
                .foregroundColor: configuration.foregroundColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        let titleRange = NSRange(location: 0, length: (configuration.chapter.title as NSString).length)
        attributed.addAttribute(.font, value: titleFont, range: titleRange)

        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let availableSize = CGSize(
            width: max(viewportSize.width - 48, 80),
            height: max(viewportSize.height - CGFloat(configuration.verticalMargin * 2), 100)
        )

        var result: [NSAttributedString] = []
        var laidOutGlyphs = 0
        let totalGlyphs = layoutManager.numberOfGlyphs
        while laidOutGlyphs < totalGlyphs {
            let container = NSTextContainer(size: availableSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)
            guard glyphRange.length > 0 else { break }
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            result.append(attributed.attributedSubstring(from: characterRange))
            laidOutGlyphs = NSMaxRange(glyphRange)
        }
        return result.isEmpty ? [attributed] : result
    }

    private func makePageController(index: Int) -> ReaderTextPageController {
        let configuration = configuration!
        return ReaderTextPageController(
            content: pages[index],
            pageIndex: index,
            backgroundColor: configuration.backgroundColor,
            foregroundColor: configuration.foregroundColor,
            verticalMargin: CGFloat(configuration.verticalMargin),
            onPreviousChapter: onPreviousChapter,
            onNextChapter: onNextChapter
        )
    }

    private func showPage(
        at proposedIndex: Int,
        animated: Bool,
        direction: UIPageViewController.NavigationDirection
    ) {
        guard pages.indices.contains(proposedIndex) else { return }
        currentIndex = proposedIndex
        let next = makePageController(index: proposedIndex)

        if let pager {
            pager.setViewControllers([next], direction: direction, animated: animated, completion: nil)
        } else if let current = fadePageController {
            addChild(next)
            next.view.frame = view.bounds
            next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            transition(
                from: current,
                to: next,
                duration: animated ? 0.14 : 0,
                options: [.transitionCrossDissolve, .curveEaseInOut],
                animations: nil
            ) { _ in
                current.willMove(toParent: nil)
                current.removeFromParent()
                next.didMove(toParent: self)
            }
            fadePageController = next
        } else {
            addChild(next)
            next.view.frame = view.bounds
            next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.insertSubview(next.view, at: 0)
            next.didMove(toParent: self)
            fadePageController = next
        }
        onProgress(currentProgress)
    }

    private func advancePage() {
        guard currentIndex + 1 < pages.count else { return }
        showPage(at: currentIndex + 1, animated: true, direction: .forward)
    }

    private func retreatPage() {
        guard currentIndex > 0 else { return }
        showPage(at: currentIndex - 1, animated: true, direction: .reverse)
    }

    @objc private func handleTap() { onTap() }

    @objc private func handleFadeSwipe(_ gesture: UISwipeGestureRecognizer) {
        if gesture.direction == .left {
            advancePage()
        } else {
            retreatPage()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        while let view = touchedView {
            if view is UIControl { return false }
            touchedView = view.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? ReaderTextPageController, page.pageIndex > 0 else { return nil }
        return makePageController(index: page.pageIndex - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? ReaderTextPageController,
              page.pageIndex + 1 < pages.count else { return nil }
        return makePageController(index: page.pageIndex + 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let page = pageViewController.viewControllers?.first as? ReaderTextPageController else { return }
        currentIndex = page.pageIndex
        onProgress(currentProgress)
    }
}

private final class ReaderTextPageController: UIViewController {
    let pageIndex: Int
    private let content: ReaderPageContent
    private let pageBackgroundColor: UIColor
    private let pageForegroundColor: UIColor
    private let verticalMargin: CGFloat
    private let onPreviousChapter: () -> Void
    private let onNextChapter: () -> Void

    init(
        content: ReaderPageContent,
        pageIndex: Int,
        backgroundColor: UIColor,
        foregroundColor: UIColor,
        verticalMargin: CGFloat,
        onPreviousChapter: @escaping () -> Void,
        onNextChapter: @escaping () -> Void
    ) {
        self.content = content
        self.pageIndex = pageIndex
        pageBackgroundColor = backgroundColor
        pageForegroundColor = foregroundColor
        self.verticalMargin = verticalMargin
        self.onPreviousChapter = onPreviousChapter
        self.onNextChapter = onNextChapter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = pageBackgroundColor
        switch content {
        case .text(let attributedText):
            let textView = UITextView()
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.backgroundColor = .clear
            textView.attributedText = attributedText
            textView.isEditable = false
            textView.isSelectable = false
            textView.isScrollEnabled = false
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            view.addSubview(textView)
            NSLayoutConstraint.activate([
                textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                textView.topAnchor.constraint(equalTo: view.topAnchor, constant: verticalMargin),
                textView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -verticalMargin)
            ])
        case .previousChapter:
            installChapterPage(
                title: "上一章",
                detail: "继续向前阅读",
                symbol: "arrow.left",
                actionTitle: "进入上一章",
                action: onPreviousChapter
            )
        case .nextChapter:
            installChapterPage(
                title: "本章读完",
                detail: "继续阅读下一章",
                symbol: "arrow.right",
                actionTitle: "进入下一章",
                action: onNextChapter
            )
        case .finished:
            installChapterPage(
                title: "全书已读完",
                detail: "阅读进度已保存",
                symbol: "checkmark.circle.fill",
                actionTitle: nil,
                action: nil
            )
        }
    }

    private func installChapterPage(
        title: String,
        detail: String,
        symbol: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) {
        let image = UIImageView(image: UIImage(systemName: symbol))
        image.tintColor = pageForegroundColor
        image.contentMode = .scaleAspectFit
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 38, weight: .semibold)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = pageForegroundColor
        titleLabel.textAlignment = .center

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = pageForegroundColor.withAlphaComponent(0.65)
        detailLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [image, titleLabel, detailLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        if let actionTitle, let action {
            let button = UIButton(
                configuration: .borderedProminent(),
                primaryAction: UIAction(title: actionTitle) { _ in action() }
            )
            stack.addArrangedSubview(button)
            stack.setCustomSpacing(22, after: detailLabel)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 52),
            image.heightAnchor.constraint(equalToConstant: 52),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
#endif

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
