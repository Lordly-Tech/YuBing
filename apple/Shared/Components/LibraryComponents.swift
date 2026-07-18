import SwiftUI

struct LibraryItemCard: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let item: LibraryItem
    var onEditBook: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onMove: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var thumbnailAspectRatio: CGFloat {
        switch item.kind {
        case .novel:
            return 0.68
        case .comic:
            return 0.74
        default:
            return 1.18
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FileThumbnailView(item: item)
                .frame(maxWidth: .infinity)
                .aspectRatio(thumbnailAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: YuBingMetrics.compactCornerRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if store.isFavorite(item) {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .padding(7)
                            .adaptiveGlass(in: Circle())
                            .padding(7)
                    }
                }

            Text(displayTitle)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 5) {
                if let artist = audioMetadata?.artist {
                    Text(artist)
                } else {
                    Text(item.kind.title)
                }
                Text("·")
                Text(audioMetadata?.album ?? (item.isDirectory ? "文件夹" : item.byteCount.formattedFileSize))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
        .contextMenu { contextActions }
    }

    private var audioMetadata: EmbeddedAudioMetadata? {
        player.metadataByPath[item.relativePath]
    }

    private var displayTitle: String {
        guard item.kind == .music else { return item.displayName }
        return audioMetadata?.title ?? item.displayName
    }

    @ViewBuilder
    private var contextActions: some View {
        Button {
            store.toggleFavorite(item)
        } label: {
            Label(store.isFavorite(item) ? "取消收藏" : "收藏", systemImage: store.isFavorite(item) ? "star.slash" : "star")
        }
        #if os(iOS)
        WatchSendContextButton(item: item)
        #endif
        ShareLink(item: item.url)
        if let onEditBook {
            Button(action: onEditBook) { Label("编辑书籍资料", systemImage: "book.closed") }
        }
        if let onRename {
            Button(action: onRename) { Label("重命名", systemImage: "pencil") }
        }
        if let onMove {
            Button(action: onMove) { Label("移动", systemImage: "folder") }
        }
        if let onDelete {
            Divider()
            Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
        }
    }
}

struct LibraryItemRow: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    let item: LibraryItem
    var onEditBook: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onMove: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnailView(item: item, size: CGSize(width: 52, height: 52))
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if store.isFavorite(item) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            Text(item.modifiedAt, format: .dateTime.month().day())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                store.toggleFavorite(item)
            } label: {
                Label(store.isFavorite(item) ? "取消收藏" : "收藏", systemImage: store.isFavorite(item) ? "star.slash" : "star")
            }
            #if os(iOS)
            WatchSendContextButton(item: item)
            #endif
            ShareLink(item: item.url)
            if let onEditBook {
                Button(action: onEditBook) { Label("编辑书籍资料", systemImage: "book.closed") }
            }
            if let onRename {
                Button(action: onRename) { Label("重命名", systemImage: "pencil") }
            }
            if let onMove {
                Button(action: onMove) { Label("移动", systemImage: "folder") }
            }
            if let onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
            }
        }
    }

    private var audioMetadata: EmbeddedAudioMetadata? {
        player.metadataByPath[item.relativePath]
    }

    private var displayTitle: String {
        guard item.kind == .music else { return item.displayName }
        return audioMetadata?.title ?? item.displayName
    }

    private var detailText: String {
        guard item.kind == .music else {
            return item.isDirectory ? item.kind.title : "\(item.kind.title) · \(item.byteCount.formattedFileSize)"
        }
        let details = [audioMetadata?.artist, audioMetadata?.album]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return details.isEmpty ? "影音 · \(item.byteCount.formattedFileSize)" : details.joined(separator: " · ")
    }
}

#if os(iOS)
private struct WatchSendContextButton: View {
    @EnvironmentObject private var watchTransfer: WatchTransferService
    let item: LibraryItem

    var body: some View {
        if item.isWatchCompatible {
            Button {
                watchTransfer.send([item])
            } label: {
                Label("发送到 Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
            }
        }
    }
}
#endif

struct ContentUnavailablePanel: View {
    let title: String
    let message: String
    let symbol: String
    var action: AnyView?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let action { action }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: YuBingMetrics.compactCornerRadius, style: .continuous))
    }
}

extension Int64 {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension TimeInterval {
    var formattedPlaybackTime: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
