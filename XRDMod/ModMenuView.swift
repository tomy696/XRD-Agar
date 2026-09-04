import SwiftUI

struct ModMenuView: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine
    @ObservedObject var zoomEngine: ZoomEngine
    @State private var activeTab: MenuTab = .macro
    @State private var showSaved = false

    enum MenuTab: String, CaseIterable {
        case macro = "Macro"
        case bots = "Bots"
        case zoom = "Zoom"
        case config = "Config"
    }

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            tabBar
            tabContent
            statusBar
        }
        .frame(width: 210, height: 300)
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
            Spacer()
            Circle()
                .fill(NetworkInterceptor.shared.hasServer ? Color.green : Color.red)
                .frame(width: 6, height: 6)
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
                .background(isActive ? xrdPurple.opacity(0.3) : Color.clear)
                .cornerRadius(6)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            switch activeTab {
            case .macro: macroTab
            case .bots: BotConfigPanel(settings: settings, botEngine: botEngine)
            case .zoom: zoomTab
            case .config: configTab
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Macro Tab

    private var macroTab: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    sectionHeader("MACRO")
                    Spacer()
                    Toggle("", isOn: $settings.isMacroEnabled)
                        .tint(xrdPurple)
                        .labelsHidden()
                        .scaleEffect(0.7)
                }

                if settings.isMacroEnabled {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("AUTO FEED ON")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    VStack(spacing: 3) {
                        HStack {
                            Text("Power")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(Int(settings.macroPower))")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(xrdCyan)
                        }
                        Slider(value: $settings.macroPower, in: 1...10, step: 1)
                            .accentColor(xrdPurple)
                        HStack {
                            Text("Slow")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(.gray.opacity(0.5))
                            Spacer()
                            Text("\(Int(settings.feedInterval * 1000))ms")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            Text("Fast")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }

                    HStack(spacing: 6) {
                        Text("SIZE")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Button(action: { settings.macroButtonSize = max(30, settings.macroButtonSize - 5) }) {
                            Text("-").font(.system(size: 12, weight: .bold))
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
                            Text("+").font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("STATUS")
                infoRow("WS Captured", NetworkInterceptor.shared.gameWebSocket != nil ? "Yes" : "No")
                infoRow("Intercepted", "\(NetworkInterceptor.shared.interceptedCount)")
                infoRow("Mass", "\(settings.ownMass)")
            }
            .sectionStyle()

            Spacer(minLength: 8)
        }
    }

    // MARK: - Zoom Tab

    private var zoomTab: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    sectionHeader("ZOOM")
                    Spacer()
                    Text(zoomEngine.activeMethod.rawValue)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                }

                infoRow("Status", zoomEngine.statusText)
                if !zoomEngine.debugInfo.isEmpty {
                    infoRow("View", zoomEngine.debugInfo)
                }

                VStack(spacing: 4) {
                    HStack {
                        Text("Level")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.1fx", zoomEngine.currentZoom))
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    Slider(
                        value: Binding(
                            get: { zoomEngine.currentZoom },
                            set: { zoomEngine.setZoom($0) }
                        ),
                        in: 0.3...3.0, step: 0.1
                    )
                    .accentColor(xrdPurple)

                    HStack(spacing: 6) {
                        ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { val in
                            Button(action: { zoomEngine.setZoom(val) }) {
                                Text(String(format: "%.1fx", val))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(abs(zoomEngine.currentZoom - val) < 0.05 ? .white : .gray)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(abs(zoomEngine.currentZoom - val) < 0.05 ? xrdPurple : Color.white.opacity(0.08))
                                    .cornerRadius(5)
                            }
                        }
                    }

                    Button(action: { zoomEngine.reset() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 10))
                            Text("RESET").font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 4) {
                if zoomEngine.activeMethod == .engineHook {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("Engine hook - real zoom")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.green.opacity(0.8))
                    }
                } else if zoomEngine.activeMethod == .objcHook {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("ObjC hook - real zoom")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.green.opacity(0.8))
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color.cyan).frame(width: 5, height: 5)
                        Text("Display zoom")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.8))
                    }
                    Text("< 1x = zoom out, > 1x = zoom in")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
            .sectionStyle()

            Spacer(minLength: 8)
        }
    }

    // MARK: - Config Tab

    private var configTab: some View {
        VStack(spacing: 8) {
            Button(action: {
                settings.save()
                showSaved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSaved = false }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down.fill").font(.system(size: 12))
                    Text("SAVE").font(.system(size: 10, weight: .black, design: .monospaced))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(xrdGradient)
                .cornerRadius(8)
            }

            if showSaved {
                Text("Saved!")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            Button(action: { settings.resetAll() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12))
                    Text("RESET ALL").font(.system(size: 10, weight: .black, design: .monospaced))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.7))
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                sectionHeader("DEBUG")
                infoRow("License", settings.isLicenseValid ? "Active" : "Inactive")
                infoRow("Server", NetworkInterceptor.shared.hasServer ? "Yes" : "No")
                infoRow("WS", NetworkInterceptor.shared.gameWebSocket != nil ? "Captured" : "None")
                infoRow("Intercepted", "\(NetworkInterceptor.shared.interceptedCount)")
                if let url = NetworkInterceptor.shared.capturedServerURL {
                    infoRow("URL", String(url.prefix(25)))
                }
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 3) {
                infoRow("Version", "2.0")
                infoRow("Mod", "XRD Agar.io")
            }
            .sectionStyle()

            Spacer(minLength: 8)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundColor(xrdCyan)
            .tracking(1.5)
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
                .fill(botEngine.isRunning ? Color.green : (NetworkInterceptor.shared.hasServer ? Color.cyan : Color.gray.opacity(0.5)))
                .frame(width: 5, height: 5)
            Text(botEngine.isRunning ? botEngine.statusMessage : (NetworkInterceptor.shared.hasServer ? "Server ready" : "Play 1 game"))
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(1)
            Spacer()
            Text("v2.0")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.gray.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.03))
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
