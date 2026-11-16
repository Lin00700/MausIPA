import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Toggle("水墨风格", isOn: $store.settings.useInkStyle)
                        .onChange(of: store.settings.useInkStyle) { _, _ in store.save() }
                    Picker("配色", selection: $store.settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .onChange(of: store.settings.appearance) { _, _ in store.save() }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("字号")
                            Spacer()
                            Text(String(format: "%.2fx", store.settings.fontScale))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Ink.inkSoft)
                        }
                        Slider(value: $store.settings.fontScale, in: 0.85...1.3, step: 0.05)
                            .onChange(of: store.settings.fontScale) { _, _ in store.save() }
                    }
                }

                Section("生成") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("温度")
                            Spacer()
                            Text(String(format: "%.1f", store.settings.temperature))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Ink.inkSoft)
                        }
                        Slider(value: $store.settings.temperature, in: 0...1.2, step: 0.1)
                            .onChange(of: store.settings.temperature) { _, _ in store.save() }
                    }
                    Stepper("最多输出 \(store.settings.maxTokens) tokens", value: $store.settings.maxTokens, in: 256...16384, step: 256)
                        .onChange(of: store.settings.maxTokens) { _, _ in store.save() }
                    Stepper("携带 \(store.settings.historyLimit) 条历史", value: $store.settings.historyLimit, in: 4...200, step: 2)
                        .onChange(of: store.settings.historyLimit) { _, _ in store.save() }
                }

                Section {
                    NavigationLink {
                        PresetsView()
                            .environmentObject(store)
                    } label: {
                        Label("系统提示词预设", systemImage: "text.quote")
                    }
                    NavigationLink {
                        RedirectsView()
                            .environmentObject(store)
                    } label: {
                        Label("模型重定向", systemImage: "arrow.triangle.swap")
                    }
                } header: {
                    Text("提示词与映射")
                } footer: {
                    Text("模型重定向可以写成「渠道ID::模型名」做跨渠道跳转，例如 zen::big-pickle。")
                }

                Section("数据") {
                    Button {
                        for thread in store.threads {
                            store.clearThread(thread.id)
                        }
                        store.toast = "已清空全部对话"
                    } label: {
                        Label("清空所有对话", systemImage: "eraser")
                    }
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("重置全部数据", systemImage: "trash")
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(Ink.inkSoft)
                    }
                    Link(destination: URL(string: "https://github.com/Lin00700/MausIPA")!) {
                        HStack {
                            Text("源代码")
                            Spacer()
                            Text("Lin00700/MausIPA")
                                .foregroundStyle(Ink.inkSoft)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Ink.inkFaint)
                        }
                    }
                    Text("借水墨之意，把几个 AI 联系人放在掌心。渠道实现参照 magpie-community/plugins 的真实端点，联系人形态受 OpenMausBot 启发，团队接力受 Timon 启发。")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.inkFaint)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper.opacity(0.001))
            .navigationTitle("设置")
            .confirmationDialog("确定重置全部数据？所有联系人与对话都会删除，钥匙串里的 Key 也会清掉。", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("重置", role: .destructive) {
                    for provider in store.providers {
                        store.updateSecret(ProviderSecret(), for: provider.id)
                    }
                    store.bots = []
                    store.threads = []
                    store.roles = []
                    store.presets = []
                    store.redirects = []
                    store.providers = []
                    store.save()
                    store.toast = "已重置，请重新添加渠道"
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

// MARK: - 提示词预设

struct PresetsView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: PromptPreset?
    @State private var draftName = ""
    @State private var draftText = ""

    var body: some View {
        List {
            ForEach(store.presets) { preset in
                Button {
                    editing = preset
                    draftName = preset.name
                    draftText = preset.text
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Ink.inkText)
                        Text(preset.text)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Ink.inkFaint)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        store.presets.removeAll { $0.id == preset.id }
                        store.save()
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Ink.paper)
        .navigationTitle("提示词预设")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let preset = PromptPreset(name: "新预设", text: "")
                    store.presets.append(preset)
                    store.save()
                    editing = preset
                    draftName = preset.name
                    draftText = ""
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { preset in
            NavigationStack {
                Form {
                    TextField("名称", text: $draftName)
                    TextEditor(text: $draftText)
                        .frame(minHeight: 160)
                        .font(.system(size: 14))
                }
                .scrollContentBackground(.hidden)
                .background(Ink.paper)
                .navigationTitle(preset.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if let index = store.presets.firstIndex(where: { $0.id == preset.id }) {
                                store.presets[index].name = draftName.trimmed.isEmpty ? "预设" : draftName
                                store.presets[index].text = draftText
                                store.save()
                            }
                            editing = nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 模型重定向

struct RedirectsView: View {
    @EnvironmentObject var store: AppStore
    @State private var from = ""
    @State private var to = ""

    var body: some View {
        Form {
            Section {
                ForEach(store.redirects) { redirect in
                    HStack(spacing: 6) {
                        Text(redirect.from)
                            .font(.system(size: 12.5, design: .monospaced))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.inkFaint)
                        Text(redirect.to)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Ink.cinnabar)
                    }
                }
                .onDelete { offsets in
                    store.redirects.remove(atOffsets: offsets)
                    store.save()
                }
            } header: {
                Text("已有规则")
            } footer: {
                Text("请求里出现左边的模型名时，改用右边的模型；右边写成「渠道ID::模型」可跨渠道。")
            }

            Section("新增") {
                TextField("原模型名", text: $from)
                    .font(.system(size: 13, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("目标模型 / 渠道::模型", text: $to)
                    .font(.system(size: 13, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("添加") {
                    let source = from.trimmed
                    let target = to.trimmed
                    guard !source.isEmpty, !target.isEmpty else { return }
                    store.redirects.append(ModelRedirect(from: source, to: target))
                    store.save()
                    from = ""
                    to = ""
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Ink.paper)
        .navigationTitle("模型重定向")
    }
}
