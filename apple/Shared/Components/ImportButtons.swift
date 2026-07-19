import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import MediaPlayer
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

            PhotosPicker(
                selection: $photoSelection,
                maxSelectionCount: 0,
                matching: photoScope.filter
            ) {
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

private struct WiFiTransferPanel: View {
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
                Button {
                    transfer.isRunning ? transfer.stop() : transfer.start()
                } label: {
                    Label(transfer.isRunning ? "停止传输" : "开始传输", systemImage: transfer.isRunning ? "stop.fill" : "play.fill")
                        .frame(minWidth: 180)
                }
                .adaptiveGlassButton(prominent: !transfer.isRunning)
            }
            .padding(28)
            .frame(minWidth: 340, minHeight: 300)
            .navigationTitle("Wi-Fi 传输")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .onDisappear { transfer.stop() }
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

#if os(iOS)
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

struct SystemMusicImportButton: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var isImporting = false

    var body: some View {
        Button {
            Task { await importSystemMusic() }
        } label: {
            if isImporting {
                ProgressView()
            } else {
                Label("扫描系统音乐库", systemImage: "music.note.house")
            }
        }
        .disabled(isImporting)
        .help("扫描本机 iTunes / iPod 音乐库")
    }

    @MainActor
    private func importSystemMusic() async {
        isImporting = true
        defer { isImporting = false }
        let status = await SystemMusicLibraryAccess.requestAuthorizationIfNeeded()
        guard status == .authorized else {
            store.alert = LibraryAlert(title: "无法访问音乐库", message: "请在系统设置中允许鱼饼访问媒体与 Apple Music。")
            return
        }

        let items = MPMediaQuery.songs().items ?? []
        var imported = 0
        var skipped = 0
        for mediaItem in items {
            guard !mediaItem.hasProtectedAsset, let url = mediaItem.assetURL else {
                skipped += 1
                continue
            }
            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let rawName = mediaItem.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (rawName?.isEmpty == false ? rawName : nil) ?? url.deletingPathExtension().lastPathComponent
            let safeTitle = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            store.importFile(url, suggestedName: "\(safeTitle).\(ext)")
            imported += 1
        }
        if imported == 0 {
            store.alert = LibraryAlert(
                title: "没有可导入的本地歌曲",
                message: skipped > 0 ? "云端或受 DRM 保护的歌曲不能复制，请先在系统音乐 App 中下载无保护文件。" : "系统音乐库中没有歌曲。"
            )
        } else if skipped > 0 {
            store.alert = LibraryAlert(title: "导入完成", message: "已导入 \(imported) 首，跳过 \(skipped) 首云端或受保护歌曲。")
        }
    }
}
#endif
