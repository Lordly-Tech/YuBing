import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class AudioPlayerController: ObservableObject {
    @Published private(set) var currentItem: LibraryItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var queue: [LibraryItem] = []

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init() {
        configureAudioSession()
        configureRemoteCommands()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds.isFinite ? time.seconds : 0
                self?.updateNowPlayingElapsedTime()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.playNext() }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func play(_ item: LibraryItem, in items: [LibraryItem]? = nil) {
        if let items {
            queue = items.filter { $0.kind == .music }
        } else if queue.isEmpty {
            queue = [item]
        }

        currentItem = item
        currentTime = 0
        duration = 0
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let playerItem = AVPlayerItem(url: item.url)
        player.replaceCurrentItem(with: playerItem)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()

        Task {
            if let loadedDuration = try? await playerItem.asset.load(.duration) {
                duration = loadedDuration.seconds.isFinite ? loadedDuration.seconds : 0
                updateNowPlayingInfo()
            }
        }
    }

    func togglePlayback() {
        guard currentItem != nil else {
            if let first = queue.first { play(first, in: queue) }
            return
        }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func seek(to seconds: TimeInterval) {
        let clamped = min(max(0, seconds), max(duration, 0))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
        updateNowPlayingElapsedTime()
    }

    func playNext() {
        guard let currentItem,
              let index = queue.firstIndex(of: currentItem),
              !queue.isEmpty else {
            isPlaying = false
            return
        }
        play(queue[(index + 1) % queue.count], in: queue)
    }

    func playPrevious() {
        guard currentTime < 4,
              let currentItem,
              let index = queue.firstIndex(of: currentItem),
              !queue.isEmpty else {
            seek(to: 0)
            return
        }
        play(queue[(index - 1 + queue.count) % queue.count], in: queue)
    }

    private func configureAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            // Playback still works in the foreground when session activation fails.
        }
        #endif
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isPlaying { self.togglePlayback() }
            }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentItem.displayName,
            MPMediaItemPropertyAlbumTitle: "鱼饼",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    private func updateNowPlayingElapsedTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
