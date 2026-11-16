import Foundation
import CryptoKit
import Security

// MARK: - HTTP 基础

enum Net {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 900
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func makeRequest(_ urlString: String, method: String = "POST", headers: [String: String], body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw LLMError(message: "地址无效：\(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    static func jsonRequest(_ urlString: String, headers: [String: String], json: Any) throws -> URLRequest {
        let data = try JSONSerialization.data(withJSONObject: json)
        var merged = headers
        merged["Content-Type"] = "application/json"
        return try makeRequest(urlString, headers: merged, body: data)
    }

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError(message: "响应异常")
            }
            if http.statusCode >= 400 {
                throw apiError(status: http.statusCode, data: data)
            }
            return (data, http)
        } catch let error as LLMError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw LLMError(message: "已停止")
        } catch {
            throw LLMError(message: error.localizedDescription)
        }
    }

    static func sendJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, _) = try await send(request)
        return JSONValue.object(data) ?? [:]
    }

    /// 从各家错误体里挑一句能看懂的话
    static func apiError(status: Int, data: Data) -> LLMError {
        var message = ""
        if let object = JSONValue.object(data) {
            if let error = object["error"] as? [String: Any] {
                message = JSONValue.string(error["message"])
                if message.isEmpty { message = JSONValue.string(error["type"]) }
                let code = JSONValue.string(error["code"])
                if !code.isEmpty { message += "（\(code)）" }
            } else if let error = object["error"] as? String {
                message = error
            }
            if message.isEmpty { message = JSONValue.string(object["message"]) }
            if message.isEmpty { message = JSONValue.string(object["msg"]) }
            if message.isEmpty { message = JSONValue.string(object["detail"]) }
            if message.isEmpty {
                let code = JSONValue.string(object["code"])
                if !code.isEmpty { message = "code \(code)" }
            }
        }
        if message.isEmpty {
            message = String(data: data.prefix(400), encoding: .utf8) ?? ""
        }
        let text = message.trimmed.isEmpty ? "HTTP \(status)" : "HTTP \(status) · \(message.trimmed.truncated(500))"
        return LLMError(message: text, status: status)
    }

    static func models(from data: Data) -> [String] {
        var result: [String] = []
        if let object = JSONValue.object(data), let list = object["data"] as? [Any] {
            for item in list {
                let dict = JSONValue.dict(item)
                let id = JSONValue.string(dict["id"])
                if !id.isEmpty { result.append(id) }
            }
        } else if let list = JSONValue.any(data) as? [Any] {
            for item in list {
                if let dict = item as? [String: Any] {
                    let id = JSONValue.string(dict["id"])
                    if !id.isEmpty { result.append(id) }
                } else if let id = item as? String {
                    result.append(id)
                }
            }
        } else if let object = JSONValue.object(data), let list = object["models"] as? [Any] {
            for item in list {
                let dict = JSONValue.dict(item)
                let id = JSONValue.string(dict["name"])
                if !id.isEmpty { result.append(id) }
            }
        }
        return Array(Set(result)).sorted()
    }
}

// MARK: - 通用工具

enum Auth {
    static func bearer(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)"]
    }

    static func uuid() -> String {
        UUID().uuidString.lowercased()
    }

    static func randomHex(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, bytes, pointer.baseAddress!)
        }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    static func hex(_ bytes: Int) -> String { randomHex(bytes) }

    static func sha1(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 模型调用

enum LLMClient {
    static func stream(_ invocation: ChatInvocation, secret: ProviderSecret, sessionID: String) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch invocation.provider.format {
                    case .openai:
                        try await streamOpenAI(invocation, secret: secret, sessionID: sessionID, continuation: continuation)
                    case .anthropic:
                        try await streamAnthropic(invocation, secret: secret, sessionID: sessionID, continuation: continuation)
                    case .gemini:
                        try await streamGemini(invocation, secret: secret, continuation: continuation)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: URL 拼装

    static func chatEndpoint(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        if trimmed.hasSuffix("/chat/completions") { return trimmed }
        return trimmed + "/chat/completions"
    }

    static func anthropicEndpoint(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        if trimmed.hasSuffix("/messages") { return trimmed }
        if trimmed.hasSuffix("/v1") { return trimmed + "/messages" }
        return trimmed + "/v1/messages"
    }

    static func geminiEndpoint(_ base: String, model: String, stream: Bool) -> String {
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        let root: String
        if trimmed.hasSuffix("/v1beta") || trimmed.hasSuffix("/v1") {
            root = trimmed
        } else {
            root = trimmed + "/v1beta"
        }
        let action = stream ? "streamGenerateContent?alt=sse" : "generateContent"
        return root + "/models/" + model + ":" + action
    }

    // MARK: OpenAI 兼容（含 Zen / Copilot / 远程服务）

    static func streamOpenAI(_ inv: ChatInvocation, secret: ProviderSecret, sessionID: String, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        let provider = inv.provider
        let model = provider.upstreamModel(inv.model)
        var messages: [[String: Any]] = []
        if !inv.system.trimmed.isEmpty {
            messages.append(["role": "system", "content": inv.system])
        }
        for turn in inv.turns {
            messages.append(["role": turn.role, "content": turn.content])
        }

        var headers: [String: String] = ["Accept": "text/event-stream"]
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true
        ]
        if inv.temperature > 0 { body["temperature"] = inv.temperature }

        switch provider.kind {
        case .zenFree:
            messages = Zen.dress(messages: messages, system: inv.system)
            body["messages"] = messages
            body["stream_options"] = ["include_usage": true]
            headers = Zen.headers(session: sessionID)
        case .copilot:
            guard !secret.inferenceToken.isEmpty else {
                throw LLMError(message: "Copilot 未登录，请先在渠道里完成设备码登录")
            }
            headers = Copilot.headers(token: secret.inferenceToken, vision: false)
        default:
            if !secret.apiKey.isEmpty {
                headers["Authorization"] = "Bearer \(secret.apiKey)"
            }
        }
        for (key, value) in provider.headers { headers[key] = value }

        let url = chatEndpoint(provider.baseURL)
        let request = try Net.jsonRequest(url, headers: headers, json: body)

        var produced = false
        let emit: (String) -> Void = { payload in
            if let events = parseOpenAI(payload) {
                for event in events { continuation.yield(event) }
                if !events.isEmpty { produced = true }
            }
        }
        do {
            try await consume(request, emit)
        } catch let error as LLMError where provider.kind == .zenFree && !produced && (error.status == 403 || error.status == 429) {
            // Zen 的免费层偶尔要求请求带工具，带上 OpenCode 自己的五个核心工具（标注为不可用）再试一次
            body["tools"] = Zen.coreTools
            let retry = try Net.jsonRequest(url, headers: headers, json: body)
            try await consume(retry, emit)
        }
    }

    // MARK: Anthropic 兼容（含 ZCode）

    static func streamAnthropic(_ inv: ChatInvocation, secret: ProviderSecret, sessionID: String, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        let provider = inv.provider
        let model = provider.upstreamModel(inv.model)
        var messages: [[String: Any]] = []
        for turn in inv.turns where turn.role != "system" {
            messages.append(["role": turn.role == "assistant" ? "assistant" : "user", "content": turn.content])
        }
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": inv.maxTokens,
            "stream": true
        ]
        if !inv.system.trimmed.isEmpty { body["system"] = inv.system }
        if inv.temperature > 0 { body["temperature"] = min(inv.temperature, 1.0) }

        var headers: [String: String] = [
            "Accept": "text/event-stream",
            "anthropic-version": "2023-06-01"
        ]
        if provider.kind == .zcode {
            let key = secret.zcodeKey.isEmpty ? secret.apiKey : secret.zcodeKey
            guard !key.isEmpty else {
                throw LLMError(message: "ZCode 未登录，请先用 Z.ai / 智谱账号登录或粘贴 GLM Coding Plan API Key")
            }
            headers["x-api-key"] = key
            headers["Authorization"] = "Bearer \(key)"
            headers["X-Title"] = "Z Code@electron"
            headers["x-session-id"] = sessionID
            headers["x-query-id"] = Auth.uuid()
            body["metadata"] = ZCode.metadata(device: secret.deviceID, session: sessionID)
        } else if !secret.apiKey.isEmpty {
            headers["x-api-key"] = secret.apiKey
            headers["Authorization"] = "Bearer \(secret.apiKey)"
        }
        for (key, value) in provider.headers { headers[key] = value }

        let url = anthropicEndpoint(provider.baseURL)
        let request = try Net.jsonRequest(url, headers: headers, json: body)
        try await consume(request) { payload in
            if let events = parseAnthropic(payload) {
                for event in events { continuation.yield(event) }
            }
        }
    }

    // MARK: Gemini 兼容

    static func streamGemini(_ inv: ChatInvocation, secret: ProviderSecret, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        let provider = inv.provider
        let model = provider.upstreamModel(inv.model)
        var contents: [[String: Any]] = []
        for turn in inv.turns where turn.role != "system" {
            contents.append([
                "role": turn.role == "assistant" ? "model" : "user",
                "parts": [["text": turn.content]]
            ])
        }
        var body: [String: Any] = ["contents": contents]
        if !inv.system.trimmed.isEmpty {
            body["systemInstruction"] = ["parts": [["text": inv.system]]]
        }
        var generation: [String: Any] = ["maxOutputTokens": inv.maxTokens]
        if inv.temperature > 0 { generation["temperature"] = inv.temperature }
        body["generationConfig"] = generation

        var headers: [String: String] = ["Accept": "text/event-stream"]
        if !secret.apiKey.isEmpty { headers["x-goog-api-key"] = secret.apiKey }
        for (key, value) in provider.headers { headers[key] = value }

        var url = geminiEndpoint(provider.baseURL, model: model, stream: true)
        if !secret.apiKey.isEmpty { url += "&key=" + secret.apiKey }
        let request = try Net.jsonRequest(url, headers: headers, json: body)
        try await consume(request) { payload in
            if let events = parseGemini(payload) {
                for event in events { continuation.yield(event) }
            }
        }
    }

    // MARK: 流式读取

    @discardableResult
    static func consume(_ request: URLRequest, _ onPayload: (String) -> Void) async throws -> String {
        do {
            let (bytes, response) = try await Net.session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError(message: "响应异常")
            }
            if http.statusCode >= 400 {
                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                    if data.count > 40000 { break }
                }
                throw Net.apiError(status: http.statusCode, data: data)
            }
            if (http.mimeType ?? "").contains("json") {
                var data = Data()
                for try await byte in bytes { data.append(byte) }
                let text = String(data: data, encoding: .utf8) ?? ""
                onPayload(text)
                return text
            }
            var collected = ""
            for try await line in bytes.lines {
                let trimmed = line.trimmed
                if trimmed.hasPrefix("data:") {
                    let payload = String(trimmed.dropFirst(5)).trimmed
                    if payload.isEmpty { continue }
                    collected += payload + "\n"
                    onPayload(payload)
                } else if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                    collected += trimmed + "\n"
                    onPayload(trimmed)
                }
            }
            return collected
        } catch let error as LLMError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw LLMError(message: error.localizedDescription)
        }
    }

    // MARK: 解析

    static func parseOpenAI(_ payload: String) -> [StreamEvent]? {
        if payload == "[DONE]" { return [] }
        guard payload.hasPrefix("{"), let data = payload.data(using: .utf8), let object = JSONValue.object(data) else {
            return nil
        }
        var events: [StreamEvent] = []
        if let model = object["model"] as? String, !model.isEmpty {
            events.append(.model(model))
        }
        if let error = object["error"] as? [String: Any] {
            let message = JSONValue.string(error["message"])
            if !message.isEmpty {
                events.append(.text("\n\n⚠️ " + message))
            }
            return events
        }
        guard let choice = JSONValue.array(object["choices"]).first else { return events }
        let choiceDict = JSONValue.dict(choice)
        let container = JSONValue.dict(choiceDict["delta"]).isEmpty ? JSONValue.dict(choiceDict["message"]) : JSONValue.dict(choiceDict["delta"])
        if let content = container["content"] as? String, !content.isEmpty {
            events.append(.text(content))
        } else if let parts = container["content"] as? [Any] {
            for part in parts {
                let dict = JSONValue.dict(part)
                let text = JSONValue.string(dict["text"])
                if !text.isEmpty { events.append(.text(text)) }
            }
        }
        for key in ["reasoning_content", "reasoning", "thinking"] {
            if let reasoning = container[key] as? String, !reasoning.isEmpty {
                events.append(.reasoning(reasoning))
            }
        }
        if let text = choiceDict["text"] as? String, !text.isEmpty {
            events.append(.text(text))
        }
        return events
    }

    static func parseAnthropic(_ payload: String) -> [StreamEvent]? {
        if payload == "[DONE]" { return [] }
        guard payload.hasPrefix("{"), let data = payload.data(using: .utf8), let object = JSONValue.object(data) else { return nil }
        var events: [StreamEvent] = []
        if let model = object["model"] as? String, !model.isEmpty { events.append(.model(model)) }
        let type = JSONValue.string(object["type"])
        switch type {
        case "content_block_delta":
            let delta = JSONValue.dict(object["delta"])
            let kind = JSONValue.string(delta["type"])
            if kind == "thinking_delta" {
                let thinking = JSONValue.string(delta["thinking"])
                if !thinking.isEmpty { events.append(.reasoning(thinking)) }
            } else {
                let text = JSONValue.string(delta["text"])
                if !text.isEmpty { events.append(.text(text)) }
            }
        case "content_block_start":
            let block = JSONValue.dict(object["content_block"])
            if JSONValue.string(block["type"]) == "text" {
                let text = JSONValue.string(block["text"])
                if !text.isEmpty { events.append(.text(text)) }
            }
        case "message":
            for item in JSONValue.array(object["content"]) {
                let block = JSONValue.dict(item)
                let blockType = JSONValue.string(block["type"])
                let text = JSONValue.string(block["text"])
                if blockType == "thinking" {
                    if !text.isEmpty { events.append(.reasoning(text)) }
                } else if !text.isEmpty {
                    events.append(.text(text))
                }
            }
        case "error":
            let error = JSONValue.dict(object["error"])
            let message = JSONValue.string(error["message"])
            if !message.isEmpty { events.append(.text("\n\n⚠️ " + message)) }
        default:
            break
        }
        return events
    }

    static func parseGemini(_ payload: String) -> [StreamEvent]? {
        guard payload.hasPrefix("{"), let data = payload.data(using: .utf8), let object = JSONValue.object(data) else { return nil }
        var events: [StreamEvent] = []
        if let error = object["error"] as? [String: Any] {
            let message = JSONValue.string(error["message"])
            if !message.isEmpty { events.append(.text("\n\n⚠️ " + message)) }
            return events
        }
        guard let candidate = JSONValue.array(object["candidates"]).first else { return events }
        let dict = JSONValue.dict(candidate)
        let content = JSONValue.dict(dict["content"])
        for part in JSONValue.array(content["parts"]) {
            let piece = JSONValue.dict(part)
            let text = JSONValue.string(piece["text"])
            if text.isEmpty { continue }
            if let thought = piece["thought"] as? Bool, thought {
                events.append(.reasoning(text))
            } else {
                events.append(.text(text))
            }
        }
        if let reason = dict["finishReason"] as? String, reason == "SAFETY" {
            events.append(.text("\n\n⚠️ 内容被 Gemini 安全策略拦截"))
        }
        return events
    }
}

