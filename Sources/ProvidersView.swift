import SwiftUI

struct ProvidersView: View {
    @EnvironmentObject var store: AppStore
    @State private var editingID: String?
    @State private var showCopilot = false
    @State private var showZCode = false

    private var builtins: [Provider] {
        store.providers.filter { $0.kind.isBuiltin }
    }

    private var customs: [Provider] {
        store.providers.filter { $0.kind == .custom }
    }

    private var remotes: [Provider] {
        store.providers.filter { $0.kind == .remote }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("内置渠道", providers: builtins, empty: "")
                    SectionLabel(title: "自定义渠道", subtitle: "OpenAI / Anthropic / Gemini 兼容，任意 Base URL 与模型别名")
                        .padding(.top, 2)
                    ForEach(customs) { provider in
                        providerCard(provider)
                    }
                    addButton(title: "添加自定义渠道") {
                        let provider = store.addProvider(kind: .custom)
                        editingID = provider.id
                    }

                    SectionLabel(title: "远程服务", subtitle: "把电脑或 VPS 上自建的助手（OpenMausBot / Timon 等）接进来")
                        .padding(.top, 2)
                    ForEach(remotes) { provider in
                        providerCard(provider)
                    }
                    addButton(title: "添加远程服务") {
                        let provider = store.addProvider(kind: .remote)
                        editingID = provider.id
                    }

                    Text("所有 Key 与令牌只存钥匙串；请求直接从这台 iPhone 发出。")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.inkFaint)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Ink.paper.opacity(0.001))
            .navigationTitle("渠道")
            .sheet(item: $editingID.asProvider()) { wrapper in
                ProviderDetailView(providerID: wrapper.id)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showCopilot) {
                CopilotSignInView(providerID: "copilot")
                    .environmentObject(store)
            }
            .sheet(isPresented: $showZCode) {
                ZCodeSignInView(providerID: "zcode")
                    .environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, providers: [Provider], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: title)
            if providers.isEmpty && !empty.isEmpty {
                Text(empty)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.inkFaint)
            }
            ForEach(providers) { provider in
                providerCard(provider)
            }
        }
    }

    private func providerCard(_ provider: Provider) -> some View {
        Button {
            editingID = provider.id
        } label: {
            HStack(spacing: 12) {
                SealAvatar(text: provider.kind.seal, color: tint(provider), size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Ink.inkText)
                        if !provider.enabled {
                            TagChip(text: "已停用", tint: Ink.inkFaint)
                        }
                    }
                    Text(store.secret(for: provider.id).summary(for: provider.kind))
                        .font(.system(size: 11.5))
                        .foregroundStyle(provider.kind == .copilot && store.secret(for: provider.id).inferenceToken.isEmpty ? Ink.cinnabarSoft : Ink.inkSoft)
                    Text(summaryLine(provider))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Ink.inkFaint)
                        .lineLimit(1)
                }
                Spacer()
                if provider.kind == .copilot {
                    Button {
                        showCopilot = true
                    } label: {
                        Text("登录")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Ink.cinnabar.opacity(0.12)))
                            .foregroundStyle(Ink.cinnabar)
                    }
                    .buttonStyle(.plain)
                }
                if provider.kind == .zcode {
                    Button {
                        showZCode = true
                    } label: {
                        Text(store.secret(for: provider.id).zcodeKey.isEmpty ? "登录" : "重登")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Ink.cinnabar.opacity(0.12)))
                            .foregroundStyle(Ink.cinnabar)
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.inkFaint)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Ink.paperRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Ink.line, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func summaryLine(_ provider: Provider) -> String {
        let model = provider.resolvedDefaultModel.isEmpty ? "未设置模型" : provider.resolvedDefaultModel
        let count = store.models(for: provider).count
        return "\(count) 个模型 · \(model)"
    }

    private func tint(_ provider: Provider) -> Color {
        switch provider.kind {
        case .zenFree: return Ink.cinnabar
        case .copilot: return Ink.jade
        case .zcode: return Color(red: 0.45, green: 0.34, blue: 0.22)
        case .custom: return Ink.inkSoft
        case .remote: return Color(red: 0.30, green: 0.36, blue: 0.45)
        }
    }

    private func addButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Ink.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .foregroundStyle(Ink.inkSoft)
        }
        .buttonStyle(.plain)
    }
}

/// 让 String 走 sheet(item:) 的小包装
struct ProviderIDBox: Identifiable {
    var id: String
}

extension Binding where Value == String? {
    func asProvider() -> Binding<ProviderIDBox?> {
        Binding<ProviderIDBox?>(
            get: { wrappedValue.map { ProviderIDBox(id: $0) } },
            set: { wrappedValue = $0?.id }
        )
    }
}

// MARK: - 渠道详情

struct ProviderDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var providerID: String

    @State private var draft = Provider(id: "", kind: .custom, name: "", format: .openai, baseURL: "", models: [], defaultModel: "")
    @State private var apiKey = ""
    @State private var modelText = ""
    @State private var headerText = ""
    @State private var aliases: [AliasPair] = []
    @State private var showCopilot = false
    @State private var showZCode = false
    @State private var zcodeSite: ZCodeSite = .zai
    @State private var loaded = false

    struct AliasPair: Identifiable {
        var id = UUID()
        var from: String = ""
        var to: String = ""
    }

    private var isBuiltin: Bool { draft.kind.isBuiltin }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(store.secret(for: providerID).summary(for: draft.kind))
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.inkSoft)
                    if !draft.note.isEmpty {
                        Text(draft.note)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Ink.inkFaint)
                    }
                    if draft.kind == .zenFree {
                        Label("无需登录，直接用公共身份 public", systemImage: "checkmark.seal")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.jade)
                    }
                }

                Section("基本信息") {
                    TextField("名称", text: $draft.name)
                    if !isBuiltin {
                        Picker("接口格式", selection: $draft.format) {
                            ForEach(APIFormat.allCases) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        Text(draft.format.hint)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Ink.inkFaint)
                    }
                    TextField("Base URL", text: $draft.baseURL)
                        .font(.system(size: 13, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Toggle("启用", isOn: $draft.enabled)
                }

                if draft.kind == .copilot {
                    Section("登录") {
                        Button {
                            showCopilot = true
                        } label: {
                            Label(store.secret(for: providerID).oauthToken.isEmpty ? "设备码登录 GitHub" : "重新登录", systemImage: "person.badge.key")
                        }
                    }
                }

                if draft.kind == .zcode {
                    Section {
                        Picker("站点", selection: $zcodeSite) {
                            ForEach(ZCodeSite.allCases) { site in
                                Text(site.title).tag(site)
                            }
                        }
                        Button {
                            if let site = ZCodeSite(rawValue: zcodeSite.rawValue) {
                                draft.baseURL = site.anthropicBase
                            }
                            showZCode = true
                        } label: {
                            Label("用网页登录 ZCode 并自动取 Key", systemImage: "globe.asia.australia")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("或粘贴 GLM Coding Plan API Key")
                                .font(.system(size: 12))
                                .foregroundStyle(Ink.inkSoft)
                            TextField("id.secret", text: $apiKey)
                                .font(.system(size: 12, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Button("保存这个 Key") {
                                var secret = store.secret(for: providerID)
                                secret.zcodeKey = apiKey.trimmed
                                secret.zcodeBase = draft.baseURL
                                if secret.deviceID.isEmpty { secret.deviceID = Auth.uuid() }
                                store.updateSecret(secret, for: providerID)
                                store.updateProvider(draft)
                                store.toast = "已保存 ZCode Key"
                            }
                            .font(.system(size: 12))
                        }
                    } header: {
                        Text("ZCode 登录")
                    } footer: {
                        Text("网页登录会用 ZCode 的 CLI 授权流程换出 zcode-api-key；没有 GLM Coding Plan 时请改用粘贴 Key。")
                    }
                    .onAppear {
                        if draft.baseURL.contains("bigmodel") { zcodeSite = .bigmodel }
                    }
                }

                if !isBuiltin {
                    Section("API Key") {
                        SecureField("仅保存在钥匙串", text: $apiKey)
                            .font(.system(size: 13, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section("模型") {
                    TextField("模型列表，用逗号或换行分隔", text: $modelText, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("默认模型", text: $draft.defaultModel)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack(spacing: 16) {
                        Button {
                            Task { await store.refreshModels(providerID: providerID) }
                        } label: {
                            Label("从服务拉取模型", systemImage: "arrow.down.circle")
                                .font(.system(size: 12.5))
                        }
                        Button {
                            Task { await store.test(providerID: providerID) }
                        } label: {
                            Label("测试连通", systemImage: "bolt")
                                .font(.system(size: 12.5))
                        }
                    }
                }

                Section {
                    ForEach($aliases) { $pair in
                        HStack(spacing: 6) {
                            TextField("别名", text: $pair.from)
                                .font(.system(size: 12, design: .monospaced))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Ink.inkFaint)
                            TextField("真实模型", text: $pair.to)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    .onDelete { offsets in
                        aliases.remove(atOffsets: offsets)
                    }
                    Button {
                        aliases.append(AliasPair())
                    } label: {
                        Label("添加别名", systemImage: "plus")
                            .font(.system(size: 12.5))
                    }
                } header: {
                    Text("模型别名")
                } footer: {
                    Text("例如把 gpt-4o 映射到 gpt-5.2；同名的全局「模型重定向」会在设置里统一处理。")
                }

                if !isBuiltin {
                    Section("额外请求头") {
                        TextField("每行一条，Key: Value", text: $headerText, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.system(size: 12, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                if !isBuiltin {
                    Section {
                        Button(role: .destructive) {
                            store.deleteProvider(providerID)
                            dismiss()
                        } label: {
                            Label("删除这个渠道", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
            .navigationTitle(draft.name.isEmpty ? "渠道" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { commit() }
                }
            }
            .sheet(isPresented: $showCopilot) {
                CopilotSignInView(providerID: providerID)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showZCode) {
                ZCodeSignInView(providerID: providerID)
                    .environmentObject(store)
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let provider = store.provider(providerID) else { return }
        draft = provider
        modelText = store.models(for: provider).joined(separator: "\n")
        apiKey = store.secret(for: provider.id).apiKey
        headerText = provider.headers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
        aliases = provider.aliases.map { AliasPair(from: $0.key, to: $0.value) }.sorted { $0.from < $1.from }
    }

    private func commit() {
        var provider = draft
        provider.models = parseList(modelText)
        provider.aliases = aliases.reduce(into: [String: String]()) { result, pair in
            let from = pair.from.trimmed
            let to = pair.to.trimmed
            if !from.isEmpty && !to.isEmpty { result[from] = to }
        }
        provider.headers = parseHeaders(headerText)
        if provider.name.trimmed.isEmpty { provider.name = provider.kind.title }
        if provider.defaultModel.trimmed.isEmpty {
            provider.defaultModel = provider.models.first ?? ""
        }
        store.updateProvider(provider)
        var secret = store.secret(for: provider.id)
        if !isBuiltin || provider.kind == .remote {
            secret.apiKey = apiKey.trimmed
        }
        if provider.kind == .zcode && !apiKey.trimmed.isEmpty {
            secret.zcodeKey = apiKey.trimmed
            secret.zcodeBase = provider.baseURL
            if secret.deviceID.isEmpty { secret.deviceID = Auth.uuid() }
        }
        store.updateSecret(secret, for: provider.id)
        dismiss()
    }

    private func parseList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
    }

    private func parseHeaders(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        (text.components(separatedBy: "\n") as [String]).forEach { line in
            guard let colon = line.firstIndex(of: ":") else { return }
            let key = String(line[line.startIndex..<colon]).trimmed
            let value = String(line[line.index(after: colon)...]).trimmed
            if !key.isEmpty && !value.isEmpty { result[key] = value }
        }
        return result
    }
}
