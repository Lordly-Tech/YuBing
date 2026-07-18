import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private enum ReadingFilter: String, CaseIterable, Identifiable {
    case all
    case novels
    case comics

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .novels: "小说"
        case .comics: "漫画"
        }
    }
}

private enum ReadingShelfStyle: String, CaseIterable, Identifiable {
    case covers
    case list

    var id: String { rawValue }
    var title: String { self == .covers ? "封面" : "列表" }
    var symbol: String { self == .covers ? "square.grid.2x2" : "list.bullet" }
}

struct ReadingLibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var filter: ReadingFilter = .all
    @State private var shelfStyle: ReadingShelfStyle = .covers
    @State private var query = ""
    @State private var isFormatGuidePresented = false
    @State private var editingBook: LibraryItem?

    private var items: [LibraryItem] {
        store.items.filter { item in
            let matchesKind: Bool
            switch filter {
            case .all: matchesKind = item.kind == .novel || item.kind == .comic
            case .novels: matchesKind = item.kind == .novel
            case .comics: matchesKind = item.kind == .comic
            }
            return matchesKind && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
        .sorted(by: .date)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailablePanel(
                    title: "还没有书",
                    message: "支持 TXT、EPUB、MOBI、AZW3、DOC、DOCX 与 PDF。",
                    symbol: "books.vertical",
                    action: AnyView(FileImportButton(title: "导入书籍", prominent: true))
                )
            } else if shelfStyle == .covers {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 230), spacing: 16)], spacing: 20) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                LibraryItemCard(item: item, onEditBook: { editingBook = item })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: YuBingMetrics.contentMaxWidth)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                LibraryItemRow(item: item, onEditBook: { editingBook = item })
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 80)
                        }
                    }
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("阅读")
        .searchable(text: $query, prompt: "搜索书名")
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Picker("类型", selection: $filter) {
                    ForEach(ReadingFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Picker("书架样式", selection: $shelfStyle) {
                    ForEach(ReadingShelfStyle.allCases) { option in
                        Image(systemName: option.symbol)
                            .accessibilityLabel(option.title)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 104)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { isFormatGuidePresented = true } label: {
                    Label("支持的阅读格式", systemImage: "info.circle")
                }
                FileImportButton(title: "导入").labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $isFormatGuidePresented) {
            ReaderFormatGuideView()
        }
        .sheet(item: $editingBook) { item in
            BookMetadataEditor(item: item)
        }
    }
}

struct BookMetadataEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var readingStore: ReadingStore
    @Environment(\.dismiss) private var dismiss

    let item: LibraryItem

    @State private var title: String
    @State private var isCoverFileImporterPresented = false
    @State private var photoSelection: PhotosPickerItem?

    init(item: LibraryItem) {
        self.item = item
        _title = State(initialValue: item.displayName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("书籍名称") {
                    TextField("名称", text: $title)
                    Button("保存名称") {
                        store.rename(item, to: title)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("书籍封面") {
                    HStack(spacing: 14) {
                        FileThumbnailView(item: item, size: CGSize(width: 92, height: 136))
                            .frame(width: 92, height: 136)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                isCoverFileImporterPresented = true
                            } label: {
                                Label("从文件选择封面", systemImage: "folder")
                            }
                            PhotosPicker(selection: $photoSelection, matching: .images) {
                                Label("从相册选择封面", systemImage: "photo")
                            }
                        }
                    }
                    Text("没有封面时，鱼饼会自动用书名生成一张封面；你补充封面后书架会切换为正式书籍封面。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑书籍资料")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isCoverFileImporterPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                importCover(result)
            }
            .onChange(of: photoSelection) { _, selection in
                guard let selection else { return }
                Task { @MainActor in
                    if let data = try? await selection.loadTransferable(type: Data.self) {
                        readingStore.saveCover(data, for: item)
                    }
                    photoSelection = nil
                }
            }
        }
        .frame(minWidth: 380, minHeight: 420)
    }

    private func importCover(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        readingStore.saveCover(data, for: item)
    }
}

private struct ReaderFormatGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("可阅读格式") {
                    formatRow("TXT", detail: "自动识别 UTF-8、UTF-16、GBK/GB18030；支持自动分章和手动封面。", symbol: "doc.plaintext")
                    formatRow("EPUB", detail: "读取书名、目录、正文顺序与内嵌封面。", symbol: "books.vertical")
                    formatRow("MOBI / AZW3", detail: "读取无 DRM 的 Kindle 文本，并在本机自动分章。", symbol: "book.closed")
                    formatRow("DOC / DOCX", detail: "提取 Word 正文后自动识别章节；复杂版式会转换为纯文本。", symbol: "doc.richtext")
                    formatRow("PDF", detail: "使用系统 PDF 阅读器保留原页面、图片和排版。", symbol: "doc.text.image")
                }

                Section("Apple Watch") {
                    Label("手机会先把电子书转换为带章节和封面的离线书籍包，再传到手表。", systemImage: "applewatch.radiowaves.left.and.right")
                    Label("手表无需连接手机即可选章、阅读和记录进度。", systemImage: "checkmark.circle")
                }

                Section("格式限制") {
                    Label("受 DRM、密码或平台账号保护的电子书无法读取。", systemImage: "lock")
                    Label("扫描版 PDF 没有可提取文字，但仍能按原页面阅读。", systemImage: "viewfinder")
                }
            }
            .navigationTitle("阅读格式")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func formatRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct GalleryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var query = ""

    private var photos: [LibraryItem] {
        store.items(of: .photo)
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted(by: .date)
    }

    var body: some View {
        LibraryGridContent(
            items: photos,
            emptyTitle: "图库是空的",
            emptyMessage: "从系统照片或文件中选择图片。",
            emptySymbol: "photo.on.rectangle.angled",
            importAction: AnyView(LibraryImportMenu(title: "添加照片", photoScope: .images, prominent: true))
        )
        .navigationTitle("图库")
        .searchable(text: $query, prompt: "搜索照片")
        .toolbar {
            LibraryImportMenu(title: "添加", photoScope: .images)
                .labelStyle(.iconOnly)
        }
    }
}

struct FavoriteLibraryView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        LibraryGridContent(
            items: store.favorites.sorted(by: .date),
            emptyTitle: "还没有收藏",
            emptyMessage: "长按或右键点按项目即可加入收藏。",
            emptySymbol: "star",
            importAction: nil
        )
        .navigationTitle("收藏")
    }
}

struct LibraryGridContent: View {
    let items: [LibraryItem]
    let emptyTitle: String
    let emptyMessage: String
    let emptySymbol: String
    let importAction: AnyView?

    var body: some View {
        if items.isEmpty {
            ContentUnavailablePanel(
                title: emptyTitle,
                message: emptyMessage,
                symbol: emptySymbol,
                action: importAction
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 230), spacing: 16)], spacing: 20) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            LibraryItemCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: YuBingMetrics.contentMaxWidth)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
