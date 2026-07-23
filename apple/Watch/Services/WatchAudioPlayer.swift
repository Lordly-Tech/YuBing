import AVFoundation
import Combine
import MediaPlayer
import WatchKit

enum WatchRepeatMode: String, CaseIterable, Identifiable {
    case off
    case all
    case one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "顺序播放"
        case .all: "列表循环"
        case .one: "单曲循环"
        }
    }
}

struct WatchEmbeddedAudioMetadata: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var year: String?
    var artworkData: Data?
    var lyrics: TimedLyrics?

    static let empty = WatchEmbeddedAudioMetadata(title: nil, artist: nil, album: nil, year: nil, artworkData: nil, lyrics: nil)

    static func load(from url: URL) async -> WatchEmbeddedAudioMetadata {
        let asset = AVURLAsset(url: url)
        let items = (try? await asset.load(.commonMetadata)) ?? []
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
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        var embeddedLyrics = ID3EmbeddedLyricsReader.read(from: url)
        for format in formats {
            guard let metadata = try? await asset.loadMetadata(for: format) else { continue }
            for item in metadata {
                guard item.identifier?.rawValue.lowercased().contains("lyric") == true else { continue }
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    embeddedLyrics = value
                    break
                }
            }
        }
        return WatchEmbeddedAudioMetadata(
            title: title,
            artist: artist,
            album: album,
            year: year,
            artworkData: artworkData,
            lyrics: AudioLyricsLoader.load(sidecarFor: url, embeddedText: embeddedLyrics)
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
    @Published private(set) var playbackRate: Float = 1
    @Published private(set) var repeatMode: WatchRepeatMode = .off
    @Published private(set) var isShuffleEnabled = false
    @Published private(set) var sleepTimerEnd: Date?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var shouldResumeAfterInterruption = false
    private var sleepTask: Task<Void, Never>?

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            // The route can become available later when headphones connect.
        }
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
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
        sleepTask?.cancel()
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
        avItem.audioTimePitchAlgorithm = .timeDomain
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
        player.defaultRate = playbackRate
        player.playImmediately(atRate: playbackRate)
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
        player.defaultRate = playbackRate
        player.playImmediately(atRate: playbackRate)
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

    func playbackPosition() -> TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : currentTime
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = min(max(rate, 0.5), 2)
        player.defaultRate = playbackRate
        if isPlaying { player.rate = playbackRate }
        updateNowPlaying()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
    }

    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        guard let minutes else {
            sleepTimerEnd = nil
            return
        }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEnd = end
        sleepTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(TimeInterval(minutes * 60)))
            } catch {
                return
            }
            guard let self, self.sleepTimerEnd == end else { return }
            self.player.pause()
            self.isPlaying = false
            self.sleepTimerEnd = nil
            self.updateNowPlaying()
        }
    }

    func next() {
        guard let currentItem, let index = queue.firstIndex(of: currentItem), !queue.isEmpty else { return }
        if repeatMode == .one {
            seek(to: 0)
            Task { @MainActor in await resumePlayback() }
            return
        }
        if isShuffleEnabled, let random = queue.filter({ $0 != currentItem }).randomElement() {
            play(random, queue: queue)
            return
        }
        if repeatMode == .off, index == queue.count - 1 {
            player.pause()
            isPlaying = false
            updateNowPlaying()
            return
        }
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
        commands.changePlaybackRateCommand.isEnabled = true
        commands.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1, 1.25, 1.5, 2].map { NSNumber(value: $0) }
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
        commands.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.setPlaybackRate(event.playbackRate) }
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackRate,
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
