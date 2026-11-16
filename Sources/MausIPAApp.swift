import SwiftUI

@main
struct MausIPAApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(store.settings.appearance.colorScheme)
                .tint(Ink.cinnabar)
                .onAppear {
                    if store.settings.gatewayAutoStart && !store.gatewayRunning {
                        store.startGateway()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        store.save()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var selection = 0

    var body: some View {
        ZStack {
            Ink.wash(store.settings.useInkStyle)
            TabView(selection: $selection) {
                ChatListView()
                    .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
                    .tag(0)
                TeamView()
                    .tabItem { Label("团队", systemImage: "person.3") }
                    .tag(1)
                ProvidersView()
                    .tabItem { Label("渠道", systemImage: "square.stack.3d.up") }
                    .tag(2)
                GatewayView()
                    .tabItem { Label("网关", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag(3)
                SettingsView()
                    .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
                    .tag(4)
            }
        }
        .overlay(alignment: .bottom) {
            if !store.toast.isEmpty {
                Text(store.toast)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Ink.inkText.opacity(0.92))
                    )
                    .foregroundStyle(Ink.paperRaised)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 68)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { store.toast = "" }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toast)
    }
}
