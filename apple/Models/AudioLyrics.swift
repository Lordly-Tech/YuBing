import CoreFoundation
import Foundation

struct TimedLyricWord: Identifiable, Hashable, Sendable {
    let id: String
    let time: TimeInterval
    let endTime: TimeInterval?
    let text: String

    init(id: String, time: TimeInterval, endTime: TimeInterval? = nil, text: String) {
        self.id = id
        self.time = time
        self.endTime = endTime
        self.text = text
    }
}

struct TimedLyricLine: Identifiable, Hashable, Sendable {
    let id: String
    let time: TimeInterval
    let duration: TimeInterval?
    let text: String
    let words: [TimedLyricWord]
    let translation: String?

    init(
        id: String,
        time: TimeInterval,
        duration: TimeInterval? = nil,
        text: String,
        words: [TimedLyricWord] = [],
        translation: String? = nil
    ) {
        self.id = id
        self.time = time
        self.duration = duration
        self.text = text
        self.words = words
        self.translation = translation
    }

    var isWordSynced: Bool {
        !words.isEmpty
    }

    func attachingTranslation(_ translation: String?) -> TimedLyricLine {
        TimedLyricLine(
            id: id,
            time: time,
            duration: duration,
            text: text,
            words: words,
            translation: translation
        )
    }
}

struct TimedLyrics: Equatable, Hashable, Sendable {
    let lines: [TimedLyricLine]
    let untimedText: String?

    var isEmpty: Bool {
        lines.isEmpty && (untimedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func lineIndex(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lines[middle].time <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return max(0, lower - 1)
    }

    func activeWordIndex(in lineIndex: Int, at time: TimeInterval) -> Int? {
        guard lines.indices.contains(lineIndex), !lines[lineIndex].words.isEmpty else { return nil }
        let words = lines[lineIndex].words
        let index = words.lastIndex { $0.time <= time }
        return index ?? 0
    }

    func activeCharacterCount(in lineIndex: Int, at time: TimeInterval) -> Int {
        guard lines.indices.contains(lineIndex) else { return 0 }
        return Int((Double(lines[lineIndex].text.count) * highlightProgress(in: lineIndex, at: time)).rounded(.up))
    }

    func highlightProgress(in lineIndex: Int, at time: TimeInterval) -> Double {
        guard lines.indices.contains(lineIndex) else { return 0 }
        let line = lines[lineIndex]
        guard !line.text.isEmpty else { return 0 }
        if !line.words.isEmpty {
            let nextLineTime = line.duration.map { line.time + $0 }
                ?? (lines.indices.contains(lineIndex + 1) ? lines[lineIndex + 1].time : line.time + 4)
            var completedCharacters = 0
            for (index, word) in line.words.enumerated() {
                let wordCount = word.text.count
                let endTime = word.endTime
                    ?? (line.words.indices.contains(index + 1) ? line.words[index + 1].time : nextLineTime)
                if time < word.time {
                    break
                }
                if time < endTime {
                    let duration = max(endTime - word.time, 0.08)
                    let wordProgress = min(max((time - word.time) / duration, 0), 1)
                    return min(
                        1,
                        (Double(completedCharacters) + Double(wordCount) * wordProgress) / Double(line.text.count)
                    )
                }
                completedCharacters += wordCount
            }
            return min(1, Double(completedCharacters) / Double(line.text.count))
        }
        let nextTime = line.duration.map { line.time + $0 }
            ?? (lines.indices.contains(lineIndex + 1) ? lines[lineIndex + 1].time : line.time + 4)
        let duration = max(nextTime - line.time, 0.8)
        return min(max((time - line.time) / duration, 0), 1)
    }

    func lineProgress(in lineIndex: Int, at time: TimeInterval) -> Double {
        highlightProgress(in: lineIndex, at: time)
    }
}

enum AudioLyricsLoader {
    static func load(sidecarFor audioURL: URL, embeddedText: String?) -> TimedLyrics? {
        let sidecars = sidecarTexts(for: audioURL)
        if sidecars.hasAnyLyrics {
            let lyrics = UnifiedAudioLyricParser.parse(
                yrc: sidecars.yrc ?? "",
                lrc: sidecars.lrc ?? "",
                translatedYRC: sidecars.translatedYRC ?? "",
                translatedLRC: sidecars.translatedLRC ?? ""
            )
            if !lyrics.isEmpty { return lyrics }
        }
        guard let embeddedText else { return nil }
        let lyrics = LRCParser.parse(embeddedText)
        return lyrics.isEmpty ? nil : lyrics
    }

    private struct SidecarTexts {
        var lrc: String?
        var yrc: String?
        var translatedLRC: String?
        var translatedYRC: String?

        var hasAnyLyrics: Bool {
            [lrc, yrc, translatedLRC, translatedYRC].contains { text in
                guard let text else { return false }
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private static func sidecarTexts(for audioURL: URL) -> SidecarTexts {
        SidecarTexts(
            lrc: decodedText(at: sidecarURL(for: audioURL, suffixes: [".lrc"])),
            yrc: decodedText(at: sidecarURL(for: audioURL, suffixes: [".yrc"])),
            translatedLRC: decodedText(at: sidecarURL(
                for: audioURL,
                suffixes: [".translation.lrc", ".translated.lrc", ".trans.lrc", ".tlrc", ".zh.lrc"]
            )),
            translatedYRC: decodedText(at: sidecarURL(
                for: audioURL,
                suffixes: [".translation.yrc", ".translated.yrc", ".trans.yrc", ".tyrc", ".zh.yrc"]
            ))
        )
    }

    private static func sidecarURL(for audioURL: URL, suffixes: [String]) -> URL? {
        let directory = audioURL.deletingLastPathComponent()
        let stem = audioURL.deletingPathExtension().lastPathComponent
        for suffix in suffixes {
            let exact = directory.appendingPathComponent("\(stem)\(suffix)")
            if FileManager.default.fileExists(atPath: exact.path) { return exact }
        }
        let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return entries?.first {
            let filename = $0.lastPathComponent.lowercased()
            return suffixes.contains { suffix in
                filename == "\(stem)\(suffix)".lowercased()
            }
        }
    }

    private static func decodedText(at url: URL?) -> String? {
        guard let url else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, gb18030, .isoLatin1] {
            if let value = String(data: data, encoding: encoding), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

enum ID3EmbeddedLyricsReader {
    static func read(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }

        guard let headerData = try? handle.read(upToCount: 10),
              headerData.count == 10 else { return nil }
        let header = [UInt8](headerData)
        guard header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 else { return nil }

        let version = Int(header[3])
        guard (2...4).contains(version) else { return nil }
        let tagSize = synchsafeInteger(header[6..<10])
        guard tagSize > 0, tagSize < 16 * 1_024 * 1_024,
              let tagData = try? handle.read(upToCount: tagSize),
              tagData.count > 0 else { return nil }

        var bytes = [UInt8](tagData)
        if (header[5] & 0x80) != 0 {
            bytes = removeUnsynchronisation(from: bytes)
        }
        return lyrics(from: bytes, version: version, headerFlags: header[5])
    }

    private static func lyrics(from bytes: [UInt8], version: Int, headerFlags: UInt8) -> String? {
        var offset = extendedHeaderLength(in: bytes, version: version, headerFlags: headerFlags)
        let frameHeaderLength = version == 2 ? 6 : 10

        while offset + frameHeaderLength <= bytes.count {
            let identifierLength = version == 2 ? 3 : 4
            let identifierBytes = bytes[offset..<offset + identifierLength]
            guard !identifierBytes.allSatisfy({ $0 == 0 }) else { break }
            guard let identifier = String(bytes: identifierBytes, encoding: .isoLatin1) else { break }

            let frameSize: Int
            if version == 2 {
                frameSize = (Int(bytes[offset + 3]) << 16) | (Int(bytes[offset + 4]) << 8) | Int(bytes[offset + 5])
            } else if version == 4 {
                frameSize = synchsafeInteger(bytes[offset + 4..<offset + 8])
            } else {
                frameSize = bigEndianInteger(bytes[offset + 4..<offset + 8])
            }

            let frameStart = offset + frameHeaderLength
            let frameEnd = frameStart + frameSize
            guard frameSize > 0, frameEnd <= bytes.count else { break }
            var payload = Array(bytes[frameStart..<frameEnd])
            if version == 4, offset + 9 < bytes.count, (bytes[offset + 9] & 0x02) != 0 {
                payload = removeUnsynchronisation(from: payload)
            }

            if identifier == "USLT" || identifier == "ULT",
               let text = unsynchronisedLyrics(from: payload) {
                return text
            }
            if identifier == "TXXX" || identifier == "TXX",
               let text = userTextLyrics(from: payload) {
                return text
            }

            offset = frameEnd
        }
        return nil
    }

    private static func unsynchronisedLyrics(from payload: [UInt8]) -> String? {
        guard payload.count > 4 else { return nil }
        let encoding = payload[0]
        let content = Array(payload.dropFirst(4))
        let lyricStart = textTerminatorEnd(in: content, encoding: encoding) ?? 0
        return decodedText(from: Array(content.dropFirst(lyricStart)), encoding: encoding)
    }

    private static func userTextLyrics(from payload: [UInt8]) -> String? {
        guard payload.count > 1 else { return nil }
        let encoding = payload[0]
        let content = Array(payload.dropFirst())
        guard let descriptionEnd = textTerminatorEnd(in: content, encoding: encoding) else { return nil }
        let terminatorLength = usesWideTerminator(encoding) ? 2 : 1
        let descriptionBytes = Array(content.prefix(max(0, descriptionEnd - terminatorLength)))
        guard let description = decodedText(from: descriptionBytes, encoding: encoding)?
            .lowercased(),
              description.contains("lyric") else { return nil }
        return decodedText(from: Array(content.dropFirst(descriptionEnd)), encoding: encoding)
    }

    private static func decodedText(from bytes: [UInt8], encoding: UInt8) -> String? {
        guard !bytes.isEmpty else { return nil }
        let data = Data(bytes)
        let candidates: [String.Encoding]
        switch encoding {
        case 1:
            candidates = [.utf16, .utf16LittleEndian, .utf16BigEndian]
        case 2:
            candidates = [.utf16BigEndian, .utf16]
        case 3:
            candidates = [.utf8]
        default:
            candidates = [.isoLatin1, .utf8]
        }

        let trimSet = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\u{feff}\0"))
        for candidate in candidates {
            if let value = String(data: data, encoding: candidate) {
                let trimmed = value.trimmingCharacters(in: trimSet)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func textTerminatorEnd(in bytes: [UInt8], encoding: UInt8) -> Int? {
        if usesWideTerminator(encoding) {
            var index = 0
            while index + 1 < bytes.count {
                if bytes[index] == 0, bytes[index + 1] == 0 {
                    return index + 2
                }
                index += 2
            }
        } else if let index = bytes.firstIndex(of: 0) {
            return index + 1
        }
        return nil
    }

    private static func usesWideTerminator(_ encoding: UInt8) -> Bool {
        encoding == 1 || encoding == 2
    }

    private static func extendedHeaderLength(in bytes: [UInt8], version: Int, headerFlags: UInt8) -> Int {
        guard (headerFlags & 0x40) != 0, bytes.count >= 4 else { return 0 }
        if version == 4 {
            return min(bytes.count, max(0, synchsafeInteger(bytes[0..<4])))
        }
        if version == 3 {
            return min(bytes.count, max(0, bigEndianInteger(bytes[0..<4]) + 4))
        }
        return 0
    }

    private static func removeUnsynchronisation(from bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            result.append(byte)
            if byte == 0xff, index + 1 < bytes.count, bytes[index + 1] == 0 {
                index += 2
            } else {
                index += 1
            }
        }
        return result
    }

    private static func synchsafeInteger(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { ($0 << 7) | Int($1 & 0x7f) }
    }

    private static func bigEndianInteger(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { ($0 << 8) | Int($1) }
    }
}

enum LRCParser {
    private static let lineExpression = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2})(?:[\.:](\d{1,3}))?\]"#
    )
    private static let wordExpression = try! NSRegularExpression(
        pattern: #"<(\d{1,3}):(\d{1,2})(?:[\.:](\d{1,3}))?>"#
    )
    private static let offsetExpression = try! NSRegularExpression(
        pattern: #"\[offset:([+-]?\d+)\]"#,
        options: [.caseInsensitive]
    )

    static func parse(_ rawText: String) -> TimedLyrics {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let offset = parseOffset(in: normalized)
        var lines: [TimedLyricLine] = []
        var untimed: [String] = []

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let range = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
            let matches = lineExpression.matches(in: rawLine, range: range)
            guard !matches.isEmpty else {
                let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, !isMetadataLine(trimmed) { untimed.append(trimmed) }
                continue
            }

            let content = lineExpression
                .stringByReplacingMatches(in: rawLine, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }

            for (index, match) in matches.enumerated() {
                let time = max(0, timestamp(from: match, in: rawLine) + offset)
                let words = parseWords(in: content, offset: offset, lineTime: time)
                let cleanText = wordExpression.stringByReplacingMatches(
                    in: content,
                    range: NSRange(content.startIndex..<content.endIndex, in: content),
                    withTemplate: ""
                )
                lines.append(
                    TimedLyricLine(
                        id: "\(time)-\(index)-\(cleanText)",
                        time: time,
                        text: cleanText,
                        words: words
                    )
                )
            }
        }

        var seen: Set<String> = []
        var unique: [TimedLyricLine] = []
        for line in lines {
            let key = "\(line.time)|\(line.text)"
            if seen.insert(key).inserted { unique.append(line) }
        }
        unique.sort { lhs, rhs in
            lhs.time == rhs.time ? lhs.text < rhs.text : lhs.time < rhs.time
        }
        let untimedText = unique.isEmpty && !untimed.isEmpty ? untimed.joined(separator: "\n") : nil
        return TimedLyrics(lines: inferDurations(in: unique), untimedText: untimedText)
    }

    private static func parseOffset(in text: String) -> TimeInterval {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = offsetExpression.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let milliseconds = Double(text[valueRange]) else { return 0 }
        return milliseconds / 1000
    }

    private static func parseWords(
        in content: String,
        offset: TimeInterval,
        lineTime: TimeInterval
    ) -> [TimedLyricWord] {
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = wordExpression.matches(in: content, range: range)
        guard !matches.isEmpty else { return [] }
        var result: [TimedLyricWord] = []

        for (index, match) in matches.enumerated() {
            guard let matchRange = Range(match.range, in: content) else { continue }
            let textStart = matchRange.upperBound
            let textEnd: String.Index
            if index + 1 < matches.count,
               let nextRange = Range(matches[index + 1].range, in: content) {
                textEnd = nextRange.lowerBound
            } else {
                textEnd = content.endIndex
            }
            let word = String(content[textStart..<textEnd])
            guard !word.isEmpty else { continue }
            let time = max(lineTime, timestamp(from: match, in: content) + offset)
            result.append(TimedLyricWord(id: "\(time)-\(index)", time: time, text: word))
        }
        return result
    }

    private static func timestamp(from match: NSTextCheckingResult, in text: String) -> TimeInterval {
        func number(at index: Int) -> Double {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else { return 0 }
            return Double(text[range]) ?? 0
        }
        let minutes = number(at: 1)
        let seconds = number(at: 2)
        let fractionRange = match.range(at: 3)
        let fraction: Double
        if fractionRange.location != NSNotFound,
           let range = Range(fractionRange, in: text) {
            let raw = String(text[range])
            fraction = (Double(raw) ?? 0) / pow(10, Double(raw.count))
        } else {
            fraction = 0
        }
        return minutes * 60 + seconds + fraction
    }

    private static func isMetadataLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return ["[ar:", "[ti:", "[al:", "[by:", "[offset:", "[re:", "[ve:"].contains {
            lower.hasPrefix($0)
        }
    }

    private static func inferDurations(in lines: [TimedLyricLine]) -> [TimedLyricLine] {
        lines.enumerated().map { index, line in
            let nextTime = lines.indices.contains(index + 1) ? lines[index + 1].time : nil
            let duration = nextTime.map { max($0 - line.time, 0.8) } ?? estimatedLastLineDuration(for: line.text)
            return TimedLyricLine(
                id: line.id,
                time: line.time,
                duration: duration,
                text: line.text,
                words: line.words,
                translation: line.translation
            )
        }
    }

    private static func estimatedLastLineDuration(for text: String) -> TimeInterval {
        let visibleCharacterCount = text.filter { !$0.isWhitespace }.count
        return min(max(Double(visibleCharacterCount) * 0.32, 2), 8)
    }
}

enum UnifiedAudioLyricParser {
    static func parse(
        yrc: String,
        lrc: String,
        translatedYRC: String = "",
        translatedLRC: String = ""
    ) -> TimedLyrics {
        let yrcLines = YRCParser.parse(yrc)
        let lrcLyrics = LRCParser.parse(lrc)
        let baseLines = yrcLines.isEmpty ? lrcLyrics.lines : yrcLines
        guard !baseLines.isEmpty else { return lrcLyrics }

        let yrcTranslations = YRCParser.parse(translatedYRC)
        let translatedYRCLines = yrcTranslations.isEmpty ? LRCParser.parse(translatedYRC).lines : yrcTranslations
        let translatedLRCLines = LRCParser.parse(translatedLRC).lines
        let directlyTranslated = attachTranslations(translatedYRCLines, to: baseLines)
        let translated = translatedLRCLines.isEmpty
            ? directlyTranslated
            : attachTranslations(translatedLRCLines, to: directlyTranslated)

        return TimedLyrics(lines: translated, untimedText: lrcLyrics.untimedText)
    }

    private static func attachTranslations(
        _ translations: [TimedLyricLine],
        to lines: [TimedLyricLine]
    ) -> [TimedLyricLine] {
        guard !translations.isEmpty else { return lines }

        var lineIndex = 0
        var translationsByLineIndex: [Int: String] = [:]
        for translation in translations {
            while lineIndex + 1 < lines.count {
                let currentDistance = abs(lines[lineIndex].time - translation.time)
                let nextDistance = abs(lines[lineIndex + 1].time - translation.time)
                guard nextDistance < currentDistance else { break }
                lineIndex += 1
            }

            let normalized = translation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard abs(lines[lineIndex].time - translation.time) <= 0.85,
                  !normalized.isEmpty,
                  normalized != lines[lineIndex].text.trimmingCharacters(in: .whitespacesAndNewlines),
                  translationsByLineIndex[lineIndex] == nil else { continue }
            translationsByLineIndex[lineIndex] = normalized
        }

        return lines.enumerated().map { index, line in
            line.attachingTranslation(translationsByLineIndex[index] ?? line.translation)
        }
    }
}

enum YRCParser {
    private static let syllableExpression = try! NSRegularExpression(
        pattern: #"\((\d+),(\d+),[^)]*\)"#
    )

    static func parse(_ source: String) -> [TimedLyricLine] {
        source
            .split(whereSeparator: \Character.isNewline)
            .compactMap { parseLine(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .sorted { $0.time < $1.time }
    }

    private static func parseLine(_ line: String) -> TimedLyricLine? {
        guard line.first == "[",
              let closingBracket = line.firstIndex(of: "]") else {
            return parseCredits(line)
        }

        let timing = line[line.index(after: line.startIndex)..<closingBracket]
            .split(separator: ",", omittingEmptySubsequences: false)
        guard timing.count >= 2,
              let startMilliseconds = Int(timing[0]),
              let durationMilliseconds = Int(timing[1]) else { return nil }

        let start = TimeInterval(startMilliseconds) / 1000
        let duration = TimeInterval(durationMilliseconds) / 1000
        let content = String(line[line.index(after: closingBracket)...])
        let contentRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = syllableExpression.matches(in: content, range: contentRange)
        guard !matches.isEmpty else {
            let text = content.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return TimedLyricLine(id: "\(start)-\(text)", time: start, duration: duration, text: text)
        }

        let storage = content as NSString
        let words = matches.enumerated().compactMap { index, match -> TimedLyricWord? in
            guard let wordStartMilliseconds = integer(in: match.range(at: 1), from: storage),
                  let wordDurationMilliseconds = integer(in: match.range(at: 2), from: storage) else { return nil }
            let textStart = NSMaxRange(match.range)
            let textEnd = index + 1 < matches.count ? matches[index + 1].range.location : storage.length
            guard textEnd >= textStart else { return nil }
            let text = storage.substring(with: NSRange(location: textStart, length: textEnd - textStart))
            guard !text.isEmpty else { return nil }
            let time = TimeInterval(wordStartMilliseconds) / 1000
            let endTime = time + TimeInterval(wordDurationMilliseconds) / 1000
            return TimedLyricWord(id: "\(time)-\(index)-\(text)", time: time, endTime: endTime, text: text)
        }

        let text = words.map(\.text).joined()
        guard !text.isEmpty else { return nil }
        return TimedLyricLine(id: "\(start)-\(text)", time: start, duration: duration, text: text, words: words)
    }

    private static func parseCredits(_ line: String) -> TimedLyricLine? {
        guard line.first == "{",
              let data = line.data(using: .utf8),
              let credits = try? JSONDecoder().decode(YRCCredits.self, from: data) else { return nil }
        let text = credits.items.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let time = TimeInterval(credits.timestamp) / 1000
        return TimedLyricLine(id: "\(time)-\(text)", time: time, text: text)
    }

    private static func integer(in range: NSRange, from string: NSString) -> Int? {
        guard range.location != NSNotFound else { return nil }
        return Int(string.substring(with: range))
    }
}

private struct YRCCredits: Decodable {
    struct Item: Decodable {
        let text: String?

        private enum CodingKeys: String, CodingKey {
            case text = "tx"
        }
    }

    let timestamp: Int
    let items: [Item]

    private enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case items = "c"
    }
}
