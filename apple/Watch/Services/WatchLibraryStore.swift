import Combine
import Foundation
import WatchConnectivity

struct WatchLibraryAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class WatchLibraryStore: NSObject, ObservableObject {
    @Published private(set) var items: [WatchLibraryItem] = []
    @Published private(set) var favoritePaths: Set<String>
    @Published private(set) var recentPaths: [String]
    @Published private(set) var readingRecords: [String: WatchReaderRecord]
    @Published private(set) var transferStatus = "等待 iPhone 传输"
    @Published var alert: WatchLibraryAlert?

    let libraryURL: URL

    private let fileManager = FileManager.default
    private let favoritesKey = "folio.watch.favoritePaths"
    private let recentsKey = "folio.watch.recentPaths"
    private let readingRecordsKey = "folio.watch.readingRecords"
    private var session: WCSession?

    override init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        libraryURL = documents.appendingPathComponent("YuBing Watch Library", isDirectory: true)
        favoritePaths = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        recentPaths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        if let data = UserDefaults.standard.data(forKey: readingRecordsKey),
           let decoded = try? JSONDecoder().decode([String: WatchReaderRecord].self, from: data) {
            readingRecords = decoded
        } else {
            readingRecords = [:]
        }
        super.init()

        do {
            try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
            items = Self.scanLibrary(at: libraryURL)
        } catch {
            alert = WatchLibraryAlert(title: "无法打开资料库", message: error.localizedDescription)
        }

        if WCSession.isSupported() {
            let session = WCSession.default
            self.session = session
            session.delegate = self
            session.activate()
        }
    }

    var favorites: [WatchLibraryItem] {
        items.filter { favoritePaths.contains($0.relativePath) }
    }

    var recents: [WatchLibraryItem] {
        recentPaths.compactMap { path in items.first(where: { $0.relativePath == path }) }
    }

    var totalBytes: Int64 {
        items.filter { !$0.isDirectory }.reduce(0) { $0 + $1.byteCount }
    }

    func children(of folder: URL) -> [WatchLibraryItem] {
        items.filter { $0.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    func items(of kinds: Set<WatchLibraryKind>) -> [WatchLibraryItem] {
        items.filter { kinds.contains($0.kind) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func isFavorite(_ item: WatchLibraryItem) -> Bool {
        favoritePaths.contains(item.relativePath)
    }

    func toggleFavorite(_ item: WatchLibraryItem) {
        if favoritePaths.contains(item.relativePath) {
            favoritePaths.remove(item.relativePath)
        } else {
            favoritePaths.insert(item.relativePath)
        }
        persistState()
        objectWillChange.send()
        publishManifest()
    }

    func markOpened(_ item: WatchLibraryItem) {
        recentPaths.removeAll { $0 == item.relativePath }
        recentPaths.insert(item.relativePath, at: 0)
        recentPaths = Array(recentPaths.prefix(20))
        persistState()
        objectWillChange.send()
    }

    func readingRecord(
        bookID: String,
        initialChapterIndex: Int = 0,
        initialChapterProgress: Double = 0
    ) -> WatchReaderRecord {
        if let value = readingRecords[bookID] { return value }
        return WatchReaderRecord(
            chapterIndex: max(initialChapterIndex, 0),
            chapterProgress: min(max(initialChapterProgress, 0), 1),
            updatedAt: .now
        )
    }

    func updateReadingProgress(bookID: String, chapterIndex: Int, progress: Double) {
        var value = readingRecord(bookID: bookID)
        value.chapterIndex = max(chapterIndex, 0)
        value.chapterProgress = min(max(progress, 0), 1)
        value.updatedAt = .now
        readingRecords[bookID] = value
        persistState()
        publishManifest()
    }

    func addReadingTime(_ duration: TimeInterval, bookID: String) {
        guard duration.isFinite, duration > 0 else { return }
        var value = readingRecord(bookID: bookID)
        value.readingTime += min(duration, 90)
        value.updatedAt = .now
        readingRecords[bookID] = value
        persistState()
        publishManifest()
    }

    @discardableResult
    func addBookmark(bookID: String, chapterIndex: Int, chapterTitle: String, progress: Double) -> WatchReaderBookmark {
        var value = readingRecord(bookID: bookID)
        let bookmark = WatchReaderBookmark(
            id: UUID(),
            name: "\(chapterTitle) · \(Int(progress * 100))%",
            chapterIndex: chapterIndex,
            chapterProgress: min(max(progress, 0), 1),
            createdAt: .now
        )
        value.bookmarks.append(bookmark)
        value.updatedAt = .now
        readingRecords[bookID] = value
        persistState()
        publishManifest()
        return bookmark
    }

    func renameBookmark(_ bookmark: WatchReaderBookmark, to name: String, bookID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var value = readingRecord(bookID: bookID)
        guard let index = value.bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        value.bookmarks[index].name = trimmed
        value.updatedAt = .now
        readingRecords[bookID] = value
        persistState()
        publishManifest()
    }

    func deleteBookmark(_ bookmark: WatchReaderBookmark, bookID: String) {
        var value = readingRecord(bookID: bookID)
        value.bookmarks.removeAll { $0.id == bookmark.id }
        value.updatedAt = .now
        readingRecords[bookID] = value
        persistState()
        publishManifest()
    }

    func createFolder(named name: String, in folder: URL) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            alert = WatchLibraryAlert(title: "名称不可用", message: "请输入不含斜杠的名称。")
            return
        }
        do {
            let destination = uniqueDestination(in: folder, named: trimmed)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            refresh()
        } catch {
            alert = WatchLibraryAlert(title: "创建失败", message: error.localizedDescription)
        }
    }

    func rename(_ item: WatchLibraryItem, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            alert = WatchLibraryAlert(title: "名称不可用", message: "请输入不含斜杠的名称。")
            return
        }
        let finalName = item.isDirectory || (trimmed as NSString).pathExtension.isEmpty
            ? (item.isDirectory ? trimmed : "\(trimmed).\(item.fileExtension)")
            : trimmed
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(finalName, isDirectory: item.isDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else {
            alert = WatchLibraryAlert(title: "名称已存在", message: "当前文件夹已有同名项目。")
            return
        }
        do {
            let oldPrefix = item.relativePath
            try fileManager.moveItem(at: item.url, to: destination)
            replacePathPrefix(oldPrefix, with: relativePath(for: destination))
            refresh()
        } catch {
            alert = WatchLibraryAlert(title: "重命名失败", message: error.localizedDescription)
        }
    }

    func move(_ item: WatchLibraryItem, to folder: URL) {
        guard !folder.standardizedFileURL.path.hasPrefix(item.url.standardizedFileURL.path + "/") else { return }
        do {
            let oldPrefix = item.relativePath
            let destination = uniqueDestination(in: folder, named: item.name)
            try fileManager.moveItem(at: item.url, to: destination)
            replacePathPrefix(oldPrefix, with: relativePath(for: destination))
            refresh()
        } catch {
            alert = WatchLibraryAlert(title: "移动失败", message: error.localizedDescription)
        }
    }

    func delete(_ item: WatchLibraryItem) {
        let removedBookID = item.kind == .novel ? (try? WatchBookLoader.load(item).sourceID) : nil
        do {
            try fileManager.removeItem(at: item.url)
            favoritePaths = favoritePaths.filter { !$0.hasPrefix(item.relativePath) }
            recentPaths.removeAll { $0.hasPrefix(item.relativePath) }
            if let removedBookID { readingRecords.removeValue(forKey: removedBookID) }
            refresh()
        } catch {
            alert = WatchLibraryAlert(title: "删除失败", message: error.localizedDescription)
        }
    }

    private func finishReceiving(_ result: Result<String, Error>) {
        switch result {
        case .success(let fileName):
            transferStatus = "已收到 \(fileName)"
            refresh()
        case .failure(let error):
            alert = WatchLibraryAlert(title: "接收失败", message: error.localizedDescription)
            transferStatus = "上次传输失败"
        }
    }

    private func refresh() {
        items = Self.scanLibrary(at: libraryURL)
        favoritePaths = favoritePaths.filter { path in items.contains(where: { $0.relativePath == path }) }
        recentPaths = recentPaths.filter { path in items.contains(where: { $0.relativePath == path }) }
        persistState()
        publishManifest()
    }

    private func publishManifest() {
        guard let session, session.activationState == .activated else { return }
        let manifest = items.filter { !$0.isDirectory }.map {
            WatchManifestRecord(id: $0.relativePath, name: $0.name, kind: $0.kind.rawValue, byteCount: $0.byteCount)
        }
        let stats = readingRecords.map { key, value in
            WatchReadingStatPayload(
                bookID: key,
                readingTime: value.readingTime,
                chapterIndex: value.chapterIndex,
                chapterProgress: value.chapterProgress,
                updatedAt: value.updatedAt
            )
        }
        guard let data = try? JSONEncoder().encode(manifest),
              let statsData = try? JSONEncoder().encode(stats) else { return }
        try? session.updateApplicationContext([
            "libraryManifest": data,
            "readingStats": statsData
        ])
    }

    private func uniqueDestination(in folder: URL, named originalName: String) -> URL {
        let first = folder.appendingPathComponent(originalName)
        guard fileManager.fileExists(atPath: first.path) else { return first }
        let ext = (originalName as NSString).pathExtension
        let stem = (originalName as NSString).deletingPathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = libraryURL.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        return String(itemPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
    }

    private func replacePathPrefix(_ oldPrefix: String, with newPrefix: String) {
        favoritePaths = Set(favoritePaths.map { path in
            path.hasPrefix(oldPrefix) ? newPrefix + path.dropFirst(oldPrefix.count) : path
        })
        recentPaths = recentPaths.map { path in
            path.hasPrefix(oldPrefix) ? newPrefix + path.dropFirst(oldPrefix.count) : path
        }
        persistState()
    }

    private func persistState() {
        UserDefaults.standard.set(Array(favoritePaths), forKey: favoritesKey)
        UserDefaults.standard.set(recentPaths, forKey: recentsKey)
        if let data = try? JSONEncoder().encode(readingRecords) {
            UserDefaults.standard.set(data, forKey: readingRecordsKey)
        }
    }

    private static func scanLibrary(at root: URL) -> [WatchLibraryItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [WatchLibraryItem] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let isDirectory = values.isDirectory ?? false
            let rootPath = root.standardizedFileURL.path
            let path = url.standardizedFileURL.path
            let relative = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
            result.append(
                WatchLibraryItem(
                    url: url,
                    name: values.name ?? url.lastPathComponent,
                    kind: WatchLibraryItem.classify(url: url, isDirectory: isDirectory),
                    byteCount: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    isDirectory: isDirectory,
                    relativePath: relative
                )
            )
        }
        return result
    }

    private nonisolated static func persistReceivedFile(_ file: WCSessionFile) -> Result<String, Error> {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root = documents.appendingPathComponent("YuBing Watch Library", isDirectory: true)
        let metadata = file.metadata ?? [:]
        let requestedPath = metadata["relativePath"] as? String
            ?? metadata["name"] as? String
            ?? file.fileURL.lastPathComponent
        let components = requestedPath
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        let fileName = components.last ?? file.fileURL.lastPathComponent
        let parent = components.dropLast().reduce(root) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }

        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            var destination = parent.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: destination.path) {
                let ext = (fileName as NSString).pathExtension
                let stem = (fileName as NSString).deletingPathExtension
                var index = 2
                repeat {
                    let nextName = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
                    destination = parent.appendingPathComponent(nextName)
                    index += 1
                } while fileManager.fileExists(atPath: destination.path)
            }
            try fileManager.copyItem(at: file.fileURL, to: destination)
            return .success(destination.lastPathComponent)
        } catch {
            return .failure(error)
        }
    }
}

extension WatchLibraryStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            if let error {
                self?.transferStatus = error.localizedDescription
            } else {
                self?.transferStatus = "已连接 iPhone"
                self?.publishManifest()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let result = Self.persistReceivedFile(file)
        Task { @MainActor [weak self] in self?.finishReceiving(result) }
    }
}
