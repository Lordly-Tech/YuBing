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
    var albumArtist: String?
    var genre: String?
    var year: String?
    var trackNumber: String?
    var discNumber: String?
    var codec: String?
    var sampleRate: Int?
    var bitDepth: Int?
    var isLossless: Bool
    var artworkData: Data?
    var lyrics: TimedLyrics?

    static let empty = EmbeddedAudioMetadata(
        title: nil,
        artist: nil,
        album: nil,
        albumArtist: nil,
        genre: nil,
        year: nil,
        trackNumber: nil,
        discNumber: nil,
        codec: nil,
        sampleRate: nil,
        bitDepth: nil,
        isLossless: false,
        artworkData: nil,
        lyrics: nil
    )

    var hasDetails: Bool {
        [title, artist, album, albumArtist, genre, year].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } || artworkData != nil
    }

    var hasAlbum: Bool {
        guard let album else { return false }
        return !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var qualityDescription: String {
        var details: [String] = []
        if isLossless { details.append("Lossless") }
        if let sampleRate {
            let value = Double(sampleRate) / 1000
            details.append(value.rounded() == value ? "\(Int(value)) kHz" : String(format: "%.1f kHz", value))
        }
        if let bitDepth, bitDepth > 0 { details.append("\(bitDepth)-bit") }
        if let codec, !codec.isEmpty { details.append(codec.uppercased()) }
        return details.joined(separator: " · ")
    }

    static func load(from url: URL) async -> EmbeddedAudioMetadata {
        let ext = url.pathExtension.lowercased()
        let containerMetadata = await Task.detached(priority: .utility) {
            try? FFmpegAudioMetadataReader.read(from: url)
        }.value
        let flacMetadata: FLACMetadataSnapshot?
        if ext == "flac" {
            flacMetadata = await Task.detached(priority: .utility) {
                try? FLACMetadataReader.read(from: url)
            }.value
        } else {
            flacMetadata = nil
        }

        let asset = AVURLAsset(url: url)
        let commonItems = (try? await asset.load(.commonMetadata)) ?? []
        var allItems = commonItems
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        for format in formats {
            if let items = try? await asset.loadMetadata(for: format) {
                allItems.append(contentsOf: items)
            }
        }

        let avTitle = await stringValue(in: allItems, identifiers: [.commonIdentifierTitle], hints: ["title"])
        let avArtist = await stringValue(in: allItems, identifiers: [.commonIdentifierArtist], hints: ["artist", "performer"])
        let avAlbum = await stringValue(in: allItems, identifiers: [.commonIdentifierAlbumName], hints: ["album"])
        let avAlbumArtist = await stringValue(in: allItems, identifiers: [], hints: ["albumartist", "album_artist"])
        let avGenre = await stringValue(in: allItems, identifiers: [], hints: ["genre", "contenttype"])
        let avYear = await stringValue(in: allItems, identifiers: [.commonIdentifierCreationDate], hints: ["year", "date"])
        let title = containerMetadata?.title ?? flacMetadata?.title ?? avTitle
        let artist = containerMetadata?.artist ?? flacMetadata?.artist ?? avArtist
        let album = containerMetadata?.album ?? flacMetadata?.album ?? avAlbum
        let albumArtist = containerMetadata?.albumArtist ?? flacMetadata?.albumArtist ?? avAlbumArtist
        let genre = containerMetadata?.genre ?? flacMetadata?.genre ?? avGenre
        let rawYear = containerMetadata?.date ?? flacMetadata?.date ?? avYear
        let year = rawYear.flatMap { value in
            let digits = value.filter(\.isNumber)
            return digits.count >= 4 ? String(digits.prefix(4)) : value
        }
        let avTrackNumber = await stringValue(in: allItems, identifiers: [], hints: ["tracknumber", "track_number"])
        let avDiscNumber = await stringValue(in: allItems, identifiers: [], hints: ["discnumber", "disc_number"])
        let avLyrics = await stringValue(in: allItems, identifiers: [], hints: ["lyric", "unsynchronizedlyric"])
        let avArtworkData = await dataValue(in: allItems, identifier: .commonIdentifierArtwork, hints: ["artwork", "picture", "cover"])
        let id3Lyrics = ID3EmbeddedLyricsReader.read(from: url)
        let trackNumber = containerMetadata?.trackNumber ?? flacMetadata?.trackNumber ?? avTrackNumber
        let discNumber = containerMetadata?.discNumber ?? flacMetadata?.discNumber ?? avDiscNumber
        let embeddedLyrics = containerMetadata?.lyrics ?? flacMetadata?.lyrics ?? avLyrics ?? id3Lyrics
        let artworkData = containerMetadata?.artworkData ?? flacMetadata?.artworkData ?? avArtworkData
        let properties = await audioProperties(from: asset)
        let losslessExtensions: Set<String> = [
            "flac", "alac", "wav", "aif", "aiff", "caf", "dsd", "dsf", "dff", "ape"
        ]
        let isLossless = containerMetadata?.isLossless == true || losslessExtensions.contains(ext) ||
            (properties.codec?.localizedCaseInsensitiveContains("alac") ?? false) ||
            (properties.codec?.localizedCaseInsensitiveContains("flac") ?? false) ||
            (properties.codec?.localizedCaseInsensitiveContains("wmal") ?? false)

        return EmbeddedAudioMetadata(
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            year: year,
            trackNumber: trackNumber,
            discNumber: discNumber,
            codec: containerMetadata?.codec ?? properties.codec ?? ext,
            sampleRate: containerMetadata?.sampleRate ?? flacMetadata?.sampleRate ?? properties.sampleRate,
            bitDepth: containerMetadata?.bitDepth ?? flacMetadata?.bitDepth ?? properties.bitDepth,
            isLossless: isLossless,
            artworkData: artworkData,
            lyrics: AudioLyricsLoader.load(sidecarFor: url, embeddedText: embeddedLyrics)
        )
    }

    private static func stringValue(
        in items: [AVMetadataItem],
        identifiers: [AVMetadataIdentifier],
        hints: [String]
    ) async -> String? {
        for item in items {
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            guard identifiers.contains(where: { item.identifier == $0 }) ||
                    hints.contains(where: { identifier.contains($0) }) else { continue }
            if let value = try? await item.load(.stringValue) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func dataValue(
        in items: [AVMetadataItem],
        identifier: AVMetadataIdentifier,
        hints: [String]
    ) async -> Data? {
        for item in items {
            let rawIdentifier = item.identifier?.rawValue.lowercased() ?? ""
            guard item.identifier == identifier || hints.contains(where: { rawIdentifier.contains($0) }) else { continue }
            if let data = try? await item.load(.dataValue), !data.isEmpty { return data }
        }
        return nil
    }

    private static func audioProperties(from asset: AVURLAsset) async -> (codec: String?, sampleRate: Int?, bitDepth: Int?) {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let descriptions = try? await track.load(.formatDescriptions),
              let description = descriptions.first else {
            return (nil, nil, nil)
        }
        let subtype = CMFormatDescriptionGetMediaSubType(description)
        let rawBytes: [UInt8] = [
            UInt8((subtype >> 24) & 0xff),
            UInt8((subtype >> 16) & 0xff),
            UInt8((subtype >> 8) & 0xff),
            UInt8(subtype & 0xff)
        ]
        let printableBytes = rawBytes.filter { byte in byte >= 32 && byte < 127 }
        let codec = String(bytes: printableBytes, encoding: .ascii)
        guard let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            return (codec, nil, nil)
        }
        let sampleRate = basic.pointee.mSampleRate > 0 ? Int(basic.pointee.mSampleRate.rounded()) : nil
        let bitDepth = basic.pointee.mBitsPerChannel > 0 ? Int(basic.pointee.mBitsPerChannel) : nil
        return (codec, sampleRate, bitDepth)
    }
}

enum AudioRepeatMode: String, CaseIterable, Identifiable {
    case off
    case all
    case one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: AppLocalization.string("顺序播放")
        case .all: AppLocalization.string("列表循环")
        case .one: AppLocalization.string("单曲循环")
        }
    }

    var symbol: String {
        switch self {
        case .off: "repeat"
        case .all: "repeat"
        case .one: "repeat.1"
        }
    }
}

@MainActor
final class AudioPlayerController: ObservableObject {
    @Published private(set) var currentItem: LibraryItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var isPreparing = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var queue: [LibraryItem] = []
    @Published private(set) var currentMetadata = EmbeddedAudioMetadata.empty
    @Published private(set) var metadataByPath: [String: EmbeddedAudioMetadata] = [:]
    @Published private(set) var playbackRate: Float = 1
    @Published private(set) var volume: Double = 1
    @Published private(set) var repeatMode: AudioRepeatMode = .off
    @Published private(set) var isShuffleEnabled = false
    @Published private(set) var sleepTimerEnd: Date?
    @Published private(set) var stopAfterCurrentTrack = false
    @Published var playbackError: String?
    @Published var isNowPlayingVisible = false

    private let player = AVPlayer()
    private let nowPlayingSession = AudioNowPlayingSession()
    private let persistence = AudioPlaybackPersistence()
    private var playbackQueue = AudioPlaybackQueue()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var audioSessionObservers: [NSObjectProtocol] = []
    private var preparationTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var playbackGeneration = UUID()
    private var lastPersistedSecond = -1
    private var shouldResumeAfterInterruption = false

    init() {
        configureNowPlayingSession()
        configureAudioSessionObservers()
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = Float(volume)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                self.persistProgressIfNeeded()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackEnded() }
        }
        restorePlaybackSnapshot()
    }

    deinit {
        preparationTask?.cancel()
        sleepTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        for observer in audioSessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func play(_ item: LibraryItem, in items: [LibraryItem]? = nil) {
        if let items, !items.isEmpty {
            let filtered = items.filter { $0.kind == .music }
            let index = filtered.firstIndex(of: item) ?? 0
            playbackQueue.replace(with: filtered, startingAt: index)
        } else if queue.isEmpty {
            playbackQueue.replace(with: [item], startingAt: 0)
        } else if !playbackQueue.select(item: item) {
            playbackQueue.replace(with: queue + [item], startingAt: queue.count)
        }
        syncQueueState()
        preparePlayback(for: item, startAt: 0, autoplay: true)
    }

    private func preparePlayback(for item: LibraryItem, startAt: TimeInterval, autoplay: Bool) {
        preparationTask?.cancel()
        let generation = UUID()
        playbackGeneration = generation
        currentItem = item
        currentMetadata = metadataByPath[item.relativePath] ?? .empty
        currentTime = max(0, startAt)
        duration = 0
        isPlaying = false
        isPreparing = true
        playbackError = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        persistSnapshot()

        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let preparedURL = UniversalAudioSource.playbackURL(for: item.url)
                async let metadata = EmbeddedAudioMetadata.load(from: item.url)
                let (url, loadedMetadata) = try await (preparedURL, metadata)
                guard !Task.isCancelled, self.playbackGeneration == generation else { return }
                self.metadataByPath[item.relativePath] = loadedMetadata
                self.currentMetadata = loadedMetadata
                self.startPlayback(url: url, sourceItem: item, startAt: startAt, autoplay: autoplay)
            } catch {
                guard !Task.isCancelled, self.playbackGeneration == generation else { return }
                self.isPreparing = false
                self.playbackError = error.localizedDescription
                self.updateNowPlayingInfo()
                self.persistSnapshot()
            }
        }
    }

    func setQueue(_ items: [LibraryItem]) {
        let filtered = items.filter { $0.kind == .music }
        guard !filtered.isEmpty, filtered != queue else { return }
        let selectedIndex = currentItem.flatMap { filtered.firstIndex(of: $0) } ?? 0
        playbackQueue.replace(with: filtered, startingAt: selectedIndex)
        syncQueueState()
        persistSnapshot()
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
        guard let currentItem, !isPreparing else {
            if currentItem == nil, let first = queue.first { play(first, in: queue) }
            return
        }
        guard player.currentItem != nil else {
            preparePlayback(for: currentItem, startAt: currentTime, autoplay: true)
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            #if os(iOS)
            do {
                try activateAudioSession()
            } catch {
                playbackError = error.localizedDescription
                updateNowPlayingInfo()
                persistSnapshot()
                return
            }
            #endif
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
        }
        updateNowPlayingInfo()
        persistSnapshot()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
        persistSnapshot()
    }

    func seek(to seconds: TimeInterval) {
        let clamped = min(max(0, seconds), max(duration, 0))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
        updateNowPlayingElapsedTime()
        persistSnapshot()
    }

    func playbackPosition() -> TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : currentTime
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = min(max(rate, 0.5), 3)
        player.defaultRate = playbackRate
        if isPlaying { player.rate = playbackRate }
        updateNowPlayingInfo()
        persistSnapshot()
    }

    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        player.volume = Float(volume)
        persistSnapshot()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        persistSnapshot()
    }

    func toggleShuffle() {
        playbackQueue.toggleShuffle()
        syncQueueState()
        persistSnapshot()
    }

    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        stopAfterCurrentTrack = false
        guard let minutes else {
            sleepTimerEnd = nil
            return
        }
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEnd = end
        sleepTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(TimeInterval(minutes * 60)))
            } catch {
                return
            }
            guard let self, self.sleepTimerEnd == end else { return }
            self.pause()
            self.sleepTimerEnd = nil
        }
    }

    func sleepAfterCurrentTrack() {
        sleepTask?.cancel()
        sleepTimerEnd = nil
        stopAfterCurrentTrack = true
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTimerEnd = nil
        stopAfterCurrentTrack = false
    }

    func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            return
        }
        guard playbackQueue.move(by: 1, wraps: repeatMode == .all),
              let next = playbackQueue.currentItem else {
            pause()
            seek(to: 0)
            return
        }
        syncQueueState()
        preparePlayback(for: next, startAt: 0, autoplay: true)
    }

    func playPrevious() {
        guard currentTime < 4, !queue.isEmpty else {
            seek(to: 0)
            return
        }
        guard playbackQueue.move(by: -1, wraps: repeatMode == .all),
              let previous = playbackQueue.currentItem else {
            seek(to: 0)
            return
        }
        syncQueueState()
        preparePlayback(for: previous, startAt: 0, autoplay: true)
    }

    func playFromQueue(at index: Int) {
        guard playbackQueue.select(index: index),
              let item = playbackQueue.currentItem else { return }
        syncQueueState()
        preparePlayback(for: item, startAt: 0, autoplay: true)
    }

    private func startPlayback(url: URL, sourceItem: LibraryItem, startAt: TimeInterval, autoplay: Bool) {
        guard currentItem == sourceItem else { return }
        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredForwardBufferDuration = 20
        playerItem.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: playerItem)
        player.defaultRate = playbackRate
        isPreparing = false
        if startAt > 0 {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
            currentTime = startAt
        }
        if autoplay {
            #if os(iOS)
            do {
                try activateAudioSession()
            } catch {
                playbackError = error.localizedDescription
                isPlaying = false
                updateNowPlayingInfo()
                persistSnapshot()
                return
            }
            #endif
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
        } else {
            isPlaying = false
        }
        updateNowPlayingInfo()
        persistSnapshot()

        Task { [weak self, weak playerItem] in
            guard let self, let playerItem else { return }
            if let loadedDuration = try? await playerItem.asset.load(.duration),
               self.currentItem == sourceItem {
                self.duration = loadedDuration.seconds.isFinite ? loadedDuration.seconds : 0
                self.updateNowPlayingInfo()
                self.persistSnapshot()
            }
        }
    }

    private func handlePlaybackEnded() {
        if stopAfterCurrentTrack {
            stopAfterCurrentTrack = false
            pause()
            seek(to: 0)
            return
        }
        if repeatMode == .one {
            seek(to: 0)
            #if os(iOS)
            try? activateAudioSession()
            #endif
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
            updateNowPlayingInfo()
            persistSnapshot()
            return
        }
        guard !queue.isEmpty else {
            pause()
            return
        }
        guard playbackQueue.move(by: 1, wraps: repeatMode == .all),
              let next = playbackQueue.currentItem else {
            pause()
            seek(to: 0)
            return
        }
        syncQueueState()
        preparePlayback(for: next, startAt: 0, autoplay: true)
    }

    private func restorePlaybackSnapshot() {
        guard let snapshot = persistence.load(), !snapshot.queue.isEmpty else { return }
        playbackQueue.restore(
            items: snapshot.queue,
            currentIndex: snapshot.currentIndex,
            isShuffled: snapshot.isShuffled,
            shuffledOrder: snapshot.shuffledOrder
        )
        syncQueueState()
        guard !queue.isEmpty else {
            persistence.clear()
            return
        }
        repeatMode = AudioRepeatMode(rawValue: snapshot.repeatMode) ?? .off
        playbackRate = min(max(snapshot.playbackRate, 0.5), 3)
        setVolume(snapshot.volume)
        currentItem = playbackQueue.currentItem
        currentTime = max(snapshot.progress, 0)
        if let currentItem {
            currentMetadata = metadataByPath[currentItem.relativePath] ?? .empty
            Task { @MainActor [weak self, currentItem] in
                guard let self else { return }
                let metadata = await self.loadMetadata(for: currentItem)
                guard self.currentItem == currentItem else { return }
                self.currentMetadata = metadata
                let asset = AVURLAsset(url: currentItem.url)
                if let loadedDuration = try? await asset.load(.duration), loadedDuration.seconds.isFinite {
                    self.duration = loadedDuration.seconds
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func syncQueueState() {
        queue = playbackQueue.items
        isShuffleEnabled = playbackQueue.isShuffled
    }

    private func persistProgressIfNeeded() {
        guard currentItem != nil else { return }
        let second = Int(currentTime)
        guard second != lastPersistedSecond else { return }
        lastPersistedSecond = second
        updateNowPlayingElapsedTime()
        persistSnapshot()
    }

    private func persistSnapshot() {
        guard !queue.isEmpty else {
            persistence.clear()
            return
        }
        persistence.save(
            AudioPlaybackSnapshot(
                queue: queue,
                currentIndex: playbackQueue.currentIndex,
                progress: currentTime,
                repeatMode: repeatMode.rawValue,
                isShuffled: isShuffleEnabled,
                shuffledOrder: playbackQueue.persistedShuffleOrder,
                playbackRate: playbackRate,
                volume: volume
            )
        )
    }

    private func configureAudioSessionObservers() {
        #if os(iOS)
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in self?.handleAudioInterruption(notification) }
            }
        )
        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in self?.handleAudioRouteChange(notification) }
            }
        )
        #endif
    }

    #if os(iOS)
    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            shouldResumeAfterInterruption = isPlaying
            pause()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            if shouldResume, shouldResumeAfterInterruption {
                togglePlayback()
            }
            shouldResumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else {
            return
        }
        shouldResumeAfterInterruption = false
        pause()
    }
    #endif

    private func configureNowPlayingSession() {
        nowPlayingSession.onPlay = { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.togglePlayback()
        }
        nowPlayingSession.onPause = { [weak self] in
            self?.pause()
        }
        nowPlayingSession.onNext = { [weak self] in
            self?.playNext()
        }
        nowPlayingSession.onPrevious = { [weak self] in
            self?.playPrevious()
        }
        nowPlayingSession.onSeek = { [weak self] position in
            self?.seek(to: position)
        }
    }

    private func updateNowPlayingInfo() {
        guard let currentItem else {
            nowPlayingSession.clear()
            return
        }
        nowPlayingSession.setItem(
            currentItem,
            metadata: currentMetadata,
            duration: duration,
            queueIndex: playbackQueue.currentIndex,
            queueCount: queue.count
        )
        nowPlayingSession.updatePlayback(
            position: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )
    }

    private func updateNowPlayingElapsedTime() {
        nowPlayingSession.updatePlayback(
            position: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )
    }
}

@MainActor
private final class AudioNowPlayingSession {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var nowPlayingInfo: [String: Any] = [:]
    private var representedPath: String?

    init() {
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
        representedPath = item.relativePath
        nowPlayingInfo = [
            MPMediaItemPropertyTitle: metadata.title ?? item.displayName,
            MPMediaItemPropertyAlbumTitle: metadata.album ?? "鱼饼",
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
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
