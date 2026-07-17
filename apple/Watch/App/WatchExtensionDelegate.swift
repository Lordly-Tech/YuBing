import Foundation
import WatchConnectivity
import WatchKit

final class WatchExtensionDelegate: NSObject, WKExtensionDelegate {
    private var connectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var activationObservation: NSKeyValueObservation?
    private var pendingObservation: NSKeyValueObservation?

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                connectivityTasks.append(connectivityTask)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
        guard !connectivityTasks.isEmpty else { return }

        let session = WCSession.default
        activationObservation = session.observe(\.activationState, options: [.initial, .new]) { [weak self] _, _ in
            self?.completeConnectivityTasksIfPossible()
        }
        pendingObservation = session.observe(\.hasContentPending, options: [.initial, .new]) { [weak self] _, _ in
            self?.completeConnectivityTasksIfPossible()
        }
        if session.activationState == .notActivated {
            session.activate()
        }
    }

    private func completeConnectivityTasksIfPossible() {
        let session = WCSession.default
        guard session.activationState == .activated, !session.hasContentPending else { return }
        connectivityTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
        connectivityTasks.removeAll()
        activationObservation = nil
        pendingObservation = nil
    }
}
