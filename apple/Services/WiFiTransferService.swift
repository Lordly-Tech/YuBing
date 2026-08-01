import Combine
import Darwin
import Foundation
import Network

final class WiFiTransferService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var address: String?
    @Published private(set) var status = AppLocalization.string("尚未启动")
    @Published private(set) var uploadProgress: Double?

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
        guard listener == nil, !isStarting else { return }
        isStarting = true
        status = AppLocalization.string("正在启动")
        do {
            let newListener = try NWListener(using: .tcp, on: .any)
            newListener.service = NWListener.Service(name: "鱼饼", type: "_yubing._tcp")
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isStarting = false
                    let port = self.listener?.port?.rawValue ?? 0
                    if let host = Self.localIPv4Address() {
                        self.update(running: true, address: "http://\(host):\(port)", status: AppLocalization.string("等待电脑上传"))
                    } else {
                        self.update(running: true, address: nil, status: AppLocalization.string("已启动，请连接 Wi-Fi 后重新开始传输"))
                    }
                case .failed(let error):
                    self.isStarting = false
                    self.listener = nil
                    self.update(running: false, address: nil, status: Self.message(for: error))
                case .cancelled:
                    self.isStarting = false
                    self.listener = nil
                    self.update(running: false, address: nil, status: AppLocalization.string("已停止"))
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = newListener
            newListener.start(queue: queue)
        } catch {
            isStarting = false
            update(running: false, address: nil, status: Self.message(for: error))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isStarting = false
        uploadProgress = nil
        update(running: false, address: nil, status: AppLocalization.string("已停止"))
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

            if let totalLength {
                self.updateUploadProgress(received: received.count, total: totalLength)
            }

            if let totalLength, received.count >= totalLength {
                self.handle(request: received, connection: connection)
            } else if complete || error != nil {
                self.updateUploadProgress(nil)
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
            respond(connection, status: "200 OK", body: Self.uploadPage(), contentType: "text/html; charset=utf-8")
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
            self.update(running: true, address: self.address, status: AppLocalization.format("正在导入 %@ 个文件", "\(files.count)"))
            for file in files {
                await self.importer?(file.data, file.name)
            }
            self.updateUploadProgress(nil)
            self.update(running: true, address: self.address, status: AppLocalization.format("已接收 %@ 个文件", "\(files.count)"))
            self.respond(connection, status: "200 OK", body: Self.successPage(), contentType: "text/html; charset=utf-8")
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

    private func updateUploadProgress(received: Int, total: Int) {
        guard total > 0 else { return }
        let progress = min(max(Double(received) / Double(total), 0), 1)
        updateUploadProgress(progress)
        update(running: true, address: address, status: AppLocalization.format("正在接收 %@%%", "\(Int(progress * 100))"))
    }

    private func updateUploadProgress(_ progress: Double?) {
        DispatchQueue.main.async {
            self.uploadProgress = progress
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
            return AppLocalization.string("本地网络权限未生效，请在系统设置中允许鱼饼访问本地网络后再次开始传输。")
        default:
            return error.localizedDescription
        }
    }

    private static func message(for error: any Error) -> String {
        (error as? NWError).map(Self.message(for:)) ?? error.localizedDescription
    }

    private static func uploadPage() -> String {
        let title = AppLocalization.string("鱼饼传输")
        let heading = AppLocalization.string("鱼饼无线传输")
        let subtitle1 = AppLocalization.string("选择文件、照片、视频或音乐")
        let subtitle2 = AppLocalization.string("上传后会自动加入鱼饼资料库")
        let chooseHint = AppLocalization.string("点这里挑选文件，可以多选哦")
        let startUpload = AppLocalization.string("开始上传")
        let readyUpload = AppLocalization.string("准备上传")
        let footer = AppLocalization.string("保持手机和电脑在同一个 Wi-Fi 下～")
        let selectedPrefix = AppLocalization.string("已选择 ")
        let selectedSuffix = AppLocalization.string(" 个：")
        let separator = AppLocalization.string("、")
        let chooseFirst = AppLocalization.string("请先选择文件")
        let uploading = AppLocalization.string("上传中")
        let uploadingPrefix = AppLocalization.string("正在上传")
        let uploadAgain = AppLocalization.string("重新上传")
        let uploadFailed = AppLocalization.string("上传失败，请重试")
        let htmlLanguage = AppLocalization.selectedLanguage.localeIdentifier
        return """
        <!doctype html><html lang="\(htmlLanguage)"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(title)</title>
        <style>
        *{box-sizing:border-box}
        body{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif;margin:0;min-height:100vh;padding:48px 20px;color:#6b3550;background:linear-gradient(160deg,#fff1f6 0%,#ffe4ef 45%,#ffeef8 100%);display:flex;align-items:center;justify-content:center}
        .card{width:100%;max-width:520px;background:rgba(255,255,255,.78);border:1px solid #ffd3e4;border-radius:28px;padding:34px 30px;box-shadow:0 18px 44px rgba(255,138,180,.24);text-align:center}
        .fish{font-size:46px;line-height:1}
        h1{margin:14px 0 6px;font-size:27px;color:#e8578f;letter-spacing:.5px}
        .sub{margin:0 0 24px;font-size:14px;line-height:1.7;color:#a8788d}
        .drop{display:block;border:2px dashed #ffb4d0;border-radius:20px;padding:26px 18px;background:#fff8fb;cursor:pointer;transition:.2s}
        .drop:hover{border-color:#ff8ab4;background:#fff2f7}
        .drop .icon{font-size:30px}
        .drop .hint{margin-top:8px;font-size:14px;color:#c07f9c}
        #files{display:none}
        .picked{margin-top:12px;font-size:13px;color:#e8578f;word-break:break-all;line-height:1.6}
        button{margin-top:22px;width:100%;font-size:17px;font-weight:600;padding:14px 22px;border-radius:999px;border:0;color:#fff;background:linear-gradient(135deg,#ffa0c4,#ff5f9d);box-shadow:0 10px 22px rgba(255,95,157,.32);cursor:pointer;transition:.2s}
        button:hover{filter:brightness(1.04)}
        button:disabled{opacity:.62;cursor:default;box-shadow:none}
        .progress{display:none;margin-top:20px}
        .bar{height:14px;background:#ffe6f0;border-radius:999px;overflow:hidden}
        .fill{height:100%;width:0;border-radius:999px;background:linear-gradient(90deg,#ffc0d8,#ff5f9d);transition:width .15s ease}
        .label{margin-top:9px;font-size:13px;color:#c07f9c}
        .foot{margin-top:22px;font-size:12px;color:#d0a3b6}
        </style>
        <div class="card">
        <div class="fish">🐟🍪</div>
        <h1>\(heading)</h1>
        <p class="sub">\(subtitle1)<br>\(subtitle2)</p>
        <form id="uploadForm">
        <label class="drop" for="files"><div class="icon">🌸</div><div class="hint">\(chooseHint)</div></label>
        <input id="files" type="file" name="files" multiple>
        <div class="picked" id="picked"></div>
        <button id="submit" type="submit">\(startUpload)</button>
        <div class="progress" id="progress"><div class="bar"><div class="fill" id="fill"></div></div><div class="label" id="label">\(readyUpload)</div></div>
        </form>
        <div class="foot">\(footer)</div>
        </div>
        <script>
        const i18n={selectedPrefix:\(Self.javascriptString(selectedPrefix)),selectedSuffix:\(Self.javascriptString(selectedSuffix)),separator:\(Self.javascriptString(separator)),chooseFirst:\(Self.javascriptString(chooseFirst)),uploading:\(Self.javascriptString(uploading)),uploadingPrefix:\(Self.javascriptString(uploadingPrefix)),uploadAgain:\(Self.javascriptString(uploadAgain)),uploadFailed:\(Self.javascriptString(uploadFailed))};
        const form=document.getElementById('uploadForm'),files=document.getElementById('files'),submit=document.getElementById('submit'),progress=document.getElementById('progress'),fill=document.getElementById('fill'),label=document.getElementById('label'),picked=document.getElementById('picked');
        files.addEventListener('change',()=>{const list=Array.from(files.files).map(f=>f.name);picked.textContent=list.length?i18n.selectedPrefix+list.length+i18n.selectedSuffix+list.join(i18n.separator):''});
        form.addEventListener('submit',e=>{e.preventDefault();if(!files.files.length){label.textContent=i18n.chooseFirst;progress.style.display='block';return}const data=new FormData();for(const file of files.files){data.append('files',file,file.name)}const xhr=new XMLHttpRequest();xhr.open('POST','/');progress.style.display='block';submit.disabled=true;submit.textContent=i18n.uploading;xhr.upload.onprogress=event=>{if(!event.lengthComputable)return;const pct=Math.round(event.loaded/event.total*100);fill.style.width=pct+'%';label.textContent=i18n.uploadingPrefix+' '+pct+'%'};xhr.onload=()=>{document.open();document.write(xhr.responseText);document.close()};xhr.onerror=()=>{submit.disabled=false;submit.textContent=i18n.uploadAgain;label.textContent=i18n.uploadFailed};xhr.send(data)});
        </script></html>
        """
    }

    private static func successPage() -> String {
        let title = AppLocalization.string("传输完成")
        let message = AppLocalization.string("文件已经加入鱼饼，可以继续选择其他文件。")
        let back = AppLocalization.string("返回上传")
        let htmlLanguage = AppLocalization.selectedLanguage.localeIdentifier
        return """
        <!doctype html><html lang="\(htmlLanguage)"><meta name="viewport" content="width=device-width"><title>\(title)</title>
        <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:680px;margin:80px auto;padding:24px}</style>
        <h1>\(title)</h1><p>\(message)</p><a href="/">\(back)</a></html>
        """
    }

    private static func javascriptString(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

}
