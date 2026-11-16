import Foundation
import SwiftUI
import Combine

struct AppData: Codable {
    var providers: [Provider] = []
    var bots: [Bot] = []
    var threads: [ChatThread] = []
    var roles: [TeamRole] = []
    var redirects: [ModelRedirect] = []
    var presets: [PromptPreset] = []
    var settings: AppSettings = AppSettings()
}

@MainActor
final class AppStore: ObservableObject {
    @Published var providers: [Provider] = []
    @Published var bots: [Bot] = []
    @Published var threads: [ChatThread] = []
    @Published var roles: [TeamRole] = []
    @Published var redirects: [ModelRedirect] = []
    @Published var presets: [PromptPreset] = []
    @Published var settings = AppSettings()
    @Published private(set) var secrets: [String: ProviderSecret] = [:]
    @Published var isGenerating = false
    @Published var generatingThread: UUID?
    @Published var gatewayRunning = false
    @Published var gatewayMessage = ""
    @Published var toast = ""

    private var streamTask: Task<Void, Never>?
    private var sessionIDs: [UUID: String] = [:]
    let gateway = GatewayServer()

    // MARK: 初始化

    init() {
        load()
        gateway.onRequest = { [weak self] request, connection in
            Task { @MainActor in
                await self?.handleGateway(request, connection)
            }
        }
    }

    private var dataURL: URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("mausipa.json")
    }

    private func load() {
        if let data = try? Data(contentsOf: dataURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: data) {
            providers = decoded.providers.filter { !$0.id.isEmpty }
            bots = decoded.bots
            threads = decoded.threads
            roles = decoded.roles
            redirects = decoded.redirects
            presets = decoded.presets
            settings = decoded.settings
        }
        if providers.isEmpty {
            seed()
        }
        for provider in providers {
            if let data = Keychain.load("provider." + provider.id),
               let secret = try? JSONDecoder().decode(ProviderSecret.self, from: data) {
                secrets[provider.id] = secret
            }
        }
        // 老版本字段补齐
        for index in providers.indices where providers[index].models.isEmpty {
            providers[index].models = defaultModels(for: providers[index].kind)
        }
        for index in providers.indices where providers[index].defaultModel.isEmpty {
            providers[index].defaultModel = providers[index].models.first ?? ""
        }
        if bots.isEmpty { seedBots() }
        if roles.isEmpty { seedRoles() }
        if presets.isEmpty { seedPresets() }
        for index in bots.indices {
            if threads(for: bots[index].id).isEmpty {
                _ = newThread(for: bots[index].id, persist: false)
            }
        }
        save()
    }

    private func seed() {
        providers = [
            Provider(id: "zen", kind: .zenFree, name: "OpenCode Zen 免费", format: .openai,
                     baseURL: Zen.base, models: Zen.defaultModels,
                     defaultModel: "deepseek-v4.1-flash-free",
                     note: "公共身份 public，免费模型即开即用。请求按 OpenCode 2.2.5 的头部与环境块发出。"),
            Provider(id: "copilot", kind: .copilot, name: "GitHub Copilot", format: .openai,
                     baseURL: Copilot.apiBase, models: Copilot.defaultModels,
                     defaultModel: "gpt-5.2",
                     note: "设备码登录 GitHub，再用 OAuth 令牌换 Copilot 推理令牌。"),
            Provider(id: "zcode", kind: .zcode, name: "ZCode · 智谱 GLM", format: .anthropic,
                     baseURL: ZCodeSite.zai.anthropicBase, models: ZCode.defaultModels,
                     defaultModel: "GLM-5.3",
                     note: "登录 Z.ai / 智谱账号自动领取 GLM Coding Plan 的 zcode-api-key，走 Anthropic Messages 接口。")
        ]
        seedBots()
        seedRoles()
        seedPresets()
    }

    private func seedBots() {
        bots = [
            Bot(name: "墨灵", seal: "墨", providerID: "zen", model: "deepseek-v4.1-flash-free",
                systemPrompt: "你是「墨灵」，一位沉静、克制的中文助手。回答准确、简洁，必要时给出可执行的步骤。用中文回答，除非用户使用其他语言。",
                temperature: 0.7, memory: ""),
            Bot(name: "阿飞", seal: "飞", providerID: "copilot", model: "gpt-5.2",
                systemPrompt: "你是「阿飞」，擅长写代码与排查工程问题。先给结论，再给关键代码，避免空话。",
                temperature: 0.4, memory: ""),
            Bot(name: "子瞻", seal: "瞻", providerID: "zcode", model: "GLM-5.3",
                systemPrompt: "你是「子瞻」，中文表达讲究，善于把复杂的事情讲清楚，也乐于润色文字。",
                temperature: 0.8, memory: "")
        ]
        for bot in bots {
            _ = newThread(for: bot.id, persist: false)
        }
    }

    private func seedRoles() {
        roles = [
            TeamRole(name: "总控", seal: "总",
                     prompt: "你是团队的总控（Orchestrator）。把任务拆成清晰的步骤，指出依赖与风险，给出可直接执行的计划；不要代替其他角色写完整实现。",
                     providerID: "zen", model: "deepseek-v4.1-flash-free"),
            TeamRole(name: "码匠", seal: "码",
                     prompt: "你是团队的码匠（Coder）。按需求给出可运行的实现，包含关键代码与验证方法，注意边界条件与错误处理。",
                     providerID: "copilot", model: "gpt-5.2"),
            TeamRole(name: "审阅", seal: "审",
                     prompt: "你是团队的审阅者（Reviewer）。用挑剔的眼光检查上一位同事的输出：指出错误、遗漏、风险与可简化之处，并给出具体改法。若确实没有问题，明确说明通过。",
                     providerID: "zcode", model: "GLM-5.3"),
            TeamRole(name: "探索", seal: "探",
                     prompt: "你是团队的探索者（Researcher）。补充背景、对比方案、列出证据与不确定之处，帮助团队在动手前看清全貌。",
                     providerID: "zen", model: "big-pickle")
        ]
    }

    private func seedPresets() {
        presets = [
            PromptPreset(name: "通用助手", text: "你是一位可靠的中文助手。回答准确、结构清晰，不确定的地方直说不确定。"),
            PromptPreset(name: "代码工程", text: "你是资深软件工程师。先给结论与最小可行方案，再给关键代码；说明如何验证，指出可能的坑。"),
            PromptPreset(name: "中英互译", text: "你是专业译者。保持原意与语气，术语统一；只给译文，必要时在末尾用一行说明取舍。"),
            PromptPreset(name: "润色改写", text: "你是中文编辑。保留作者原意，改掉啰嗦与病句，让句子干净有力；只给改后的版本。")
        ]
    }

    // MARK: 保存

    func save() {
        let data = AppData(providers: providers, bots: bots, threads: threads, roles: roles,
                           redirects: redirects, presets: presets, settings: settings)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: dataURL, options: .atomic)
        }
    }

    // MARK: 查询

    func provider(_ id: String) -> Provider? {
        providers.first { $0.id == id }
    }

    func bot(_ id: UUID) -> Bot? {
        bots.first { $0.id == id }
    }

    func thread(_ id: UUID) -> ChatThread? {
        threads.first { $0.id == id }
    }

    func threads(for botID: UUID) -> [ChatThread] {
        threads.filter { $0.botID == botID }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func activeThread(for botID: UUID) -> ChatThread? {
        threads(for: botID).first
    }

    func secret(for providerID: String) -> ProviderSecret {
        secrets[providerID] ?? ProviderSecret()
    }

    func updateSecret(_ secret: ProviderSecret, for providerID: String) {
        secrets[providerID] = secret
        if secret.isEmpty {
            Keychain.delete("provider." + providerID)
        } else if let data = try? JSONEncoder().encode(secret) {
            Keychain.save(data, account: "provider." + providerID)
        }
        objectWillChange.send()
    }

    func defaultModels(for kind: ProviderKind) -> [String] {
        switch kind {
        case .zenFree: return Zen.defaultModels
        case .copilot: return Copilot.defaultModels
        case .zcode: return ZCode.defaultModels
        case .custom, .remote: return []
        }
    }

    func models(for provider: Provider) -> [String] {
        provider.models.isEmpty ? defaultModels(for: provider.kind) : provider.models
    }

    // MARK: 会话管理

    @discardableResult
    func newThread(for botID: UUID, persist: Bool = true) -> UUID {
        var thread = ChatThread(botID: botID)
        let bot = bots.first { $0.id == botID }
        thread.title = "与 \(bot?.name ?? "助手") 的新对话"
        thread.messages = [
            ChatMessage(role: .assistant,
                        text: greeting(for: bot),
                        modelLabel: bot.map { "\(provider($0.providerID)?.name ?? "未配置") · \($0.model)" } ?? "")
        ]
        threads.insert(thread, at: 0)
        if persist { save() }
        return thread.id
    }

    private func greeting(for bot: Bot?) -> String {
        switch bot?.providerID {
        case "zen": return "墨已研好。想聊点什么？"
        case "copilot": return "在。有代码或工程上的问题，直接说。"
        case "zcode": return "今日有闲，聊聊？"
        default: return "你好，我是\(bot?.name ?? "助手")。"
        }
    }

    func deleteThread(_ id: UUID) {
        threads.removeAll { $0.id == id }
        save()
    }

    func clearThread(_ id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        let bot = bots.first { $0.id == threads[index].botID }
        threads[index].messages = [ChatMessage(role: .assistant, text: greeting(for: bot))]
        threads[index].updatedAt = Date()
        save()
    }

    func deleteBot(_ id: UUID) {
        bots.removeAll { $0.id == id }
        threads.removeAll { $0.botID == id }
        save()
    }

    func updateBot(_ bot: Bot) {
        if let index = bots.firstIndex(where: { $0.id == bot.id }) {
            bots[index] = bot
            save()
        }
    }

    func addBot() -> Bot {
        let provider = providers.first ?? Provider(id: "zen", kind: .zenFree, name: "OpenCode Zen 免费",
                                                   format: .openai, baseURL: Zen.base,
                                                   models: Zen.defaultModels,
                                                   defaultModel: "deepseek-v4.1-flash-free")
        var bot = Bot(name: "新联系人", seal: "新", providerID: provider.id,
                      model: provider.resolvedDefaultModel, systemPrompt: "", temperature: 0.7)
        bot.seal = String(bot.name.prefix(1))
        bots.append(bot)
        _ = newThread(for: bot.id, persist: false)
        save()
        return bot
    }

    // MARK: 发送消息

    func send(threadID: UUID, text: String) {
        guard !isGenerating else { return }
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].messages.append(ChatMessage(role: .user, text: trimmed))
        threads[index].updatedAt = Date()
        if threads[index].messages.filter({ $0.role == .user }).count == 1 {
            threads[index].title = trimmed.replacingOccurrences(of: "\n", with: " ").truncated(20)
        }
        let botID = threads[index].botID
        guard let contact = self.bot(botID) else { return }
        save()

        let thread = threads[index]
        let base = systemPrompt(for: contact)
        let turns = historyTurns(thread) + [ChatTurn(role: "user", content: trimmed)]
        guard let resolved = resolve(providerID: contact.providerID, model: contact.model) else {
            appendNotice(threadID: threadID, "渠道「\(contact.providerID)」不存在，请在「渠道」里重新选择。")
            return
        }
        streamTask = Task {
            _ = await performTurn(threadID: threadID, provider: resolved.provider, model: resolved.model,
                                  system: base, turns: turns, role: nil, handoffFrom: "", managesBusy: true)
        }
    }

    /// 把某条回答接力给团队里的另一个角色
    func handoff(threadID: UUID, role: TeamRole) {
        guard !isGenerating else { return }
        guard let thread = thread(threadID) else { return }
        guard let last = thread.messages.last(where: { $0.role == .assistant && !$0.isError && !$0.text.trimmed.isEmpty }) else {
            toast = "还没有可以接力的回答"
            return
        }
        guard let resolved = resolve(providerID: role.providerID, model: role.model) else {
            toast = "「\(role.name)」绑定的渠道不存在"
            return
        }
        let source = last.roleLabel.isEmpty ? (bot(thread.botID)?.name ?? "助手") : last.roleLabel
        let prompt = """
        【接力】上一位同事「\(source)」的产出如下。请你以「\(role.name)」的身份接手，按你的职责继续处理。

        \(last.text)
        """
        var turns = historyTurns(thread)
        turns.append(ChatTurn(role: "user", content: prompt))
        let system = role.prompt
        streamTask = Task {
            _ = await performTurn(threadID: threadID, provider: resolved.provider, model: resolved.model,
                                  system: system, turns: turns, role: role,
                                  handoffFrom: source, managesBusy: true)
        }
    }

    /// 团队连跑：按顺序把任务交给多个角色
    func teamRun(threadID: UUID, roleIDs: [UUID], prompt: String) {
        guard !isGenerating else { return }
        let chosen = roleIDs.compactMap { id in roles.first { $0.id == id } }
        guard !chosen.isEmpty else { return }
        let trimmed = prompt.trimmed
        guard !trimmed.isEmpty else { return }
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].messages.append(ChatMessage(role: .user, text: trimmed))
        threads[index].updatedAt = Date()
        if threads[index].messages.filter({ $0.role == .user }).count == 1 {
            threads[index].title = trimmed.replacingOccurrences(of: "\n", with: " ").truncated(20)
        }
        let thread = threads[index]
        save()

        streamTask = Task {
            var carry = trimmed
            var from = ""
            for (offset, role) in chosen.enumerated() {
                guard let resolved = resolve(providerID: role.providerID, model: role.model) else { continue }
                var turns = historyTurns(thread)
                let body: String
                if offset == 0 {
                    body = "【团队任务】\n\(carry)"
                } else {
                    body = "【团队接力】上一位同事「\(from)」的产出如下，请你以「\(role.name)」的身份继续：\n\n\(carry)"
                }
                turns.append(ChatTurn(role: "user", content: body))
                let result = await performTurn(threadID: threadID, provider: resolved.provider,
                                               model: resolved.model, system: role.prompt,
                                               turns: turns, role: role, handoffFrom: offset == 0 ? "" : from,
                                               managesBusy: offset == 0)
                carry = result.isEmpty ? carry : result
                from = role.name
            }
            isGenerating = false
            generatingThread = nil
            save()
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isGenerating = false
        generatingThread = nil
        for index in threads.indices {
            for messageIndex in threads[index].messages.indices where threads[index].messages[messageIndex].isStreaming {
                threads[index].messages[messageIndex].isStreaming = false
            }
        }
    }

    // MARK: 提示词

    func systemPrompt(for bot: Bot) -> String {
        var parts: [String] = []
        if !bot.systemPrompt.trimmed.isEmpty { parts.append(bot.systemPrompt) }
        if !bot.memory.trimmed.isEmpty { parts.append("【长期记忆】\n" + bot.memory) }
        return parts.joined(separator: "\n\n")
    }

    func historyTurns(_ thread: ChatThread) -> [ChatTurn] {
        let usable = thread.messages.filter { !$0.isError && !$0.text.trimmed.isEmpty && !$0.isStreaming }
        let limited = usable.suffix(max(settings.historyLimit, 2))
        return limited.map { message in
            ChatTurn(role: message.role == .assistant ? "assistant" : "user", content: message.text)
        }
    }

    /// 模型重定向：先看全局映射，再看渠道别名
    func resolve(providerID: String, model: String) -> (provider: Provider, model: String)? {
        var provider = self.provider(providerID)
        var target = model
        if let redirect = redirects.first(where: { $0.from.caseInsensitiveCompare(model) == .orderedSame }) {
            let to = redirect.to.trimmed
            if to.contains("::") {
                let parts = to.components(separatedBy: "::")
                if parts.count == 2, let other = self.provider(parts[0].trimmed) {
                    provider = other
                    target = parts[1].trimmed
                }
            } else if !to.isEmpty {
                target = to
            }
        }
        guard let provider else { return nil }
        if target.isEmpty { target = provider.resolvedDefaultModel }
        return (provider, target)
    }

    // MARK: 一次生成

    @discardableResult
    func performTurn(threadID: UUID, provider: Provider, model: String, system: String,
                     turns: [ChatTurn], role: TeamRole?, handoffFrom: String,
                     managesBusy: Bool) async -> String {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return "" }
        var placeholder = ChatMessage(role: .assistant)
        placeholder.isStreaming = true
        placeholder.modelLabel = provider.name + " · " + model
        if let role {
            placeholder.roleLabel = role.name
            placeholder.roleSeal = role.seal
        }
        placeholder.handoffFrom = handoffFrom
        threads[index].messages.append(placeholder)
        let messageID = placeholder.id
        if managesBusy {
            isGenerating = true
            generatingThread = threadID
        }

        let secret = await preparedSecret(for: provider)
        let session = sessionID(for: threadID, provider: provider)
        let invocation = ChatInvocation(provider: provider, model: model, system: system,
                                        turns: turns, temperature: settings.temperature,
                                        maxTokens: settings.maxTokens)
        var collected = ""
        do {
            for try await event in LLMClient.stream(invocation, secret: secret, sessionID: session) {
                if Task.isCancelled { break }
                switch event {
                case .text(let text):
                    collected += text
                    updateMessage(threadID, messageID) { $0.text += text }
                case .reasoning(let text):
                    updateMessage(threadID, messageID) { $0.reasoning += text }
                case .model:
                    break
                }
            }
        } catch is CancellationError {
            // 用户手动停止，保留已经生成的部分
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            appendNotice(threadID: threadID, "⚠️ \(message)")
            updateMessage(threadID, messageID) { $0.isError = true }
        }
        updateMessage(threadID, messageID) { $0.isStreaming = false }
        if let threadIndex = threads.firstIndex(where: { $0.id == threadID }) {
            threads[threadIndex].updatedAt = Date()
        }
        if managesBusy {
            isGenerating = false
            generatingThread = nil
            save()
        }
        return collected
    }

    private func sessionID(for threadID: UUID, provider: Provider) -> String {
        if let existing = sessionIDs[threadID] { return existing }
        let value = provider.kind == .zenFree ? Zen.newSession() : Auth.uuid()
        sessionIDs[threadID] = value
        return value
    }

    private func preparedSecret(for provider: Provider) async -> ProviderSecret {
        var secret = self.secret(for: provider.id)
        guard provider.kind == .copilot else { return secret }
        let now = Date().timeIntervalSince1970 * 1000
        if !secret.oauthToken.isEmpty && (secret.inferenceToken.isEmpty || secret.expiresAt < now + 60_000) {
            do {
                let renewed = try await Copilot.exchange(oauth: secret.oauthToken)
                secret.inferenceToken = renewed.token
                secret.expiresAt = renewed.expiresAt
                updateSecret(secret, for: provider.id)
            } catch {
                // 令牌换不到时把错误留给请求本身去说
            }
        }
        return secret
    }

    func appendNotice(threadID: UUID, _ text: String) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        var message = ChatMessage(role: .assistant, text: text)
        message.isError = true
        threads[index].messages.append(message)
        threads[index].updatedAt = Date()
    }

    private func updateMessage(_ threadID: UUID, _ messageID: UUID, _ mutate: (inout ChatMessage) -> Void) {
        guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }) else { return }
        guard let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        mutate(&threads[threadIndex].messages[messageIndex])
    }

    // MARK: 模型列表

    func refreshModels(providerID: String) async {
        guard let provider = self.provider(providerID) else { return }
        do {
            let models = try await fetchModels(for: provider)
            guard !models.isEmpty else {
                toast = "没有取到模型"
                return
            }
            if let index = providers.firstIndex(where: { $0.id == providerID }) {
                providers[index].models = models
                if !models.contains(providers[index].defaultModel) {
                    providers[index].defaultModel = models.first ?? ""
                }
                save()
            }
            toast = "已更新 \(models.count) 个模型"
        } catch {
            toast = "取模型失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func fetchModels(for provider: Provider) async throws -> [String] {
        switch provider.kind {
        case .zenFree:
            return try await Zen.fetchModels()
        case .copilot:
            let secret = await preparedSecret(for: provider)
            guard !secret.inferenceToken.isEmpty else { throw LLMError(message: "先登录 Copilot") }
            return try await Copilot.fetchModels(token: secret.inferenceToken)
        case .zcode:
            let secret = self.secret(for: provider.id)
            return try await ZCode.fetchModels(key: secret.zcodeKey, base: provider.baseURL)
        case .custom, .remote:
            let base = provider.baseURL.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !base.isEmpty else { throw LLMError(message: "先填 Base URL") }
            let url: String
            if base.hasSuffix("/v1") { url = base + "/models" } else { url = base + "/v1/models" }
            var headers: [String: String] = ["Accept": "application/json"]
            let secret = self.secret(for: provider.id)
            if !secret.apiKey.isEmpty { headers["Authorization"] = "Bearer \(secret.apiKey)" }
            for (key, value) in provider.headers { headers[key] = value }
            let request = try Net.makeRequest(url, method: "GET", headers: headers)
            let (data, _) = try await Net.send(request)
            var models = Net.models(from: data)
            if models.isEmpty && provider.format == .anthropic {
                models = provider.models
            }
            return models
        }
    }

    func test(providerID: String) async {
        guard let provider = self.provider(providerID) else { return }
        toast = "正在测试…"
        let secret = secret(for: providerID)
        let model = provider.resolvedDefaultModel
        let invocation = ChatInvocation(provider: provider, model: model, system: "只回复两个字：可用",
                                        turns: [ChatTurn(role: "user", content: "连通性测试")],
                                        temperature: 0, maxTokens: 32)
        var text = ""
        do {
            for try await event in LLMClient.stream(invocation, secret: secret, sessionID: Auth.uuid()) {
                if case .text(let piece) = event { text += piece }
            }
            toast = "可用 · 返回：\(text.trimmed.truncated(40))"
        } catch {
            toast = "不可用：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: 渠道维护

    func addProvider(kind: ProviderKind) -> Provider {
        let id = Auth.uuid()
        let provider: Provider
        switch kind {
        case .remote:
            provider = Provider(id: id, kind: .remote, name: "远程服务", format: .openai,
                                baseURL: "", models: [], defaultModel: "",
                                note: "填写电脑或 VPS 上 OpenMausBot / Timon 之类的服务地址，例如 https://myhost:8787/v1，并填入配对令牌。")
        case .custom:
            provider = Provider(id: id, kind: .custom, name: "自定义渠道", format: .openai,
                                baseURL: "", models: [], defaultModel: "",
                                note: "支持 OpenAI / Anthropic / Gemini 三种兼容格式。")
        default:
            provider = Provider(id: id, kind: kind, name: kind.title, format: .openai,
                                baseURL: Zen.base, models: defaultModels(for: kind),
                                defaultModel: defaultModels(for: kind).first ?? "")
        }
        providers.append(provider)
        save()
        return provider
    }

    func updateProvider(_ provider: Provider) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
            save()
        }
    }

    func deleteProvider(_ id: String) {
        providers.removeAll { $0.id == id }
        Keychain.delete("provider." + id)
        secrets[id] = nil
        save()
    }

    // MARK: 网关

    func startGateway() {
        do {
            try gateway.start(port: UInt16(settings.gatewayPort))
            gatewayRunning = true
            gatewayMessage = "已启动 · \(endpointBase)"
        } catch {
            gatewayRunning = false
            gatewayMessage = "启动失败：" + error.localizedDescription
        }
    }

    func stopGateway() {
        gateway.stop()
        gatewayRunning = false
        gatewayMessage = "已停止"
    }

    var endpointBase: String {
        let ip = LAN.addresses().first ?? "127.0.0.1"
        return "http://\(ip):\(settings.gatewayPort)"
    }

    private func handleGateway(_ request: GatewayRequest, _ connection: GatewayConnection) async {
        if settings.gatewayTokenEnabled, !settings.gatewayToken.isEmpty {
            let token = request.header("authorization").replacingOccurrences(of: "Bearer ", with: "")
            if token != settings.gatewayToken {
                connection.sendJSON(["error": ["message": "invalid gateway token", "type": "unauthorized"]], status: 401)
                return
            }
        }
        switch (request.method, request.path) {
        case ("GET", "/health"):
            connection.sendJSON(["ok": true, "app": "MausIPA"])
        case ("GET", "/v1/models"):
            var data: [[String: Any]] = []
            for provider in providers where provider.enabled {
                for model in models(for: provider) {
                    data.append(["id": "\(provider.id)/\(model)", "object": "model", "owned_by": provider.name])
                }
                for model in models(for: provider) {
                    data.append(["id": model, "object": "model", "owned_by": provider.name])
                }
            }
            connection.sendJSON(["object": "list", "data": data])
        case ("POST", "/v1/chat/completions"):
            await handleGatewayChat(request, connection)
        default:
            connection.sendJSON(["error": ["message": "not found", "type": "invalid_request_error"]], status: 404)
        }
    }

    private func handleGatewayChat(_ request: GatewayRequest, _ connection: GatewayConnection) async {
        let body = request.json
        let requestedModel = JSONValue.string(body["model"])
        let stream = (body["stream"] as? Bool) ?? false
        let rawMessages = JSONValue.array(body["messages"])
        guard !rawMessages.isEmpty else {
            connection.sendJSON(["error": ["message": "messages is required", "type": "invalid_request_error"]], status: 400)
            return
        }
        var systemParts: [String] = []
        var turns: [ChatTurn] = []
        for item in rawMessages {
            let dict = JSONValue.dict(item)
            let role = JSONValue.string(dict["role"])
            var text = ""
            if let content = dict["content"] as? String {
                text = content
            } else if let parts = dict["content"] as? [Any] {
                text = parts.map { JSONValue.string(JSONValue.dict($0)["text"]) }.joined()
            }
            guard !text.isEmpty else { continue }
            if role == "system" || role == "developer" {
                systemParts.append(text)
            } else {
                turns.append(ChatTurn(role: role == "assistant" ? "assistant" : "user", content: text))
            }
        }
        let resolved = gatewayResolve(requestedModel)
        guard let resolved else {
            connection.sendJSON(["error": ["message": "no provider configured for model \(requestedModel)", "type": "invalid_request_error"]], status: 400)
            return
        }
        let provider = resolved.provider
        let secret = await preparedSecret(for: provider)
        let temperature = JSONValue.double(body["temperature"])
        let maxTokens = JSONValue.int(body["max_tokens"])
        let invocation = ChatInvocation(provider: provider, model: resolved.model,
                                        system: systemParts.joined(separator: "\n\n"),
                                        turns: turns,
                                        temperature: temperature > 0 ? temperature : settings.temperature,
                                        maxTokens: maxTokens > 0 ? maxTokens : settings.maxTokens)
        let completionID = "chatcmpl-" + Auth.randomHex(8)
        let created = Int(Date().timeIntervalSince1970)
        let responseModel = requestedModel.isEmpty ? resolved.model : requestedModel

        if stream {
            connection.sendHead(200, contentType: "text/event-stream; charset=utf-8", chunked: true)
            var wrote = false
            do {
                for try await event in LLMClient.stream(invocation, secret: secret, sessionID: Auth.uuid()) {
                    var delta: [String: Any] = [:]
                    switch event {
                    case .text(let text):
                        delta["content"] = text
                    case .reasoning(let text):
                        delta["reasoning_content"] = text
                    case .model:
                        continue
                    }
                    let chunk: [String: Any] = [
                        "id": completionID, "object": "chat.completion.chunk", "created": created,
                        "model": responseModel,
                        "choices": [["index": 0, "delta": delta, "finish_reason": NSNull()]]
                    ]
                    connection.sendEvent("data: " + jsonText(chunk) + "\n\n")
                    wrote = true
                }
                let final: [String: Any] = [
                    "id": completionID, "object": "chat.completion.chunk", "created": created,
                    "model": responseModel,
                    "choices": [["index": 0, "delta": [:], "finish_reason": "stop"]]
                ]
                connection.sendEvent("data: " + jsonText(final) + "\n\n")
                connection.sendEvent("data: [DONE]\n\n")
                _ = wrote
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let chunk: [String: Any] = ["error": ["message": message, "type": "upstream_error"]]
                connection.sendEvent("data: " + jsonText(chunk) + "\n\n")
            }
            connection.finish(chunked: true)
        } else {
            var text = ""
            var reasoning = ""
            do {
                for try await event in LLMClient.stream(invocation, secret: secret, sessionID: Auth.uuid()) {
                    switch event {
                    case .text(let piece): text += piece
                    case .reasoning(let piece): reasoning += piece
                    case .model: break
                    }
                }
                let message: [String: Any] = ["role": "assistant", "content": text,
                                              "reasoning_content": reasoning]
                let payload: [String: Any] = [
                    "id": completionID, "object": "chat.completion", "created": created,
                    "model": responseModel,
                    "choices": [["index": 0, "message": message, "finish_reason": "stop"]],
                    "usage": ["prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0]
                ]
                connection.sendJSON(payload)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                connection.sendJSON(["error": ["message": message, "type": "upstream_error"]], status: 502)
            }
        }
    }

    private func gatewayResolve(_ requested: String) -> (provider: Provider, model: String)? {
        if requested.isEmpty {
            guard let provider = providers.first(where: { $0.enabled }) else { return nil }
            return (provider, provider.resolvedDefaultModel)
        }
        if requested.contains("/") {
            let parts = requested.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2, let provider = self.provider(parts[0]) {
                return (provider, parts[1])
            }
        }
        for provider in providers where provider.enabled {
            if models(for: provider).contains(requested) {
                return (provider, requested)
            }
        }
        return resolve(providerID: providers.first(where: { $0.enabled })?.id ?? "", model: requested)
    }

    private func jsonText(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
