import CryptoKit
import Foundation

// Adapted from youshen2/MeloX under GPL-3.0.
func meloXArtworkURL(from source: String?, dimension: Int = 1_024) -> URL? {
    guard var source = source?.trimmingCharacters(in: .whitespacesAndNewlines),
          !source.isEmpty else { return nil }

    if source.hasPrefix("//") {
        source = "https:\(source)"
    } else if !source.contains("://") {
        source = "https://\(source)"
    }
    guard var components = URLComponents(string: source) else { return nil }
    if components.scheme?.lowercased() == "http" {
        components.scheme = "https"
    }
    components.query = nil
    components.queryItems = [
        URLQueryItem(name: "param", value: "\(dimension)y\(dimension)")
    ]
    return components.url
}

func meloXArtworkURL(fromPicID picID: Int64?, dimension: Int = 1_024) -> URL? {
    guard let picID, picID > 0 else { return nil }
    let source = Array(String(picID).utf8)
    let magic = Array("3go8&$8*3*3h0k(2)2".utf8)
    let encrypted = Data(source.enumerated().map { index, byte in
        byte ^ magic[index % magic.count]
    })
    let encodedID = Data(Insecure.MD5.hash(data: encrypted))
        .base64EncodedString()
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "+", with: "-")
    return meloXArtworkURL(
        from: "https://p1.music.126.net/\(encodedID)/\(picID).jpg",
        dimension: dimension
    )
}

struct MeloXArtist: Decodable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let picURL: String?
    let avatarURL: String?
    let aliases: [String]

    var artworkURL: URL? {
        meloXArtworkURL(from: avatarURL ?? picURL)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, alias, picUrl, img1v1Url
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "未知歌手"
        picURL = try values.decodeIfPresent(String.self, forKey: .picUrl)
        avatarURL = try values.decodeIfPresent(String.self, forKey: .img1v1Url)
        aliases = try values.decodeIfPresent([String].self, forKey: .alias) ?? []
    }
}

struct MeloXAlbum: Decodable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let picURL: String?
    let picID: Int64?
    let artists: [MeloXArtist]
    let publishTime: Double?
    let size: Int?
    let type: String?
    let albumDescription: String?

    var artworkURL: URL? {
        meloXArtworkURL(from: picURL) ?? meloXArtworkURL(fromPicID: picID)
    }

    var artistText: String {
        let value = artists.map(\.name).joined(separator: " / ")
        return value.isEmpty ? "未知歌手" : value
    }

    enum CodingKeys: String, CodingKey {
        case id, name, picUrl, blurPicUrl, artists, artist
        case pic, picStr = "pic_str", picId, picIdStr = "picId_str"
        case publishTime, size, type, description
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "未知专辑"
        picURL = try values.decodeIfPresent(String.self, forKey: .picUrl)
            ?? values.decodeIfPresent(String.self, forKey: .blurPicUrl)
        if let decodedArtists = try values.decodeIfPresent([MeloXArtist].self, forKey: .artists) {
            artists = decodedArtists
        } else if let artist = try values.decodeIfPresent(MeloXArtist.self, forKey: .artist) {
            artists = [artist]
        } else {
            artists = []
        }
        publishTime = try values.decodeIfPresent(Double.self, forKey: .publishTime)
        size = try values.decodeIfPresent(Int.self, forKey: .size)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        albumDescription = try values.decodeIfPresent(String.self, forKey: .description)
        picID = Self.decodePicID(from: values)
    }

    private static func decodePicID(
        from values: KeyedDecodingContainer<CodingKeys>
    ) -> Int64? {
        for key in [CodingKeys.pic, .picId] {
            if let value = try? values.decode(Int64.self, forKey: key) { return value }
            if let value = try? values.decode(String.self, forKey: key) { return Int64(value) }
        }
        for key in [CodingKeys.picStr, .picIdStr] {
            if let value = try? values.decode(String.self, forKey: key) { return Int64(value) }
        }
        return nil
    }
}

struct MeloXSong: Decodable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let artists: [MeloXArtist]
    let album: MeloXAlbum?
    let durationMS: Int
    let trackNumber: Int?
    let disc: String?
    let fee: Int?
    let aliases: [String]

    var artistText: String {
        let value = artists.map(\.name).joined(separator: " / ")
        return value.isEmpty ? "未知歌手" : value
    }

    var durationText: String {
        let seconds = max(durationMS, 0) / 1_000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, ar, artists, al, album, dt, duration, no, cd, fee
        case aliases = "alia"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "未知歌曲"
        artists = try values.decodeIfPresent([MeloXArtist].self, forKey: .ar)
            ?? values.decodeIfPresent([MeloXArtist].self, forKey: .artists)
            ?? []
        album = try values.decodeIfPresent(MeloXAlbum.self, forKey: .al)
            ?? values.decodeIfPresent(MeloXAlbum.self, forKey: .album)
        durationMS = try values.decodeIfPresent(Int.self, forKey: .dt)
            ?? values.decodeIfPresent(Int.self, forKey: .duration)
            ?? 0
        trackNumber = try values.decodeIfPresent(Int.self, forKey: .no)
        disc = try values.decodeIfPresent(String.self, forKey: .cd)
        fee = try values.decodeIfPresent(Int.self, forKey: .fee)
        aliases = try values.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}

struct MeloXUserSummary: Decodable, Hashable, Sendable {
    let userID: Int
    let nickname: String

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case nickname
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userID = try values.decodeIfPresent(Int.self, forKey: .userID) ?? 0
        nickname = try values.decodeIfPresent(String.self, forKey: .nickname) ?? "网易云音乐"
    }
}

struct MeloXTrackReference: Decodable, Hashable, Sendable {
    let id: Int
}

struct MeloXPlaylist: Decodable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let coverURLString: String?
    let playlistDescription: String?
    let trackCount: Int
    let playCount: Int
    let updateFrequency: String?
    let toplistType: String?
    let copywriter: String?
    let creator: MeloXUserSummary?
    var tracks: [MeloXSong]
    let trackIDs: [MeloXTrackReference]

    var artworkURL: URL? { meloXArtworkURL(from: coverURLString) }

    enum CodingKeys: String, CodingKey {
        case id, name, coverImgUrl, picUrl, description, trackCount, playCount
        case updateFrequency, copywriter, creator, tracks, trackIds
        case toplistType = "ToplistType"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "未知歌单"
        coverURLString = try values.decodeIfPresent(String.self, forKey: .coverImgUrl)
            ?? values.decodeIfPresent(String.self, forKey: .picUrl)
        playlistDescription = try values.decodeIfPresent(String.self, forKey: .description)
        trackCount = try values.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        playCount = try values.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        updateFrequency = try values.decodeIfPresent(String.self, forKey: .updateFrequency)
        toplistType = try values.decodeIfPresent(String.self, forKey: .toplistType)
        copywriter = try values.decodeIfPresent(String.self, forKey: .copywriter)
        creator = try values.decodeIfPresent(MeloXUserSummary.self, forKey: .creator)
        tracks = try values.decodeIfPresent([MeloXSong].self, forKey: .tracks) ?? []
        trackIDs = try values.decodeIfPresent([MeloXTrackReference].self, forKey: .trackIds) ?? []
    }
}

struct MeloXPersonalizedResponse: Decodable { let result: [MeloXPlaylist] }
struct MeloXToplistsResponse: Decodable { let list: [MeloXPlaylist] }
struct MeloXTopPlaylistsResponse: Decodable { let playlists: [MeloXPlaylist] }
struct MeloXPlaylistDetailResponse: Decodable { let playlist: MeloXPlaylist }
struct MeloXAlbumDetailResponse: Decodable { let album: MeloXAlbum; let songs: [MeloXSong] }
struct MeloXNewAlbumsResponse: Decodable { let albums: [MeloXAlbum] }
struct MeloXSongDetailResponse: Decodable { let songs: [MeloXSong] }

struct MeloXSongURLResponse: Decodable {
    let data: [MeloXSongURL]
}

struct MeloXSongURL: Decodable {
    let id: Int
    let url: String?
}

struct MeloXLyricResponse: Decodable {
    let lrc: MeloXLyricContent?
    let yrc: MeloXLyricContent?
    let tlyric: MeloXLyricContent?
    let ytlrc: MeloXLyricContent?
}

struct MeloXLyricContent: Decodable {
    let lyric: String?
}
