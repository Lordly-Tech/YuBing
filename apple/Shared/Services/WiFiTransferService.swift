import Combine
import Darwin
import Foundation
import Network

final class WiFiTransferService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var address: String?
    @Published private(set) var status = "尚未启动"

    private let queue = DispatchQueue(label: "top.lordly.yubing.wifi-transfer", qos: .userInitiated)
    private var listener: NWListener?
    private var importer: ((Data, String) async -> Void)?

    func attach(store: LibraryStore) {
        importer = { [weak store] data, name in
            await MainActor.run {
                store?.importData(data, suggestedName: name)
            }
        }
    }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            listener.service = NWListener.Service(name: "鱼饼", type: "_yubing._tcp")
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let port = listener?.port?.rawValue ?? 0
                    if let host = Self.localIPv4Address() {
                        self.update(running: true, address: "http://\(host):\(port)", status: "等待电脑上传")
                    } else {
                        self.update(running: true, address: nil, status: "已启动，请连接 Wi-Fi 后重新开始传输")
                    }
                case .failed(let error):
                    self.update(running: false, address: nil, status: Self.message(for: error))
                    self.stop()
                case .cancelled:
                    self.update(running: false, address: nil, status: "已停止")
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
            update(running: false, address: nil, status: "正在启动")
        } catch {
            update(running: false, address: nil, status: Self.message(for: error))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        update(running: false, address: nil, status: "已停止")
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, data: Data(), expectedLength: nil)
    }

    private func receive(on connection: NWConnection, data: Data, expectedLength: Int?) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] chunk, _, complete, error in
            guard let self else { return }
            var received = data
            if let chunk { received.append(chunk) }

            var totalLength = expectedLength
            if totalLength == nil,
               let headerRange = received.range(of: Data("\r\n\r\n".utf8)),
               let header = String(data: Data(received[..<headerRange.lowerBound]), encoding: .utf8) {
                let contentLength = header
                    .components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
                totalLength = headerRange.upperBound + contentLength
            }

            if let totalLength, received.count >= totalLength {
                self.handle(request: received, connection: connection)
            } else if complete || error != nil {
                self.respond(connection, status: "400 Bad Request", body: "Incomplete request")
            } else {
                self.receive(on: connection, data: received, expectedLength: totalLength)
            }
        }
    }

    private func handle(request: Data, connection: NWConnection) {
        guard let headerRange = request.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: Data(request[..<headerRange.lowerBound]), encoding: .utf8) else {
            respond(connection, status: "400 Bad Request", body: "Invalid request")
            return
        }
        let firstLine = header.components(separatedBy: "\r\n").first ?? ""
        if firstLine.hasPrefix("GET ") {
            respond(connection, status: "200 OK", body: Self.uploadPage, contentType: "text/html; charset=utf-8")
            return
        }
        guard firstLine.hasPrefix("POST "),
              let boundaryLine = header.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-type:") }),
              let boundary = boundaryLine.components(separatedBy: "boundary=").last else {
            respond(connection, status: "405 Method Not Allowed", body: "Unsupported request")
            return
        }

        let body = Data(request[headerRange.upperBound...])
        let files = multipartFiles(in: body, boundary: boundary.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        guard !files.isEmpty else {
            respond(connection, status: "400 Bad Request", body: "No files")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            for file in files {
                await self.importer?(file.data, file.name)
            }
            self.update(running: true, address: self.address, status: "已接收 \(files.count) 个文件")
            self.respond(connection, status: "200 OK", body: Self.successPage, contentType: "text/html; charset=utf-8")
        }
    }

    private func multipartFiles(in body: Data, boundary: String) -> [(name: String, data: Data)] {
        let marker = Data("--\(boundary)".utf8)
        var parts: [Data] = []
        var cursor = body.startIndex
        while let range = body.range(of: marker, in: cursor..<body.endIndex) {
            if cursor != body.startIndex {
                parts.append(Data(body[cursor..<range.lowerBound]))
            }
            cursor = range.upperBound
        }
        var result: [(String, Data)] = []
        for part in parts {
            guard let separator = part.range(of: Data("\r\n\r\n".utf8)),
                  let headers = String(data: part[..<separator.lowerBound], encoding: .utf8),
                  let nameStart = headers.range(of: "filename=\"")?.upperBound,
                  let nameEnd = headers[nameStart...].firstIndex(of: "\"") else { continue }
            let originalName = String(headers[nameStart..<nameEnd])
            let safeName = URL(fileURLWithPath: originalName).lastPathComponent
            var fileData = Data(part[separator.upperBound...])
            while fileData.suffix(2) == Data("\r\n".utf8) { fileData.removeLast(2) }
            if fileData.suffix(2) == Data("--".utf8) { fileData.removeLast(2) }
            if !safeName.isEmpty, !fileData.isEmpty { result.append((safeName, fileData)) }
        }
        return result
    }

    private func respond(_ connection: NWConnection, status: String, body: String, contentType: String = "text/plain; charset=utf-8") {
        let payload = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + payload, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func update(running: Bool, address: String?, status: String) {
        DispatchQueue.main.async {
            self.isRunning = running
            self.address = address
            self.status = status
        }
    }

    private static func localIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        var fallback: String?
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            if name == "lo0" { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(MemoryLayout<sockaddr_in>.size),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let value = String(cString: host)
            if name == "en0" { return value }
            if name.hasPrefix("en") || name.hasPrefix("bridge") {
                fallback = fallback ?? value
            }
        }
        return fallback
    }

    private static func message(for error: NWError) -> String {
        switch error {
        case .posix(let code) where code == .EPERM:
            return "本地网络权限未生效，请在系统设置中允许鱼饼访问本地网络后再次开始传输。"
        default:
            return error.localizedDescription
        }
    }

    private static let uploadPage = """
    <!doctype html><html lang="zh-CN"><meta name="viewport" content="width=device-width"><title>鱼饼传输</title>
    <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:680px;margin:60px auto;padding:24px}h1{font-size:34px}form{border:1px solid #ccc;padding:24px;border-radius:8px}input{width:100%;margin:18px 0}button{font-size:18px;padding:12px 22px}</style>
    <h1>🐟🍪！无线传输</h1><p>选择文件、照片、视频或音乐，上传后会自动加入鱼饼资料库。</p>
    <form method="post" enctype="multipart/form-data"><input type="file" name="files" multiple><button type="submit">上传</button></form></html>
    """

    private static let successPage = """
    <!doctype html><html lang="zh-CN"><meta name="viewport" content="width=device-width"><title>传输完成</title>
    <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:680px;margin:80px auto;padding:24px}</style>
    <h1>传输完成</h1><p>文件已经加入鱼饼，可以继续选择其他文件。</p><a href="/">返回上传</a></html>
    """
}
