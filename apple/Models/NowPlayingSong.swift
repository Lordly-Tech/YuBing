import Foundation

struct NowPlayingSong: Identifiable {
    let item: LibraryItem
    let metadata: EmbeddedAudioMetadata
    let duration: TimeInterval

    var id: String { item.id }
    var name: String { metadata.title ?? item.displayName }
    var artistText: String { metadata.artist ?? metadata.albumArtist ?? "本地音乐" }
    var albumText: String { metadata.album ?? "未知专辑" }
    var artworkData: Data? { metadata.artworkData }
    var durationMS: Int { Int(max(duration, 0) * 1_000) }
}

extension AudioPlayerController {
    var progress: TimeInterval { currentTime }
}
