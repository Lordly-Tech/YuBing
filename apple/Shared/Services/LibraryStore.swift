import Combine
import Foundation

struct LibraryAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var favoritePaths: Set<String>
    @Published private(set) var recentPaths: [String]
    @Published var alert: LibraryAlert?

    let libraryURL: URL

    private let fileManager = FileManager.default
    private let favoritesKey = "folio.favoritePaths"
    private let recentsKey = "folio.recentPaths"

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        libraryURL = documents.appendingPathComponent("YuBing Library", isDirectory: true)
        favoritePaths = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        recentPaths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []

        do {
            try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
            try seedWelcomeFileIfNeeded()
            items = Self.scanLibrary(at: libraryURL)
        } catch {
            alert = LibraryAlert(title: "无法打开资料库", message: error.localizedDescription)
        }
    }

    var favorites: [LibraryItem] {
        items.filter { favoritePaths.contains($0.relativePath) }
    }

    var recents: [LibraryItem] {
        recentPaths.compactMap { path in items.first(where: { $0.relativePath == path }) }
    }

    var totalBytes: Int64 {
        items.filter { !$0.isDirectory }.reduce(0) { $0 + $1.byteCount }
    }

    func items(of kind: LibraryKind) -> [LibraryItem] {
        items.filter { $0.kind == kind }
    }

    func children(of folder: URL) -> [LibraryItem] {
        let normalizedFolder = folder.standardizedFileURL
        return items.filter { item in
            item.url.deletingLastPathComponent().standardizedFileURL == normalizedFolder
        }
    }

    func isFavorite(_ item: LibraryItem) -> Bool {
        favoritePaths.contains(item.relativePath)
    }

    func refresh() {
        items = Self.scanLibrary(at: libraryURL)
        favoritePaths = favoritePaths.filter { path in items.contains(where: { $0.relativePath == path }) }
        recentPaths = recentPaths.filter { path in items.contains(where: { $0.relativePath == path }) }
        persistState()
    }

    func importFiles(_ urls: [URL], into folder: URL? = nil) {
        let destinationFolder = folder ?? libraryURL
        var failures: [String] = []

        for sourceURL in urls {
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

            do {
                let destination = uniqueDestination(in: destinationFolder, named: sourceURL.lastPathComponent)
                try fileManager.copyItem(at: sourceURL, to: destination)
            } catch {
                failures.append("\(sourceURL.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        refresh()
        if !failures.isEmpty {
            alert = LibraryAlert(title: "部分文件未能导入", message: failures.joined(separator: "\n"))
        }
    }

    func importData(_ data: Data, suggestedName: String, into folder: URL? = nil) {
        do {
            let destination = uniqueDestination(in: folder ?? libraryURL, named: suggestedName)
            try data.write(to: destination, options: .atomic)
            refresh()
        } catch {
            alert = LibraryAlert(title: "导入失败", message: error.localizedDescription)
        }
    }

    func importFile(_ sourceURL: URL, suggestedName: String, into folder: URL? = nil) {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        do {
            let destination = uniqueDestination(in: folder ?? libraryURL, named: suggestedName)
            try fileManager.copyItem(at: sourceURL, to: destination)
            refresh()
        } catch {
            alert = LibraryAlert(title: "导入失败", message: error.localizedDescription)
        }
    }

    func createFolder(named name: String, in folder: URL) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            alert = LibraryAlert(title: "名称不可用", message: "文件夹名称不能为空或包含斜杠。")
            return
        }
        do {
            try fileManager.createDirectory(
                at: uniqueDestination(in: folder, named: trimmed),
                withIntermediateDirectories: false
            )
            refresh()
        } catch {
            alert = LibraryAlert(title: "无法新建文件夹", message: error.localizedDescription)
        }
    }

    func rename(_ item: LibraryItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            alert = LibraryAlert(title: "名称不可用", message: "名称不能为空或包含斜杠。")
            return
        }

        let finalName: String
        if item.isDirectory || (trimmed as NSString).pathExtension.isEmpty {
            finalName = item.isDirectory ? trimmed : "\(trimmed).\(item.fileExtension)"
        } else {
            finalName = trimmed
        }
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(finalName, isDirectory: item.isDirectory)
        guard destination.standardizedFileURL != item.url.standardizedFileURL else { return }
        guard !fileManager.fileExists(atPath: destination.path) else {
            alert = LibraryAlert(title: "名称已存在", message: "当前文件夹中已有同名项目。")
            return
        }

        do {
            let oldPrefix = item.relativePath
            try fileManager.moveItem(at: item.url, to: destination)
            let newPrefix = relativePath(for: destination)
            replacePathPrefix(oldPrefix, with: newPrefix)
            refresh()
        } catch {
            alert = LibraryAlert(title: "重命名失败", message: error.localizedDescription)
        }
    }

    func move(_ item: LibraryItem, to folder: URL) {
        guard !folder.standardizedFileURL.path.hasPrefix(item.url.standardizedFileURL.path + "/") else {
            alert = LibraryAlert(title: "无法移动", message: "文件夹不能移入自身。")
            return
        }
        let destination = uniqueDestination(in: folder, named: item.name)
        do {
            let oldPrefix = item.relativePath
            try fileManager.moveItem(at: item.url, to: destination)
            replacePathPrefix(oldPrefix, with: relativePath(for: destination))
            refresh()
        } catch {
            alert = LibraryAlert(title: "移动失败", message: error.localizedDescription)
        }
    }

    func delete(_ item: LibraryItem) {
        do {
            try fileManager.removeItem(at: item.url)
            favoritePaths = favoritePaths.filter { !$0.hasPrefix(item.relativePath) }
            recentPaths.removeAll { $0.hasPrefix(item.relativePath) }
            refresh()
        } catch {
            alert = LibraryAlert(title: "删除失败", message: error.localizedDescription)
        }
    }

    func toggleFavorite(_ item: LibraryItem) {
        if favoritePaths.contains(item.relativePath) {
            favoritePaths.remove(item.relativePath)
        } else {
            favoritePaths.insert(item.relativePath)
        }
        persistState()
        objectWillChange.send()
    }

    func markOpened(_ item: LibraryItem) {
        recentPaths.removeAll { $0 == item.relativePath }
        recentPaths.insert(item.relativePath, at: 0)
        recentPaths = Array(recentPaths.prefix(30))
        persistState()
        objectWillChange.send()
    }

    func relativePath(for url: URL) -> String {
        let rootPath = libraryURL.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(itemPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
    }

    private func uniqueDestination(in folder: URL, named originalName: String) -> URL {
        let proposed = folder.appendingPathComponent(originalName)
        guard fileManager.fileExists(atPath: proposed.path) else { return proposed }

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
    }

    private func seedWelcomeFileIfNeeded() throws {
        let existing = try fileManager.contentsOfDirectory(atPath: libraryURL.path)
        guard existing.isEmpty,
              let sample = Bundle.main.url(forResource: "Welcome", withExtension: "txt") else { return }
        try fileManager.copyItem(at: sample, to: libraryURL.appendingPathComponent("欢迎使用 鱼饼.txt"))
    }

    private static func scanLibrary(at root: URL) -> [LibraryItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [LibraryItem] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let isDirectory = values.isDirectory ?? false
            let rootPath = root.standardizedFileURL.path
            let path = url.standardizedFileURL.path
            let relative = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
            result.append(
                LibraryItem(
                    url: url,
                    name: values.name ?? url.lastPathComponent,
                    kind: LibraryItem.classify(url: url, isDirectory: isDirectory),
                    byteCount: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    isDirectory: isDirectory,
                    relativePath: relative
                )
            )
        }
        return result
    }
}
