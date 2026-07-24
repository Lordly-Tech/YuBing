import AVFoundation
import MediaPlayer

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class AudioNowPlayingSession {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    #if os(iOS)
    private let playbackSession: MPNowPlayingSession
    #endif
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var nowPlayingInfo: [String: Any] = [:]
    private var representedPath: String?

    #if os(iOS)
    private var nowPlayingCenter: MPNowPlayingInfoCenter {
        playbackSession.nowPlayingInfoCenter
    }

    private var commandCenter: MPRemoteCommandCenter {
        playbackSession.remoteCommandCenter
    }
    #else
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    #endif

    init(player: AVPlayer) {
        #if os(iOS)
        playbackSession = MPNowPlayingSession(players: [player])
        playbackSession.automaticallyPublishesNowPlayingInfo = false
        #endif
        installRemoteCommands()
    }

    deinit {
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
    }

    func setItem(
        _ item: LibraryItem,
        metadata: EmbeddedAudioMetadata,
        duration: TimeInterval,
        queueIndex: Int,
        queueCount: Int
    ) {
        #if os(iOS)
        playbackSession.becomeActiveIfPossible(completion: nil)
        #endif
        representedPath = item.relativePath
        nowPlayingInfo = [
            MPMediaItemPropertyTitle: metadata.title ?? item.displayName,
            MPMediaItemPropertyAlbumTitle: metadata.album ?? "鱼饼",
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyExternalContentIdentifier: item.relativePath,
            MPNowPlayingInfoPropertyServiceIdentifier: "top.lordly.yubing",
            MPNowPlayingInfoPropertyPlaybackQueueIndex: max(queueIndex, 0),
            MPNowPlayingInfoPropertyPlaybackQueueCount: max(queueCount, 1),
            MPNowPlayingInfoPropertyAssetURL: item.url
        ]
        if let artist = metadata.artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        if let albumArtist = metadata.albumArtist {
            nowPlayingInfo[MPMediaItemPropertyAlbumArtist] = albumArtist
        }
        if let genre = metadata.genre {
            nowPlayingInfo[MPMediaItemPropertyGenre] = genre
        }
        if let year = metadata.year {
            nowPlayingInfo[MPMediaItemPropertyReleaseDate] = year
        }
        if let artwork = mediaArtwork(from: metadata.artworkData) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
    }

    func updatePlayback(
        position: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        playbackRate: Float
    ) {
        guard representedPath != nil else { return }
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = max(duration, 0)
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(position, 0)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = playbackRate
        nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
        #if os(iOS)
        nowPlayingCenter.playbackState = isPlaying ? .playing : .paused
        #endif
        commandCenter.playCommand.isEnabled = !isPlaying
        commandCenter.pauseCommand.isEnabled = isPlaying
    }

    func clear() {
        representedPath = nil
        nowPlayingInfo = [:]
        nowPlayingCenter.nowPlayingInfo = nil
        #if os(iOS)
        nowPlayingCenter.playbackState = .stopped
        #endif
    }

    private func installRemoteCommands() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.stopCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.changeRepeatModeCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.isEnabled = false

        addTarget(to: commandCenter.playCommand) { [weak self] _ in
            Task { @MainActor in self?.onPlay?() }
            return .success
        }
        addTarget(to: commandCenter.pauseCommand) { [weak self] _ in
            Task { @MainActor in self?.onPause?() }
            return .success
        }
        addTarget(to: commandCenter.nextTrackCommand) { [weak self] _ in
            Task { @MainActor in self?.onNext?() }
            return .success
        }
        addTarget(to: commandCenter.previousTrackCommand) { [weak self] _ in
            Task { @MainActor in self?.onPrevious?() }
            return .success
        }
        addTarget(to: commandCenter.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.onSeek?(event.positionTime) }
            return .success
        }
    }

    private func addTarget(
        to command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget(handler: handler)
        commandTargets.append((command, target))
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
