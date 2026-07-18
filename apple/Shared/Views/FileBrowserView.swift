import SwiftUI

private enum FileDisplayMode: String, CaseIterable {
    case list
    case grid

    var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }
}

struct FileBrowserView: View {
    @EnvironmentObject private var store: LibraryStore

    var folderURL: URL?

    @State private var query = ""
    @State private var sort: LibrarySort = .name
    @State private var displayMode: FileDisplayMode = .list
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var renamingItem: LibraryItem?
    @State private var renameText = ""
    @State private var deletingItem: LibraryItem?
    @State private var movingItem: LibraryItem?
    @State private var editingBook: LibraryItem?

    private var currentFolder: URL { folderURL ?? store.libraryURL }

    private var visibleItems: [LibraryItem] {
        store.children(of: currentFolder)
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted(by: sort)
    }

    var body: some View {
        Group {
            if visibleItems.isEmpty, query.isEmpty {
                ContentUnavailablePanel(
                    title: folderURL == nil ? "资料库是空的" : "文件夹是空的",
                    message: "从文件导入内容，或新建文件夹。",
                    symbol: "folder",
                    action: AnyView(FileImportButton(destination: currentFolder, title: "导入文件", prominent: true))
                )
            } else if visibleItems.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if displayMode == .grid {
                grid
            } else {
                list
            }
        }
        .navigationTitle(folderURL?.lastPathComponent ?? "文件")
        .searchable(text: $query, prompt: "搜索当前文件夹")
        .toolbar { toolbarContent }
        .alert("新建文件夹", isPresented: $isCreatingFolder) {
            TextField("名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") {
                store.createFolder(named: newFolderName, in: currentFolder)
                newFolderName = ""
            }
        } message: {
            Text("文件夹会创建在“\(currentFolder.lastPathComponent)”中。")
        }
        .alert("重命名", isPresented: renamePresented) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renamingItem = nil }
            Button("完成") {
                if let item = renamingItem { store.rename(item, to: renameText) }
                renamingItem = nil
            }
        }
        .confirmationDialog(
            deletingItem.map { "删除“\($0.displayName)”？" } ?? "删除项目？",
            isPresented: deletePresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let deletingItem { store.delete(deletingItem) }
                deletingItem = nil
            }
            Button("取消", role: .cancel) { deletingItem = nil }
        } message: {
            Text("此操作无法撤销。")
        }
        .sheet(item: $movingItem) { item in
            MoveDestinationView(item: item)
        }
        .sheet(item: $editingBook) { item in
            BookMetadataEditor(item: item)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 230), spacing: 16)], spacing: 20) {
                ForEach(visibleItems) { item in
                    NavigationLink(value: item) {
                        LibraryItemCard(
                            item: item,
                            onEditBook: item.kind == .novel || item.kind == .comic ? { editingBook = item } : nil,
                            onRename: { beginRename(item) },
                            onMove: { movingItem = item },
                            onDelete: { deletingItem = item }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: YuBingMetrics.contentMaxWidth)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleItems) { item in
                    NavigationLink(value: item) {
                        LibraryItemRow(
                            item: item,
                            onEditBook: item.kind == .novel || item.kind == .comic ? { editingBook = item } : nil,
                            onRename: { beginRename(item) },
                            onMove: { movingItem = item },
                            onDelete: { deletingItem = item }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 80)
                }
            }
            .frame(maxWidth: YuBingMetrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Picker("排序", selection: $sort) {
                    ForEach(LibrarySort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Label("排序", systemImage: "arrow.up.arrow.down")
            }
            .help("排序")

            Picker("显示方式", selection: $displayMode) {
                ForEach(FileDisplayMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 82)

            Button {
                isCreatingFolder = true
            } label: {
                Label("新建文件夹", systemImage: "folder.badge.plus")
            }
            .help("新建文件夹")

            FileImportButton(destination: currentFolder, title: "导入")
                .labelStyle(.iconOnly)
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renamingItem != nil },
            set: { if !$0 { renamingItem = nil } }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deletingItem != nil },
            set: { if !$0 { deletingItem = nil } }
        )
    }

    private func beginRename(_ item: LibraryItem) {
        renamingItem = item
        renameText = item.isDirectory ? item.name : item.displayName
    }
}

private struct MoveDestinationView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem

    private var folders: [LibraryItem] {
        store.items.filter { candidate in
            candidate.isDirectory &&
            candidate.url != item.url &&
            !candidate.url.standardizedFileURL.path.hasPrefix(item.url.standardizedFileURL.path + "/")
        }
        .sorted(by: .name)
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    store.move(item, to: store.libraryURL)
                    dismiss()
                } label: {
                    Label("资料库根目录", systemImage: "internaldrive")
                }
                ForEach(folders) { folder in
                    Button {
                        store.move(item, to: folder.url)
                        dismiss()
                    } label: {
                        Label(folder.relativePath, systemImage: "folder")
                    }
                }
            }
            .navigationTitle("移动“\(item.displayName)”")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 360)
    }
}
