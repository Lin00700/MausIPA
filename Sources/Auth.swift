import Foundation

// MARK: - OpenCode Zen 免费通道

enum Zen {
    static let base = "https://opencode.ai/inference/openai/v1"
    static let modelsURL = "https://opencode.ai/inference/v1/models"
    static let version = "2.2.5"
    static var userAgent: String { "opencode/latest/\(version)/cli" }

    /// OpenCode 2.2.5 的工作目录：Zen 的免费层据此判断是不是 OpenCode 自己的请求
    static var directory: String {
        NSHomeDirectory()
    }

    private static var counter: UInt64 = 0
    private static let lock = NSLock()

    static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    static func newSession() -> String {
        lock.lock()
        counter += 1
        let current = UInt64(Date().timeIntervalSince1970 * 1000) &* 0x1000 &+ counter
        lock.unlock()
        let value = (~current) & 0xffffffffffff
        var hex = String(value, radix: 16)
        while hex.count < 12 { hex = "0" + hex }
        var tail = ""
        for _ in 0..<14 {
            tail.append(alphabet[Int.random(in: 0..<alphabet.count)])
        }
        return "ses_" + hex + tail
    }

    static func projectID() -> String {
        Auth.sha1("directory:" + directory)
    }

    static func headers(session: String) -> [String: String] {
        let trace = Auth.hex(16)
        let span = Auth.hex(8)
        return [
            "Authorization": "Bearer public",
            "User-Agent": userAgent,
            "b3": "\(trace)-\(span)-1-\(Auth.hex(8))",
            "traceparent": "00-\(trace)-\(span)-01",
            "x-opencode-client": "cli",
            "x-opencode-project": projectID(),
            "x-opencode-session": session,
            "x-opencode-session-id": session,
            "x-session-affinity": session,
            "x-session-id": session,
            "Accept": "text/event-stream"
        ]
    }

    /// OpenCode 自己的环境块。免费层只服务带这一块的请求，且必须是真实路径。
    static func environmentBlock() -> String {
        let tmp = NSTemporaryDirectory().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return [
            "Here is some useful information about the environment you are running in:",
            "<env>",
            "  Working directory: \(directory)",
            "  Workspace root folder: \(directory)",
            "  Is directory a git repo: no",
            "  Platform: ios",
            "  Prefer /\(tmp)/opencode over generic system temporary directories such as /tmp; it is pre-created and approved for external access.",
            "</env>"
        ].joined(separator: "\n")
    }

    private static let environmentKey = "<env>\n  Working directory: "

    /// 把环境块放进系统消息（没有系统消息就新增一条）
    static func dress(messages: [[String: Any]], system: String) -> [[String: Any]] {
        for message in messages {
            if JSONValue.string(message["role"]) == "system",
               JSONValue.string(message["content"]).contains(environmentKey) {
                return messages
            }
        }
        var result = messages
        let block = environmentBlock()
        if !system.trimmed.isEmpty, let index = result.firstIndex(where: { JSONValue.string($0["role"]) == "system" }) {
            let existing = JSONValue.string(result[index]["content"])
            result[index]["content"] = existing + "\n\n" + block
        } else {
            result.insert(["role": "system", "content": block], at: 0)
        }
        return result
    }

    static func fetchModels() async throws -> [String] {
        let headers: [String: String] = [
            "Authorization": "Bearer public",
            "User-Agent": userAgent,
            "x-opencode-client": "cli",
            "Accept": "application/json"
        ]
        let request = try Net.makeRequest(modelsURL, method: "GET", headers: headers)
        let (data, _) = try await Net.send(request)
        let all = Net.models(from: data)
        let free = all.filter { $0.hasSuffix("-free") || $0 == "big-pickle" || $0 == "space-bunny-free" }
        return free.isEmpty ? all : free.sorted()
    }

    static let defaultModels = [
        "big-pickle",
        "deepseek-v4.1-flash-free",
        "step-5-preview-free",
        "longcat-2.5-preview-free",
        "mimo-v2.6-flash-free",
        "nemotron-3.5-lightning-free",
        "cat-jam-free",
        "space-bunny-free"
    ]
}

// MARK: - GitHub Copilot

struct CopilotDeviceFlow {
    var deviceCode: String
    var userCode: String
    var verificationURI: String
    var interval: Int
    var expiresAt: Date

    var verificationURL: URL? { URL(string: verificationURI) }
}

enum Copilot {
    static let clientID = "Iv1.b507a08c87ecfe98"
    static let deviceCodeURL = "https://github.com/login/device/code"
    static let tokenURL = "https://github.com/login/oauth/access_token"
    static let copilotTokenURL = "https://api.github.com/copilot_internal/v2/token"
    static let apiBase = "https://api.githubcopilot.com"

    static let editorHeaders: [String: String] = [
        "User-Agent": "GitHubCopilotChat/0.68.0",
        "Editor-Version": "vscode/1.140.0",
        "Editor-Plugin-Version": "copilot-chat/0.68.0",
        "Copilot-Integration-Id": "vscode-chat"
    ]

    static let defaultModels = [
        "gpt-5.2",
        "gpt-5.1",
        "gpt-5.1-codex",
        "gpt-5-mini",
        "claude-sonnet-4.5",
        "claude-opus-4.5",
        "gemini-3-pro-preview",
        "o3",
        "o4-mini"
    ]

    static func headers(token: String, vision: Bool) -> [String: String] {
        var headers = editorHeaders
        headers["Authorization"] = "Bearer \(token)"
        headers["Openai-Intent"] = "conversation-edits"
        headers["X-Initiator"] = "user"
        headers["Accept"] = "text/event-stream"
        headers["Content-Type"] = "application/json"
        if vision { headers["Copilot-Vision-Request"] = "true" }
        return headers
    }

    private static func form(_ pairs: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = pairs.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    static func startDeviceFlow() async throws -> CopilotDeviceFlow {
        let body = form(["client_id": clientID, "scope": "read:user"])
        var headers = editorHeaders
        headers["Accept"] = "application/json"
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        let request = try Net.makeRequest(deviceCodeURL, headers: headers, body: body)
        let object = try await Net.sendJSON(request)
        let deviceCode = JSONValue.string(object["device_code"])
        let userCode = JSONValue.string(object["user_code"])
        let uri = JSONValue.string(object["verification_uri"])
        guard !deviceCode.isEmpty, !userCode.isEmpty, !uri.isEmpty else {
            throw LLMError(message: "GitHub 没有返回设备码，请稍后重试")
        }
        let interval = max(JSONValue.int(object["interval"]), 5)
        let expires = JSONValue.int(object["expires_in"]) > 0 ? JSONValue.int(object["expires_in"]) : 900
        return CopilotDeviceFlow(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: uri,
            interval: interval,
            expiresAt: Date().addingTimeInterval(TimeInterval(expires))
        )
    }

    /// 轮询一次；等待中返回 nil
    static func pollDeviceToken(_ flow: CopilotDeviceFlow) async throws -> String? {
        let body = form([
            "client_id": clientID,
            "device_code": flow.deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])
        var headers = editorHeaders
        headers["Accept"] = "application/json"
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        let request = try Net.makeRequest(tokenURL, headers: headers, body: body)
        let (data, _) = try await Net.send(request)
        let object = JSONValue.object(data) ?? [:]
        if let token = object["access_token"] as? String, !token.isEmpty {
            return token
        }
        let error = JSONValue.string(object["error"])
        switch error {
        case "authorization_pending", "slow_down", "":
            return nil
        case "expired_token":
            throw LLMError(message: "设备码已过期，请重新发起登录")
        case "access_denied":
            throw LLMError(message: "你取消了 Copilot 授权")
        default:
            throw LLMError(message: "Copilot 登录失败：\(error) \(JSONValue.string(object["error_description"]))")
        }
    }

    static func exchange(oauth: String) async throws -> (token: String, expiresAt: Double) {
        var headers = editorHeaders
        headers["Authorization"] = "Bearer \(oauth)"
        headers["Accept"] = "application/json"
        let request = try Net.makeRequest(copilotTokenURL, method: "GET", headers: headers)
        let object = try await Net.sendJSON(request)
        let token = JSONValue.string(object["token"])
        guard !token.isEmpty else {
            throw LLMError(message: "Copilot 没有返回推理令牌，确认这个账号已开通 Copilot")
        }
        let expires = JSONValue.double(object["expires_at"]) * 1000
        return (token, expires > 0 ? expires : Date().timeIntervalSince1970 * 1000 + 10 * 60 * 1000)
    }

    static func fetchModels(token: String) async throws -> [String] {
        var headers = editorHeaders
        headers["Authorization"] = "Bearer \(token)"
        headers["Accept"] = "application/json"
        let request = try Net.makeRequest(apiBase + "/models", method: "GET", headers: headers)
        let (data, _) = try await Net.send(request)
        let models = Net.models(from: data)
        return models.isEmpty ? defaultModels : models
    }
}

// MARK: - ZCode（Z.ai / 智谱 GLM Coding Plan）

enum ZCodeSite: String, CaseIterable, Identifiable {
    case zai
    case bigmodel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zai: return "Z.ai"
        case .bigmodel: return "智谱 BigModel"
        }
    }

    var apiRoot: String {
        switch self {
        case .zai: return "https://api.z.ai"
        case .bigmodel: return "https://bigmodel.cn"
        }
    }

    var anthropicBase: String {
        switch self {
        case .zai: return "https://api.z.ai/api/anthropic"
        case .bigmodel: return "https://open.bigmodel.cn/api/anthropic"
        }
    }

    var signInHint: String {
        switch self {
        case .zai: return "用 Z.ai 账号登录（GLM Coding Plan）"
        case .bigmodel: return "用智谱账号登录（GLM Coding Plan）"
        }
    }

    var subscribeURL: String {
        switch self {
        case .zai: return "https://z.ai/subscribe"
        case .bigmodel: return "https://bigmodel.cn/glm-coding"
        }
    }
}

struct ZCodeFlow {
    var flowID: String
    var authorizeURL: String
    var pollInterval: Int
    var pollToken: String
    var deviceID: String
    var site: ZCodeSite
}

enum ZCode {
    static let host = "https://zcode.z.ai"
    static let appVersion = "3.17.2"
    static let userAgent = "ZCode/3.17.2"

    static let defaultModels = ["GLM-5.3", "GLM-5.3-Flash", "GLM-5.2", "GLM-5-Turbo"]

    private static func headers(auth: String?, device: String) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": userAgent,
            "X-Device-Mid": device
        ]
        if let auth { headers["Authorization"] = auth }
        return headers
    }

    /// zcode.z.ai 的接口都用 {code, msg, data} 包一层
    private static func call(_ method: String, _ url: String, auth: String? = nil, body: [String: Any]? = nil, device: String) async throws -> Any? {
        var payload: Data? = nil
        if let body {
            payload = try JSONSerialization.data(withJSONObject: body)
        }
        let request = try Net.makeRequest(url, method: method, headers: headers(auth: auth, device: device), body: payload)
        let (data, _) = try await Net.send(request)
        guard let object = JSONValue.object(data) else {
            throw LLMError(message: "ZCode 返回了无法解析的内容")
        }
        let code = JSONValue.string(object["code"])
        if !code.isEmpty && code != "0" && code != "200" {
            throw LLMError(message: JSONValue.string(object["msg"]).isEmpty ? "ZCode 错误 code \(code)" : JSONValue.string(object["msg"]))
        }
        return object["data"]
    }

    static func startFlow(site: ZCodeSite) async throws -> ZCodeFlow {
        let pollToken = "Bearer " + Auth.randomHex(32)
        let device = Auth.uuid()
        let data = try await call("POST", host + "/api/v1/oauth/cli/init",
                                  auth: pollToken,
                                  body: ["provider": site.rawValue],
                                  device: device)
        let dict = JSONValue.dict(data)
        let flowID = JSONValue.string(dict["flow_id"])
        var authorize = JSONValue.string(dict["authorize_url"])
        guard !flowID.isEmpty, let url = URL(string: authorize), url.scheme == "https" else {
            throw LLMError(message: "ZCode 没有给出登录页，请稍后再试")
        }
        // 让 Z.ai / 智谱登录完把页面交回 zcode.z.ai，与 ZCode 客户端一致
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let back = host + "/app/oauth/login?" + "redirect=zcode%3A%2F%2Foauth%2Fcallback&app_version=" + appVersion
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: site == .bigmodel ? "redirect" : "redirect_uri", value: back))
        components?.queryItems = items
        authorize = components?.url?.absoluteString ?? authorize
        let interval = max(JSONValue.int(dict["poll_interval_sec"]), 1)
        return ZCodeFlow(flowID: flowID, authorizeURL: authorize, pollInterval: interval, pollToken: pollToken, deviceID: device, site: site)
    }

    private static func pollOnce(_ flow: ZCodeFlow) async throws -> [String: Any] {
        let url = host + "/api/v1/oauth/cli/poll/" + flow.flowID
        let data = try await call("GET", url, auth: flow.pollToken, device: flow.deviceID)
        return JSONValue.dict(data)
    }

    /// 轮询到登录完成，返回 (站点 access_token, ZCode 会话 JWT)
    static func waitForSignIn(_ flow: ZCodeFlow) async throws -> (token: String, jwt: String) {
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(max(flow.pollInterval, 1)) * 1_000_000_000)
            let data: [String: Any]
            do {
                data = try await pollOnce(flow)
            } catch let error as LLMError where error.status >= 400 && error.status < 500 && error.status != 408 && error.status != 429 {
                throw error
            } catch {
                continue
            }
            let status = JSONValue.string(data["status"])
            if status.isEmpty || status == "pending" { continue }
            if status == "failed" { throw LLMError(message: "ZCode 登录被拒绝") }
            if status != "ready" { throw LLMError(message: "ZCode 登录返回了意外状态：\(status)") }
            let siteDict = JSONValue.dict(data[flow.site.rawValue])
            var token = JSONValue.string(siteDict["access_token"])
            if token.isEmpty { token = JSONValue.string(siteDict["accessToken"]) }
            let jwt = JSONValue.string(data["token"])
            if token.isEmpty && jwt.isEmpty {
                throw LLMError(message: "ZCode 没有返回登录令牌")
            }
            return (token, jwt)
        }
        throw LLMError(message: "登录超时，请重新发起")
    }

    /// 用站点令牌换业务令牌（智谱直接用）
    static func businessAuth(site: ZCodeSite, token: String) async throws -> String {
        if site == .bigmodel { return token }
        let data = try await call("POST", "https://api.z.ai/api/auth/z/login", body: ["token": token], device: Auth.uuid())
        let access = JSONValue.string(JSONValue.dict(data)["access_token"])
        guard !access.isEmpty else { throw LLMError(message: "Z.ai 没有返回业务令牌") }
        return "Bearer " + access
    }

    /// 在默认项目里找/建 zcode-api-key，并取出 <id>.<secret>
    static func mintKey(site: ZCodeSite, auth: String) async throws -> (key: String, label: String) {
        let device = Auth.uuid()
        let infoData = try await call("GET", site.apiRoot + "/api/biz/customer/getCustomerInfo", auth: auth, device: device)
        let info = JSONValue.dict(infoData)
        var organizationID = ""
        var projectID = ""
        for item in JSONValue.array(info["organizations"]) {
            let org = JSONValue.dict(item)
            let orgID = JSONValue.string(org["organizationId"])
            guard !orgID.isEmpty else { continue }
            let projects = JSONValue.array(org["projects"]).map { JSONValue.dict($0) }
                .filter { !JSONValue.string($0["projectId"]).isEmpty && JSONValue.string($0["projectType"]) != "2" }
            guard !projects.isEmpty else { continue }
            let fallback = projects.first
            let preferred = projects.first { JSONValue.string($0["projectName"]).contains("默认项目") } ?? fallback
            let named = JSONValue.string(org["organizationName"]).contains("默认机构")
            if organizationID.isEmpty || named {
                organizationID = orgID
                projectID = JSONValue.string(preferred?["projectId"])
            }
            if named { break }
        }
        guard !organizationID.isEmpty, !projectID.isEmpty else {
            throw LLMError(message: "这个账号还没有可用于 API Key 的项目")
        }
        let keysURL = site.apiRoot + "/api/biz/v1/organization/" + organizationID + "/projects/" + projectID + "/api_keys"
        var keyID = ""
        let listData = try await call("GET", keysURL, auth: auth, device: device)
        for item in JSONValue.array(listData) {
            let key = JSONValue.dict(item)
            if JSONValue.string(key["name"]) == "zcode-api-key" {
                keyID = JSONValue.string(key["apiKey"])
            }
        }
        if keyID.isEmpty {
            let created = try await call("POST", keysURL, auth: auth, body: ["name": "zcode-api-key"], device: device)
            keyID = JSONValue.string(JSONValue.dict(created)["apiKey"])
        }
        guard !keyID.isEmpty else { throw LLMError(message: "ZCode 没有给出 API Key") }
        let secretData = try await call("GET", keysURL + "/copy/" + keyID, auth: auth, device: device)
        let secret = JSONValue.string(JSONValue.dict(secretData)["secretKey"])
        guard !secret.isEmpty else { throw LLMError(message: "ZCode 没有给出 API Key 的密钥") }
        let label = site == .zai ? "GLM Coding Plan" : "智谱 GLM Coding Plan"
        return ("\(keyID).\(secret)", label)
    }

    /// 完整登录：网站登录 → 业务令牌 → API Key
    static func finishSignIn(flow: ZCodeFlow) async throws -> ProviderSecret {
        let tokens = try await waitForSignIn(flow)
        var secret = ProviderSecret()
        secret.deviceID = flow.deviceID
        secret.zcodeJWT = tokens.jwt
        secret.zcodeBase = flow.site.anthropicBase
        secret.accountLabel = flow.site.title
        guard !tokens.token.isEmpty else {
            throw LLMError(message: "ZCode 没有返回站点令牌，请改用「粘贴 GLM Coding Plan API Key」")
        }
        let auth = try await businessAuth(site: flow.site, token: tokens.token)
        let minted = try await mintKey(site: flow.site, auth: auth)
        secret.zcodeKey = minted.key
        return secret
    }

    static func metadata(device: String, session: String) -> [String: Any] {
        let payload: [String: Any] = [
            "device_id": device,
            "account_uuid": "",
            "session_id": session
        ]
        let text = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ["user_id": text]
    }

    static func fetchModels(key: String, base: String) async throws -> [String] {
        // Anthropic 接口没有模型列表，用计划页列出的常用模型
        _ = key
        _ = base
        return defaultModels
    }
}
