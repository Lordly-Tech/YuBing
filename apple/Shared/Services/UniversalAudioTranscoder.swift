import CryptoKit
import FFmpeg
import Foundation

enum UniversalAudioError: LocalizedError {
    case noAudioStream
    case noDecodedFrames

    var errorDescription: String? {
        switch self {
        case .noAudioStream:
            "文件中没有可播放的音轨。"
        case .noDecodedFrames:
            "音频解码器没有输出有效内容。"
        }
    }
}

enum UniversalAudioSource {
    static let transcodedExtensions: Set<String> = [
        "dsd", "dsf", "dff", "ape", "ogg", "oga", "opus", "wma"
    ]

    static func playbackURL(for sourceURL: URL) async throws -> URL {
        guard transcodedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            return sourceURL
        }

        let destination = try cachedDestination(for: sourceURL)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        return try await Task.detached(priority: .userInitiated) {
            let temporary = destination
                .deletingLastPathComponent()
                .appendingPathComponent("\(UUID().uuidString).m4a")
            do {
                try transcodeToALAC(sourceURL: sourceURL, destinationURL: temporary)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: destination)
                }
                return destination
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
        }.value
    }

    static func watchTransferURL(for sourceURL: URL) async throws -> URL {
        try await playbackURL(for: sourceURL)
    }

    private static func cachedDestination(for sourceURL: URL) throws -> URL {
        let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let identity = [
            sourceURL.standardizedFileURL.path,
            String(values?.fileSize ?? 0),
            String(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YuBing Audio Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(digest).m4a")
    }

    private static func transcodeToALAC(sourceURL: URL, destinationURL: URL) throws {
        let input = try FormatContext.openInput(url: sourceURL.path)
        let streamIndex: Int32
        do {
            streamIndex = try input.findBestStream(type: .audio)
        } catch {
            throw UniversalAudioError.noAudioStream
        }
        let decoder = try input.stream(at: Int(streamIndex)).makeDecoderContext()
        var packet = Packet()
        var frame = Frame()
        var session: ALACTranscodeSession?

        while try input.readFrame(into: &packet) {
            if packet.streamIndex == streamIndex {
                _ = try decoder.sendPacket(packet)
                while true {
                    frame.unref()
                    guard try decoder.receiveFrame(into: &frame) == .success else { break }
                    if session == nil {
                        session = try ALACTranscodeSession(firstFrame: frame, destinationURL: destinationURL)
                    }
                    try session?.write(frame)
                }
            }
            packet.unref()
        }

        _ = try decoder.sendFlush()
        while true {
            frame.unref()
            guard try decoder.receiveFrame(into: &frame) == .success else { break }
            if session == nil {
                session = try ALACTranscodeSession(firstFrame: frame, destinationURL: destinationURL)
            }
            try session?.write(frame)
        }

        guard let session else { throw UniversalAudioError.noDecodedFrames }
        try session.finish()
    }
}

private final class ALACTranscodeSession {
    private let writer: MediaWriter
    private var resampler: AudioResampler
    private let targetFormat = SampleFormat(rawValue: 7) // AV_SAMPLE_FMT_S32P
    private let targetLayout: ChannelLayout
    private let targetSampleRate: Int32
    private let timeBase: Rational
    private var sampleCursor: Int64 = 0
    private var lastCapacity: Int32 = 4096

    init(firstFrame: borrowing Frame, destinationURL: URL) throws {
        let sourceRate = firstFrame.sampleRate > 0 ? firstFrame.sampleRate : 44_100
        targetSampleRate = min(sourceRate, 192_000)
        let sourceLayout = firstFrame.channelLayout.channelCount > 0 ? firstFrame.channelLayout : .stereo
        targetLayout = sourceLayout.channelCount > 2 ? .stereo : sourceLayout
        timeBase = Rational(numerator: 1, denominator: targetSampleRate)

        writer = try MediaWriter(url: destinationURL.path, formatName: "ipod")
        try writer.addAudioStream(
            codecID: CodecID(rawValue: 0x15010), // AV_CODEC_ID_ALAC
            sampleRate: targetSampleRate,
            sampleFormat: targetFormat,
            channelLayout: targetLayout,
            timeBase: timeBase
        )
        try writer.start()

        resampler = try AudioResampler(
            srcChannelLayout: sourceLayout,
            srcSampleRate: sourceRate,
            srcFormat: firstFrame.sampleFormat,
            dstChannelLayout: targetLayout,
            dstSampleRate: targetSampleRate,
            dstFormat: targetFormat
        )
    }

    func write(_ source: borrowing Frame) throws {
        let sourceRate = max(source.sampleRate, 1)
        let estimated = Int32(
            ceil(Double(max(source.numberOfSamples, 1)) * Double(targetSampleRate) / Double(sourceRate))
        ) + 256
        lastCapacity = max(lastCapacity, estimated)

        var converted = Frame()
        converted.sampleFormat = targetFormat
        converted.sampleRate = targetSampleRate
        converted.channelLayout = targetLayout
        converted.numberOfSamples = estimated
        converted.timeBase = timeBase
        converted.pts = sampleCursor
        try converted.allocateBuffers()

        let outputSamples = try resampler.convert(source: source, into: &converted)
        guard outputSamples > 0 else { return }
        converted.numberOfSamples = outputSamples
        try writer.writeAudioFrame(converted)
        sampleCursor += Int64(outputSamples)
    }

    func finish() throws {
        var tail = Frame()
        tail.sampleFormat = targetFormat
        tail.sampleRate = targetSampleRate
        tail.channelLayout = targetLayout
        tail.numberOfSamples = lastCapacity
        tail.timeBase = timeBase
        tail.pts = sampleCursor
        try tail.allocateBuffers()
        let outputSamples = try resampler.flush(into: &tail)
        if outputSamples > 0 {
            tail.numberOfSamples = outputSamples
            try writer.writeAudioFrame(tail)
        }
        try writer.finish()
    }
}
