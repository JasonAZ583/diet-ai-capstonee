import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard, vault, suggest, log
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Today"
        case .vault: return "Vault"
        case .suggest: return "AI Suggest"
        case .log: return "Log"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .vault: return "tray.full.fill"
        case .suggest: return "sparkles"
        case .log: return "calendar"
        }
    }
}

struct ContentView: View {
    @State private var tab: AppTab = .dashboard

    init() {
        // Force dark appearance so the deck palette reads consistently.
        UIView.appearance().overrideUserInterfaceStyle = .dark
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Deck.bg.ignoresSafeArea()

            Group {
                switch tab {
                case .dashboard: DashboardView()
                case .vault:     VaultView()
                case .suggest:   SuggestView()
                case .log:       CalendarLogView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LiquidGlassGroup(spacing: 32) {
                FloatingTabBar(selection: $tab)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .tint(Deck.accent)
        .onReceive(NotificationCenter.default.publisher(for: .switchToSuggest)) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { tab = .suggest }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToVault)) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { tab = .vault }
        }
    }
}

// MARK: - Floating glass tab bar

struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var glassNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .regular))
                        Text(tab.label)
                            .font(.deckMono(10))
                            .tracking(0.4)
                    }
                    .foregroundStyle(selection == tab ? Deck.accent : Deck.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            interactive: true
        )
        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
    }
}

#Preview {
    ContentView()
}
