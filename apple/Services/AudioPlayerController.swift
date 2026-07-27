import AVFoundation
import Foundation


struct EmbeddedAudioMetadata: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var year: String?
    var trackNumber: String?
    var discNumber: String?
    var composer: String?
    var codec: String?
    var channelLayout: String?
    var sampleRate: Int?
    var bitDepth: Int?
    var channelCount: Int?
    var bitRate: Int?
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
        composer: nil,
        codec: nil,
        channelLayout: nil,
        sampleRate: nil,
        bitDepth: nil,
        channelCount: nil,
        bitRate: nil,
        isLossless: false,
        artworkData: nil,
        lyrics: nil
    )

    var hasDetails: Bool {
        [title, artist, album, albumArtist, genre, year, composer].contains { value in
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
        if let sampleRate, sampleRate > 0 {
            let value = Double(sampleRate) / 1_000
            details.append(value.rounded() == value ? "\(Int(value)) kHz" : String(format: "%.1f kHz", value))
        }
        if let bitDepth, bitDepth > 0 { details.append("\(bitDepth)-bit") }
        if let codec, !codec.isEmpty { details.append(codec.uppercased()) }
        return details.joined(separator: " · ")
    }

    var sampleRateDescription: String? {
        guard let sampleRate, sampleRate > 0 else { return nil }
        let value = Double(sampleRate) / 1_000
        let formatted = value.rounded() == value
            ? "\(Int(value)) kHz"
            : String(format: "%.1f kHz", value)
        return "\(sampleRate.formatted()) Hz (\(formatted))"
    }

    var bitRateDescription: String? {
        guard let bitRate, bitRate > 0 else { return nil }
        let kilobits = Int((Double(bitRate) / 1_000).rounded())
        guard kilobits > 0 else { return nil }
        return "\(kilobits) kbps"
    }

    var channelDescription: String? {
        guard let channelCount, channelCount > 0 else { return nil }
        guard let name = Self.channelLayoutName(count: channelCount, layout: channelLayout) else {
            return "\(channelCount)"
        }
        return "\(channelCount) (\(name))"
    }

    private static func channelLayoutName(count: Int, layout: String?) -> String? {
        switch count {
        case 1: return AppLocalization.string("单声道")
        case 2: return AppLocalization.string("立体声")
        default: break
        }
        guard let layout else { return nil }
        let trimmed = layout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        let avComposer = await stringValue(
            in: allItems,
            identifiers: [],
            hints: ["composer", "tcom", "\u{00A9}wrt", "wrt"]
        )
        let avTrackNumber = await stringValue(in: allItems, identifiers: [], hints: ["tracknumber", "track_number"])
        let avDiscNumber = await stringValue(in: allItems, identifiers: [], hints: ["discnumber", "disc_number"])
        let avLyrics = await stringValue(in: allItems, identifiers: [], hints: ["lyric", "unsynchronizedlyric"])
        let avArtworkData = await dataValue(in: allItems, identifier: .commonIdentifierArtwork, hints: ["artwork", "picture", "cover"])
        let id3Lyrics = ID3EmbeddedLyricsReader.read(from: url)
        let trackNumber = containerMetadata?.trackNumber ?? flacMetadata?.trackNumber ?? avTrackNumber
        let discNumber = containerMetadata?.discNumber ?? flacMetadata?.discNumber ?? avDiscNumber
        let composer = containerMetadata?.composer ?? flacMetadata?.composer ?? avComposer
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
            composer: composer,
            codec: containerMetadata?.codec ?? properties.codec ?? ext,
            channelLayout: containerMetadata?.channelLayout,
            sampleRate: containerMetadata?.sampleRate ?? flacMetadata?.sampleRate ?? properties.sampleRate,
            bitDepth: containerMetadata?.bitDepth ?? flacMetadata?.bitDepth ?? properties.bitDepth,
            channelCount: containerMetadata?.channelCount
                ?? flacMetadata?.channelCount
                ?? properties.channelCount,
            bitRate: containerMetadata?.bitRate
                ?? flacMetadata?.bitRate
                ?? properties.bitRate
                ?? estimatedBitRate(for: url, duration: properties.duration),
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

    private static func audioProperties(
        from asset: AVURLAsset
    ) async -> (
        codec: String?,
        sampleRate: Int?,
        bitDepth: Int?,
        channelCount: Int?,
        bitRate: Int?,
        duration: TimeInterval?
    ) {
        let assetDuration = (try? await asset.load(.duration)).map(CMTimeGetSeconds)
        let duration = (assetDuration?.isFinite == true && (assetDuration ?? 0) > 0) ? assetDuration : nil
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let descriptions = try? await track.load(.formatDescriptions),
              let description = descriptions.first else {
            return (nil, nil, nil, nil, nil, duration)
        }
        let estimatedRate = (try? await track.load(.estimatedDataRate)).flatMap { rate -> Int? in
            guard rate.isFinite, rate > 0 else { return nil }
            return Int(rate.rounded())
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
            return (codec, nil, nil, nil, estimatedRate, duration)
        }
        let sampleRate = basic.pointee.mSampleRate > 0 ? Int(basic.pointee.mSampleRate.rounded()) : nil
        let bitDepth = basic.pointee.mBitsPerChannel > 0 ? Int(basic.pointee.mBitsPerChannel) : nil
        let channelCount = basic.pointee.mChannelsPerFrame > 0
            ? Int(basic.pointee.mChannelsPerFrame)
            : nil
        return (codec, sampleRate, bitDepth, channelCount, estimatedRate, duration)
    }

    private static func estimatedBitRate(for url: URL, duration: TimeInterval?) -> Int? {
        guard let duration, duration > 0,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0 else { return nil }
        return Int((Double(size) * 8 / duration).rounded())
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
import Observation

@MainActor
@Observable
final class AudioPlayerController {
    private(set) var currentItem: LibraryItem?
    private(set) var isPlaying = false
    private(set) var isPreparing = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var queue: [LibraryItem] = []
    private(set) var currentMetadata = EmbeddedAudioMetadata.empty
    private(set) var metadataByPath: [String: EmbeddedAudioMetadata] = [:]
    private(set) var playbackRate: Float = 1
    private(set) var volume: Double = 1
    private(set) var repeatMode: AudioRepeatMode = .off
    private(set) var isShuffleEnabled = false
    private(set) var sleepTimerEnd: Date?
    private(set) var stopAfterCurrentTrack = false
    private(set) var seekRevision = 0
    private(set) var totalListeningTime: TimeInterval
    var playbackError: String?

    @ObservationIgnored
    private let engine: AudioPlaybackEngine

    @ObservationIgnored
    private let nowPlayingSession: AudioNowPlayingSession

    @ObservationIgnored
    private let persistence = AudioPlaybackPersistence()

    @ObservationIgnored
    private var playbackQueue = AudioPlaybackQueue()

    @ObservationIgnored
    private var preparationTask: Task<Void, Never>?

    @ObservationIgnored
    private var sleepTask: Task<Void, Never>?

    @ObservationIgnored
    private var playbackGeneration = UUID()

    @ObservationIgnored
    private var shouldResumeAfterInterruption = false

    @ObservationIgnored
    private var isResolvingSource = false

    @ObservationIgnored
    private var lastPersistedSecond = -1

    @ObservationIgnored
    private var lastListeningTick = Date()

    /// Deliberately untracked: `estimatedProgress(at:)` reads this from
    /// per-frame view bodies, so tracking it would invalidate those views on
    /// every progress sample and undo the point of the migration.
    @ObservationIgnored
    private var lastProgressUpdateDate = Date()

    private static let totalListeningTimeKey = "yubing.totalListeningTime"

    init() {
        let engine = AudioPlaybackEngine()
        self.engine = engine
        totalListeningTime = UserDefaults.standard.double(forKey: Self.totalListeningTimeKey)
        nowPlayingSession = AudioNowPlayingSession(player: engine.nowPlayingPlayer)
        bindEngine()
        bindRemoteCommands()
        engine.setPlaybackRate(playbackRate)
        engine.setVolume(volume)
        restorePlaybackSnapshot()
    }

    deinit {
        preparationTask?.cancel()
        sleepTask?.cancel()
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
        isResolvingSource = true
        playbackError = nil
        lastProgressUpdateDate = Date()
        engine.unload()
        updateNowPlayingInfo()
        persistSnapshot()

        if !item.url.isFileURL {
            let metadata = metadataByPath[item.relativePath] ?? .empty
            currentMetadata = metadata
            startPlayback(url: item.url, sourceItem: item, startAt: startAt, autoplay: autoplay)
            return
        }

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
                self.isResolvingSource = false
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
        updateNowPlayingInfo()
        persistSnapshot()
    }

    func loadMetadata(for item: LibraryItem) async -> EmbeddedAudioMetadata {
        if let cached = metadataByPath[item.relativePath] { return cached }
        guard item.url.isFileURL else { return .empty }
        let metadata = await EmbeddedAudioMetadata.load(from: item.url)
        metadataByPath[item.relativePath] = metadata
        if currentItem == item {
            currentMetadata = metadata
            updateNowPlayingInfo()
        }
        return metadata
    }

    func registerMetadata(_ metadata: EmbeddedAudioMetadata, for item: LibraryItem) {
        metadataByPath[item.relativePath] = metadata
        guard currentItem == item else { return }
        currentMetadata = metadata
        updateNowPlayingInfo()
    }

    func togglePlayback() {
        guard let currentItem else {
            if let first = queue.first { play(first, in: queue) }
            return
        }
        if engine.hasCurrentItem {
            if isPlaying {
                engine.pause()
                persistSnapshot()
            } else {
                playbackError = nil
                engine.play()
            }
        } else if !isResolvingSource {
            preparePlayback(for: currentItem, startAt: currentTime, autoplay: true)
        }
    }

    func pause() {
        engine.pause()
        persistSnapshot()
    }

    func seek(to seconds: TimeInterval) {
        let maximum = max(duration, 0)
        let clamped = maximum > 0 ? min(max(0, seconds), maximum) : max(0, seconds)
        engine.seek(to: clamped)
        currentTime = clamped
        seekRevision += 1
        lastProgressUpdateDate = Date()
        updateNowPlayingState()
        persistSnapshot()
    }

    func playbackPosition() -> TimeInterval {
        engine.hasCurrentItem ? engine.currentTime : currentTime
    }

    /// Playback position extrapolated for per-frame consumers such as the
    /// word-by-word lyrics.
    ///
    /// `AVPlayer` only reports progress twice a second, so the position is
    /// extrapolated from the most recent sample. Each new sample re-anchors the
    /// estimate, which keeps the error bounded by one sampling interval instead
    /// of letting it accumulate.
    func estimatedProgress(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return currentTime }
        let elapsed = max(date.timeIntervalSince(lastProgressUpdateDate), 0)
        let estimated = currentTime + elapsed * Double(playbackRate)
        return duration > 0 ? min(estimated, duration) : estimated
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = min(max(rate, 0.5), 3)
        engine.setPlaybackRate(playbackRate)
        updateNowPlayingState()
        persistSnapshot()
    }

    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        engine.setVolume(volume)
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
        updateNowPlayingInfo()
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
            engine.pause()
            return
        }
        guard playbackQueue.move(by: 1, wraps: repeatMode == .all),
              let next = playbackQueue.currentItem else {
            engine.pause()
            engine.seek(to: 0)
            currentTime = 0
            seekRevision += 1
            persistSnapshot()
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
        isResolvingSource = false
        updateNowPlayingInfo()
        engine.setPlaybackRate(playbackRate)
        engine.setVolume(volume)
        engine.load(url: url, startAt: startAt, autoplay: autoplay)
    }

    private func handlePlaybackEnded() {
        if stopAfterCurrentTrack {
            stopAfterCurrentTrack = false
            engine.pause()
            engine.seek(to: 0)
            currentTime = 0
            seekRevision += 1
            persistSnapshot()
            return
        }
        if repeatMode == .one {
            engine.seek(to: 0)
            currentTime = 0
            seekRevision += 1
            engine.play()
            return
        }
        guard !queue.isEmpty else {
            engine.pause()
            return
        }
        guard playbackQueue.move(by: 1, wraps: repeatMode == .all),
              let next = playbackQueue.currentItem else {
            engine.pause()
            engine.seek(to: 0)
            currentTime = 0
            seekRevision += 1
            persistSnapshot()
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
        guard let item = playbackQueue.currentItem else {
            persistence.clear()
            return
        }
        repeatMode = AudioRepeatMode(rawValue: snapshot.repeatMode) ?? .off
        playbackRate = min(max(snapshot.playbackRate, 0.5), 3)
        volume = min(max(snapshot.volume, 0), 1)
        engine.setPlaybackRate(playbackRate)
        engine.setVolume(volume)
        preparePlayback(for: item, startAt: max(snapshot.progress, 0), autoplay: false)
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
        persistSnapshot()
    }

    private func persistSnapshot() {
        guard currentItem?.url.isFileURL != false else { return }
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

    private func bindEngine() {
        engine.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.commitListeningTimeIfNeeded()
            switch state {
            case .idle:
                self.isPlaying = false
                if !self.isResolvingSource {
                    self.isPreparing = false
                }
            case .loading:
                self.isPlaying = false
                self.isPreparing = true
            case .paused:
                self.isPlaying = false
                self.isPreparing = false
            case .playing:
                self.isPlaying = true
                self.isPreparing = false
                self.playbackError = nil
            }
            self.currentTime = self.engine.hasCurrentItem
                ? self.engine.currentTime
                : self.currentTime
            self.lastProgressUpdateDate = Date()
            self.lastListeningTick = Date()
            self.updateNowPlayingState()
        }
        engine.onProgressChanged = { [weak self] value in
            guard let self else { return }
            self.commitListeningTimeIfNeeded()
            self.currentTime = value
            self.lastProgressUpdateDate = Date()
            self.persistProgressIfNeeded()
        }
        engine.onDurationChanged = { [weak self] value in
            guard let self else { return }
            self.duration = value
            self.updateNowPlayingState()
            self.persistSnapshot()
        }
        engine.onPlaybackEnded = { [weak self] in
            self?.handlePlaybackEnded()
        }
        engine.onFailure = { [weak self] error in
            guard let self else { return }
            self.isResolvingSource = false
            self.isPreparing = false
            self.isPlaying = false
            self.playbackError = error.localizedDescription
            self.updateNowPlayingState()
            if let playbackError = error as? AudioPlaybackError,
               case .itemFailed = playbackError {
                self.engine.unload()
            }
            self.persistSnapshot()
        }
        engine.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.shouldResumeAfterInterruption = self.isPlaying
            self.engine.pause()
        }
        engine.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            if shouldResume, self.shouldResumeAfterInterruption {
                self.engine.play()
            }
            self.shouldResumeAfterInterruption = false
        }
        engine.onOutputDeviceDisconnected = { [weak self] in
            self?.shouldResumeAfterInterruption = false
        }
    }

    private func bindRemoteCommands() {
        nowPlayingSession.onPlay = { [weak self] in
            guard let self else { return }
            if self.engine.hasCurrentItem {
                self.engine.play()
            } else if let item = self.currentItem, !self.isResolvingSource {
                self.preparePlayback(for: item, startAt: self.currentTime, autoplay: true)
            }
        }
        nowPlayingSession.onPause = { [weak self] in
            self?.engine.pause()
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
        updateNowPlayingState()
    }

    private func updateNowPlayingState() {
        nowPlayingSession.updatePlayback(
            position: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )
    }

    private func commitListeningTimeIfNeeded() {
        guard isPlaying else {
            lastListeningTick = Date()
            return
        }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastListeningTick)
        lastListeningTick = now
        guard elapsed.isFinite, elapsed > 0 else { return }
        totalListeningTime += min(elapsed, 90)
        UserDefaults.standard.set(totalListeningTime, forKey: Self.totalListeningTimeKey)
    }
}
