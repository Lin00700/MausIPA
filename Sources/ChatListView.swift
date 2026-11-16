import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: Bot?
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    banner
                    ForEach(store.bots) { bot in
                        NavigationLink(value: bot.id) {
                            BotRow(bot: bot, thread: store.activeThread(for: bot.id))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editing = bot
                            } label: { Label("编辑联系人", systemImage: "pencil") }
                            Button {
                                store.newThread(for: bot.id)
                            } label: { Label("新对话", systemImage: "square.and.pencil") }
                            Divider()
                            Button(role: .destructive) {
                                store.deleteBot(bot.id)
                            } label: { Label("删除联系人", systemImage: "trash") }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .background(Ink.paper.opacity(0.001))
            .navigationTitle("对话")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: UUID.self) { id in
                ChatView(botID: id)
                    .environmentObject(store)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = store.addBot()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { bot in
                BotEditView(bot: bot)
                    .environmentObject(store)
            }
        }
    }

    private var banner: some View {
        InkCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("把每个 AI 当成一个联系人")
                    .font(InkFont.title(0.95))
                    .foregroundStyle(Ink.inkText)
                Text("每个联系人有自己的渠道、模型、人格与记忆；对话留在本机。点开即聊，长按可编辑。")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct BotRow: View {
    @EnvironmentObject var store: AppStore
    var bot: Bot
    var thread: ChatThread?

    var body: some View {
        HStack(spacing: 12) {
            SealAvatar(text: bot.initial, color: tint, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(bot.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Ink.inkText)
                    if let provider = store.provider(bot.providerID) {
                        TagChip(text: provider.name, tint: Ink.inkFaint)
                    }
                }
                Text(thread?.preview ?? "还没有对话")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.inkSoft)
                    .lineLimit(1)
                Text(bot.model)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Ink.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let thread {
                Text(shortTime(thread.updatedAt))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Ink.inkFaint)
            }
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

    private var tint: Color {
        switch bot.providerID {
        case "zen": return Ink.cinnabar
        case "copilot": return Ink.jade
        case "zcode": return Color(red: 0.45, green: 0.34, blue: 0.22)
        default: return Ink.inkSoft
        }
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M/d"
        }
        return formatter.string(from: date)
    }
}

// MARK: - 编辑联系人

struct BotEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Bot
    @State private var isNew = false

    init(bot: Bot) {
        _draft = State(initialValue: bot)
    }

    private var providerModels: [String] {
        guard let provider = store.provider(draft.providerID) else { return [] }
        return store.models(for: provider)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        SealAvatar(text: draft.seal.isEmpty ? String(draft.name.prefix(1)) : draft.seal, size: 56)
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("名字", text: $draft.name)
                                .font(.system(size: 17, weight: .semibold))
                            HStack(spacing: 6) {
                                Text("印章")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ink.inkSoft)
                                TextField("一", text: $draft.seal)
                                    .frame(width: 40)
                                    .textFieldStyle(.roundedBorder)
                                Text("显示在头像上，一个字最好")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Ink.inkFaint)
                            }
                        }
                    }
                }

                Section("渠道与模型") {
                    if store.providers.isEmpty {
                        Text("先去「渠道」添加一个渠道")
                            .foregroundStyle(Ink.cinnabar)
                    } else {
                        Picker("渠道", selection: $draft.providerID) {
                            ForEach(store.providers) { provider in
                                Text(provider.name).tag(provider.id)
                            }
                        }
                        .onChange(of: draft.providerID) { _, newValue in
                            if let provider = store.provider(newValue) {
                                draft.model = provider.resolvedDefaultModel
                            }
                        }
                        ModelField(model: $draft.model, options: providerModels)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("温度")
                            Spacer()
                            Text(String(format: "%.1f", draft.temperature))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Ink.inkSoft)
                        }
                        Slider(value: $draft.temperature, in: 0...1.2, step: 0.1)
                    }
                }

                Section("人格提示词") {
                    TextEditor(text: $draft.systemPrompt)
                        .frame(minHeight: 90)
                        .font(.system(size: 14))
                }

                Section {
                    TextEditor(text: $draft.memory)
                        .frame(minHeight: 70)
                        .font(.system(size: 14))
                } header: {
                    Text("长期记忆")
                } footer: {
                    Text("这段文字每次都会跟在提示词后面，用来记住偏好、项目背景等。")
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            store.deleteBot(draft.id)
                            dismiss()
                        } label: {
                            Label("删除这个联系人", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
            .navigationTitle(isNew ? "新建联系人" : "编辑联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var bot = draft
                        bot.name = bot.name.trimmed.isEmpty ? "助手" : bot.name
                        bot.seal = bot.seal.trimmed
                        if bot.model.trimmed.isEmpty, let provider = store.provider(bot.providerID) {
                            bot.model = provider.resolvedDefaultModel
                        }
                        store.updateBot(bot)
                        dismiss()
                    }
                }
            }
            .onAppear {
                isNew = !store.bots.contains { $0.id == draft.id }
            }
        }
    }
}

struct ModelField: View {
    @Binding var model: String
    var options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("模型名，例如 gpt-4o", text: $model)
                .font(.system(size: 14, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !options.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(options, id: \.self) { option in
                            Button {
                                model = option
                            } label: {
                                Text(option)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(model == option ? Ink.cinnabar.opacity(0.14) : Ink.paperDeep)
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(model == option ? Ink.cinnabar.opacity(0.5) : Ink.line, lineWidth: 0.7)
                                    )
                                    .foregroundStyle(model == option ? Ink.cinnabar : Ink.inkSoft)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
