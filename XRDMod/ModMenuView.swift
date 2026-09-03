import SwiftUI

struct ModMenuView: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine
    @State private var activeTab: MenuTab = .controls
    @State private var menuOpacity: Double = 0.95

    enum MenuTab: String, CaseIterable {
        case controls = "Controls"
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
        .frame(width: 340, height: 520)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(menuOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(xrdGradient, lineWidth: 2)
                )
        )
        .shadow(color: xrdPurple.opacity(0.4), radius: 20)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 4) {
            Text("XRD")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(xrdGradient)
                .shadow(color: xrdPurple.opacity(0.8), radius: 10)
                .shadow(color: xrdCyan.opacity(0.5), radius: 20)

            Text("AGAR.IO MOD MENU")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .tracking(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MenuTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
        .padding(.horizontal, 12)
    }

    private func tabButton(_ tab: MenuTab) -> some View {
        let isActive = activeTab == tab
        return Button(action: { withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab } }) {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
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
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Controls Tab

    private var controlsTab: some View {
        VStack(spacing: 16) {
            // Zoom
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ZOOM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(xrdCyan)
                    Spacer()
                    Text(String(format: "%.1fx", settings.zoomLevel))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }

                Slider(value: $settings.zoomLevel, in: 0.2...5.0, step: 0.1)
                    .accentColor(xrdPurple)

                HStack {
                    Text("0.2x").font(.system(size: 9)).foregroundColor(.gray)
                    Spacer()
                    Text("5.0x").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
            .sectionStyle()

            // Auto Feed
            VStack(spacing: 8) {
                autoFeedButton
                Text("Ejects mass continuously without holding W")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            .sectionStyle()

            // Info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("YOUR MASS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(settings.ownMass)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(xrdCyan)
                }

                HStack {
                    Text("SERVER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                    Text(serverDisplayName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }

                HStack {
                    Text("PLAYERS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(settings.currentPlayers.count)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .sectionStyle()

            Spacer(minLength: 20)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(settings.isConnected ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(botEngine.statusMessage)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text("v1.0")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Extracted Subviews

    private var autoFeedButton: some View {
        let feeding = settings.isAutoFeeding
        let icon = feeding ? "pause.circle.fill" : "play.circle.fill"
        let label = feeding ? "STOP AUTO FEED" : "START AUTO FEED"
        let bg = feeding ? Color.red : Color.purple
        return Button(action: { settings.isAutoFeeding.toggle() }) {
            HStack {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(bg)
            .cornerRadius(10)
        }
    }

    private var serverDisplayName: String {
        if settings.serverURL.isEmpty { return "N/A" }
        return settings.serverURL.components(separatedBy: "//").last ?? "N/A"
    }

    // MARK: - Colors

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(
            colors: [xrdPurple, xrdCyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Section Style

extension View {
    func sectionStyle() -> some View {
        self
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
