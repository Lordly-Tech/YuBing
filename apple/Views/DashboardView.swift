import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var readingStore: ReadingStore
    @Environment(AudioPlayerController.self) private var player

    private var recentItems: [LibraryItem] {
        let stored = store.recents
        if !stored.isEmpty { return Array(stored.prefix(8)) }
        return Array(store.items.filter { !$0.isDirectory }.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(8))
    }

    private var mediaCount: Int {
        store.items(of: .music).count + store.items(of: .video).count
    }

    private var totalReadingTime: TimeInterval {
        readingStore.records.values.reduce(0) { $0 + $1.totalReadingTime }
    }

    private var touchedBookCount: Int {
        readingStore.records.values.filter { $0.totalReadingTime > 0 || $0.chapterProgress > 0 }.count
    }

    private var playedSongCount: Int {
        player.totalListeningTime > 0 ? store.items(of: .music).count : 0
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header
                metrics

                #if os(iOS)
                watchSummary
                #endif

                if !recentItems.isEmpty {
                    sectionHeader("最近打开", symbol: "clock")
                    recentList
                }

                timeSummaryGrid
            }
            .frame(maxWidth: YuBingMetrics.contentMaxWidth, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("首页")
        .toolbar {
            ToolbarItem {
                LibraryImportMenu(title: "添加", photoScope: .media)
                    .labelStyle(.iconOnly)
                    .help("添加文件")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("🐟🍪！")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
            }
            Spacer(minLength: 16)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
            MetricTile(title: "小说与漫画", value: "\(store.items(of: .novel).count + store.items(of: .comic).count)", symbol: "books.vertical", tint: .blue)
            MetricTile(title: "媒体", value: "\(mediaCount)", symbol: "play.rectangle", tint: .pink)
            MetricTile(title: "照片", value: "\(store.items(of: .photo).count)", symbol: "photo.on.rectangle", tint: .green)
            MetricTile(title: "已用空间", value: store.totalBytes.formattedFileSize, symbol: "internaldrive", tint: .orange)
        }
    }

    private var recentList: some View {
        VStack(spacing: 0) {
            ForEach(Array(recentItems.prefix(6).enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: item) {
                    LibraryItemRow(item: item)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                if index + 1 < min(recentItems.count, 6) {
                    Divider().padding(.leading, 80)
                }
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: YuBingMetrics.compactCornerRadius, style: .continuous))
    }

    private var timeSummaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
            NavigationLink {
                ReadingTimeDetailView()
            } label: {
                readingTimeCard
            }
            .buttonStyle(.plain)

            NavigationLink {
                ListeningTimeDetailView()
            } label: {
                listeningTimeCard
            }
            .buttonStyle(.plain)
        }
    }

    private var readingTimeCard: some View {
        TimeSummaryCard(
            title: "阅读时长",
            subtitle: "所有设备累计",
            value: totalReadingTime.formattedReadingDuration,
            detail: touchedBookCount == 0 ? AppLocalization.string("还没有阅读记录") : "\(AppLocalization.string("已记录")) \(touchedBookCount) \(AppLocalization.string("本书"))",
            symbol: "book.pages.fill",
            tint: .blue,
            progress: min(max(totalReadingTime / (60 * 60 * 5), 0.08), 1)
        )
    }

    private var listeningTimeCard: some View {
        TimeSummaryCard(
            title: "听歌时长",
            subtitle: "本机累计播放",
            value: player.totalListeningTime.formattedReadingDuration,
            detail: playedSongCount == 0 ? AppLocalization.string("还没有听歌记录") : "\(store.items(of: .music).count) \(AppLocalization.string("首歌曲"))",
            symbol: "music.note",
            tint: .pink,
            progress: min(max(player.totalListeningTime / (60 * 60 * 5), 0.08), 1)
        )
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(AppLocalization.string(title), systemImage: symbol)
            .font(.title3.weight(.semibold))
    }

    #if os(iOS)
    @ViewBuilder
    private var watchSummary: some View {
        WatchDashboardSummary()
    }
    #endif
}

private struct TimeSummaryCard: View {
    let title: String
    let subtitle: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(AppLocalization.string(title))
                        .font(.title3.weight(.semibold))
                    Text(AppLocalization.string(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
            }

            ZStack {
                ReadingArcShape()
                    .stroke(.quaternary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                ReadingArcShape(progress: progress)
                    .stroke(.primary.opacity(0.86), style: StrokeStyle(lineWidth: 12, lineCap: .round))

                VStack(spacing: 4) {
                    Text(value)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 18)
            }
            .frame(height: 132)
        }
        .padding(18)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: YuBingMetrics.panelCornerRadius, style: .continuous))
    }
}

private struct ReadingTimeDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var readingStore: ReadingStore

    private var rows: [(LibraryItem, ReadingRecord)] {
        readingStore.records.compactMap { path, record in
            guard record.totalReadingTime > 0,
                  let item = store.items.first(where: { $0.relativePath == path }) else { return nil }
            return (item, record)
        }
        .sorted { $0.1.totalReadingTime > $1.1.totalReadingTime }
    }

    var body: some View {
        List {
            Section {
                ForEach(rows, id: \.0.id) { item, record in
                    LabeledContent(item.displayName, value: record.totalReadingTime.formattedReadingDuration)
                }
            } footer: {
                Text("只统计已经打开阅读过的书籍。")
            }
        }
        .navigationTitle("阅读时长")
    }
}

private struct ListeningTimeDetailView: View {
    @Environment(AudioPlayerController.self) private var player

    var body: some View {
        List {
            Section {
                LabeledContent("累计听歌时长", value: player.totalListeningTime.formattedReadingDuration)
            } footer: {
                Text("听歌时长会在本机播放时自动累计。")
            }
        }
        .navigationTitle("听歌时长")
    }
}

private struct ReadingArcShape: Shape {
    var progress: Double = 1

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height * 1.8) / 2
        let center = CGPoint(x: rect.midX, y: rect.maxY - 2)
        let start = Angle.degrees(198)
        let end = Angle.degrees(342 - (1 - min(max(progress, 0), 1)) * 144)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}

#if os(iOS)
private struct WatchDashboardSummary: View {
    @EnvironmentObject private var transfer: WatchTransferService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                    .frame(width: 42, height: 42)
                    .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Watch")
                        .font(.headline)
                    Text(AppLocalization.string(transfer.lastStatus))
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

            if let progress = transfer.overallProgress {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: progress)
                        .tint(.cyan)
                    HStack {
                        Text(transfer.activeTransferTitle ?? AppLocalization.string("正在传输"))
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: YuBingMetrics.compactCornerRadius))
    }
}
#endif
