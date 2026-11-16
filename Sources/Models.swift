import Foundation
import SwiftUI

// MARK: - 渠道

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case zenFree
    case copilot
    case zcode
    case custom
    case remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zenFree: return "OpenCode Zen 免费"
        case .copilot: return "GitHub Copilot"
        case .zcode: return "ZCode · 智谱 GLM"
        case .custom: return "自定义渠道"
        case .remote: return "远程服务"
        }
    }

    var seal: String {
        switch self {
        case .zenFree: return "禅"
        case .copilot: return "飞"
        case .zcode: return "智"
        case .custom: return "自"
        case .remote: return "远"
        }
    }

    var symbol: String {
        switch self {
        case .zenFree: return "leaf"
        case .copilot: return "airplane"
        case .zcode: return "sparkles"
        case .custom: return "slider.horizontal.3"
        case .remote: return "externaldrive.connected.to.line.below"
        }
    }

    var isBuiltin: Bool { self == .zenFree || self == .copilot || self == .zcode }
}

enum APIFormat: String, Codable, CaseIterable, Identifiable {
    case openai
    case anthropic
    case gemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openai: return "OpenAI 兼容"
        case .anthropic: return "Anthropic 兼容"
        case .gemini: return "Gemini 兼容"
        }
    }

    var hint: String {
        switch self {
        case .openai: return "POST {base}/chat/completions"
        case .anthropic: return "POST {base}/v1/messages"
        case .gemini: return "POST {base}/v1beta/models/{model}:streamGenerateContent"
        }
    }
}

struct Provider: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var kind: ProviderKind
    var name: String
    var format: APIFormat
    var baseURL: String
    var models: [String]
    var defaultModel: String
    /// 别名 → 真实模型名，可把 "gpt-4o" 指向任意上游模型
    var aliases: [String: String] = [:]
    /// 额外请求头，例如自建服务的 X-Api-Key
    var headers: [String: String] = [:]
    var enabled: Bool = true
    var note: String = ""

    var resolvedDefaultModel: String {
        if !defaultModel.isEmpty { return defaultModel }
        return models.first ?? ""
    }

    func upstreamModel(_ requested: String) -> String {
        let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mapped = aliases[trimmed], !mapped.isEmpty { return mapped }
        if let mapped = aliases[trimmed.lowercased()], !mapped.isEmpty { return mapped }
        return trimmed
    }
}

// MARK: - 会话

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: ChatRole
    var text: String = ""
    var reasoning: String = ""
    var modelLabel: String = ""
    var roleLabel: String = ""
    var roleSeal: String = ""
    var createdAt = Date()
    var isError: Bool = false
    var isStreaming: Bool = false
    var handoffFrom: String = ""
}

struct ChatThread: Identifiable, Codable, Equatable {
    var id = UUID()
    var botID: UUID
    var title: String = "新对话"
    var messages: [ChatMessage] = []
    var createdAt = Date()
    var updatedAt = Date()

    var preview: String {
        if let last = messages.last(where: { !$0.text.isEmpty }) {
            let clean = last.text.replacingOccurrences(of: "\n", with: " ")
            return clean.count > 60 ? String(clean.prefix(60)) + "…" : clean
        }
        return "还没有对话"
    }
}

// MARK: - Bot 联系人

struct Bot: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var seal: String
    var providerID: String
    var model: String
    var systemPrompt: String
    var temperature: Double = 0.7
    var memory: String = ""
    var createdAt = Date()

    var initial: String {
        if !seal.isEmpty { return String(seal.prefix(1)) }
        return String(name.prefix(1))
    }
}

// MARK: - 团队角色

struct TeamRole: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var seal: String
    var prompt: String
    var providerID: String
    var model: String
}

// MARK: - 设置

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "宣纸白"
        case .dark: return "深墨"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppSettings: Codable, Equatable {
    var useInkStyle: Bool = true
    var appearance: AppearanceMode = .system
    var fontScale: Double = 1.0
    var foldReasoning: Bool = true
    var temperature: Double = 0.7
    var maxTokens: Int = 2048
    var gatewayPort: Int = 8787
    var gatewayTokenEnabled: Bool = false
    var gatewayToken: String = ""
    var gatewayAutoStart: Bool = false
    var historyLimit: Int = 30
}

struct PromptPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var text: String
}

struct ModelRedirect: Identifiable, Codable, Equatable {
    var id = UUID()
    /// 请求里出现的模型名，例如 "gpt-4o"
    var from: String
    /// 目标："providerID::model" 可跨渠道，或单纯的上游模型名
    var to: String
}

// MARK: - 请求结构

struct ChatTurn {
    var role: String
    var content: String
}

struct ChatInvocation {
    var provider: Provider
    var model: String
    var system: String
    var turns: [ChatTurn]
    var temperature: Double
    var maxTokens: Int
}

enum StreamEvent {
    case text(String)
    case reasoning(String)
    case model(String)
}

// MARK: - 错误

struct LLMError: LocalizedError {
    var message: String
    var status: Int = 0

    var errorDescription: String? { message }
}

/// OpenAI 的 /v1/models 里的一项
struct RemoteModel: Identifiable, Codable, Equatable {
    var id: String
    var ownedBy: String = ""

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
    }
}

/// 把任意错误变成一句给用户看的话
func describeError(_ error: Error) -> String {
    if let llm = error as? LLMError { return llm.message }
    let text = error.localizedDescription
    return text.isEmpty ? "未知错误" : text
}

// MARK: - JSON 小工具

enum JSONValue {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func any(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    static func string(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    static func int(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let n = Int(s) { return n }
        return 0
    }

    static func double(_ value: Any?) -> Double {
        if let n = value as? Double { return n }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let n = Double(s) { return n }
        return 0
    }

    static func dict(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    static func pretty(_ any: Any) -> String {
        guard JSONSerialization.isValidJSONObject(any),
              let data = try? JSONSerialization.data(withJSONObject: any, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfEmpty: String? { isEmpty ? nil : self }

    func truncated(_ limit: Int) -> String {
        count > limit ? String(prefix(limit)) + "…" : self
    }
}
