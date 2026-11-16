import SwiftUI

// MARK: - GitHub Copilot 设备码登录

struct CopilotSignInView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var providerID: String

    @State private var flow: CopilotDeviceFlow?
    @State private var status = "正在向 GitHub 申请设备码…"
    @State private var errorMessage = ""
    @State private var workItem: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    InkCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("1. 在浏览器里打开授权页")
                                .font(.system(size: 13, weight: .semibold))
                            if let flow {
                                Link(destination: flow.verificationURL ?? URL(string: "https://github.com/login/device")!) {
                                    HStack {
                                        Image(systemName: "safari")
                                        Text(flow.verificationURI)
                                            .font(.system(size: 13, design: .monospaced))
                                    }
                                    .foregroundStyle(Ink.cinnabar)
                                }
                                Text("2. 输入这个设备码")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.top, 4)
                                HStack {
                                    Text(flow.userCode)
                                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                                        .tracking(4)
                                        .foregroundStyle(Ink.inkText)
                                    Spacer()
                                    CopyButton(value: flow.userCode, label: "复制设备码")
                                }
                                Text("3. 授权后这里会自动完成登录")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ink.inkSoft)
                            } else {
                                ProgressView()
                            }
                        }
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Ink.cinnabar)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Ink.cinnabar.opacity(0.08))
                            )
                    }

                    HStack(spacing: 6) {
                        LoadingDots()
                        Text(status)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.inkSoft)
                    }

                    Text("Copilot 登录只换取本机使用的推理令牌，令牌保存在钥匙串，可随时在渠道里重新登录。")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.inkFaint)
                }
                .padding(16)
            }
            .background(Ink.paper)
            .navigationTitle("登录 GitHub Copilot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        workItem?.cancel()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: begin)
            .onDisappear { workItem?.cancel() }
        }
    }

    private func begin() {
        guard workItem == nil else { return }
        workItem = Task { @MainActor in
            do {
                let device = try await Copilot.startDeviceFlow()
                flow = device
                status = "等待你在 GitHub 上确认…"
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: UInt64(max(device.interval, 5)) * 1_000_000_000)
                    if Date() > device.expiresAt {
                        errorMessage = "设备码已过期，请关闭后重新登录"
                        return
                    }
                    if let token = try await Copilot.pollDeviceToken(device) {
                        status = "已授权，正在换取 Copilot 令牌…"
                        let renewed = try await Copilot.exchange(oauth: token)
                        var secret = store.secret(for: providerID)
                        secret.oauthToken = token
                        secret.inferenceToken = renewed.token
                        secret.expiresAt = renewed.expiresAt
                        secret.accountLabel = "GitHub Copilot"
                        store.updateSecret(secret, for: providerID)
                        status = "登录成功"
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        dismiss()
                        return
                    }
                }
            } catch {
                errorMessage = describeError(error)
                status = "登录未完成"
            }
        }
    }
}

// MARK: - ZCode 网页登录

struct ZCodeSignInView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var providerID: String

    @State private var site: ZCodeSite = .zai
    @State private var flow: ZCodeFlow?
    @State private var status = ""
    @State private var errorMessage = ""
    @State private var working = false
    @State private var workItem: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let flow {
                    WebView(url: URL(string: flow.authorizeURL)!)
                        .overlay(alignment: .top) {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text(status.isEmpty ? "等待登录完成…" : status)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Ink.inkSoft)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Ink.paperRaised.opacity(0.95)))
                            .padding(.top, 8)
                        }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("站点", selection: $site) {
                                ForEach(ZCodeSite.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(site.signInHint)
                                .font(.system(size: 13))
                                .foregroundStyle(Ink.inkSoft)

                            Text("登录后，MausIPA 会用 ZCode 的 CLI 授权流程换出 zcode-api-key，再走 Anthropic Messages 接口。没有 GLM Coding Plan 的账号会提示改用粘贴 Key。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Ink.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                begin()
                            } label: {
                                HStack {
                                    if working { ProgressView().scaleEffect(0.8) }
                                    Text(working ? "正在打开登录页…" : "打开 \(site.title) 登录")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Ink.cinnabar)
                                )
                                .foregroundStyle(Color.white)
                            }
                            .buttonStyle(.plain)
                            .disabled(working)

                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Ink.cinnabar)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Ink.paper)
            .navigationTitle("登录 ZCode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        workItem?.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear { workItem?.cancel() }
        }
    }

    private func begin() {
        working = true
        errorMessage = ""
        workItem = Task { @MainActor in
            do {
                let created = try await ZCode.startFlow(site: site)
                flow = created
                status = "请在页面中完成登录…"
                status = "登录中，完成后会自动返回"
                let secret = try await ZCode.finishSignIn(created)
                var stored = store.secret(for: providerID)
                stored.zcodeKey = secret.zcodeKey
                stored.zcodeJWT = secret.zcodeJWT
                stored.zcodeBase = secret.zcodeBase
                stored.deviceID = secret.deviceID
                stored.accountLabel = secret.accountLabel
                store.updateSecret(stored, for: providerID)
                if var provider = store.provider(providerID) {
                    provider.baseURL = secret.zcodeBase
                    if provider.models.isEmpty { provider.models = ZCode.defaultModels }
                    store.updateProvider(provider)
                }
                status = "登录成功，已取得 API Key"
                try? await Task.sleep(nanoseconds: 700_000_000)
                dismiss()
            } catch {
                errorMessage = describeError(error)
                working = false
            }
        }
    }
}
