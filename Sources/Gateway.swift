import Foundation
import Network

// MARK: - 请求结构

struct GatewayRequest {
    var method: String = "GET"
    var path: String = "/"
    var query: String = ""
    var headers: [String: String] = [:]
    var body: Data = Data()

    var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }

    func header(_ name: String) -> String {
        headers[name.lowercased()] ?? ""
    }
}

// MARK: - 局域网地址

enum LAN {
    static func addresses() -> [String] {
        var result: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return result }
        defer { freeifaddrs(pointer) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let interface = current.pointee
            cursor = interface.ifa_next
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(addr.pointee.sa_len)
            if getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.isEmpty { result.append(ip) }
            }
        }
        return result
    }
}

// MARK: - 网关

final class GatewayServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.lin.mausipa.gateway")
    private var connections: [GatewayConnection] = []
    private(set) var port: UInt16 = 8787

    var onRequest: ((GatewayRequest, GatewayConnection) -> Void)?

    var isRunning: Bool { listener != nil }

    func start(port: UInt16) throws {
        guard port > 0 else { throw LLMError(message: "端口无效") }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw LLMError(message: "端口无效") }
        stop()
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: nwPort)
        listener.service = NWListener.Service(name: "MausIPA", type: "_mausipa._tcp")
        listener.newConnectionHandler = { [weak self] nwConnection in
            guard let self else { return }
            let wrapper = GatewayConnection(connection: nwConnection, queue: self.queue)
            wrapper.onRequest = self.onRequest
            self.connections.append(wrapper)
            wrapper.start()
        }
        listener.stateUpdateHandler = { _ in }
        listener.start(queue: queue)
        self.listener = listener
        self.port = port
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [weak self] in
            guard let self else { return }
            for connection in self.connections { connection.close() }
            self.connections.removeAll()
        }
    }
}

final class GatewayConnection {
    private let connection: NWConnection
    private let queue: DispatchQueue
    var onRequest: ((GatewayRequest, GatewayConnection) -> Void)?

    private var buffer = Data()
    private var headerEnd = -1
    private var contentLength = 0
    private var request: GatewayRequest?
    private var handled = false

    private var pending: [Data] = []
    private var sending = false
    private var closeWhenDrained = false
    private var closed = false

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func close() {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self.closed = true
            self.connection.cancel()
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty { self.buffer.append(data) }
            if self.parseIfReady() { return }
            if isComplete || error != nil {
                self.close()
            } else {
                self.receive()
            }
        }
    }

    /// 返回 true 表示请求已交给处理方
    private func parseIfReady() -> Bool {
        if headerEnd < 0 {
            let marker = Data("\r\n\r\n".utf8)
            if let range = buffer.range(of: marker) {
                headerEnd = range.upperBound
                let head = String(data: buffer[Data.Index(0)..<range.lowerBound], encoding: .utf8) ?? ""
                var lines = head.components(separatedBy: "\r\n")
                guard let requestLine = lines.first else { return false }
                let parts = requestLine.split(separator: " ")
                var req = GatewayRequest()
                if parts.count >= 2 {
                    req.method = String(parts[0]).uppercased()
                    let target = String(parts[1])
                    if let questionMark = target.firstIndex(of: "?") {
                        req.path = String(target[target.startIndex..<questionMark])
                        req.query = String(target[target.index(after: questionMark)...])
                    } else {
                        req.path = target
                    }
                }
                lines.removeFirst()
                for line in lines {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = String(line[line.startIndex..<colon]).lowercased().trimmed
                    let value = String(line[line.index(after: colon)...]).trimmed
                    req.headers[key] = value
                }
                contentLength = max(Int(req.headers["content-length"] ?? "0") ?? 0, 0)
                request = req
            } else {
                return false
            }
        }
        guard let request else { return false }
        let bodyStart = headerEnd
        let available = buffer.count - bodyStart
        if available < contentLength {
            return false
        }
        if request.method == "OPTIONS" {
            sendHead(204, contentType: "text/plain", chunked: false, extra: [
                "Access-Control-Allow-Headers": "Authorization, Content-Type",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                "Access-Control-Max-Age": "86400"
            ])
            finish(chunked: false)
            handled = true
            return true
        }
        guard !handled else { return true }
        handled = true
        var full = request
        if contentLength > 0 {
            full.body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        }
        onRequest?(full, self)
        return true
    }

    // MARK: 回写（全部在 queue 上串行执行）

    private func onQueue(_ block: @escaping () -> Void) {
        queue.async(execute: block)
    }

    func sendHead(_ status: Int, contentType: String, chunked: Bool, extra: [String: String] = [:]) {
        var lines = [
            "HTTP/1.1 \(status) \(reason(status))",
            "Content-Type: \(contentType)",
            "Access-Control-Allow-Origin: *",
            "Connection: close",
            "Cache-Control: no-store"
        ]
        if chunked {
            lines.append("Transfer-Encoding: chunked")
        }
        for (key, value) in extra {
            lines.append("\(key): \(value)")
        }
        let head = lines.joined(separator: "\r\n") + "\r\n\r\n"
        let data = Data(head.utf8)
        onQueue { [weak self] in
            guard let self, !self.closed else { return }
            self.pending.append(data)
            self.pump()
        }
    }

    func sendBody(_ data: Data, chunked: Bool) {
        let payload: Data
        if chunked {
            var framed = Data("\(String(data.count, radix: 16))\r\n".utf8)
            framed.append(data)
            framed.append(Data("\r\n".utf8))
            payload = framed
        } else {
            payload = data
        }
        onQueue { [weak self] in
            guard let self, !self.closed else { return }
            self.pending.append(payload)
            self.pump()
        }
    }

    func sendEvent(_ text: String) {
        sendBody(Data(text.utf8), chunked: true)
    }

    func finish(chunked: Bool) {
        onQueue { [weak self] in
            guard let self, !self.closed else { return }
            if chunked { self.pending.append(Data("0\r\n\r\n".utf8)) }
            self.closeWhenDrained = true
            self.pump()
        }
    }

    func sendJSON(_ object: Any, status: Int = 200) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        var lines = [
            "HTTP/1.1 \(status) \(reason(status))",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(data.count)",
            "Access-Control-Allow-Origin: *",
            "Connection: close",
            "Cache-Control: no-store"
        ]
        lines.append("")
        lines.append("")
        let head = Data(lines.joined(separator: "\r\n").utf8)
        onQueue { [weak self] in
            guard let self, !self.closed else { return }
            self.pending.append(head)
            self.pending.append(data)
            self.closeWhenDrained = true
            self.pump()
        }
    }

    private func pump() {
        guard !sending, !closed else { return }
        guard !pending.isEmpty else {
            if closeWhenDrained {
                closeWhenDrained = false
                connection.send(content: nil, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                    self?.close()
                })
            }
            return
        }
        sending = true
        let data = pending.removeFirst()
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.sending = false
            self.pump()
        })
    }

    private func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }
}
