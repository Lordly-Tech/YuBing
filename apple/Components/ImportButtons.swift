import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import MediaPlayer
import UIKit
#endif

enum PhotoImportScope {
    case images
    case videos
    case media

    var filter: PHPickerFilter {
        switch self {
        case .images: .images
        case .videos: .videos
        case .media: .any(of: [.images, .videos])
        }
    }

    var title: String {
        switch self {
        case .images: AppLocalization.string("从相册选择照片")
        case .videos: AppLocalization.string("从相册选择视频")
        case .media: AppLocalization.string("从相册选择照片或视频")
        }
    }
}

struct FileImportButton: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var isImporterPresented = false

    var destination: URL?
    var title = "导入文件"
    var prominent = false

    var body: some View {
        Button {
            isImporterPresented = true
        } label: {
            Label(AppLocalization.string(title), systemImage: "square.and.arrow.down")
        }
        .adaptiveGlassButton(prominent: prominent)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                store.importFiles(urls, into: destination)
            case .failure(let error):
                store.alert = LibraryAlert(title: "无法导入", message: error.localizedDescription)
            }
        }
    }
}

struct PhotoImportButton: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var selection: [PhotosPickerItem] = []

    var destination: URL?

    var body: some View {
        PhotosPicker(selection: $selection, maxSelectionCount: 0, matching: .images) {
            Label("从照片导入", systemImage: "photo.badge.plus")
        }
        .adaptiveGlassButton()
        .onChange(of: selection) { _, newItems in
            Task { @MainActor in
                await importPickerItems(newItems, into: destination, store: store)
                selection.removeAll()
            }
        }
    }
}

struct LibraryImportMenu: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var wifiTransfer: WiFiTransferService
    @State private var isFileImporterPresented = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsPhotoPicker = false
    @State private var showsWiFiTransfer = false

    var destination: URL?
    var title = "添加"
    var photoScope: PhotoImportScope = .media
    var prominent = false

    var body: some View {
        Menu {
            Button {
                isFileImporterPresented = true
            } label: {
                Label("从文件选择", systemImage: "folder")
            }

            Button {
                showsPhotoPicker = true
            } label: {
                Label(photoScope.title, systemImage: "photo.on.rectangle.angled")
            }

            Button {
                showsWiFiTransfer = true
            } label: {
                Label("同一 Wi-Fi 传输", systemImage: "wifi")
            }
        } label: {
            Label(AppLocalization.string(title), systemImage: "plus")
        }
        .adaptiveGlassButton(prominent: prominent)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                store.importFiles(urls, into: destination)
            case .failure(let error):
                store.alert = LibraryAlert(title: "无法导入", message: error.localizedDescription)
            }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoSelection, maxSelectionCount: 0, matching: photoScope.filter)
        .onChange(of: photoSelection) { _, newItems in
            Task { @MainActor in
                await importPickerItems(newItems, into: destination, store: store)
                photoSelection.removeAll()
            }
        }
        .sheet(isPresented: $showsWiFiTransfer) {
            WiFiTransferPanel()
                .environmentObject(wifiTransfer)
        }
    }
}

struct WiFiTransferPanel: View {
    @EnvironmentObject private var transfer: WiFiTransferService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: transfer.isRunning ? "wifi" : "wifi.slash")
                    .font(.system(size: 54))
                    .foregroundStyle(transfer.isRunning ? .green : .secondary)
                Text(AppLocalization.string(transfer.status))
                    .font(.headline)
                if let address = transfer.address {
                    Text(address)
                        .font(.title3.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                    ShareLink(item: address) {
                        Label("分享地址", systemImage: "square.and.arrow.up")
                    }
                }
                if let progress = transfer.uploadProgress {
                    VStack(alignment: .leading, spacing: 7) {
                        ProgressView(value: progress)
                            .tint(.pink)
                        HStack {
                            Text("正在传输")
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Button {
                    if transfer.isRunning {
                        transfer.stop()
                    } else {
                        transfer.start()
                    }
                } label: {
                    if transfer.isStarting {
                        ProgressView()
                    } else {
                        Label(transfer.isRunning ? "停止传输" : "开始传输", systemImage: transfer.isRunning ? "stop.fill" : "play.fill")
                    }
                }
                .disabled(transfer.isStarting)
                .adaptiveGlassButton(prominent: !transfer.isRunning)
            }
            .padding(28)
            .frame(minWidth: 340, minHeight: 300)
            .navigationTitle("Wi-Fi 传输")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}

private struct ImportedPickerFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .data) { received in
            let fileExtension = received.file.pathExtension
            let name = fileExtension.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(fileExtension)"
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

@MainActor
private func importPickerItems(
    _ items: [PhotosPickerItem],
    into destination: URL?,
    store: LibraryStore
) async {
    for item in items {
        let type = item.supportedContentTypes.first
        let fileExtension = type?.preferredFilenameExtension ?? "jpg"
        let stem = item.itemIdentifier?
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") ?? UUID().uuidString
        let suggestedName = "\(stem).\(fileExtension)"

        if let file = try? await item.loadTransferable(type: ImportedPickerFile.self) {
            store.importFile(file.url, suggestedName: suggestedName, into: destination)
            try? FileManager.default.removeItem(at: file.url)
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            store.importData(data, suggestedName: suggestedName, into: destination)
        }
    }
}

/// Import entry point for the music page: file picker, system music library
/// scan and Wi-Fi transfer in one menu.
struct MusicImportMenu: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var wifiTransfer: WiFiTransferService
    @State private var isFileImporterPresented = false
    @State private var showsWiFiTransfer = false
    #if os(iOS)
    @State private var systemImportProgress: SystemMusicImportProgress?
    #endif

    var title = "添加"
    var prominent = false

    var body: some View {
        Menu {
            Button {
                isFileImporterPresented = true
            } label: {
                Label("从文件选择", systemImage: "folder")
            }

            #if os(iOS)
            Button {
                Task { await importSystemMusic() }
            } label: {
                Label("从音乐库导入", systemImage: "music.note.house")
            }
            #endif

            Button {
                showsWiFiTransfer = true
            } label: {
                Label("同一 Wi-Fi 传输", systemImage: "wifi")
            }
        } label: {
            menuLabel
        }
        .adaptiveGlassButton(prominent: prominent)
        .disabled(isSystemImportRunning)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                store.importFiles(urls)
            case .failure(let error):
                store.alert = LibraryAlert(title: "无法导入", message: error.localizedDescription)
            }
        }
        .sheet(isPresented: $showsWiFiTransfer) {
            WiFiTransferPanel()
                .environmentObject(wifiTransfer)
        }
    }

    private var isSystemImportRunning: Bool {
        #if os(iOS)
        systemImportProgress != nil
        #else
        false
        #endif
    }

    @ViewBuilder
    private var menuLabel: some View {
        #if os(iOS)
        if let systemImportProgress {
            Label {
                Text(verbatim: "\(systemImportProgress.completed)/\(systemImportProgress.total)")
                    .monospacedDigit()
            } icon: {
                ProgressView()
            }
        } else {
            Label(AppLocalization.string(title), systemImage: "plus")
        }
        #else
        Label(AppLocalization.string(title), systemImage: "plus")
        #endif
    }

    #if os(iOS)
    @MainActor
    private func importSystemMusic() async {
        guard systemImportProgress == nil else { return }
        systemImportProgress = SystemMusicImportProgress(completed: 0, total: 0)
        defer { systemImportProgress = nil }

        let summary = await SystemMusicLibraryImporter.importAllSongs(into: store) { progress in
            systemImportProgress = progress
        }
        store.alert = summary.alert
    }
    #endif
}

#if os(iOS)
struct SystemMusicImportProgress: Equatable {
    var completed: Int
    var total: Int
}

enum SystemMusicLibraryAccess {
    @MainActor
    static func requestAuthorizationIfNeeded() async -> MPMediaLibraryAuthorizationStatus {
        let current = MPMediaLibrary.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

/// Copies songs out of the system music library.
///
/// `MPMediaItem.assetURL` is an `ipod-library://` URL, so it cannot be copied
/// with `FileManager`. Every track is re-exported to an `.m4a` file inside the
/// app library instead, which is also what keeps the imported file inside
/// `LibraryItem.musicExtensions` so it shows up on the music page.
enum SystemMusicLibraryImporter {
    struct Summary {
        var imported = 0
        var duplicates = 0
        var protectedItems = 0
        var failed = 0

        var alert: LibraryAlert? {
            guard imported > 0 else {
                if protectedItems > 0 || failed > 0 {
                    return LibraryAlert(
                        title: "没有可导入的歌曲",
                        message: "云端或受 DRM 保护的歌曲无法导出，请先在系统音乐 App 中下载无保护文件。"
                    )
                }
                if duplicates > 0 {
                    return LibraryAlert(title: "音乐库已是最新", message: "系统音乐库中的歌曲都已导入。")
                }
                return LibraryAlert(title: "没有可导入的歌曲", message: "系统音乐库中没有歌曲。")
            }

            var details = [count("已导入 %lld 首", imported)]
            if duplicates > 0 { details.append(count("跳过 %lld 首重复", duplicates)) }
            if protectedItems > 0 { details.append(count("跳过 %lld 首受保护", protectedItems)) }
            if failed > 0 { details.append(count("%lld 首导出失败", failed)) }
            return LibraryAlert(
                title: "导入完成",
                message: details.joined(separator: "、") + "。"
            )
        }

        private func count(_ key: String, _ value: Int) -> String {
            String(format: AppLocalization.string(key), value)
        }
    }

    @MainActor
    static func importAllSongs(
        into store: LibraryStore,
        progress: (SystemMusicImportProgress) -> Void
    ) async -> Summary {
        var summary = Summary()

        let status = await SystemMusicLibraryAccess.requestAuthorizationIfNeeded()
        guard status == .authorized else {
            store.alert = LibraryAlert(
                title: "无法访问音乐库",
                message: "请在系统设置中允许鱼饼访问媒体与 Apple Music。"
            )
            return summary
        }

        let mediaItems = MPMediaQuery.songs().items ?? []
        var existingNames = Set(
            store.items(of: .music).map { $0.name.lowercased() }
        )
        progress(SystemMusicImportProgress(completed: 0, total: mediaItems.count))

        for (index, mediaItem) in mediaItems.enumerated() {
            defer {
                progress(
                    SystemMusicImportProgress(
                        completed: index + 1,
                        total: mediaItems.count
                    )
                )
            }

            guard !mediaItem.hasProtectedAsset, let assetURL = mediaItem.assetURL else {
                summary.protectedItems += 1
                continue
            }

            let fileName = "\(displayName(for: mediaItem, fallback: assetURL)).m4a"
            guard !existingNames.contains(fileName.lowercased()) else {
                summary.duplicates += 1
                continue
            }

            let destination = store.reserveImportDestination(named: fileName)
            do {
                try await export(mediaItem, from: assetURL, to: destination)
                existingNames.insert(destination.lastPathComponent.lowercased())
                summary.imported += 1
            } catch {
                try? FileManager.default.removeItem(at: destination)
                summary.failed += 1
            }
        }

        store.refresh()
        return summary
    }

    private static func displayName(for mediaItem: MPMediaItem, fallback: URL) -> String {
        let title = mediaItem.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = mediaItem.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: String
        if let title, !title.isEmpty {
            base = (artist?.isEmpty == false) ? "\(artist!) - \(title)" : title
        } else {
            base = fallback.deletingPathExtension().lastPathComponent
        }
        return sanitized(base)
    }

    private static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? UUID().uuidString : String(cleaned.prefix(120))
    }

    private static func export(
        _ mediaItem: MPMediaItem,
        from assetURL: URL,
        to destination: URL
    ) async throws {
        let asset = AVURLAsset(url: assetURL)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw SystemMusicImportError.unsupportedAsset
        }
        session.metadata = metadata(for: mediaItem)
        try await session.export(to: destination, as: .m4a)
    }

    private static func metadata(for mediaItem: MPMediaItem) -> [AVMetadataItem] {
        var values: [(AVMetadataIdentifier, Any)] = []
        if let title = mediaItem.title { values.append((.commonIdentifierTitle, title)) }
        if let artist = mediaItem.artist { values.append((.commonIdentifierArtist, artist)) }
        if let album = mediaItem.albumTitle { values.append((.commonIdentifierAlbumName, album)) }
        if let artwork = mediaItem.artwork?
            .image(at: CGSize(width: 600, height: 600))?
            .pngData() {
            values.append((.commonIdentifierArtwork, artwork))
        }

        return values.map { identifier, value in
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as? NSCopying & NSObjectProtocol
            return item
        }
    }
}

private enum SystemMusicImportError: Error {
    case unsupportedAsset
}
#endif
