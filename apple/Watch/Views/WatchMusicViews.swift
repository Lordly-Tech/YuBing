import ImageIO
import SwiftUI
import WatchKit

// Watch player and lyric motion adapt MeloX's GPL-3.0 playback experience for watchOS.

struct WatchMusicLibraryView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer
    @State private var query = ""

    private var mediaItems: [WatchLibraryItem] {
        store.items(of: [.music])
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var audioTracks: [WatchLibraryItem] { store.items(of: [.music]) }

    var body: some View {
        Group {
            if mediaItems.isEmpty {
                ContentUnavailableView(
                    "还没有音乐",
                    systemImage: "music.note.list",
                    description: Text("从 iPhone 传入音乐后可离线播放。")
                )
            } else {
                List(mediaItems) { item in
                    Button {
                        player.play(item, queue: audioTracks)
                        store.markOpened(item)
                    } label: {
                        HStack(spacing: 8) {
                            WatchAudioArtwork(
                                data: player.metadataByPath[item.relativePath]?.artworkData,
                                size: 42
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.metadataByPath[item.relativePath]?.title ?? item.displayName)
                                    .lineLimit(1)
                                Text(audioDetail(for: item))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(
                                systemName: player.currentItem == item && player.isPlaying
                                    ? "speaker.wave.2.fill"
                                    : "play.circle.fill"
                            )
                            .foregroundStyle(.pink)
                        }
                    }
                    .task { _ = await player.loadMetadata(for: item) }
                }
            }
        }
        .navigationTitle("音乐")
        .searchable(text: $query, prompt: "搜索")
        .toolbar {
            if let item = player.currentItem {
                NavigationLink {
                    WatchNowPlayingView(startingItem: item)
                } label: {
                    Label("正在播放", systemImage: "waveform")
                }
            }
        }
    }

    private func audioDetail(for item: WatchLibraryItem) -> String {
        let metadata = player.metadataByPath[item.relativePath]
        let details = [metadata?.artist, metadata?.album]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return details.isEmpty ? item.byteCount.watchFormattedFileSize : details.joined(separator: " · ")
    }
}

private enum WatchPlayerPage: Hashable {
    case artwork
    case lyrics
    case queue
}

struct WatchNowPlayingView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer
    let startingItem: WatchLibraryItem
    @State private var page: WatchPlayerPage = .artwork

    private var tracks: [WatchLibraryItem] { store.items(of: [.music]) }

    var body: some View {
        TabView(selection: $page) {
            WatchArtworkPlayerView().tag(WatchPlayerPage.artwork)
            WatchLyricsView().tag(WatchPlayerPage.lyrics)
            WatchPlaybackQueueView().tag(WatchPlayerPage.queue)
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle(player.currentMetadata.title ?? startingItem.displayName)
        .onAppear {
            if player.currentItem != startingItem {
                player.play(startingItem, queue: tracks)
            }
            store.markOpened(startingItem)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("播放速度") {
                        ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { rate in
                            Button {
                                player.setPlaybackRate(Float(rate))
                            } label: {
                                if player.playbackRate == Float(rate) {
                                    Label("\(rate.formatted())x", systemImage: "checkmark")
                                } else {
                                    Text("\(rate.formatted())x")
                                }
                            }
                        }
                    }
                    Button { player.cycleRepeatMode() } label: {
                        Label(player.repeatMode.title, systemImage: player.repeatMode == .one ? "repeat.1" : "repeat")
                    }
                    Button { player.toggleShuffle() } label: {
                        Label("随机播放", systemImage: player.isShuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }
}

private struct WatchArtworkPlayerView: View {
    @EnvironmentObject private var player: WatchAudioPlayer

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = min(proxy.size.width * 0.48, proxy.size.height * 0.42)
            VStack(spacing: 7) {
                WatchAudioArtwork(data: player.currentMetadata.artworkData, size: artworkSize)
                    .scaleEffect(player.isPlaying ? 1 : 0.9)
                    .animation(.smooth(duration: 0.4), value: player.isPlaying)

                VStack(spacing: 1) {
                    Text(player.currentMetadata.title ?? player.currentItem?.displayName ?? "音乐")
                        .font(.headline)
                        .lineLimit(1)
                    Text(player.currentMetadata.artist ?? player.currentMetadata.album ?? "本地音乐")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Slider(
                    value: Binding(
                        get: { min(player.currentTime, max(player.duration, 1)) },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .tint(.pink)
                .accessibilityLabel("播放进度")

                HStack(spacing: 16) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill")
                    }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill")
                    }
                }
                .buttonStyle(.plain)
                .font(.headline)

                HStack {
                    Text(player.currentTime.watchPlaybackTime)
                    Spacer()
                    Text("−\(max(player.duration - player.currentTime, 0).watchPlaybackTime)")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct WatchLyricsView: View {
    @EnvironmentObject private var player: WatchAudioPlayer
    @State private var visualActiveIndex: Int?
    @State private var isBrowsing = false
    @State private var browseGeneration = 0

    private var activeIndex: Int? {
        player.currentMetadata.lyrics?.lineIndex(at: player.currentTime)
    }

    var body: some View {
        Group {
            if let lyrics = player.currentMetadata.lyrics, !lyrics.lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                                WatchAnimatedLyricLine(
                                    line: line,
                                    nextLineTime: lyrics.lines.indices.contains(index + 1)
                                        ? lyrics.lines[index + 1].time
                                        : nil,
                                    isActive: index == activeIndex
                                )
                                .scaleEffect(index == visualActiveIndex ? 1.08 : 1, anchor: .leading)
                                .opacity(lyricOpacity(for: index))
                                .blur(radius: lyricBlur(for: index))
                                .offset(y: index == visualActiveIndex ? -2 : 0)
                                .animation(focusAnimation(for: index), value: visualActiveIndex)
                                .id(line.id)
                                .contentShape(Rectangle())
                                .onTapGesture { player.seek(to: line.time) }
                            }
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 55)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { _ in
                                browseGeneration += 1
                                isBrowsing = true
                            }
                            .onEnded { _ in scheduleFollowing() }
                    )
                    .onAppear {
                        visualActiveIndex = activeIndex
                        scrollToActive(lyrics, proxy: proxy, animated: false)
                    }
                    .onChange(of: activeIndex) { _, index in
                        visualActiveIndex = index
                        guard !isBrowsing else { return }
                        scrollToActive(lyrics, proxy: proxy, animated: true)
                    }
                }
            } else {
                ContentUnavailableView(
                    "没有歌词",
                    systemImage: "quote.bubble",
                    description: Text("从 iPhone 一并传入 LRC 或 YRC 歌词。")
                )
            }
        }
    }

    private func scrollToActive(
        _ lyrics: TimedLyrics,
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let activeIndex, lyrics.lines.indices.contains(activeIndex) else { return }
        let action = { proxy.scrollTo(lyrics.lines[activeIndex].id, anchor: .center) }
        if animated {
            withAnimation(.smooth(duration: 0.32), action)
        } else {
            action()
        }
    }

    private func lyricOpacity(for index: Int) -> Double {
        guard let visualActiveIndex else { return 0.5 }
        let distance = abs(index - visualActiveIndex)
        if index == activeIndex { return 1 }
        return max(0.2, 0.62 - Double(distance) * 0.13)
    }

    private func lyricBlur(for index: Int) -> CGFloat {
        guard let visualActiveIndex else { return 0 }
        return max(CGFloat(abs(index - visualActiveIndex) - 1) * 0.8, 0)
    }

    private func focusAnimation(for index: Int) -> Animation {
        let active = visualActiveIndex ?? index
        return .spring(duration: 0.52, bounce: 0.35)
            .delay(Double(min(max(index - active, 0), 8)) * 0.022)
    }

    private func scheduleFollowing() {
        let generation = browseGeneration
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
            guard generation == browseGeneration else { return }
            isBrowsing = false
        }
    }
}

private struct WatchAnimatedLyricLine: View {
    @EnvironmentObject private var player: WatchAudioPlayer
    let line: TimedLyricLine
    let nextLineTime: TimeInterval?
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isActive {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !player.isPlaying)) { _ in
                    WatchLyricFlowLayout(spacing: 0) {
                        ForEach(timedCharacters) { character in
                            let progress = character.progress(at: player.playbackPosition())
                            Text(character.text)
                                .font(.headline.bold())
                                .foregroundStyle(.white.opacity(0.28 + progress * 0.72))
                                .offset(y: CGFloat(-2.5 * progress))
                                .scaleEffect(CGFloat(1 + 0.05 * sin(.pi * progress)))
                                .shadow(
                                    color: .pink.opacity(0.72 * character.glow(at: player.playbackPosition())),
                                    radius: 5
                                )
                        }
                    }
                }
            } else {
                Text(line.text)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let translation = line.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
               !translation.isEmpty {
                Text(translation)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timedCharacters: [WatchLyricCharacter] {
        let lineEnd = line.duration.map { line.time + $0 }
            ?? nextLineTime
            ?? line.time + 4
        let syllables: [(String, TimeInterval, TimeInterval)]
        if line.words.isEmpty {
            let characters = Array(line.text)
            let duration = max(lineEnd - line.time, 0.1) / Double(max(characters.count, 1))
            syllables = characters.enumerated().map { index, value in
                let start = line.time + Double(index) * duration
                return (String(value), start, start + duration)
            }
        } else {
            syllables = line.words.enumerated().map { index, word in
                let end = word.endTime
                    ?? (line.words.indices.contains(index + 1) ? line.words[index + 1].time : lineEnd)
                return (word.text, word.time, max(end, word.time + 0.01))
            }
        }

        return syllables.flatMap { text, start, end in
            let characters = Array(text)
            let duration = max(end - start, 0.01) / Double(max(characters.count, 1))
            return characters.enumerated().map { index, value in
                let characterStart = start + Double(index) * duration
                return WatchLyricCharacter(
                    id: "\(characterStart)-\(index)-\(value)",
                    text: String(value),
                    start: characterStart,
                    end: characterStart + duration
                )
            }
        }
    }
}

private struct WatchLyricCharacter: Identifiable {
    let id: String
    let text: String
    let start: TimeInterval
    let end: TimeInterval

    func progress(at time: TimeInterval) -> Double {
        min(max((time - start) / max(end - start, 0.01), 0), 1)
    }

    func glow(at time: TimeInterval) -> Double {
        let progress = progress(at: time)
        if time <= end { return sin(.pi * progress) * 0.35 + 0.65 * progress }
        return max(0, 1 - (time - end) / 0.55) * 0.65
    }
}

private struct WatchLyricFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(subviews: subviews, width: proposal.width ?? 180).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, point) in result.points.enumerated() where subviews.indices.contains(index) {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + 2
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

private struct WatchPlaybackQueueView: View {
    @EnvironmentObject private var player: WatchAudioPlayer

    var body: some View {
        if player.queue.isEmpty {
            ContentUnavailableView("队列为空", systemImage: "list.bullet")
        } else {
            List(player.queue) { item in
                Button {
                    player.play(item, queue: player.queue)
                } label: {
                    HStack(spacing: 7) {
                        WatchAudioArtwork(
                            data: player.metadataByPath[item.relativePath]?.artworkData,
                            size: 34
                        )
                        Text(player.metadataByPath[item.relativePath]?.title ?? item.displayName)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if player.currentItem == item {
                            Image(systemName: "speaker.wave.2.fill").foregroundStyle(.pink)
                        }
                    }
                }
            }
        }
    }
}

struct WatchGalleryView: View {
    @EnvironmentObject private var store: WatchLibraryStore

    private var mediaItems: [WatchLibraryItem] { store.items(of: [.photo, .video]) }

    var body: some View {
        Group {
            if mediaItems.isEmpty {
                ContentUnavailableView(
                    "图库是空的",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("从 iPhone 传入照片或视频后可离线查看。")
                )
            } else {
                List(mediaItems) { item in
                    NavigationLink { WatchItemDestination(item: item) } label: {
                        WatchFileRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("图库")
    }
}

private struct WatchAudioArtwork: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.pink.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WatchVideoPlayerView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    let item: WatchLibraryItem
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.purple)
                VStack(spacing: 2) {
                    Text(item.displayName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(item.byteCount.watchFormattedFileSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button { playVideo() } label: {
                    Label("播放视频", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .watchGlassButton(prominent: true)
                if let message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(item.displayName)
        .onAppear { store.markOpened(item) }
    }

    private func playVideo() {
        guard let controller = WKExtension.shared().rootInterfaceController else {
            message = "暂时无法打开系统播放器。"
            return
        }
        let options: [AnyHashable: Any] = [WKMediaPlayerControllerOptionsAutoplayKey: true]
        controller.presentMediaPlayerController(with: item.url, options: options) { didPlayToEnd, _, error in
            Task { @MainActor in
                if let error {
                    message = error.localizedDescription
                } else {
                    message = didPlayToEnd ? "播放完成" : "已关闭播放器"
                }
            }
        }
    }
}
