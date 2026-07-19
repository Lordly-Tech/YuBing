import Foundation

struct FLACMetadataSnapshot: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var date: String?
    var trackNumber: String?
    var discNumber: String?
    var sampleRate: Int?
    var bitDepth: Int?
    var artworkData: Data?
    var lyrics: String?
}

enum FLACMetadataReader {
    private static let signature = Data([0x66, 0x4c, 0x61, 0x43])
    private static let maximumLoadedBlockSize = 32 * 1_024 * 1_024

    static func read(from url: URL) throws -> FLACMetadataSnapshot {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try seekPastOptionalID3Tag(in: handle)
        guard try readExactly(4, from: handle) == signature else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var comments: [String: [String]] = [:]
        var sampleRate: Int?
        var bitDepth: Int?
        var artworkData: Data?
        var didReachLastBlock = false

        while !didReachLastBlock {
            let header = try readExactly(4, from: handle)
            let firstByte = header.byte(at: 0)
            didReachLastBlock = (firstByte & 0x80) != 0
            let blockType = firstByte & 0x7f
            let blockLength = Int(header.byte(at: 1)) << 16 |
                Int(header.byte(at: 2)) << 8 |
                Int(header.byte(at: 3))

            guard blockType == 0 || blockType == 4 || blockType == 6 else {
                try handle.seek(toOffset: handle.offsetInFile + UInt64(blockLength))
                continue
            }
            guard blockLength <= maximumLoadedBlockSize else {
                try handle.seek(toOffset: handle.offsetInFile + UInt64(blockLength))
                continue
            }

            let block = try readExactly(blockLength, from: handle)
            switch blockType {
            case 0:
                let properties = streamProperties(from: block)
                sampleRate = properties.sampleRate
                bitDepth = properties.bitDepth
            case 4:
                comments = vorbisComments(from: block)
            case 6:
                if let picture = picture(from: block), picture.isFrontCover || artworkData == nil {
                    artworkData = picture.data
                }
            default:
                break
            }
        }

        return FLACMetadataSnapshot(
            title: firstValue(in: comments, keys: ["TITLE"]),
            artist: firstValue(in: comments, keys: ["ARTIST", "PERFORMER"]),
            album: firstValue(in: comments, keys: ["ALBUM"]),
            albumArtist: firstValue(in: comments, keys: ["ALBUMARTIST"]),
            genre: firstValue(in: comments, keys: ["GENRE"]),
            date: firstValue(in: comments, keys: ["DATE", "YEAR", "ORIGINALDATE"]),
            trackNumber: firstValue(in: comments, keys: ["TRACKNUMBER", "TRACK"]),
            discNumber: firstValue(in: comments, keys: ["DISCNUMBER", "DISC"]),
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            artworkData: artworkData,
            lyrics: firstValue(
                in: comments,
                keys: ["LYRICS", "SYNCEDLYRICS", "UNSYNCEDLYRICS", "UNSYNCHRONIZEDLYRICS"]
            )
        )
    }

    private static func seekPastOptionalID3Tag(in handle: FileHandle) throws {
        try handle.seek(toOffset: 0)
        let header = try readExactly(10, from: handle)
        if header.prefix(3) == Data([0x49, 0x44, 0x33]) {
            let tagSize = Int(header.byte(at: 6) & 0x7f) << 21 |
                Int(header.byte(at: 7) & 0x7f) << 14 |
                Int(header.byte(at: 8) & 0x7f) << 7 |
                Int(header.byte(at: 9) & 0x7f)
            try handle.seek(toOffset: UInt64(10 + tagSize))
        } else {
            try handle.seek(toOffset: 0)
        }
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        guard count >= 0, let data = try handle.read(upToCount: count), data.count == count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }

    private static func streamProperties(from data: Data) -> (sampleRate: Int?, bitDepth: Int?) {
        guard data.count >= 14 else { return (nil, nil) }
        let sampleRate = Int(data.byte(at: 10)) << 12 |
            Int(data.byte(at: 11)) << 4 |
            Int(data.byte(at: 12) >> 4)
        let bitDepth = (Int(data.byte(at: 12) & 0x01) << 4 |
            Int(data.byte(at: 13) >> 4)) + 1
        return (sampleRate > 0 ? sampleRate : nil, bitDepth > 0 ? bitDepth : nil)
    }

    private static func vorbisComments(from data: Data) -> [String: [String]] {
        var cursor = 0
        guard let vendorLength = data.littleEndianUInt32(at: cursor) else { return [:] }
        cursor += 4 + Int(vendorLength)
        guard cursor <= data.count,
              let commentCount = data.littleEndianUInt32(at: cursor),
              commentCount <= 100_000 else { return [:] }
        cursor += 4

        var result: [String: [String]] = [:]
        for _ in 0..<Int(commentCount) {
            guard let length = data.littleEndianUInt32(at: cursor) else { break }
            cursor += 4
            let end = cursor + Int(length)
            guard end <= data.count else { break }
            let entryData = data.subdata(in: cursor..<end)
            cursor = end
            guard let entry = String(data: entryData, encoding: .utf8),
                  let separator = entry.firstIndex(of: "=") else { continue }
            let rawKey = String(entry[..<separator])
            let value = String(entry[entry.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            result[normalizedKey(rawKey), default: []].append(value)
        }
        return result
    }

    private static func normalizedKey(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func firstValue(in comments: [String: [String]], keys: [String]) -> String? {
        keys.lazy
            .compactMap { comments[normalizedKey($0)]?.first }
            .first
    }

    private static func picture(from data: Data) -> (data: Data, isFrontCover: Bool)? {
        var cursor = 0
        guard let pictureType = data.bigEndianUInt32(at: cursor) else { return nil }
        cursor += 4

        guard let mimeLength = data.bigEndianUInt32(at: cursor) else { return nil }
        cursor += 4 + Int(mimeLength)
        guard cursor <= data.count,
              let descriptionLength = data.bigEndianUInt32(at: cursor) else { return nil }
        cursor += 4 + Int(descriptionLength)

        // Width, height, color depth and indexed-color count.
        cursor += 16
        guard cursor <= data.count,
              let pictureLength = data.bigEndianUInt32(at: cursor) else { return nil }
        cursor += 4
        let end = cursor + Int(pictureLength)
        guard end <= data.count else { return nil }
        return (data.subdata(in: cursor..<end), pictureType == 3)
    }
}

private extension Data {
    func byte(at offset: Int) -> UInt8 {
        self[index(startIndex, offsetBy: offset)]
    }

    func littleEndianUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return UInt32(byte(at: offset)) |
            UInt32(byte(at: offset + 1)) << 8 |
            UInt32(byte(at: offset + 2)) << 16 |
            UInt32(byte(at: offset + 3)) << 24
    }

    func bigEndianUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return UInt32(byte(at: offset)) << 24 |
            UInt32(byte(at: offset + 1)) << 16 |
            UInt32(byte(at: offset + 2)) << 8 |
            UInt32(byte(at: offset + 3))
    }
}
