import SwiftUI

struct ModMenuView: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine
    @State private var activeTab: MenuTab = .controls

    enum MenuTab: String, CaseIterable {
        case controls = "Main"
        case bots = "Bots"
        case players = "Players"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            tabBar
            tabContent
            statusBar
        }
        .frame(width: 220, height: 310)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(xrdGradient, lineWidth: 1.5)
                )
        )
        .shadow(color: xrdPurple.opacity(0.3), radius: 12)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("XRD")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(xrdGradient)
                .shadow(color: xrdPurple.opacity(0.6), radius: 6)
            Spacer()
            Text("MOD MENU")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .tracking(2)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MenuTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }

    private func tabButton(_ tab: MenuTab) -> some View {
        let isActive = activeTab == tab
        return Button(action: { withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab } }) {
            Text(tab.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(isActive ? Color.purple.opacity(0.3) : Color.clear)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            switch activeTab {
            case .controls:
                controlsTab
            case .bots:
                BotConfigPanel(settings: settings, botEngine: botEngine)
            case .players:
                PlayerListView(settings: settings, botEngine: botEngine)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Controls Tab

    private var controlsTab: some View {
        VStack(spacing: 8) {
            // Zoom
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ZOOM")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(xrdCyan)
                    Spacer()
                    Text(String(format: "%.1fx", settings.zoomLevel))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white)
                }
                Slider(value: $settings.zoomLevel, in: 0.2...5.0, step: 0.1)
                    .accentColor(xrdPurple)
            }
            .sectionStyle()

            // Auto Feed
            Button(action: { settings.isAutoFeeding.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: settings.isAutoFeeding ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 14))
                    Text(settings.isAutoFeeding ? "STOP FEED" : "AUTO FEED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(settings.isAutoFeeding ? Color.red : Color.purple)
                .cornerRadius(8)
            }

            // Macro
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("MACRO")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(xrdCyan)
                    Spacer()
                    Toggle("", isOn: $settings.isMacroEnabled)
                        .tint(xrdPurple)
                        .labelsHidden()
                        .scaleEffect(0.7)
                }

                if settings.isMacroEnabled {
                    HStack(spacing: 6) {
                        Text("SIZE")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Button(action: { settings.macroButtonSize = max(30, settings.macroButtonSize - 5) }) {
                            Text("-")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(4)
                        }
                        Text("\(Int(settings.macroButtonSize))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 26)
                        Button(action: { settings.macroButtonSize = min(100, settings.macroButtonSize + 5) }) {
                            Text("+")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(4)
                        }
                        Spacer()
                        if settings.isMacroActive {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("ON")
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .sectionStyle()

            // Info
            VStack(alignment: .leading, spacing: 3) {
                infoRow("MASS", "\(settings.ownMass)")
                infoRow("SERVER", serverDisplayName)
                infoRow("PLAYERS", "\(settings.currentPlayers.count)")
            }
            .sectionStyle()

            Spacer(minLength: 8)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(xrdCyan)
                .lineLimit(1)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(botEngine.isRunning ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 5, height: 5)
            Text(botEngine.statusMessage)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(1)
            Spacer()
            Text("v1.0")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.gray.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.03))
    }

    private var serverDisplayName: String {
        settings.serverURL.isEmpty ? "N/A" : (settings.serverURL.components(separatedBy: "//").last ?? "N/A")
    }

    // MARK: - Colors

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Section Style

extension View {
    func sectionStyle() -> some View {
        self
            .padding(8)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}
