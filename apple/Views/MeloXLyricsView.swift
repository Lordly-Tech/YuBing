import SwiftUI

// Focus following and staggered lyric movement adapted from youshen2/MeloX (GPL-3.0).

enum NowPlayingLyricsPresentation: Equatable {
    case portrait
    case landscape
}

struct NowPlayingLyricsPage: View {
    @EnvironmentObject private var player: AudioPlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: LibraryItem
    @Binding var showsSleepTimer: Bool
    let lyrics: TimedLyrics?
    let presentation: NowPlayingLyricsPresentation
    let onToggleInterface: (() -> Void)?

    @AppStorage("yubing.lyrics.fontSize") private var fontSize = 25.0
    @AppStorage("yubing.lyrics.lineSpacing") private var lineSpacing = 27.0
    @AppStorage("yubing.lyrics.translationEnabled") private var translationEnabled = true
    @AppStorage("yubing.lyrics.focusCascadeDelay") private var cascadeDelay = 0.025
    @AppStorage("yubing.lyrics.focusCascadeBounce") private var cascadeBounce = true
    @State private var isBrowsingLyrics = false
    @State private var browsingGeneration = 0
    @State private var visualActiveIndex: Int?
    @State private var showsSettings = false

    init(
        item: LibraryItem,
        showsSleepTimer: Binding<Bool>,
        lyrics: TimedLyrics?,
        presentation: NowPlayingLyricsPresentation = .portrait,
        onToggleInterface: (() -> Void)? = nil
    ) {
        self.item = item
        _showsSleepTimer = showsSleepTimer
        self.lyrics = lyrics
        self.presentation = presentation
        self.onToggleInterface = onToggleInterface
    }

    private var activeIndex: Int? {
        lyrics?.lineIndex(at: player.currentTime)
    }

    var body: some View {
        VStack(spacing: presentation == .portrait ? 18 : 0) {
            if presentation == .portrait { songHeader }
            lyricsContent
        }
        .padding(.bottom, presentation == .portrait ? 12 : 0)
        .sheet(isPresented: $showsSettings) {
            MeloXLyricsSettingsView()
        }
        .onAppear { visualActiveIndex = activeIndex }
        .onChange(of: activeIndex) { _, index in
            visualActiveIndex = index
        }
    }

    private var songHeader: some View {
        HStack(spacing: 12) {
            AudioArtwork(data: player.currentMetadata.artworkData, fallbackSymbol: "music.note")
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentMetadata.title ?? item.displayName)
                    .font(.headline).lineLimit(1)
                Text(player.currentMetadata.artist ?? player.currentMetadata.album ?? "本地音乐")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { showsSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("歌词设置")

            NowPlayingSongActions(item: item, showsSleepTimer: $showsSleepTimer)
        }
    }

    @ViewBuilder
    private var lyricsContent: some View {
        if let lyrics, !lyrics.lines.isEmpty {
            synchronizedLyrics(lyrics)
        } else if let text = musicCleaned(lyrics?.untimedText) {
            ScrollView {
                Text(text)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 32)
            }
            .scrollIndicators(.hidden)
            .contentShape(Rectangle())
            .onTapGesture { onToggleInterface?() }
        } else {
            ContentUnavailableView(
                "没有歌词",
                systemImage: "quote.bubble",
                description: Text("导入同名 LRC/YRC 文件，或播放带内嵌歌词的音频。")
            )
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onToggleInterface?() }
        }
    }

    private func synchronizedLyrics(_ lyrics: TimedLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CGFloat(lineSpacing)) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        let distance = visualDistance(from: index)
                        let nextTime = lyrics.lines.indices.contains(index + 1)
                            ? lyrics.lines[index + 1].time
                            : nil

                        MeloXSynchronizedLyricText(
                            line: line,
                            nextLineTime: nextTime,
                            isPlaybackLine: index == activeIndex,
                            fontSize: CGFloat(fontSize),
                            alignment: .leading,
                            visualScale: index == visualActiveIndex ? 1.12 : 1
                        )
                        .opacity(lineOpacity(distance: distance, index: index))
                        .blur(radius: lineBlur(distance: distance))
                        .offset(y: index == visualActiveIndex ? -3 : 0)
                        .animation(focusAnimation(for: index), value: visualActiveIndex)
                        .id(line.id)
                        .contentShape(Rectangle())
                        .gesture(lyricTapGesture(for: line))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accessibilityText(for: line))
                        .accessibilityValue(index == activeIndex ? "当前播放" : "")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 96)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        browsingGeneration += 1
                        isBrowsingLyrics = true
                    }
                    .onEnded { _ in schedulePlaybackFollowing() }
            )
            .onAppear { scrollToActive(in: lyrics, proxy: proxy, animated: false) }
            .onChange(of: activeIndex) { _, _ in
                guard !isBrowsingLyrics else { return }
                scrollToActive(in: lyrics, proxy: proxy, animated: true)
            }
            .onChange(of: player.seekRevision) { _, _ in
                isBrowsingLyrics = false
                scrollToActive(in: lyrics, proxy: proxy, animated: false)
            }
        }
    }

    private func scrollToActive(
        in lyrics: TimedLyrics,
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let activeIndex, lyrics.lines.indices.contains(activeIndex) else { return }
        let update = {
            proxy.scrollTo(
                lyrics.lines[activeIndex].id,
                anchor: presentation == .landscape ? UnitPoint(x: 0.5, y: 0.34) : .center
            )
        }
        if animated, !reduceMotion {
            withAnimation(.smooth(duration: 0.34), update)
        } else {
            update()
        }
    }

    private func visualDistance(from index: Int) -> Int {
        guard let visualActiveIndex else { return index }
        return abs(index - visualActiveIndex)
    }

    private func lineOpacity(distance: Int, index: Int) -> Double {
        if index == activeIndex { return 1 }
        switch distance {
        case 0...1: return 0.58
        case 2: return 0.4
        case 3: return 0.28
        default: return 0.16
        }
    }

    private func lineBlur(distance: Int) -> CGFloat {
        guard distance > 1 else { return 0 }
        return min(CGFloat(distance - 1) * 1.45, 7)
    }

    private func focusAnimation(for index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let active = visualActiveIndex ?? index
        let order = max(index - active, 0)
        let delay = Double(min(order, 10)) * max(cascadeDelay, 0)
        let animation: Animation = cascadeBounce
            ? .spring(duration: 0.56, bounce: 0.38)
            : .smooth(duration: 0.34)
        return animation.delay(delay)
    }

    private func schedulePlaybackFollowing() {
        let generation = browsingGeneration
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
            guard generation == browsingGeneration else { return }
            isBrowsingLyrics = false
        }
    }

    private func lyricTapGesture(for line: TimedLyricLine) -> some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { gesture in
                switch gesture {
                case .first:
                    player.seek(to: line.time)
                    isBrowsingLyrics = false
                case .second:
                    onToggleInterface?()
                }
            }
    }

    private func accessibilityText(for line: TimedLyricLine) -> String {
        guard translationEnabled, let translation = musicCleaned(line.translation) else {
            return line.text
        }
        return "\(line.text)，翻译：\(translation)"
    }
}

struct MeloXLyricsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var wrapsInNavigation = true
    @AppStorage("yubing.lyrics.fontSize") private var fontSize = 25.0
    @AppStorage("yubing.lyrics.lineSpacing") private var lineSpacing = 27.0
    @AppStorage("yubing.lyrics.wordByWord") private var wordByWord = true
    @AppStorage("yubing.lyrics.pseudoWordByWord") private var pseudoWordByWord = true
    @AppStorage("yubing.lyrics.glowEnabled") private var glowEnabled = true
    @AppStorage("yubing.lyrics.glowIntensity") private var glowIntensity = 1.0
    @AppStorage("yubing.lyrics.translationEnabled") private var translationEnabled = true
    @AppStorage("yubing.lyrics.focusCascadeDelay") private var cascadeDelay = 0.025
    @AppStorage("yubing.lyrics.focusCascadeBounce") private var cascadeBounce = true
    @AppStorage("yubing.lyrics.refreshRate") private var refreshRate = 60.0

    var body: some View {
        Group {
            if wrapsInNavigation {
                NavigationStack { settingsForm }
            } else {
                settingsForm
            }
        }
        .frame(minWidth: 340, minHeight: 480)
    }

    private var settingsForm: some View {
        Form {
                Section("逐字动效") {
                    Toggle("逐字高亮", isOn: $wordByWord)
                    Toggle("无逐字时间时模拟", isOn: $pseudoWordByWord)
                    Toggle("逐字辉光", isOn: $glowEnabled)
                    if glowEnabled {
                        LabeledContent("辉光强度") {
                            Slider(value: $glowIntensity, in: 0.2...1.5)
                                .frame(minWidth: 120)
                        }
                    }
                }

                Section("歌词焦点") {
                    LabeledContent("字号") {
                        Slider(value: $fontSize, in: 20...36)
                            .frame(minWidth: 120)
                    }
                    LabeledContent("行距") {
                        Slider(value: $lineSpacing, in: 14...40)
                            .frame(minWidth: 120)
                    }
                    LabeledContent("错峰延迟") {
                        Slider(value: $cascadeDelay, in: 0...0.05)
                            .frame(minWidth: 120)
                    }
                    Toggle("错峰回弹", isOn: $cascadeBounce)
                }

                Section("内容与刷新") {
                    Toggle("显示翻译", isOn: $translationEnabled)
                    Picker("歌词刷新率", selection: $refreshRate) {
                        Text("30 FPS").tag(30.0)
                        Text("60 FPS").tag(60.0)
                        Text("90 FPS").tag(90.0)
                        Text("120 FPS").tag(120.0)
                    }
                }
        }
        .navigationTitle("歌词设置")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }
}
