import CoreFoundation
import Foundation

struct TimedLyricWord: Identifiable, Hashable, Sendable {
    let id: String
    let time: TimeInterval
    let text: String
}

struct TimedLyricLine: Identifiable, Hashable, Sendable {
    let id: String
    let time: TimeInterval
    let text: String
    let words: [TimedLyricWord]
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
}

enum AudioLyricsLoader {
    static func load(sidecarFor audioURL: URL, embeddedText: String?) -> TimedLyrics? {
        if let sidecar = sidecarURL(for: audioURL),
           let text = decodedText(at: sidecar) {
            let lyrics = LRCParser.parse(text)
            if !lyrics.isEmpty { return lyrics }
        }
        guard let embeddedText else { return nil }
        let lyrics = LRCParser.parse(embeddedText)
        return lyrics.isEmpty ? nil : lyrics
    }

    private static func sidecarURL(for audioURL: URL) -> URL? {
        let directory = audioURL.deletingLastPathComponent()
        let stem = audioURL.deletingPathExtension().lastPathComponent
        let exact = directory.appendingPathComponent("\(stem).lrc")
        if FileManager.default.fileExists(atPath: exact.path) { return exact }
        let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return entries?.first {
            $0.pathExtension.lowercased() == "lrc" &&
            $0.deletingPathExtension().lastPathComponent.compare(stem, options: .caseInsensitive) == .orderedSame
        }
    }

    private static func decodedText(at url: URL) -> String? {
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
        return TimedLyrics(lines: unique, untimedText: untimedText)
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
}
