import SwiftUI

struct WatchFileBrowserView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    var folderURL: URL?

    @State private var query = ""
    @State private var editorMode: WatchNameEditor.Mode?
    @State private var movingItem: WatchLibraryItem?
    @State private var deletingItem: WatchLibraryItem?

    private var folder: URL { folderURL ?? store.libraryURL }
    private var items: [WatchLibraryItem] {
        store.children(of: folder).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if items.isEmpty, query.isEmpty {
                ContentUnavailableView(
                    folderURL == nil ? "还没有文件" : "空文件夹",
                    systemImage: "folder",
                    description: Text(folderURL == nil ? "请在 iPhone 的 鱼饼 中传输文件。" : "可在这里创建子文件夹。")
                )
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink {
                            WatchItemDestination(item: item)
                        } label: {
                            WatchFileRow(item: item)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.toggleFavorite(item)
                            } label: {
                                Label("收藏", systemImage: store.isFavorite(item) ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deletingItem = item } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button { editorMode = .rename(item) } label: { Label("重命名", systemImage: "pencil") }
                            Button { movingItem = item } label: { Label("移动", systemImage: "folder") }
                            Button(role: .destructive) { deletingItem = item } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .navigationTitle(folderURL?.lastPathComponent ?? "文件")
        .searchable(text: $query, prompt: "搜索")
        .toolbar {
            Button {
                editorMode = .newFolder(folder)
            } label: {
                Label("新建文件夹", systemImage: "folder.badge.plus")
            }
        }
        .sheet(item: $editorMode) { mode in
            WatchNameEditor(mode: mode)
        }
        .sheet(item: $movingItem) { item in
            WatchMoveDestinationView(item: item)
        }
        .confirmationDialog("删除这个项目？", isPresented: deletePresented) {
            Button("删除", role: .destructive) {
                if let deletingItem { store.delete(deletingItem) }
                deletingItem = nil
            }
            Button("取消", role: .cancel) { deletingItem = nil }
        }
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } })
    }
}

struct WatchNameEditor: View {
    enum Mode: Identifiable {
        case newFolder(URL)
        case rename(WatchLibraryItem)

        var id: String {
            switch self {
            case .newFolder(let url): "new-\(url.path)"
            case .rename(let item): "rename-\(item.id)"
            }
        }
    }

    @EnvironmentObject private var store: WatchLibraryStore
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        switch mode {
                        case .newFolder(let folder): store.createFolder(named: name, in: folder)
                        case .rename(let item): store.rename(item, to: name)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if case .rename(let item) = mode { name = item.isDirectory ? item.name : item.displayName }
        }
    }

    private var title: String {
        if case .newFolder = mode { return "新建文件夹" }
        return "重命名"
    }
}

private struct WatchMoveDestinationView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @Environment(\.dismiss) private var dismiss
    let item: WatchLibraryItem

    private var folders: [WatchLibraryItem] {
        store.items.filter {
            $0.isDirectory && $0.url != item.url && !$0.url.path.hasPrefix(item.url.path + "/")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button { move(to: store.libraryURL) } label: { Label("资料库", systemImage: "internaldrive") }
                ForEach(folders) { folder in
                    Button { move(to: folder.url) } label: { Label(folder.relativePath, systemImage: "folder") }
                }
            }
            .navigationTitle("移动到")
        }
    }

    private func move(to folder: URL) {
        store.move(item, to: folder)
        dismiss()
    }
}

