import Foundation

struct LyricSyllable: Identifiable, Hashable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    var id: String {
        "\(startTime)-\(endTime)-\(text)"
    }
}

struct LyricLine: Identifiable, Hashable {
    let time: TimeInterval
    let duration: TimeInterval?
    let text: String
    let syllables: [LyricSyllable]
    let translation: String?

    init(
        time: TimeInterval,
        duration: TimeInterval? = nil,
        text: String,
        syllables: [LyricSyllable] = [],
        translation: String? = nil
    ) {
        self.time = time
        self.duration = duration
        self.text = text
        self.syllables = syllables
        self.translation = translation
    }

    var id: String {
        "\(time)-\(text)"
    }

    var isSyllableSynced: Bool {
        !syllables.isEmpty
    }

    func makePseudoSyllables() -> [LyricSyllable] {
        guard syllables.isEmpty,
              let duration,
              duration > 0 else { return [] }

        let characters = Array(text)
        guard !characters.isEmpty else { return [] }

        let characterDuration = duration / Double(characters.count)
        return characters.enumerated().map { index, character in
            let startTime = time + Double(index) * characterDuration
            return LyricSyllable(
                text: String(character),
                startTime: startTime,
                endTime: startTime + characterDuration
            )
        }
    }

    func attachingTranslation(_ translation: String?) -> LyricLine {
        LyricLine(
            time: time,
            duration: duration,
            text: text,
            syllables: syllables,
            translation: translation
        )
    }

    func accessibilityText(includingTranslation: Bool) -> String {
        guard includingTranslation, let translation else { return text }
        return "\(text)，翻译：\(translation)"
    }
}

extension TimedLyrics {
    var meloXLyricLines: [LyricLine] {
        lines.map { line in
            LyricLine(
                time: line.time,
                duration: line.duration,
                text: line.text,
                syllables: line.words.enumerated().map { index, word in
                    let fallbackEnd = line.words.indices.contains(index + 1)
                        ? line.words[index + 1].time
                        : line.duration.map { line.time + $0 } ?? word.time
                    return LyricSyllable(
                        text: word.text,
                        startTime: word.time,
                        endTime: max(word.endTime ?? fallbackEnd, word.time)
                    )
                },
                translation: line.translation
            )
        }
    }
}
