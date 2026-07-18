#if os(iOS)
import SwiftUI

struct WatchTransferView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var transfer: WatchTransferService
    @State private var selectedPaths: Set<String> = []
    @State private var query = ""

    private var compatibleItems: [LibraryItem] {
        store.items
            .filter { !$0.isDirectory && $0.isWatchCompatible }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted(by: .date)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: transfer.isPaired && transfer.isWatchAppInstalled ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                        .font(.title2)
                        .foregroundStyle(transfer.isPaired && transfer.isWatchAppInstalled ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(transfer.lastStatus)
                            .font(.headline)
                        Text("传输会在后台完成，文件随后可在手表上离线使用。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let progress = transfer.overallProgress {
                            ProgressView(value: progress)
                                .tint(.cyan)
                            Text("\(transfer.activeTransferTitle ?? "正在传输") · \(Int(progress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("选择要传输的文件") {
                if compatibleItems.isEmpty {
                    ContentUnavailableView(
                        "没有兼容文件",
                        systemImage: "applewatch",
                        description: Text("支持 TXT、EPUB、MOBI、AZW3、DOC、DOCX、PDF、图片与影音文件。")
                    )
                } else {
                    ForEach(compatibleItems) { item in
                        Button {
                            if selectedPaths.contains(item.relativePath) {
                                selectedPaths.remove(item.relativePath)
                            } else {
                                selectedPaths.insert(item.relativePath)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedPaths.contains(item.relativePath) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedPaths.contains(item.relativePath) ? .blue : .secondary)
                                LibraryItemRow(item: item)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !transfer.watchItems.isEmpty {
                Section("手表上的资料库") {
                    ForEach(transfer.watchItems) { item in
                        HStack {
                            Image(systemName: symbol(for: item.kind))
                                .foregroundStyle(.secondary)
                            Text(item.name)
                                .lineLimit(1)
                            Spacer()
                            Text(item.byteCount.formattedFileSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("传到 Watch")
        .searchable(text: $query, prompt: "搜索兼容文件")
        .safeAreaInset(edge: .bottom) {
            Button {
                transfer.send(store.items.filter { selectedPaths.contains($0.relativePath) })
                selectedPaths.removeAll()
            } label: {
                Label(selectedPaths.isEmpty ? "选择文件" : "传输 \(selectedPaths.count) 个文件", systemImage: "applewatch.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton(prominent: true)
            .disabled(selectedPaths.isEmpty || !transfer.isPaired || !transfer.isWatchAppInstalled)
            .padding()
        }
    }

    private func symbol(for rawKind: String) -> String {
        LibraryKind(rawValue: rawKind)?.symbol ?? "doc"
    }
}
#endif
