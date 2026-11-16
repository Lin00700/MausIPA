import Foundation
import Security

/// 所有 API Key 与令牌只进钥匙串，不落 UserDefaults、不写文件。
enum Keychain {
    private static let service = "com.lin.mausipa"

    static func save(_ data: Data, account: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 一个渠道的全部凭据。
struct ProviderSecret: Codable, Equatable {
    var apiKey: String = ""
    /// GitHub OAuth token（Copilot 用来换推理令牌）
    var oauthToken: String = ""
    /// Copilot 推理令牌
    var inferenceToken: String = ""
    /// 推理令牌过期时间（毫秒时间戳）
    var expiresAt: Double = 0
    /// ZCode 签发的 API Key（<id>.<secret>）
    var zcodeKey: String = ""
    /// ZCode 会话令牌（JWT），用于读取套餐与额度
    var zcodeJWT: String = ""
    /// ZCode 站点根，例如 https://api.z.ai/api/anthropic
    var zcodeBase: String = ""
    /// ZCode 设备 id
    var deviceID: String = ""
    var accountLabel: String = ""
    var extra: [String: String] = [:]

    static let empty = ProviderSecret()

    var isEmpty: Bool {
        apiKey.isEmpty && oauthToken.isEmpty && inferenceToken.isEmpty && zcodeKey.isEmpty
    }

    /// 给界面看的一句话状态
    func summary(for kind: ProviderKind) -> String {
        switch kind {
        case .zenFree:
            return "公共身份 public · 无需登录"
        case .copilot:
            if !inferenceToken.isEmpty && expiresAt > Date().timeIntervalSince1970 * 1000 {
                return accountLabel.isEmpty ? "已连接 Copilot" : "已连接 \(accountLabel)"
            }
            return oauthToken.isEmpty ? "未登录" : "令牌待刷新"
        case .zcode:
            if !zcodeKey.isEmpty {
                let site = zcodeBase.contains("bigmodel") ? "BigModel" : "Z.ai"
                return "已连接 \(site) GLM Coding Plan"
            }
            return zcodeJWT.isEmpty ? "未登录" : "会话已保存，但无可用的 API Key"
        case .custom, .remote:
            return apiKey.isEmpty ? "未填写 API Key" : "已填写 API Key"
        }
    }
}
