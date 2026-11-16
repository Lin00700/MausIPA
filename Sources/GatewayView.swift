import SwiftUI

struct GatewayView: View {
    @EnvironmentObject var store: AppStore
    @State private var portText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    configCard
                    endpointCard
                    examplesCard
                    Text("iOS 会在 App 进入后台后暂停监听，需要给其他设备用时请把 MausIPA 留在前台。网关只在你自己的局域网内可达。")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Ink.paper.opacity(0.001))
            .navigationTitle("网关")
            .onAppear { portText = String(store.settings.gatewayPort) }
        }
    }

    private var statusCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.gatewayRunning ? Ink.jade : Ink.inkFaint)
                        .frame(width: 8, height: 8)
                    Text(store.gatewayRunning ? "运行中" : "未启动")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Ink.inkText)
                    Spacer()
                    Button {
                        if store.gatewayRunning {
                            store.stopGateway()
                        } else {
                            store.startGateway()
                        }
                    } label: {
                        Text(store.gatewayRunning ? "停止" : "启动")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(store.gatewayRunning ? Ink.inkSoft.opacity(0.15) : Ink.cinnabar))
                            .foregroundStyle(store.gatewayRunning ? Ink.inkSoft : Color.white)
                    }
                    .buttonStyle(.plain)
                }
                Text(store.gatewayMessage.isEmpty ? "同 Wi-Fi 下的设备可以调用这台 iPhone 上的任意渠道。" : store.gatewayMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.inkSoft)
            }
        }
    }

    private var configCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "设置")
                HStack {
                    Text("端口")
                        .font(.system(size: 13))
                    TextField("8787", text: $portText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                    Spacer()
                    Button("应用") {
                        if let value = Int(portText), value > 0, value < 65536 {
                            store.settings.gatewayPort = value
                            store.save()
                            if store.gatewayRunning {
                                store.stopGateway()
                                store.startGateway()
                            }
                        } else {
                            portText = String(store.settings.gatewayPort)
                        }
                    }
                    .font(.system(size: 12))
                }
                Toggle("要求令牌", isOn: $store.settings.gatewayTokenEnabled)
                    .font(.system(size: 13))
                    .onChange(of: store.settings.gatewayTokenEnabled) { _, _ in store.save() }
                if store.settings.gatewayTokenEnabled {
                    HStack {
                        Text(store.settings.gatewayToken.isEmpty ? "还没生成" : store.settings.gatewayToken)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Ink.inkSoft)
                            .lineLimit(1)
                        Spacer()
                        Button("生成") {
                            store.settings.gatewayToken = "sk-" + Auth.randomHex(16)
                            store.save()
                        }
                        .font(.system(size: 12))
                        if !store.settings.gatewayToken.isEmpty {
                            CopyButton(value: store.settings.gatewayToken)
                        }
                    }
                }
                Toggle("打开 App 时自动启动", isOn: $store.settings.gatewayAutoStart)
                    .font(.system(size: 13))
                    .onChange(of: store.settings.gatewayAutoStart) { _, _ in store.save() }
            }
        }
    }

    private var endpointCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "地址", subtitle: "Base URL 填到 /v1 这一级")
                HStack {
                    Text(store.endpointBase + "/v1")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Ink.cinnabar)
                        .textSelection(.enabled)
                    Spacer()
                    CopyButton(value: store.endpointBase + "/v1")
                }
                ForEach(LAN.addresses(), id: \.self) { ip in
                    Text("局域网 IP：\(ip)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Ink.inkFaint)
                }
                if LAN.addresses().isEmpty {
                    Text("还没拿到局域网 IP，确认已连接 Wi-Fi 并允许本地网络访问。")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.inkFaint)
                }
            }
        }
    }

    private var examplesCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "调用示例", subtitle: "任何 OpenAI 兼容客户端都能接入")
                CodeBlockView(language: "bash", code: """
curl \(store.endpointBase)/v1/models \\
  -H "Authorization: Bearer \(store.settings.gatewayTokenEnabled ? store.settings.gatewayToken : "any")"

curl \(store.endpointBase)/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer \(store.settings.gatewayTokenEnabled ? store.settings.gatewayToken : "any")" \\
  -d '{"model":"zen/deepseek-v4.1-flash-free","stream":true,
       "messages":[{"role":"user","content":"你好"}]}'
""")
                Text("模型名可以用「渠道ID/模型名」，也可以直接写模型名。")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.inkFaint)
            }
        }
    }
}
