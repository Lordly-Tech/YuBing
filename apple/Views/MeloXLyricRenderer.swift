import SwiftUI

// Timed glow, lift, and syllable expansion adapted from youshen2/MeloX (GPL-3.0).

struct MeloXLyricSyllable: Identifiable, Hashable, Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    var id: String { "\(startTime)-\(endTime)-\(text)" }
}

extension TimedLyricLine {
    func meloXSyllables(
        nextLineTime: TimeInterval?,
        usesWordTiming: Bool,
        usesPseudoTiming: Bool
    ) -> [MeloXLyricSyllable] {
        if usesWordTiming, !words.isEmpty {
            let lineEnd = duration.map { time + $0 }
                ?? nextLineTime
                ?? time + 4
            return words.enumerated().map { index, word in
                let end = word.endTime
                    ?? (words.indices.contains(index + 1) ? words[index + 1].time : lineEnd)
                return MeloXLyricSyllable(
                    text: word.text,
                    startTime: word.time,
                    endTime: max(end, word.time + 0.01)
                )
            }
        }

        guard usesPseudoTiming,
              !text.isEmpty,
              let duration,
              duration > 0 else { return [] }
        let characters = Array(text)
        let characterDuration = duration / Double(max(characters.count, 1))
        return characters.enumerated().map { index, character in
            let start = time + Double(index) * characterDuration
            return MeloXLyricSyllable(
                text: String(character),
                startTime: start,
                endTime: start + characterDuration
            )
        }
    }
}

enum MeloXLyricTextAlignment: Equatable {
    case leading
    case center

    var horizontalAlignment: HorizontalAlignment {
        self == .leading ? .leading : .center
    }

    var textAlignment: TextAlignment {
        self == .leading ? .leading : .center
    }

    var frameAlignment: Alignment {
        self == .leading ? .leading : .center
    }

    var scaleAnchor: UnitPoint {
        self == .leading ? .leading : .center
    }
}

struct MeloXSynchronizedLyricText: View {
    @EnvironmentObject private var player: AudioPlayerController
    @AppStorage("yubing.lyrics.wordByWord") private var wordByWord = true
    @AppStorage("yubing.lyrics.pseudoWordByWord") private var pseudoWordByWord = true
    @AppStorage("yubing.lyrics.glowEnabled") private var glowEnabled = true
    @AppStorage("yubing.lyrics.glowIntensity") private var glowIntensity = 1.0
    @AppStorage("yubing.lyrics.translationEnabled") private var translationEnabled = true
    @AppStorage("yubing.lyrics.translationOpacity") private var translationOpacity = 0.68
    @AppStorage("yubing.lyrics.refreshRate") private var refreshRate = 60.0

    let line: TimedLyricLine
    let nextLineTime: TimeInterval?
    let isPlaybackLine: Bool
    let fontSize: CGFloat
    let alignment: MeloXLyricTextAlignment
    var visualScale: CGFloat = 1
    var primaryColor: Color = .white

    var body: some View {
        VStack(alignment: alignment.horizontalAlignment, spacing: translationSpacing) {
            primaryLyric

            if translationEnabled, let translation = musicCleaned(line.translation) {
                Text(translation)
                    .font(.system(size: max(fontSize * 0.56, 12), weight: .semibold))
                    .foregroundStyle(.white.opacity(translationOpacity))
            }
        }
        .multilineTextAlignment(alignment.textAlignment)
        .scaleEffect(visualScale, anchor: alignment.scaleAnchor)
        .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
    }

    @ViewBuilder
    private var primaryLyric: some View {
        let syllables = activeSyllables
        if isPlaybackLine, !syllables.isEmpty {
            TimelineView(
                .animation(
                    minimumInterval: 1 / min(max(refreshRate, 30), 120),
                    paused: !player.isPlaying
                )
            ) { context in
                let playbackTime = player.isPlaying
                    ? player.estimatedProgress(at: context.date)
                    : player.currentTime
                if #available(iOS 18.0, macOS 15.0, *) {
                    MeloXTimedLyricTextBuilder.text(from: syllables)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundStyle(primaryColor)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textRenderer(
                            MeloXLyricGlowTextRenderer(
                                playbackTime: playbackTime,
                                style: .init(
                                    glowRadius: glowEnabled ? CGFloat(8 * glowIntensity) : 0,
                                    glowOpacity: glowEnabled ? min(glowIntensity, 1.5) : 0,
                                    unplayedOpacity: 0.3,
                                    maximumUnplayedBlurRadius: 1.5,
                                    playedRise: 3.5,
                                    maximumLongSyllableScale: 1.07
                                )
                            )
                        )
                } else {
                    fallbackText(at: playbackTime)
                }
            }
        } else {
            Text(line.text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(primaryColor)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activeSyllables: [MeloXLyricSyllable] {
        line.meloXSyllables(
            nextLineTime: nextLineTime,
            usesWordTiming: wordByWord,
            usesPseudoTiming: wordByWord && pseudoWordByWord
        )
    }

    private func fallbackText(at playbackTime: TimeInterval) -> some View {
        let duration = max((line.duration ?? nextLineTime.map { $0 - line.time } ?? 4), 0.1)
        let progress = min(max((playbackTime - line.time) / duration, 0), 1)
        return Text(line.text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white.opacity(0.3))
            .overlay(alignment: .leading) {
                Text(line.text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(primaryColor)
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle().frame(width: proxy.size.width * progress)
                        }
                    }
                    .shadow(
                        color: glowEnabled ? primaryColor.opacity(0.65 * min(glowIntensity, 1.3)) : .clear,
                        radius: glowEnabled ? 10 : 0
                    )
                    .offset(y: -CGFloat(progress) * 2)
            }
    }

    private var translationSpacing: CGFloat {
        translationEnabled && line.translation != nil ? 6 : 0
    }
}

@available(iOS 18.0, macOS 15.0, *)
struct MeloXLyricTimingTextAttribute: TextAttribute, Hashable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let syllableStartTime: TimeInterval
    let syllableEndTime: TimeInterval
    let characterIndex: Int
    let characterCount: Int
}

@available(iOS 18.0, macOS 15.0, *)
enum MeloXTimedLyricTextBuilder {
    static func text(from syllables: [MeloXLyricSyllable]) -> Text {
        timedCharacters(from: syllables).reduce(Text(verbatim: "")) { result, character in
            let fragment = Text(verbatim: character.text).customAttribute(
                MeloXLyricTimingTextAttribute(
                    startTime: character.startTime,
                    endTime: character.endTime,
                    syllableStartTime: character.syllableStartTime,
                    syllableEndTime: character.syllableEndTime,
                    characterIndex: character.characterIndex,
                    characterCount: character.characterCount
                )
            )
            return Text("\(result)\(fragment)")
        }
    }

    private static func timedCharacters(
        from syllables: [MeloXLyricSyllable]
    ) -> [TimedCharacter] {
        syllables.flatMap { syllable in
            let characters = Array(syllable.text)
            guard !characters.isEmpty else { return [] }
            let duration = max(syllable.endTime - syllable.startTime, 0)
            let characterDuration = duration / Double(characters.count)
            return characters.enumerated().map { index, character in
                let start = syllable.startTime + Double(index) * characterDuration
                return TimedCharacter(
                    text: String(character),
                    startTime: start,
                    endTime: index == characters.count - 1
                        ? max(syllable.endTime, start)
                        : start + characterDuration,
                    syllableStartTime: syllable.startTime,
                    syllableEndTime: syllable.endTime,
                    characterIndex: index,
                    characterCount: characters.count
                )
            }
        }
    }

    private struct TimedCharacter {
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let syllableStartTime: TimeInterval
        let syllableEndTime: TimeInterval
        let characterIndex: Int
        let characterCount: Int
    }
}

@available(iOS 18.0, macOS 15.0, *)
struct MeloXLyricGlowTextRenderer: TextRenderer {
    struct Style: Equatable, Sendable {
        let glowRadius: CGFloat
        let glowOpacity: Double
        let unplayedOpacity: Double
        let maximumUnplayedBlurRadius: CGFloat
        let playedRise: CGFloat
        let maximumLongSyllableScale: CGFloat
    }

    var playbackTime: TimeInterval
    let style: Style

    var animatableData: Double {
        get { playbackTime }
        set { playbackTime = newValue }
    }

    var displayPadding: EdgeInsets {
        let padding = style.glowRadius * 6
        return EdgeInsets(
            top: padding + max(style.playedRise, 0) + 4,
            leading: padding + 4,
            bottom: padding + 4,
            trailing: padding + 4
        )
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                draw(run, in: &context)
            }
        }
    }

    private func draw(_ run: Text.Layout.Run, in context: inout GraphicsContext) {
        guard let timing = run[MeloXLyricTimingTextAttribute.self] else {
            context.draw(run)
            return
        }

        let rawProgress = playedProgress(for: timing)
        let revealProgress = smootherStep(rawProgress)
        var unplayed = context
        unplayed.opacity = style.unplayedOpacity * (1 - revealProgress)
        let blur = unplayedBlurRadius(for: timing)
        if blur > 0 { unplayed.addFilter(.blur(radius: blur)) }
        unplayed.draw(run)
        guard revealProgress > 0 else { return }

        let lift = liftProgress(for: timing)
        let scale = expansionScale(for: timing)
        let bounds = run.typographicBounds.rect
        let transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: bounds.midX * (1 - scale),
            ty: bounds.midY * (1 - scale) - style.playedRise * CGFloat(lift)
        )
        var played = context
        played.addFilter(.projectionTransform(ProjectionTransform(transform)))
        played.drawLayer { layer in
            let strength = glowStrength(for: timing, rawProgress: rawProgress)
            if style.glowRadius > 0, strength > 0 {
                drawGlow(run, strength: strength, rawProgress: rawProgress, in: &layer)
            }
            var glyph = layer
            glyph.opacity = revealProgress
            glyph.draw(run)
        }
    }

    private func drawGlow(
        _ run: Text.Layout.Run,
        strength: Double,
        rawProgress: Double,
        in context: inout GraphicsContext
    ) {
        let pulse = 1 + 0.2 * sin(.pi * rawProgress)
        for (radiusScale, opacityScale) in [(1.75, 0.72), (0.62, 1.0)] {
            var glow = context
            glow.opacity = min(style.glowOpacity * strength * opacityScale, 1)
            glow.blendMode = .plusLighter
            glow.addFilter(
                .blur(radius: style.glowRadius * CGFloat(radiusScale) * CGFloat(pulse))
            )
            glow.draw(run)
        }
    }

    private func playedProgress(for timing: MeloXLyricTimingTextAttribute) -> Double {
        guard playbackTime >= timing.startTime else { return 0 }
        guard playbackTime < timing.endTime else { return 1 }
        let duration = timing.endTime - timing.startTime
        return duration > 0 ? unit((playbackTime - timing.startTime) / duration) : 1
    }

    private func liftProgress(for timing: MeloXLyricTimingTextAttribute) -> Double {
        guard playbackTime > timing.startTime else { return 0 }
        let end = timing.endTime + 0.32
        return smootherStep((playbackTime - timing.startTime) / max(end - timing.startTime, 0.01))
    }

    private func expansionScale(for timing: MeloXLyricTimingTextAttribute) -> CGFloat {
        let maximum = max(style.maximumLongSyllableScale, 1)
        let duration = timing.syllableEndTime - timing.syllableStartTime
        guard maximum > 1, duration >= 0.7, timing.characterCount > 0 else { return 1 }
        let characterDuration = duration / Double(timing.characterCount)
        let overlap = min(characterDuration * 0.32, 0.14)
        let start = timing.startTime - (timing.characterIndex > 0 ? overlap : 0)
        let end = timing.endTime + (timing.characterIndex < timing.characterCount - 1 ? overlap : 0)
        guard playbackTime > start, playbackTime < end else { return 1 }
        let envelope = sin(.pi * smootherStep((playbackTime - start) / max(end - start, 0.01)))
        return 1 + (maximum - 1) * CGFloat(envelope)
    }

    private func unplayedBlurRadius(for timing: MeloXLyricTimingTextAttribute) -> CGFloat {
        guard style.maximumUnplayedBlurRadius > 0, playbackTime < timing.startTime else { return 0 }
        let distance = smootherStep((timing.startTime - playbackTime) / 2.4)
        return style.maximumUnplayedBlurRadius * CGFloat(0.12 + 0.88 * distance)
    }

    private func glowStrength(
        for timing: MeloXLyricTimingTextAttribute,
        rawProgress: Double
    ) -> Double {
        if playbackTime <= timing.endTime {
            let attack = smootherStep(rawProgress / 0.24)
            return attack * (0.82 + 0.18 * sin(.pi * rawProgress))
        }
        let tail = (playbackTime - timing.endTime) / 0.55
        return tail < 1 ? (1 - smootherStep(tail)) * 0.82 : 0
    }

    private func smootherStep(_ value: Double) -> Double {
        let progress = unit(value)
        return progress * progress * progress * (progress * (progress * 6 - 15) + 10)
    }

    private func unit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
