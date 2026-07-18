import CryptoKit
import Foundation

enum UniversalAudioError: LocalizedError {
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let message):
            message
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
            let temporary = destination.deletingLastPathComponent()
                .appendingPathComponent("\(UUID().uuidString).m4a")
            var errorBuffer = [CChar](repeating: 0, count: 1024)
            let result = sourceURL.path.withCString { input in
                temporary.path.withCString { output in
                    yubing_transcode_to_alac(input, output, &errorBuffer, Int32(errorBuffer.count))
                }
            }
            guard result >= 0 else {
                try? FileManager.default.removeItem(at: temporary)
                let message = String(cString: errorBuffer)
                throw UniversalAudioError.conversionFailed(
                    message.isEmpty ? "无法解码此音频格式。" : message
                )
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            return destination
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
}
