import SwiftUI

struct TeamView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: TeamRole?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    InkCard {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("一张桌子上的几位同事")
                                .font(InkFont.title(0.95))
                                .foregroundStyle(Ink.inkText)
                            Text("每个角色可以绑不同的渠道与模型。在对话里点「接力」，把上一条回答交给另一位角色接着做；也可以在「团队任务」里排好顺序一次跑完。")
                                .font(.system(size: 12))
                                .foregroundStyle(Ink.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ForEach(store.roles) { role in
                        Button {
                            editing = role
                        } label: {
                            roleCard(role)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editing = role
                            } label: { Label("编辑角色", systemImage: "pencil") }
                            Button(role: .destructive) {
                                store.roles.removeAll { $0.id == role.id }
                                store.save()
                            } label: { Label("删除角色", systemImage: "trash") }
                        }
                    }

                    Button {
                        var role = TeamRole(name: "新角色", seal: "新", prompt: "", providerID: store.providers.first?.id ?? "",
                                            model: store.providers.first?.resolvedDefaultModel ?? "")
                        role.seal = String(role.name.prefix(1))
                        store.roles.append(role)
                        store.save()
                        editing = role
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text("添加角色")
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
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Ink.paper.opacity(0.001))
            .navigationTitle("团队")
            .sheet(item: $editing) { role in
                RoleEditView(role: role)
                    .environmentObject(store)
            }
        }
    }

    private func roleCard(_ role: TeamRole) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SealAvatar(text: role.seal, color: Ink.cinnabar, size: 42)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(role.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Ink.inkText)
                    if let provider = store.provider(role.providerID) {
                        TagChip(text: provider.name, tint: Ink.inkFaint)
                    }
                }
                Text("\(role.providerID.isEmpty ? "未绑定渠道" : role.model)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Ink.inkText)
                    .lineLimit(1)
                Text(role.prompt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.inkSoft)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(Ink.inkFaint)
                .padding(.top, 4)
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
}

struct RoleEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TeamRole

    init(role: TeamRole) {
        _draft = State(initialValue: role)
    }

    private var models: [String] {
        guard let provider = store.provider(draft.providerID) else { return [] }
        return store.models(for: provider)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        SealAvatar(text: draft.seal, size: 50)
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("角色名", text: $draft.name)
                            TextField("印章字", text: $draft.seal)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                Section("渠道与模型") {
                    Picker("渠道", selection: $draft.providerID) {
                        ForEach(store.providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .onChange(of: draft.providerID) { _, value in
                        if let provider = store.provider(value) {
                            draft.model = provider.resolvedDefaultModel
                        }
                    }
                    ModelField(model: $draft.model, options: models)
                }
                Section("职责提示词") {
                    TextEditor(text: $draft.prompt)
                        .frame(minHeight: 120)
                        .font(.system(size: 14))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
            .navigationTitle("编辑角色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var role = draft
                        role.name = role.name.trimmed.isEmpty ? "角色" : role.name
                        if let index = store.roles.firstIndex(where: { $0.id == role.id }) {
                            store.roles[index] = role
                            store.save()
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
