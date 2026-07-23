import Combine
import CommonCrypto
import CryptoKit
import Foundation

enum MeloXAPIError: LocalizedError {
    case requestEncoding
    case invalidResponse
    case emptyResponse(Int)
    case server(Int, String)
    case noPlayableSource

    var errorDescription: String? {
        switch self {
        case .requestEncoding:
            "无法生成网易云音乐请求。"
        case .invalidResponse:
            "音乐服务返回了无法识别的数据。"
        case .emptyResponse(let code):
            "音乐服务返回了空响应（\(code)）。"
        case .server(let code, let message):
            "请求失败（\(code)）：\(message)"
        case .noPlayableSource:
            "当前歌曲可能因版权或地区限制，没有可用的播放地址。"
        }
    }
}

// The request format and routes are adapted from MeloX's direct Netease client.
final class MeloXDirectClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func eapi<Response: Decodable>(
        _ uri: String,
        data: [String: Any] = [:]
    ) async throws -> Response {
        var requestData = data
        requestData["header"] = eapiHeader
        requestData["e_r"] = false
        let json = try jsonString(requestData)
        let message = "nobody\(uri)use\(json)md5forencrypt"
        let digest = Insecure.MD5.hash(data: Data(message.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let payload = "\(uri)-36cd479b6b5-\(json)-36cd479b6b5-\(digest)"
        let params = try aesECB(Data(payload.utf8), key: "e82ckenh8dichen8")
            .map { String(format: "%02X", $0) }
            .joined()
        let path = uri.replacingOccurrences(of: "/api/", with: "/eapi/")
        guard let url = URL(string: "https://interface.music.163.com\(path)") else {
            throw MeloXAPIError.requestEncoding
        }
        return try await send(url: url, form: ["params": params])
    }

    private func send<Response: Decodable>(
        url: URL,
        form: [String: String]
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 20
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "os=ios; appver=9.0.90; __remember_me=true",
            forHTTPHeaderField: "Cookie"
        )
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MeloXAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MeloXAPIError.server(
                response.statusCode,
                HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            )
        }
        guard !data.isEmpty else {
            throw MeloXAPIError.emptyResponse(response.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = payload?["code"] as? Int ?? response.statusCode
            let message = payload?["message"] as? String
                ?? payload?["msg"] as? String
                ?? error.localizedDescription
            throw MeloXAPIError.server(code, message)
        }
    }

    private var eapiHeader: [String: String] {
        [
            "os": "ios",
            "appver": "9.0.90",
            "osver": "18.0",
            "buildver": String(Int(Date().timeIntervalSince1970)),
            "channel": "distribution",
            "requestId": "\(Int64(Date().timeIntervalSince1970 * 1_000))_0000",
            "__csrf": ""
        ]
    }

    private func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let value = String(data: data, encoding: .utf8) else {
            throw MeloXAPIError.requestEncoding
        }
        return value
    }

    private func aesECB(_ data: Data, key: String) throws -> Data {
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let capacity = output.count
        var length = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withCString { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding) | CCOptions(kCCOptionECBMode),
                        keyBytes,
                        kCCKeySizeAES128,
                        nil,
                        dataBytes.baseAddress,
                        data.count,
                        outputBytes.baseAddress,
                        capacity,
                        &length
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw MeloXAPIError.requestEncoding }
        output.removeSubrange(length..<output.count)
        return output
    }
}

final class MeloXMusicAPI: @unchecked Sendable {
    private let client: MeloXDirectClient

    init(client: MeloXDirectClient = MeloXDirectClient()) {
        self.client = client
    }

    func playlists(category: String, limit: Int = 50) async throws -> [MeloXPlaylist] {
        switch category {
        case "推荐歌单":
            let response: MeloXPersonalizedResponse = try await client.eapi(
                "/api/personalized/playlist",
                data: ["limit": limit, "total": true, "n": 1_000]
            )
            return response.result
        case "排行榜":
            let response: MeloXToplistsResponse = try await client.eapi("/api/toplist")
            return response.list
        case "精品歌单":
            let response: MeloXTopPlaylistsResponse = try await client.eapi(
                "/api/playlist/highquality/list",
                data: ["cat": "全部", "limit": limit, "lasttime": 0, "total": true]
            )
            if !response.playlists.isEmpty { return response.playlists }
            let fallback: MeloXTopPlaylistsResponse = try await client.eapi(
                "/api/playlist/list",
                data: [
                    "cat": "全部",
                    "order": "hot",
                    "offset": 0,
                    "limit": limit,
                    "total": true
                ]
            )
            return fallback.playlists
        default:
            let response: MeloXTopPlaylistsResponse = try await client.eapi(
                "/api/playlist/list",
                data: [
                    "cat": category,
                    "order": "hot",
                    "offset": 0,
                    "limit": limit,
                    "total": true
                ]
            )
            return response.playlists
        }
    }

    func newAlbums(limit: Int = 12) async throws -> [MeloXAlbum] {
        let response: MeloXNewAlbumsResponse = try await client.eapi(
            "/api/album/new",
            data: ["limit": limit, "offset": 0, "total": true, "area": "ALL"]
        )
        return response.albums
    }

    func playlist(id: Int, trackLimit: Int = 100) async throws -> MeloXPlaylist {
        let count = min(max(trackLimit, 1), 100)
        let response: MeloXPlaylistDetailResponse = try await client.eapi(
            "/api/v6/playlist/detail",
            data: ["id": id, "n": count, "s": 8]
        )
        var playlist = response.playlist
        let ids = playlist.trackIDs.prefix(count).map(\.id)
        if !ids.isEmpty {
            var songs: [Int: MeloXSong] = [:]
            for song in playlist.tracks {
                songs[song.id] = song
            }
            let missing = ids.filter { songs[$0] == nil }
            if !missing.isEmpty {
                for song in try await songDetails(ids: missing) {
                    songs[song.id] = song
                }
            }
            playlist.tracks = ids.compactMap { songs[$0] }
        } else if playlist.tracks.count > count {
            playlist.tracks = Array(playlist.tracks.prefix(count))
        }
        return playlist
    }

    func album(id: Int) async throws -> (MeloXAlbum, [MeloXSong]) {
        let response: MeloXAlbumDetailResponse = try await client.eapi("/api/v1/album/\(id)")
        return (response.album, response.songs)
    }

    func songDetails(ids: [Int]) async throws -> [MeloXSong] {
        guard !ids.isEmpty else { return [] }
        let values = ids.map { ["id": $0] }
        let data = try JSONSerialization.data(withJSONObject: values)
        guard let json = String(data: data, encoding: .utf8) else {
            throw MeloXAPIError.requestEncoding
        }
        let response: MeloXSongDetailResponse = try await client.eapi(
            "/api/v3/song/detail",
            data: ["c": json]
        )
        return response.songs
    }

    func songURL(id: Int) async throws -> URL {
        guard let url = try await songURLs(ids: [id])[id] else {
            throw MeloXAPIError.noPlayableSource
        }
        return url
    }

    func songURLs(ids: [Int]) async throws -> [Int: URL] {
        guard !ids.isEmpty else { return [:] }
        let encodedIDs = "[" + ids.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let response: MeloXSongURLResponse = try await client.eapi(
            "/api/song/enhance/player/url",
            data: ["ids": encodedIDs, "br": 320_000]
        )
        return response.data.reduce(into: [:]) { result, source in
            guard let rawURL = source.url,
                  var components = URLComponents(string: rawURL) else { return }
            if components.scheme?.lowercased() == "http" {
                components.scheme = "https"
            }
            if let url = components.url {
                result[source.id] = url
            }
        }
    }

    func lyrics(id: Int) async throws -> TimedLyrics? {
        do {
            let response: MeloXLyricResponse = try await client.eapi(
                "/api/song/lyric/v1",
                data: [
                    "id": id,
                    "cp": false,
                    "tv": 0,
                    "lv": 0,
                    "rv": 0,
                    "kv": 0,
                    "yv": 0,
                    "ytv": 0,
                    "yrv": 0
                ]
            )
            let value = UnifiedAudioLyricParser.parse(
                yrc: response.yrc?.lyric ?? "",
                lrc: response.lrc?.lyric ?? "",
                translatedYRC: response.ytlrc?.lyric ?? "",
                translatedLRC: response.tlyric?.lyric ?? ""
            )
            return value.isEmpty ? nil : value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let response: MeloXLyricResponse = try await client.eapi(
                "/api/song/lyric",
                data: ["id": id, "tv": -1, "lv": -1, "rv": -1, "kv": -1]
            )
            let value = UnifiedAudioLyricParser.parse(
                yrc: "",
                lrc: response.lrc?.lyric ?? "",
                translatedYRC: "",
                translatedLRC: response.tlyric?.lyric ?? ""
            )
            return value.isEmpty ? nil : value
        }
    }
}

@MainActor
final class MeloXMusicService: ObservableObject {
    @Published private(set) var playbackError: String?

    private let api: MeloXMusicAPI
    private var songsByID: [Int: MeloXSong] = [:]
    private weak var player: AudioPlayerController?
    private var playerObservation: AnyCancellable?
    private var hydrationTask: Task<Void, Never>?

    init(api: MeloXMusicAPI = MeloXMusicAPI()) {
        self.api = api
    }

    func attach(player: AudioPlayerController) {
        guard self.player !== player else { return }
        self.player = player
        playerObservation = player.$currentItem
            .removeDuplicates()
            .sink { [weak self] item in
                guard let self, let item else { return }
                self.hydrateIfNeeded(item)
            }
    }

    func playlists(category: String, limit: Int = 50) async throws -> [MeloXPlaylist] {
        try await api.playlists(category: category, limit: limit)
    }

    func newAlbums(limit: Int = 12) async throws -> [MeloXAlbum] {
        try await api.newAlbums(limit: limit)
    }

    func playlist(id: Int) async throws -> MeloXPlaylist {
        try await api.playlist(id: id)
    }

    func album(id: Int) async throws -> (MeloXAlbum, [MeloXSong]) {
        try await api.album(id: id)
    }

    func play(_ song: MeloXSong, in songs: [MeloXSong]) async {
        guard let player else { return }
        let queueSongs = songs.isEmpty ? [song] : songs
        for value in queueSongs { songsByID[value.id] = value }

        do {
            let resolvedURLs = try await api.songURLs(ids: queueSongs.map(\.id))
            let items = queueSongs.map { value in
                makeItem(
                    for: value,
                    url: resolvedURLs[value.id] ?? fallbackURL(for: value.id)
                )
            }
            for (value, item) in zip(queueSongs, items) {
                player.registerMetadata(baseMetadata(for: value), for: item)
            }
            guard let selected = items.first(where: { onlineSongID(for: $0) == song.id }) else { return }
            player.play(selected, in: items)
            playbackError = nil
            hydrateIfNeeded(selected, force: true)
        } catch {
            playbackError = error.localizedDescription
            player.playbackError = error.localizedDescription
        }
    }

    private func hydrateIfNeeded(_ item: LibraryItem, force: Bool = false) {
        guard let id = onlineSongID(for: item), let song = songsByID[id], let player else { return }
        let existing = player.metadataByPath[item.relativePath]
        guard force || existing?.lyrics == nil || existing?.artworkData == nil else { return }

        hydrationTask?.cancel()
        hydrationTask = Task { [weak self, weak player] in
            guard let self, let player else { return }
            async let lyricResult: TimedLyrics? = try? self.api.lyrics(id: id)
            async let artworkResult: Data? = self.artworkData(for: song)
            let (lyrics, artwork) = await (lyricResult, artworkResult)
            guard !Task.isCancelled else { return }
            var metadata = player.metadataByPath[item.relativePath] ?? self.baseMetadata(for: song)
            if let lyrics { metadata.lyrics = lyrics }
            if let artwork { metadata.artworkData = artwork }
            player.registerMetadata(metadata, for: item)
        }
    }

    private func artworkData(for song: MeloXSong) async -> Data? {
        guard let url = song.album?.artworkURL else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              !data.isEmpty else { return nil }
        return data
    }

    private func makeItem(for song: MeloXSong, url: URL) -> LibraryItem {
        LibraryItem(
            url: url,
            name: "\(song.name).mp3",
            kind: .music,
            byteCount: 0,
            modifiedAt: Date(),
            isDirectory: false,
            relativePath: "MeloX/\(song.id).mp3"
        )
    }

    private func baseMetadata(for song: MeloXSong) -> EmbeddedAudioMetadata {
        EmbeddedAudioMetadata(
            title: song.name,
            artist: song.artistText,
            album: song.album?.name,
            albumArtist: song.album?.artistText,
            genre: nil,
            year: song.album?.publishTime.map { timestamp in
                String(Calendar.current.component(
                    .year,
                    from: Date(timeIntervalSince1970: timestamp / 1_000)
                ))
            },
            trackNumber: song.trackNumber.map(String.init),
            discNumber: song.disc,
            codec: "stream",
            sampleRate: nil,
            bitDepth: nil,
            isLossless: false,
            artworkData: nil,
            lyrics: nil
        )
    }

    private func fallbackURL(for id: Int) -> URL {
        URL(string: "https://music.163.com/song/media/outer/url?id=\(id).mp3")!
    }

    private func onlineSongID(for item: LibraryItem) -> Int? {
        guard item.relativePath.hasPrefix("MeloX/") else { return nil }
        return Int(URL(fileURLWithPath: item.relativePath).deletingPathExtension().lastPathComponent)
    }
}
