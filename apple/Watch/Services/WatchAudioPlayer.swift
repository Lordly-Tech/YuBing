import AVFoundation
import Combine
import MediaPlayer
import WatchKit

@MainActor
final class WatchAudioPlayer: ObservableObject {
    @Published private(set) var currentItem: WatchLibraryItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var queue: [WatchLibraryItem] = []

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            // The route can become available later when headphones connect.
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds.isFinite ? time.seconds : 0
                self?.updateNowPlaying()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let type = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.ended.rawValue
            else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.player.play()
            }
        }
        configureRemoteCommands()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func play(_ item: WatchLibraryItem, queue: [WatchLibraryItem]) {
        self.queue = queue.filter { $0.kind == .music }
        currentItem = item
        currentTime = 0
        duration = 0
        activateAudioSession()
        let avItem = AVPlayerItem(url: item.url)
        player.replaceCurrentItem(with: avItem)
        player.play()
        isPlaying = true
        updateNowPlaying()
        WKExtension.shared().isFrontmostTimeoutExtended = true

        Task {
            if let loaded = try? await avItem.asset.load(.duration) {
                duration = loaded.seconds.isFinite ? loaded.seconds : 0
                updateNowPlaying()
            }
        }
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // watchOS may defer activation; playback still works.
        }
    }

    func toggle() {
        guard currentItem != nil else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        let value = min(max(time, 0), max(duration, 0))
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600))
        currentTime = value
        updateNowPlaying()
    }

    func next() {
        guard let currentItem, let index = queue.firstIndex(of: currentItem), !queue.isEmpty else { return }
        play(queue[(index + 1) % queue.count], queue: queue)
    }

    func previous() {
        guard currentTime < 4,
              let currentItem,
              let index = queue.firstIndex(of: currentItem),
              !queue.isEmpty else {
            seek(to: 0)
            return
        }
        play(queue[(index - 1 + queue.count) % queue.count], queue: queue)
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.toggle() } }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let currentItem else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentItem.displayName,
            MPMediaItemPropertyAlbumTitle: "鱼饼 Watch",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
