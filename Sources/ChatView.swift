import SwiftUI

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    let botID: UUID

    @State private var input = ""
    @State private var threadID: UUID?
    @State private var showHandoff = false
    @State private var showTeam = false
    @State private var showModelPicker = false
    @State private var showEdit = false
    @State private var showHistory = false

    private var bot: Bot? { store.bot(botID) }
    private var thread: ChatThread? { threadID.flatMap { store.thread($0) } }
    private var scale: Double { store.settings.fontScale }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Ink.line).frame(height: 0.7)
            messages
            composer
        }
        .background(Ink.paper.opacity(0.001))
        .navigationTitle(bot?.name ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showHandoff = true
                } label: {
                    Image(systemName: "arrow.triangle.branch")
                }
                .disabled(thread?.messages.contains(where: { $0.role == .assistant && !$0.text.trimmed.isEmpty }) != true)

                Menu {
                    Button {
                        threadID = store.newThread(for: botID)
                    } label: { Label("新对话", systemImage: "square.and.pencil") }
                    Button {
                        showHistory = true
                    } label: { Label("历史对话", systemImage: "clock.arrow.circlepath") }
                    Button {
                        showModelPicker = true
                    } label: { Label("切换模型", systemImage: "cpu") }
                    Button {
                        showTeam = true
                    } label: { Label("团队任务", systemImage: "person.3") }
                    Button {
                        showEdit = true
                    } label: { Label("编辑联系人", systemImage: "pencil") }
                    Divider()
                    Button(role: .destructive) {
                        if let threadID { store.clearThread(threadID) }
                    } label: { Label("清空这个对话", systemImage: "eraser") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear(perform: ensureThread)
        .onChange(of: botID) { _, _ in ensureThread() }
        .sheet(isPresented: $showHandoff) {
            HandoffSheet(threadID: threadID)
                .environmentObject(store)
        }
        .sheet(isPresented: $showTeam) {
            TeamRunSheet(threadID: threadID)
                .environmentObject(store)
        }
        .sheet(isPresented: $showModelPicker) {
            if let bot {
                ModelPickerSheet(bot: bot)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showEdit) {
            if let bot {
                BotEditView(bot: bot)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet(botID: botID, selected: $threadID)
                .environmentObject(store)
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            SealAvatar(text: bot?.initial ?? "墨", size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(bot?.name ?? "助手")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.inkText)
                Text(modelLine)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Ink.inkFaint)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                showTeam = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.3")
                        .font(.system(size: 10))
                    Text("团队")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Ink.cinnabar.opacity(0.1)))
                .foregroundStyle(Ink.cinnabar)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var modelLine: String {
        guard let bot else { return "" }
        let provider = store.provider(bot.providerID)?.name ?? "未配置渠道"
        return provider + " · " + bot.model
    }

    // MARK: 消息

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(thread?.messages ?? []) { message in
                        MessageRow(message: message, scale: scale, botName: bot?.name ?? "助手", botSeal: bot?.initial ?? "墨") { source in
                            handoffFrom(message: source)
                        }
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: thread?.messages.count ?? 0) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: thread?.messages.last?.text ?? "") { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: threadID) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: 输入

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Ink.line).frame(height: 0.7)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("说点什么…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 15 * scale))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Ink.paperRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Ink.line, lineWidth: 0.8)
                            )
                    )

                Button {
                    if store.isGenerating {
                        store.stop()
                    } else {
                        send()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(canSend ? Ink.cinnabar : Ink.line)
                        Image(systemName: store.isGenerating ? "stop.fill" : input.trimmed.isEmpty ? "arrow.up" : "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(canSend ? Color.white : Ink.inkFaint)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Ink.paper)
    }

    private var canSend: Bool {
        store.isGenerating || !input.trimmed.isEmpty
    }

    // MARK: 行为

    private func send() {
        guard let threadID else { return }
        let text = input
        input = ""
        store.send(threadID: threadID, text: text)
    }

    private func ensureThread() {
        if let existing = threadID, store.thread(existing) != nil { return }
        if let active = store.activeThread(for: botID) {
            threadID = active.id
        } else {
            threadID = store.newThread(for: botID)
        }
    }

    private func handoffFrom(message: ChatMessage) {
        _ = message
        showHandoff = true
    }
}

// MARK: - 单条消息

struct MessageRow: View {
    var message: ChatMessage
    var scale: Double
    var botName: String
    var botSeal: String
    var onHandoff: (ChatMessage) -> Void

    @State private var expanded = false

    private var split: (visible: String, thinking: String) {
        Thinking.split(message.text)
    }

    private var reasoning: String {
        [message.reasoning, split.thinking].filter { !$0.trimmed.isEmpty }.joined(separator: "\n\n")
    }

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 15.5 * scale))
                    .foregroundStyle(Ink.inkText)
                    .lineSpacing(3)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Ink.cinnabar.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Ink.cinnabar.opacity(0.18), lineWidth: 0.7)
                            )
                    )
                    .textSelection(.enabled)
            }
        } else {
            HStack(alignment: .top, spacing: 9) {
                SealAvatar(text: message.roleSeal.isEmpty ? botSeal : message.roleSeal,
                           color: message.isError ? Ink.cinnabarSoft : Ink.inkSoft,
                           size: 30)
                VStack(alignment: .leading, spacing: 7) {
                    nameLine
                    if !reasoning.isEmpty {
                        reasoningBox
                    }
                    if message.isError {
                        MarkdownText(text: split.visible, scale: scale, color: Ink.cinnabar)
                    } else if split.visible.isEmpty && message.isStreaming {
                        LoadingDots()
                            .padding(.vertical, 4)
                    } else {
                        MarkdownText(text: split.visible, scale: scale)
                    }
                    if message.isStreaming && !split.visible.isEmpty {
                        LoadingDots()
                    }
                    footer
                }
            }
        }
    }

    private var nameLine: some View {
        HStack(spacing: 6) {
            Text(message.roleLabel.isEmpty ? botName : message.roleLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.inkSoft)
            if !message.handoffFrom.isEmpty {
                TagChip(text: "接力自 \(message.handoffFrom)", tint: Ink.cinnabar)
            }
            if !message.modelLabel.isEmpty {
                Text(message.modelLabel)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Ink.inkFaint)
                    .lineLimit(1)
            }
        }
    }

    private var reasoningBox: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("思考过程")
                        .font(.system(size: 11))
                    Text("\(reasoning.count) 字")
                        .font(.system(size: 10))
                        .foregroundStyle(Ink.inkFaint)
                }
                .foregroundStyle(Ink.inkSoft)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(reasoning)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.inkSoft)
                    .lineSpacing(3)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Ink.paperDeep)
                    )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !message.text.trimmed.isEmpty {
                CopyButton(value: message.text)
                Button {
                    onHandoff(message)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text("接力")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Ink.inkSoft)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 1)
    }
}

// MARK: - 接力

struct HandoffSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var threadID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("把上一条回答交给团队里的另一位角色，用同一段上下文继续。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.inkSoft)
                        .padding(.bottom, 4)

                    ForEach(store.roles) { role in
                        Button {
                            if let threadID { store.handoff(threadID: threadID, role: role) }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                SealAvatar(text: role.seal, color: Ink.cinnabar, size: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(role.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Ink.inkText)
                                    Text("\(store.provider(role.providerID)?.name ?? "未配置") · \(role.model)")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(Ink.inkFaint)
                                }
                                Spacer()
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ink.inkFaint)
                            }
                            .padding(11)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Ink.paperRaised)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Ink.line, lineWidth: 0.8)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Ink.paper)
            .navigationTitle("接力给")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 团队任务

struct TeamRunSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var threadID: UUID?

    @State private var selected: [UUID] = []
    @State private var prompt = ""
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        ForEach(selected, id: \.self) { id in
                            if let role = store.roles.first(where: { $0.id == id }) {
                                HStack(spacing: 10) {
                                    SealAvatar(text: role.seal, size: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(role.name)
                                            .font(.system(size: 14, weight: .medium))
                                        Text("\(store.provider(role.providerID)?.name ?? "未配置") · \(role.model)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Ink.inkFaint)
                                    }
                                    Spacer()
                                    Button {
                                        selected.removeAll { $0 == id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(Ink.cinnabar)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .onMove { source, destination in
                            selected.move(fromOffsets: source, toOffset: destination)
                        }
                    } header: {
                        Text("执行顺序")
                    } footer: {
                        Text("按顺序把任务交给这些角色，每一步都能看到上一位的产出。")
                    }

                    Section("加入角色") {
                        ForEach(store.roles) { role in
                            Button {
                                if let index = selected.firstIndex(of: role.id) {
                                    selected.remove(at: index)
                                } else {
                                    selected.append(role.id)
                                }
                            } label: {
                                HStack {
                                    Text(role.name)
                                        .foregroundStyle(Ink.inkText)
                                    Text("\(store.provider(role.providerID)?.name ?? "") · \(role.model)")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(Ink.inkFaint)
                                    Spacer()
                                    if selected.contains(role.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Ink.cinnabar)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section("任务") {
                        TextEditor(text: $prompt)
                            .frame(minHeight: 90)
                            .font(.system(size: 14))
                    }
                }
                .scrollContentBackground(.hidden)
                .environment(\.editMode, $editMode)

                Button {
                    if let threadID {
                        store.teamRun(threadID: threadID, roleIDs: selected, prompt: prompt)
                    }
                    dismiss()
                } label: {
                    Text("开始团队任务")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(canRun ? Ink.cinnabar : Ink.line)
                        )
                        .foregroundStyle(canRun ? Color.white : Ink.inkFaint)
                }
                .buttonStyle(.plain)
                .disabled(!canRun)
                .padding(16)
            }
            .background(Ink.paper)
            .navigationTitle("团队任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode == .active ? "完成" : "排序") {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
            }
            .onAppear {
                if selected.isEmpty {
                    selected = Array(store.roles.prefix(3).map { $0.id })
                }
            }
        }
    }

    private var canRun: Bool {
        !selected.isEmpty && !prompt.trimmed.isEmpty
    }
}

// MARK: - 切换模型

struct ModelPickerSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var bot: Bot

    @State private var model: String = ""
    @State private var providerID: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("渠道") {
                    Picker("渠道", selection: $providerID) {
                        ForEach(store.providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                }
                Section("模型") {
                    ForEach(options, id: \.self) { option in
                        Button {
                            model = option
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(Ink.inkText)
                                Spacer()
                                if model == option {
                                    Image(systemName: "checkmark").foregroundStyle(Ink.cinnabar)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("或直接输入模型名", text: $model)
                        .font(.system(size: 14, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
            .navigationTitle("切换模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = bot
                        updated.providerID = providerID
                        updated.model = model
                        store.updateBot(updated)
                        dismiss()
                    }
                }
            }
            .onAppear {
                providerID = bot.providerID
                model = bot.model
            }
        }
    }

    private var options: [String] {
        guard let provider = store.provider(providerID) else { return [] }
        return store.models(for: provider)
    }
}

// MARK: - 历史对话

struct HistorySheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var botID: UUID
    @Binding var selected: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.threads(for: botID)) { thread in
                    Button {
                        selected = thread.id
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(thread.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Ink.inkText)
                            Text(thread.preview)
                                .font(.system(size: 12))
                                .foregroundStyle(Ink.inkFaint)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteThread(thread.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
            .navigationTitle("历史对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selected = store.newThread(for: botID)
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}
