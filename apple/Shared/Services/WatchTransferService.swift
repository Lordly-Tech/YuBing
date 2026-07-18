#if os(iOS)
import Combine
import Foundation
import WatchConnectivity

extension Notification.Name {
    static let yuBingWatchTransferDidStart = Notification.Name("YuBingWatchTransferDidStart")
}

struct WatchManifestItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
    let byteCount: Int64
}

struct WatchTransferProgressItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let byteCount: Int64
    var fractionCompleted: Double
}

@MainActor
final class WatchTransferService: NSObject, ObservableObject {
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastStatus = "正在连接 Apple Watch"
    @Published private(set) var watchItems: [WatchManifestItem] = []
    @Published private(set) var activeTransferProgress: [WatchTransferProgressItem] = []

    private var session: WCSession?
    private weak var readingStore: ReadingStore?
    private var bufferedReadingStats: [WatchReadingStatPayload] = []
    private var transferProgressIDs: [ObjectIdentifier: UUID] = [:]
    private var transferProgressObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    var overallProgress: Double? {
        guard !activeTransferProgress.isEmpty else { return nil }
        let total = activeTransferProgress.reduce(0) { $0 + min(max($1.fractionCompleted, 0), 1) }
        return total / Double(activeTransferProgress.count)
    }

    var activeTransferTitle: String? {
        guard let first = activeTransferProgress.first else { return nil }
        if activeTransferProgress.count == 1 { return first.name }
        return "\(first.name) 等 \(activeTransferProgress.count) 个文件"
    }

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            lastStatus = "此设备不支持 Watch 连接"
            return
        }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    func attach(readingStore: ReadingStore) {
        self.readingStore = readingStore
        if !bufferedReadingStats.isEmpty {
            readingStore.mergeWatchStats(bufferedReadingStats)
            bufferedReadingStats.removeAll()
        }
    }

    func send(_ items: [LibraryItem]) {
        // A transfer attempt should always return to the home card, including
        // the failure case where the companion Watch app is not installed.
        NotificationCenter.default.post(name: .yuBingWatchTransferDidStart, object: nil)
        #if targetEnvironment(simulator)
        lastStatus = "Watch 文件传输需要在配对真机上测试"
        return
        #endif
        guard let session, session.activationState == .activated else {
            lastStatus = "Watch 连接尚未就绪"
            return
        }
        guard session.isPaired else {
            lastStatus = "请先将 Apple Watch 与此 iPhone 配对"
            return
        }
        guard session.isWatchAppInstalled else {
            lastStatus = "Apple Watch 尚未安装鱼饼 Watch App，请先安装后再传输"
            return
        }

        let compatible = items.filter(\.isWatchCompatible)
        guard !compatible.isEmpty else {
            lastStatus = "所选项目不支持在 Watch 上打开"
            return
        }

        lastStatus = "准备传输 \(compatible.count) 个文件"
        Task { [weak self] in
            guard let self else { return }
            var enqueued = 0
            var failures: [String] = []
            for item in compatible {
                do {
                    if item.kind == .novel {
                        self.lastStatus = "正在为 Watch 整理《\(item.displayName)》"
                        let transfer = try await self.makeWatchBookTransfer(for: item)
                        let fileTransfer = session.transferFile(transfer.url, metadata: transfer.metadata)
                        self.track(fileTransfer, name: transfer.metadata["name"] as? String ?? item.name, byteCount: transfer.metadata["byteCount"] as? Int64 ?? item.byteCount)
                    } else {
                        let fileTransfer = session.transferFile(item.url, metadata: self.metadata(for: item))
                        self.track(fileTransfer, name: item.name, byteCount: item.byteCount)
                    }
                    enqueued += 1
                } catch {
                    failures.append("\(item.displayName)：\(error.localizedDescription)")
                }
            }
            self.pendingCount = session.outstandingFileTransfers.count
            if failures.isEmpty {
                self.lastStatus = "已加入后台传输队列（\(enqueued) 个）"
            } else if enqueued > 0 {
                self.lastStatus = "已发送 \(enqueued) 个，\(failures.count) 个转换失败"
            } else {
                self.lastStatus = failures.joined(separator: "\n")
            }
        }
    }

    private func metadata(for item: LibraryItem) -> [String: Any] {
        [
            "name": item.name,
            "kind": item.kind.rawValue,
            "relativePath": item.relativePath,
            "byteCount": item.byteCount
        ]
    }

    private func makeWatchBookTransfer(for item: LibraryItem) async throws -> (url: URL, metadata: [String: Any]) {
        let sourceURL = item.url
        let parsed = try await Task.detached(priority: .userInitiated) {
            try BookParser.parse(url: sourceURL)
        }.value

        let storedCover = await readingStore?.coverData(for: item, discoverIfNeeded: false)
        let cover = storedCover ?? parsed.coverData
        if storedCover == nil, let cover {
            readingStore?.saveCover(cover, for: item)
        }
        let record = readingStore?.record(for: item) ?? ReadingRecord()
        let package = WatchBookPackage(
            version: 1,
            sourceID: item.relativePath,
            title: parsed.title,
            originalFileName: item.name,
            format: parsed.format,
            chapters: parsed.chapters,
            totalLength: parsed.totalLength,
            coverData: cover,
            initialChapterIndex: min(max(record.chapterIndex, 0), max(parsed.chapters.count - 1, 0)),
            initialChapterProgress: min(max(record.chapterProgress, 0), 1)
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(package)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuBing Watch Transfers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).\(WatchBookPackage.fileExtension)"
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)

        let stem = (item.relativePath as NSString).deletingPathExtension
        let relativePath = "\(stem).\(WatchBookPackage.fileExtension)"
        return (
            url,
            [
                "name": "\(parsed.title).\(WatchBookPackage.fileExtension)",
                "kind": LibraryKind.novel.rawValue,
                "relativePath": relativePath,
                "byteCount": Int64(data.count),
                "sourceID": item.relativePath
            ]
        )
    }

    private func updateSessionState(_ session: WCSession) {
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        pendingCount = session.outstandingFileTransfers.count
        if session.isPaired, session.isWatchAppInstalled {
            lastStatus = pendingCount == 0 ? "Apple Watch 已就绪" : "还有 \(pendingCount) 个文件正在传输"
        } else {
            lastStatus = "未找到已安装 鱼饼 的配对手表"
        }
    }

    private func track(_ fileTransfer: WCSessionFileTransfer, name: String, byteCount: Int64) {
        let objectID = ObjectIdentifier(fileTransfer)
        let id = UUID()
        transferProgressIDs[objectID] = id
        activeTransferProgress.append(
            WatchTransferProgressItem(
                id: id,
                name: name,
                byteCount: byteCount,
                fractionCompleted: fileTransfer.progress.fractionCompleted
            )
        )
        pendingCount = session?.outstandingFileTransfers.count ?? activeTransferProgress.count
        let observation = fileTransfer.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.updateTransferProgress(id: id, fraction: progress.fractionCompleted)
            }
        }
        transferProgressObservations[objectID] = observation
        NotificationCenter.default.post(name: .yuBingWatchTransferDidStart, object: nil)
    }

    private func updateTransferProgress(id: UUID, fraction: Double) {
        guard let index = activeTransferProgress.firstIndex(where: { $0.id == id }) else { return }
        activeTransferProgress[index].fractionCompleted = min(max(fraction, 0), 1)
        if let progress = overallProgress {
            lastStatus = "正在传输 \(Int(progress * 100))%"
        }
    }

    private func finishTracking(_ fileTransfer: WCSessionFileTransfer) {
        let objectID = ObjectIdentifier(fileTransfer)
        if let progressID = transferProgressIDs.removeValue(forKey: objectID) {
            activeTransferProgress.removeAll { $0.id == progressID }
        }
        transferProgressObservations[objectID] = nil
    }
}

extension WatchTransferService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            if let error {
                self?.lastStatus = error.localizedDescription
            } else {
                self?.updateSessionState(session)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.updateSessionState(session) }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        let temporaryURL = fileTransfer.file.fileURL
        Task { @MainActor [weak self] in
            if temporaryURL.pathExtension.lowercased() == WatchBookPackage.fileExtension {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            self?.finishTracking(fileTransfer)
            self?.pendingCount = session.outstandingFileTransfers.count
            if let error {
                self?.lastStatus = "传输失败：\(error.localizedDescription)"
            } else if !(self?.activeTransferProgress.isEmpty ?? true) {
                self?.lastStatus = "还有 \(session.outstandingFileTransfers.count) 个文件正在传输"
            } else if session.outstandingFileTransfers.isEmpty {
                self?.lastStatus = "文件已传到 Apple Watch"
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let manifest = (applicationContext["libraryManifest"] as? Data)
            .flatMap { try? JSONDecoder().decode([WatchManifestItem].self, from: $0) }
        let stats = (applicationContext["readingStats"] as? Data)
            .flatMap { try? JSONDecoder().decode([WatchReadingStatPayload].self, from: $0) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let manifest { self.watchItems = manifest }
            if let stats {
                if let readingStore = self.readingStore {
                    readingStore.mergeWatchStats(stats)
                } else {
                    self.bufferedReadingStats = stats
                }
            }
            self.updateSessionState(session)
        }
    }
}
#endif
