#if os(iOS)
import Combine
import Foundation
import WatchConnectivity

struct WatchManifestItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
    let byteCount: Int64
}

@MainActor
final class WatchTransferService: NSObject, ObservableObject {
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastStatus = "正在连接 Apple Watch"
    @Published private(set) var watchItems: [WatchManifestItem] = []

    private var session: WCSession?

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

    func send(_ items: [LibraryItem]) {
        #if targetEnvironment(simulator)
        lastStatus = "Watch 文件传输需要在配对真机上测试"
        return
        #endif
        guard let session, session.activationState == .activated else {
            lastStatus = "Watch 连接尚未就绪"
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            lastStatus = "请先在配对的 Apple Watch 上安装 鱼饼"
            return
        }

        let compatible = items.filter(\.isWatchCompatible)
        for item in compatible {
            session.transferFile(
                item.url,
                metadata: [
                    "name": item.name,
                    "kind": item.kind.rawValue,
                    "relativePath": item.relativePath,
                    "byteCount": item.byteCount
                ]
            )
        }
        pendingCount = session.outstandingFileTransfers.count
        lastStatus = compatible.isEmpty ? "所选项目不支持在 Watch 上打开" : "已加入后台传输队列"
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
        Task { @MainActor [weak self] in
            self?.pendingCount = session.outstandingFileTransfers.count
            if let error {
                self?.lastStatus = "传输失败：\(error.localizedDescription)"
            } else if session.outstandingFileTransfers.isEmpty {
                self?.lastStatus = "文件已传到 Apple Watch"
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext["libraryManifest"] as? Data,
              let manifest = try? JSONDecoder().decode([WatchManifestItem].self, from: data) else { return }
        Task { @MainActor [weak self] in
            self?.watchItems = manifest
            self?.updateSessionState(session)
        }
    }
}
#endif
