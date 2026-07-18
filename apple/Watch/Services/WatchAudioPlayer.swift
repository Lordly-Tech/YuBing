import AVFoundation
import Combine
import MediaPlayer
import WatchKit

struct WatchEmbeddedAudioMetadata: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var year: String?
    var artworkData: Data?

    static let empty = WatchEmbeddedAudioMetadata(title: nil, artist: nil, album: nil, year: nil, artworkData: nil)

    static func load(from url: URL) async -> WatchEmbeddedAudioMetadata {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return .empty }
        let title = await stringValue(in: items, identifier: .commonIdentifierTitle)
        let artist = await stringValue(in: items, identifier: .commonIdentifierArtist)
        let album = await stringValue(in: items, identifier: .commonIdentifierAlbumName)
        let year = await stringValue(in: items, identifier: .commonIdentifierCreationDate)
        let artworkItem = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: .commonIdentifierArtwork
        ).first
        let artworkData: Data?
        if let artworkItem {
            artworkData = try? await artworkItem.load(.dataValue)
        } else {
            artworkData = nil
        }
        return WatchEmbeddedAudioMetadata(
            title: title,
            artist: artist,
            album: album,
            year: year,
            artworkData: artworkData
        )
    }

    private static func stringValue(
        in items: [AVMetadataItem],
        identifier: AVMetadataIdentifier
    ) async -> String? {
        guard let item = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: identifier
        ).first else { return nil }
        return try? await item.load(.stringValue)
    }
}

@MainActor
final class WatchAudioPlayer: ObservableObject {
    @Published private(set) var currentItem: WatchLibraryItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var queue: [WatchLibraryItem] = []
    @Published private(set) var currentMetadata = WatchEmbeddedAudioMetadata.empty
    @Published private(set) var metadataByPath: [String: WatchEmbeddedAudioMetadata] = [:]

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var shouldResumeAfterInterruption = false

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            // The route can become available later when headphones connect.
        }
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
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
            guard let self,
                  let info = notification.userInfo,
                  let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            Task { @MainActor in
                if type == .began {
                    self.shouldResumeAfterInterruption = self.isPlaying
                    self.player.pause()
                    self.isPlaying = false
                    self.updateNowPlaying()
                } else if self.shouldResumeAfterInterruption {
                    self.shouldResumeAfterInterruption = false
                    await self.resumePlayback()
                }
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
        currentMetadata = metadataByPath[item.relativePath] ?? .empty
        currentTime = 0
        duration = 0

        let avItem = AVPlayerItem(url: item.url)
        avItem.preferredForwardBufferDuration = 15
        player.replaceCurrentItem(with: avItem)
        isPlaying = false
        updateNowPlaying()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startPlayback(avItem, item: item)
        }
    }

    private func startPlayback(_ avItem: AVPlayerItem, item: WatchLibraryItem) async {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
            try await AVAudioSession.sharedInstance().activate()
        } catch {
            // The system may wait for a Bluetooth route; keep the item ready.
        }
        guard player.currentItem === avItem else { return }
        player.play()
        isPlaying = true
        updateNowPlaying()

        async let loadedDuration = try? await avItem.asset.load(.duration)
        async let loadedMetadata = loadMetadata(for: item)
        if let loaded = await loadedDuration {
            duration = loaded.seconds.isFinite ? loaded.seconds : 0
        }
        currentMetadata = await loadedMetadata
        updateNowPlaying()
    }

    func toggle() {
        guard currentItem != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            updateNowPlaying()
        } else {
            Task { @MainActor in await resumePlayback() }
        }
    }

    private func resumePlayback() async {
        guard currentItem != nil else { return }
        do { try await AVAudioSession.sharedInstance().activate() } catch { return }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func loadMetadata(for item: WatchLibraryItem) async -> WatchEmbeddedAudioMetadata {
        if let cached = metadataByPath[item.relativePath] { return cached }
        let metadata = await WatchEmbeddedAudioMetadata.load(from: item.url)
        metadataByPath[item.relativePath] = metadata
        if currentItem == item {
            currentMetadata = metadata
            updateNowPlaying()
        }
        return metadata
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
        let liveTime = player.currentTime().seconds.isFinite ? player.currentTime().seconds : currentTime
        guard liveTime < 4,
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
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
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
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let currentItem else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentMetadata.title ?? currentItem.displayName,
            MPMediaItemPropertyAlbumTitle: currentMetadata.album ?? "鱼饼 Watch",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyAssetURL: currentItem.url
        ]
        if let artist = currentMetadata.artist { info[MPMediaItemPropertyArtist] = artist }
        if let year = currentMetadata.year { info[MPMediaItemPropertyReleaseDate] = year }
        if let data = currentMetadata.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
