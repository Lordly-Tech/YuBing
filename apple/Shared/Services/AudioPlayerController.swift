import AVFoundation
import Combine
import MediaPlayer

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EmbeddedAudioMetadata: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var year: String?
    var artworkData: Data?

    static let empty = EmbeddedAudioMetadata(title: nil, artist: nil, album: nil, year: nil, artworkData: nil)

    var hasDetails: Bool {
        [title, artist, album, year].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } || artworkData != nil
    }

    static func load(from url: URL) async -> EmbeddedAudioMetadata {
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

        return EmbeddedAudioMetadata(
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
final class AudioPlayerController: ObservableObject {
    @Published private(set) var currentItem: LibraryItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var queue: [LibraryItem] = []
    @Published private(set) var currentMetadata = EmbeddedAudioMetadata.empty
    @Published private(set) var metadataByPath: [String: EmbeddedAudioMetadata] = [:]

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init() {
        configureAudioSession()
        configureRemoteCommands()
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
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
        currentMetadata = metadataByPath[item.relativePath] ?? .empty
        currentTime = 0
        duration = 0
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let playerItem = AVPlayerItem(url: item.url)
        playerItem.preferredForwardBufferDuration = 15
        player.replaceCurrentItem(with: playerItem)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()

        Task {
            async let loadedDuration = try? await playerItem.asset.load(.duration)
            async let loadedMetadata = EmbeddedAudioMetadata.load(from: item.url)
            if let loadedDuration = await loadedDuration {
                duration = loadedDuration.seconds.isFinite ? loadedDuration.seconds : 0
                updateNowPlayingInfo()
            }
            let metadata = await loadedMetadata
            metadataByPath[item.relativePath] = metadata
            if currentItem == item {
                currentMetadata = metadata
                updateNowPlayingInfo()
            }
        }
    }

    func loadMetadata(for item: LibraryItem) async -> EmbeddedAudioMetadata {
        if let cached = metadataByPath[item.relativePath] { return cached }
        let metadata = await EmbeddedAudioMetadata.load(from: item.url)
        metadataByPath[item.relativePath] = metadata
        if currentItem == item {
            currentMetadata = metadata
            updateNowPlayingInfo()
        }
        return metadata
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
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
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
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentMetadata.title ?? currentItem.displayName,
            MPMediaItemPropertyAlbumTitle: currentMetadata.album ?? "鱼饼",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyAssetURL: currentItem.url
        ]
        if let artist = currentMetadata.artist { info[MPMediaItemPropertyArtist] = artist }
        if let year = currentMetadata.year { info[MPMediaItemPropertyReleaseDate] = year }
        if let artwork = mediaArtwork(from: currentMetadata.artworkData) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsedTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func mediaArtwork(from data: Data?) -> MPMediaItemArtwork? {
        guard let data else { return nil }
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #else
        guard let image = UIImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #endif
    }
}
