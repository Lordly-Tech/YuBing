import SwiftUI

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

struct ReadingLibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var filter: ReadingFilter = .all
    @State private var query = ""

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
        LibraryGridContent(
            items: items,
            emptyTitle: "还没有书",
            emptyMessage: "导入 TXT、Markdown、EPUB、PDF 或漫画文件。",
            emptySymbol: "books.vertical",
            importAction: AnyView(FileImportButton(title: "导入书籍", prominent: true))
        )
        .navigationTitle("阅读")
        .searchable(text: $query, prompt: "搜索书名")
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("类型", selection: $filter) {
                ForEach(ReadingFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .toolbar { FileImportButton(title: "导入").labelStyle(.iconOnly) }
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
            importAction: AnyView(PhotoImportButton())
        )
        .navigationTitle("图库")
        .searchable(text: $query, prompt: "搜索照片")
        .toolbar {
            ToolbarItemGroup {
                PhotoImportButton().labelStyle(.iconOnly)
                FileImportButton(title: "导入").labelStyle(.iconOnly)
            }
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

