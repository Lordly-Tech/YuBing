import Compression
import Foundation
import PDFKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum BookParserError: LocalizedError {
    case unsupportedFormat(String)
    case unreadable(String)
    case protectedBook
    case unsupportedCompression

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "暂不支持读取 \(format.uppercased()) 文件。"
        case .unreadable(let message):
            message
        case .protectedBook:
            "这本书带有 DRM 或密码保护，鱼饼无法读取。请导入无 DRM 的文件。"
        case .unsupportedCompression:
            "电子书使用了当前版本无法解压的压缩方式。"
        }
    }
}

enum BookParser {
    static let textBookExtensions: Set<String> = ["txt", "epub", "mobi", "azw3", "azw", "doc", "docx", "md", "markdown"]
    static let advertisedExtensions: [String] = ["TXT", "EPUB", "MOBI", "AZW3", "DOC", "DOCX", "PDF"]

    static func parse(url: URL) throws -> ParsedBook {
        let format = url.pathExtension.lowercased()
        switch format {
        case "txt", "md", "markdown":
            let text = try decodePlainText(Data(contentsOf: url))
            return makeBook(title: url.deletingPathExtension().lastPathComponent, format: format, text: text)
        case "epub":
            return try EPUBBookDecoder.decode(url: url)
        case "mobi", "azw", "azw3":
            let text = try MOBIBookDecoder.decode(url: url)
            return makeBook(title: url.deletingPathExtension().lastPathComponent, format: format, text: text)
        case "doc":
            let text = try decodeLegacyWord(url: url)
            return makeBook(title: url.deletingPathExtension().lastPathComponent, format: format, text: text)
        case "docx":
            let archive = try SimpleZIPArchive(url: url)
            guard let document = try archive.data(for: "word/document.xml") else {
                throw BookParserError.unreadable("DOCX 文件中没有找到正文。")
            }
            let text = WordDocumentTextParser.parse(document)
            return makeBook(title: url.deletingPathExtension().lastPathComponent, format: format, text: text)
        case "pdf":
            return try decodePDF(url: url)
        default:
            throw BookParserError.unsupportedFormat(format)
        }
    }

    private static func makeBook(title: String, format: String, text: String, coverData: Data? = nil) -> ParsedBook {
        let normalized = normalize(text)
        let chapters = BookChapterDetector.chapters(in: normalized, fallbackTitle: "全文")
        return ParsedBook(
            title: title,
            format: format,
            chapters: chapters,
            totalLength: max((normalized as NSString).length, 1),
            coverData: coverData
        )
    }

    fileprivate static func makeBook(
        title: String,
        format: String,
        sections: [(title: String, text: String)],
        coverData: Data?
    ) -> ParsedBook {
        let chapters = BookChapterDetector.chapters(from: sections)
        let total = chapters.last.map { $0.startOffset + $0.length } ?? 0
        return ParsedBook(
            title: title,
            format: format,
            chapters: chapters,
            totalLength: max(total, 1),
            coverData: coverData
        )
    }

    fileprivate static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"\n[ \t]+\n"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{4,}"#, with: "\n\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func decodePlainText(_ data: Data) throws -> String {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            String.Encoding(rawValue: 0x8000_0632), // GB 18030 / GBK
            .windowsCP1252,
            .isoLatin1
        ]
        for encoding in encodings {
            if let value = String(data: data, encoding: encoding), !value.isEmpty {
                return value.replacingOccurrences(of: "\u{FEFF}", with: "")
            }
        }
        throw BookParserError.unreadable("无法识别文本编码。建议将文件另存为 UTF-8 后再导入。")
    }

    private static func decodeLegacyWord(url: URL) throws -> String {
        if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil),
           attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
            return attributed.string
        }

        let data = try Data(contentsOf: url)
        let recovered = LegacyWordTextRecovery.recover(data)
        guard recovered.count > 40 else {
            throw BookParserError.unreadable("无法提取这个 DOC 文件的正文。可在 Pages 或 Word 中另存为 DOCX 后再导入。")
        }
        return recovered
    }

    private static func decodePDF(url: URL) throws -> ParsedBook {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw BookParserError.unreadable("PDF 文件已损坏或带有密码保护。")
        }
        let sections = (0..<document.pageCount).compactMap { index -> (title: String, text: String)? in
            guard let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return ("第 \(index + 1) 页", text)
        }
        guard !sections.isEmpty else {
            throw BookParserError.unreadable("这是图片型 PDF，没有可提取的文字；仍可使用 PDF 阅读器查看原页面。")
        }
        return makeBook(
            title: url.deletingPathExtension().lastPathComponent,
            format: "pdf",
            sections: sections,
            coverData: nil
        )
    }
}

private enum BookChapterDetector {
    private static let headingPattern = #"(?im)^[ \t]{0,6}(?:(?:第[0-9０-９一二三四五六七八九十百千万零〇两]+[卷部篇章节回集册](?:[ \t·:：—-]+[^\n]{0,45})?)|(?:(?:卷|部|篇)[ \t]*[0-9０-９一二三四五六七八九十百千万零〇两]+[^\n]{0,35})|(?:序章|楔子|前言|序言|引子|尾声|后记|番外(?:[ \t]*[0-9０-９一二三四五六七八九十]+)?)(?:[ \t·:：—-]+[^\n]{0,35})?|(?:(?:chapter|part|book)[ \t]+[0-9a-zivxlcdm]+(?:[ \t·:：—-]+[^\n]{0,50})?))[ \t]*$"#

    static func chapters(in text: String, fallbackTitle: String) -> [BookChapter] {
        let value = BookParser.normalize(text)
        let source = value as NSString
        guard source.length > 0 else {
            return [BookChapter(index: 0, title: fallbackTitle, text: "（没有可显示的文字）", startOffset: 0, length: 1)]
        }

        let regex = try? NSRegularExpression(pattern: headingPattern)
        let matches = regex?.matches(in: value, range: NSRange(location: 0, length: source.length)) ?? []
        if matches.count >= 2 {
            var boundaries: [(offset: Int, title: String)] = matches.map { match in
                let title = source.substring(with: match.range)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (match.range.location, title)
            }
            if let first = boundaries.first, first.offset > 300 {
                boundaries.insert((0, "开始"), at: 0)
            }
            return build(text: source, boundaries: boundaries)
        }

        return smartChapters(text: source, fallbackTitle: fallbackTitle)
    }

    static func chapters(from sections: [(title: String, text: String)]) -> [BookChapter] {
        var result: [BookChapter] = []
        var globalOffset = 0

        for section in sections {
            let normalized = BookParser.normalize(section.text)
            guard (normalized as NSString).length > 0 else { continue }
            let detected = chapters(in: normalized, fallbackTitle: section.title)
            let shouldKeepSectionTitle = detected.count == 1

            for chapter in detected {
                let title = shouldKeepSectionTitle ? section.title : chapter.title
                result.append(
                    BookChapter(
                        index: result.count,
                        title: title.isEmpty ? "第 \(result.count + 1) 章" : title,
                        text: chapter.text,
                        startOffset: globalOffset + chapter.startOffset,
                        length: chapter.length
                    )
                )
            }
            globalOffset += (normalized as NSString).length + 2
        }

        if result.isEmpty {
            return [BookChapter(index: 0, title: "全文", text: "（没有可显示的文字）", startOffset: 0, length: 1)]
        }
        return result
    }

    private static func build(text: NSString, boundaries: [(offset: Int, title: String)]) -> [BookChapter] {
        boundaries.enumerated().compactMap { position, boundary in
            let end = position + 1 < boundaries.count ? boundaries[position + 1].offset : text.length
            guard end > boundary.offset else { return nil }
            let raw = text.substring(with: NSRange(location: boundary.offset, length: end - boundary.offset))
            let body = BookParser.normalize(raw)
            guard !body.isEmpty else { return nil }
            return BookChapter(
                index: position,
                title: boundary.title,
                text: body,
                startOffset: boundary.offset,
                length: max(end - boundary.offset, 1)
            )
        }
        .enumerated()
        .map { index, chapter in
            BookChapter(
                index: index,
                title: chapter.title,
                text: chapter.text,
                startOffset: chapter.startOffset,
                length: chapter.length
            )
        }
    }

    private static func smartChapters(text: NSString, fallbackTitle: String) -> [BookChapter] {
        let targetLength = 18_000
        guard text.length > targetLength * 2 else {
            return [BookChapter(index: 0, title: fallbackTitle, text: text as String, startOffset: 0, length: max(text.length, 1))]
        }

        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            var end = min(location + targetLength, text.length)
            if end < text.length {
                let searchStart = max(end - 1_500, location)
                let searchLength = min(3_000, text.length - searchStart)
                let breakRange = text.range(
                    of: "\n\n",
                    options: .backwards,
                    range: NSRange(location: searchStart, length: searchLength)
                )
                if breakRange.location != NSNotFound, breakRange.location > location + 4_000 {
                    end = breakRange.location + breakRange.length
                }
            }
            ranges.append(NSRange(location: location, length: max(end - location, 1)))
            location = end
        }

        let useVolumes = ranges.count > 20
        return ranges.enumerated().map { index, range in
            let volume = index / 20 + 1
            let chapter = index % 20 + 1
            let title = useVolumes ? "第 \(volume) 卷 · 第 \(chapter) 章" : "智能分章 \(index + 1)"
            return BookChapter(
                index: index,
                title: title,
                text: BookParser.normalize(text.substring(with: range)),
                startOffset: range.location,
                length: range.length
            )
        }
    }
}

private struct SimpleZIPArchive {
    private struct Entry {
        let path: String
        let flags: UInt16
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let archiveData: Data
    private let entries: [String: Entry]

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        archiveData = data
        entries = try Self.readEntries(from: data)
    }

    func data(for requestedPath: String) throws -> Data? {
        let path = Self.normalizedPath(requestedPath)
        guard let entry = entries[path] else { return nil }
        guard entry.flags & 0x1 == 0 else { throw BookParserError.protectedBook }
        let header = entry.localHeaderOffset
        guard archiveData.uint32LE(at: header) == 0x0403_4B50,
              let nameLength = archiveData.uint16LE(at: header + 26),
              let extraLength = archiveData.uint16LE(at: header + 28) else {
            throw BookParserError.unreadable("压缩文件的目录已损坏。")
        }
        let start = header + 30 + Int(nameLength) + Int(extraLength)
        let end = start + entry.compressedSize
        guard start >= 0, end <= archiveData.count else {
            throw BookParserError.unreadable("压缩文件的数据不完整。")
        }
        let compressed = archiveData.subdata(in: start..<end)
        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw BookParserError.unsupportedCompression
        }
    }

    fileprivate static func normalizedPath(_ path: String, relativeTo basePath: String = "") -> String {
        let decoded = (path.removingPercentEncoding ?? path)
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "#", maxSplits: 1)
            .first
            .map(String.init) ?? path
        let base = basePath.isEmpty ? "" : (basePath as NSString).deletingLastPathComponent
        let combined = base.isEmpty ? decoded : "\(base)/\(decoded)"
        var components: [String] = []
        for component in combined.split(separator: "/").map(String.init) {
            if component == "." || component.isEmpty { continue }
            if component == ".." {
                if !components.isEmpty { components.removeLast() }
            } else {
                components.append(component)
            }
        }
        return components.joined(separator: "/")
    }

    private static func readEntries(from data: Data) throws -> [String: Entry] {
        let minimumEOCDSize = 22
        guard data.count >= minimumEOCDSize else {
            throw BookParserError.unreadable("压缩文件太短。")
        }
        let lowerBound = max(0, data.count - 65_557)
        var eocd: Int?
        var cursor = data.count - minimumEOCDSize
        while cursor >= lowerBound {
            if data.uint32LE(at: cursor) == 0x0605_4B50 {
                eocd = cursor
                break
            }
            cursor -= 1
        }
        guard let eocd,
              let count = data.uint16LE(at: eocd + 10),
              let centralOffset = data.uint32LE(at: eocd + 16) else {
            throw BookParserError.unreadable("找不到压缩文件目录。")
        }

        var result: [String: Entry] = [:]
        cursor = Int(centralOffset)
        for _ in 0..<Int(count) {
            guard data.uint32LE(at: cursor) == 0x0201_4B50,
                  let flags = data.uint16LE(at: cursor + 8),
                  let method = data.uint16LE(at: cursor + 10),
                  let compressedSize = data.uint32LE(at: cursor + 20),
                  let uncompressedSize = data.uint32LE(at: cursor + 24),
                  let nameLength = data.uint16LE(at: cursor + 28),
                  let extraLength = data.uint16LE(at: cursor + 30),
                  let commentLength = data.uint16LE(at: cursor + 32),
                  let localOffset = data.uint32LE(at: cursor + 42) else {
                throw BookParserError.unreadable("压缩文件目录已损坏。")
            }
            let nameStart = cursor + 46
            let nameEnd = nameStart + Int(nameLength)
            guard nameEnd <= data.count else { throw BookParserError.unreadable("压缩文件名不完整。") }
            let nameData = data.subdata(in: nameStart..<nameEnd)
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""
            let path = normalizedPath(name)
            result[path] = Entry(
                path: path,
                flags: flags,
                method: method,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                localHeaderOffset: Int(localOffset)
            )
            cursor = nameEnd + Int(extraLength) + Int(commentLength)
        }
        return result
    }

    private static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let decoded = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let destinationAddress = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceAddress = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationAddress,
                    expectedSize,
                    sourceAddress,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decoded > 0 else { throw BookParserError.unsupportedCompression }
        output.removeSubrange(decoded..<output.count)
        return output
    }
}

private enum EPUBBookDecoder {
    static func decode(url: URL) throws -> ParsedBook {
        let archive = try SimpleZIPArchive(url: url)
        guard let containerData = try archive.data(for: "META-INF/container.xml"),
              let containerXML = String(data: containerData, encoding: .utf8),
              let rootPath = firstCapture(#"full-path\s*=\s*[\"']([^\"']+)[\"']"#, in: containerXML),
              let packageData = try archive.data(for: rootPath) else {
            throw BookParserError.unreadable("EPUB 中没有找到内容目录。")
        }

        let package = EPUBPackageParser.parse(packageData)
        guard !package.spine.isEmpty else {
            throw BookParserError.unreadable("EPUB 的阅读顺序为空。")
        }

        var navigation: [String: String] = [:]
        if let navItem = package.manifest.values.first(where: { $0.properties.contains("nav") })
            ?? package.manifest.values.first(where: { $0.mediaType.contains("ncx") }),
           let navData = try archive.data(for: SimpleZIPArchive.normalizedPath(navItem.href, relativeTo: rootPath)) {
            navigation = EPUBNavigationParser.parse(
                navData,
                navigationPath: SimpleZIPArchive.normalizedPath(navItem.href, relativeTo: rootPath)
            )
        }

        var sections: [(title: String, text: String)] = []
        for id in package.spine {
            guard let item = package.manifest[id] else { continue }
            let path = SimpleZIPArchive.normalizedPath(item.href, relativeTo: rootPath)
            guard let data = try archive.data(for: path) else { continue }
            let markup = MarkupTextParser.parse(data)
            guard markup.text.count > 20 else { continue }
            let title = navigation[path]
                ?? markup.firstHeading
                ?? "第 \(sections.count + 1) 章"
            sections.append((title, markup.text))
        }

        guard !sections.isEmpty else {
            throw BookParserError.unreadable("EPUB 中没有找到可阅读的正文。")
        }

        let coverItem = package.manifest.values.first { item in
            item.properties.contains("cover-image") || item.id == package.coverID
        }
        let coverData: Data?
        if let coverItem {
            coverData = try archive.data(for: SimpleZIPArchive.normalizedPath(coverItem.href, relativeTo: rootPath))
        } else {
            coverData = nil
        }

        return BookParser.makeBook(
            title: package.title.isEmpty ? url.deletingPathExtension().lastPathComponent : package.title,
            format: "epub",
            sections: sections,
            coverData: coverData
        )
    }

    private static func firstCapture(_ pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }
}

private struct EPUBManifestEntry {
    let id: String
    let href: String
    let mediaType: String
    let properties: Set<String>
}

private final class EPUBPackageParser: NSObject, XMLParserDelegate {
    var manifest: [String: EPUBManifestEntry] = [:]
    var spine: [String] = []
    var title = ""
    var coverID: String?

    private var isReadingTitle = false
    private var titleBuffer = ""

    static func parse(_ data: Data) -> EPUBPackageParser {
        let delegate = EPUBPackageParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
        switch name {
        case "item":
            guard let id = attributeDict["id"], let href = attributeDict["href"] else { return }
            manifest[id] = EPUBManifestEntry(
                id: id,
                href: href,
                mediaType: attributeDict["media-type"] ?? "",
                properties: Set((attributeDict["properties"] ?? "").split(separator: " ").map(String.init))
            )
        case "itemref":
            if let idref = attributeDict["idref"], attributeDict["linear"]?.lowercased() != "no" {
                spine.append(idref)
            }
        case "meta":
            if attributeDict["name"]?.lowercased() == "cover" {
                coverID = attributeDict["content"]
            }
        case "title":
            isReadingTitle = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingTitle { titleBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
        if name == "title" {
            isReadingTitle = false
            if title.isEmpty {
                title = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            titleBuffer = ""
        }
    }
}

private enum EPUBNavigationParser {
    static func parse(_ data: Data, navigationPath: String) -> [String: String] {
        guard let source = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16) else { return [:] }
        var result: [String: String] = [:]

        let anchorPattern = #"(?is)<a\b[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#
        if let regex = try? NSRegularExpression(pattern: anchorPattern) {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) where match.numberOfRanges > 2 {
                guard let hrefRange = Range(match.range(at: 1), in: source),
                      let titleRange = Range(match.range(at: 2), in: source) else { continue }
                let path = SimpleZIPArchive.normalizedPath(String(source[hrefRange]), relativeTo: navigationPath)
                let title = MarkupTextParser.plainText(String(source[titleRange]))
                if !title.isEmpty { result[path] = title }
            }
        }

        let ncxPattern = #"(?is)<navPoint\b.*?<text\b[^>]*>(.*?)</text>.*?<content\b[^>]*src\s*=\s*[\"']([^\"']+)[\"']"#
        if let regex = try? NSRegularExpression(pattern: ncxPattern) {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) where match.numberOfRanges > 2 {
                guard let titleRange = Range(match.range(at: 1), in: source),
                      let hrefRange = Range(match.range(at: 2), in: source) else { continue }
                let path = SimpleZIPArchive.normalizedPath(String(source[hrefRange]), relativeTo: navigationPath)
                let title = MarkupTextParser.plainText(String(source[titleRange]))
                if !title.isEmpty { result[path] = title }
            }
        }
        return result
    }
}

private final class MarkupTextParser: NSObject, XMLParserDelegate {
    private static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "br", "div", "figcaption", "footer",
        "h1", "h2", "h3", "h4", "h5", "h6", "header", "li", "main", "p", "section", "tr"
    ]

    private var output = ""
    private var headingDepth = 0
    private var headingBuffer = ""
    private(set) var firstHeading: String?

    static func parse(_ data: Data) -> (text: String, firstHeading: String?) {
        let delegate = MarkupTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        if parser.parse() {
            return (BookParser.normalize(delegate.output), delegate.firstHeading)
        }
        let source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? ""
        return (plainText(source), nil)
    }

    static func plainText(_ markup: String) -> String {
        var value = markup
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</(?:p|div|h[1-6]|li|section|tr)>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'"
        ]
        for (entity, replacement) in entities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        value = value.replacingOccurrences(
            of: #"&#(\d+);"#,
            with: "$1",
            options: .regularExpression
        )
        return BookParser.normalize(value)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
        if Self.blockElements.contains(name), !output.hasSuffix("\n") { output += "\n" }
        if name.range(of: #"h[1-6]"#, options: .regularExpression) != nil {
            headingDepth += 1
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        output += string
        if headingDepth > 0 { headingBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
        if name.range(of: #"h[1-6]"#, options: .regularExpression) != nil {
            headingDepth = max(headingDepth - 1, 0)
            let heading = headingBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if firstHeading == nil, !heading.isEmpty { firstHeading = heading }
            headingBuffer = ""
        }
        if Self.blockElements.contains(name), !output.hasSuffix("\n") { output += "\n" }
    }
}

private final class WordDocumentTextParser: NSObject, XMLParserDelegate {
    private var output = ""
    private var paragraph = ""
    private var isText = false
    private var preserveSpace = false

    static func parse(_ data: Data) -> String {
        let delegate = WordDocumentTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return BookParser.normalize(delegate.output)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
        if name == "t" {
            isText = true
            preserveSpace = attributeDict["xml:space"] == "preserve"
        } else if name == "tab" {
            paragraph += "\t"
        } else if name == "br" {
            paragraph += "\n"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isText else { return }
        paragraph += preserveSpace ? string : string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
        if name == "t" {
            isText = false
        } else if name == "p" {
            let value = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { output += value + "\n\n" }
            paragraph = ""
        }
    }
}

private enum MOBIBookDecoder {
    static func decode(url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count > 86,
              let recordCount = data.uint16BE(at: 76),
              recordCount > 1 else {
            throw BookParserError.unreadable("MOBI/AZW3 文件头已损坏。")
        }

        var offsets: [Int] = []
        for index in 0..<Int(recordCount) {
            guard let offset = data.uint32BE(at: 78 + index * 8) else {
                throw BookParserError.unreadable("MOBI/AZW3 记录目录不完整。")
            }
            offsets.append(Int(offset))
        }
        offsets.append(data.count)
        guard offsets[0] + 16 <= data.count else {
            throw BookParserError.unreadable("MOBI/AZW3 正文头不完整。")
        }

        let recordZero = offsets[0]
        guard let compression = data.uint16BE(at: recordZero),
              let textRecordCount = data.uint16BE(at: recordZero + 8),
              let encryption = data.uint16BE(at: recordZero + 12) else {
            throw BookParserError.unreadable("MOBI/AZW3 正文信息不完整。")
        }
        guard encryption == 0 else { throw BookParserError.protectedBook }

        var encoding: String.Encoding = .windowsCP1252
        if data.ascii(at: recordZero + 16, count: 4) == "MOBI",
           let codePage = data.uint32BE(at: recordZero + 28), codePage == 65_001 {
            encoding = .utf8
        }

        var decoded = Data()
        let upper = min(Int(textRecordCount), offsets.count - 2)
        if upper >= 1 {
            for recordIndex in 1...upper {
                guard recordIndex + 1 < offsets.count else { break }
                let start = offsets[recordIndex]
                let end = offsets[recordIndex + 1]
                guard start >= 0, end > start, end <= data.count else { continue }
                let record = data.subdata(in: start..<end)
                switch compression {
                case 1:
                    decoded.append(record)
                case 2:
                    decoded.append(try palmDOCDecompress(record))
                case 17_480:
                    throw BookParserError.unsupportedCompression
                default:
                    throw BookParserError.unsupportedCompression
                }
            }
        }

        guard var source = String(data: decoded, encoding: encoding)
                ?? String(data: decoded, encoding: .utf8) else {
            throw BookParserError.unreadable("无法解码 MOBI/AZW3 正文。")
        }
        source = source.replacingOccurrences(of: "\0", with: "")
        let text = MarkupTextParser.plainText(source)
        guard text.count > 20 else {
            throw BookParserError.unreadable("MOBI/AZW3 中没有找到可阅读的正文。")
        }
        return text
    }

    private static func palmDOCDecompress(_ data: Data) throws -> Data {
        let input = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(input.count * 2)
        var index = 0

        while index < input.count {
            let byte = input[index]
            index += 1
            switch byte {
            case 0x00:
                output.append(byte)
            case 0x01...0x08:
                let count = min(Int(byte), input.count - index)
                output.append(contentsOf: input[index..<(index + count)])
                index += count
            case 0x09...0x7F:
                output.append(byte)
            case 0x80...0xBF:
                guard index < input.count else { break }
                let pair = (Int(byte) << 8) | Int(input[index])
                index += 1
                let distance = (pair >> 3) & 0x07FF
                let length = (pair & 0x7) + 3
                guard distance > 0, distance <= output.count else { continue }
                for _ in 0..<length {
                    output.append(output[output.count - distance])
                }
            default:
                output.append(0x20)
                output.append(byte ^ 0x80)
            }
        }
        return Data(output)
    }
}

private enum LegacyWordTextRecovery {
    static func recover(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var unicodeRuns: [String] = []
        var current: [UInt16] = []
        var index = 0
        while index + 1 < bytes.count {
            let value = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
            if value == 9 || value == 10 || value == 13 || value >= 32 && value < 0xD800 {
                current.append(value)
            } else {
                if current.count >= 12 { unicodeRuns.append(String(decoding: current, as: UTF16.self)) }
                current.removeAll(keepingCapacity: true)
            }
            index += 2
        }
        if current.count >= 12 { unicodeRuns.append(String(decoding: current, as: UTF16.self)) }
        let unicode = unicodeRuns.joined(separator: "\n")
        if unicode.count > 80 { return BookParser.normalize(unicode) }

        var asciiRuns: [String] = []
        var ascii: [UInt8] = []
        for byte in bytes {
            if byte == 9 || byte == 10 || byte == 13 || (32...126).contains(byte) {
                ascii.append(byte)
            } else {
                if ascii.count >= 20 { asciiRuns.append(String(decoding: ascii, as: UTF8.self)) }
                ascii.removeAll(keepingCapacity: true)
            }
        }
        return BookParser.normalize(asciiRuns.joined(separator: "\n"))
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return withUnsafeBytes { raw in
            UInt16(raw[offset]) | (UInt16(raw[offset + 1]) << 8)
        }
    }

    func uint32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { raw in
            UInt32(raw[offset])
                | (UInt32(raw[offset + 1]) << 8)
                | (UInt32(raw[offset + 2]) << 16)
                | (UInt32(raw[offset + 3]) << 24)
        }
    }

    func uint16BE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return withUnsafeBytes { raw in
            (UInt16(raw[offset]) << 8) | UInt16(raw[offset + 1])
        }
    }

    func uint32BE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { raw in
            (UInt32(raw[offset]) << 24)
                | (UInt32(raw[offset + 1]) << 16)
                | (UInt32(raw[offset + 2]) << 8)
                | UInt32(raw[offset + 3])
        }
    }

    func ascii(at offset: Int, count length: Int) -> String? {
        guard offset >= 0, offset + length <= count else { return nil }
        return String(data: subdata(in: offset..<(offset + length)), encoding: .ascii)
    }
}
