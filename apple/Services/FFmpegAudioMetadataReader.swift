import Foundation

struct FFmpegAudioMetadataSnapshot: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var date: String?
    var trackNumber: String?
    var discNumber: String?
    var lyrics: String?
    var codec: String?
    var sampleRate: Int?
    var bitDepth: Int?
    var isLossless: Bool
    var artworkData: Data?
}

enum FFmpegAudioMetadataReader {
    static func read(from url: URL) throws -> FFmpegAudioMetadataSnapshot {
        var rawMetadata = YuBingAudioMetadata()
        var errorBuffer = [CChar](repeating: 0, count: 1_024)
        let result = url.path.withCString { path in
            yubing_read_audio_metadata(
                path,
                &rawMetadata,
                &errorBuffer,
                Int32(errorBuffer.count)
            )
        }
        defer { yubing_free_audio_metadata(&rawMetadata) }

        guard result >= 0 else {
            let message = String(cString: errorBuffer)
            throw NSError(
                domain: "YuBingAudioMetadata",
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        let artworkData: Data?
        if let bytes = rawMetadata.artwork_data,
           rawMetadata.artwork_size > 0,
           rawMetadata.artwork_size <= Int64(Int.max) {
            artworkData = Data(bytes: bytes, count: Int(rawMetadata.artwork_size))
        } else {
            artworkData = nil
        }

        return FFmpegAudioMetadataSnapshot(
            title: string(from: rawMetadata.title),
            artist: string(from: rawMetadata.artist),
            album: string(from: rawMetadata.album),
            albumArtist: string(from: rawMetadata.album_artist),
            genre: string(from: rawMetadata.genre),
            date: string(from: rawMetadata.date),
            trackNumber: string(from: rawMetadata.track_number),
            discNumber: string(from: rawMetadata.disc_number),
            lyrics: string(from: rawMetadata.lyrics),
            codec: string(from: rawMetadata.codec),
            sampleRate: rawMetadata.sample_rate > 0 ? Int(rawMetadata.sample_rate) : nil,
            bitDepth: rawMetadata.bit_depth > 0 ? Int(rawMetadata.bit_depth) : nil,
            isLossless: rawMetadata.is_lossless != 0,
            artworkData: artworkData
        )
    }

    private static func string(from pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        let value = String(cString: pointer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
