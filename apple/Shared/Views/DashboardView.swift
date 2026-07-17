import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: LibraryStore

    private var recentItems: [LibraryItem] {
        let stored = store.recents
        if !stored.isEmpty { return Array(stored.prefix(8)) }
        return Array(store.items.filter { !$0.isDirectory }.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(8))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header
                metrics

                if !recentItems.isEmpty {
                    sectionHeader("最近打开", symbol: "clock")
                    recentGrid
                }

                sectionHeader("资料库", symbol: "square.stack.3d.up")
                libraryOverview

                #if os(iOS)
                watchSummary
                #endif
            }
            .frame(maxWidth: YuBingMetrics.contentMaxWidth, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("首页")
        .toolbar {
            ToolbarItemGroup {
                PhotoImportButton()
                    .labelStyle(.iconOnly)
                    .help("从照片导入")
                FileImportButton(title: "导入", prominent: true)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("鱼饼")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("书、声音、照片和文件，都在这里。")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            FileImportButton(title: "导入文件", prominent: true)
                .fixedSize()
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
            MetricTile(title: "小说与漫画", value: "\(store.items(of: .novel).count + store.items(of: .comic).count)", symbol: "books.vertical", tint: .blue)
            MetricTile(title: "音乐", value: "\(store.items(of: .music).count)", symbol: "waveform", tint: .pink)
            MetricTile(title: "照片", value: "\(store.items(of: .photo).count)", symbol: "photo.on.rectangle", tint: .green)
            MetricTile(title: "已用空间", value: store.totalBytes.formattedFileSize, symbol: "internaldrive", tint: .orange)
        }
    }

    private var recentGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 14)], spacing: 18) {
            ForEach(recentItems) { item in
                NavigationLink(value: item) {
                    LibraryItemCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var libraryOverview: some View {
        VStack(spacing: 0) {
            overviewRow(section: .reading, count: store.items(of: .novel).count + store.items(of: .comic).count, tint: .blue)
            Divider().padding(.leading, 52)
            overviewRow(section: .music, count: store.items(of: .music).count, tint: .pink)
            Divider().padding(.leading, 52)
            overviewRow(section: .gallery, count: store.items(of: .photo).count, tint: .green)
            Divider().padding(.leading, 52)
            overviewRow(section: .files, count: store.items.count, tint: .orange)
        }
        .padding(.horizontal, 14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: YuBingMetrics.compactCornerRadius, style: .continuous))
    }

    private func overviewRow(section: AppSection, count: Int, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbol)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            Text(section.title)
                .font(.body.weight(.medium))
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 13)
    }

    #if os(iOS)
    @ViewBuilder
    private var watchSummary: some View {
        WatchDashboardSummary()
    }
    #endif

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.semibold))
    }
}

#if os(iOS)
private struct WatchDashboardSummary: View {
    @EnvironmentObject private var transfer: WatchTransferService

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "applewatch")
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 42, height: 42)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text("Apple Watch")
                    .font(.headline)
                Text(transfer.lastStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if transfer.pendingCount > 0 {
                Text("\(transfer.pendingCount)")
                    .font(.caption.weight(.bold))
                    .padding(7)
                    .adaptiveGlass(in: Circle())
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: YuBingMetrics.compactCornerRadius))
    }
}
#endif

