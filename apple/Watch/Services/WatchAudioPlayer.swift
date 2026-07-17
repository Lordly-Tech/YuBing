import AVFoundation
import Combine
import MediaPlayer

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

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
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
        configureRemoteCommands()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func play(_ item: WatchLibraryItem, queue: [WatchLibraryItem]) {
        self.queue = queue.filter { $0.kind == .music }
        currentItem = item
        currentTime = 0
        duration = 0
        try? AVAudioSession.sharedInstance().setActive(true)
        let avItem = AVPlayerItem(url: item.url)
        player.replaceCurrentItem(with: avItem)
        player.play()
        isPlaying = true
        updateNowPlaying()

        Task {
            if let loaded = try? await avItem.asset.load(.duration) {
                duration = loaded.seconds.isFinite ? loaded.seconds : 0
                updateNowPlaying()
            }
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
