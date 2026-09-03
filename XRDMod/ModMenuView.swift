import SwiftUI

struct ModMenuView: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine
    @State private var activeTab: MenuTab = .macros
    @State private var showSaved = false

    enum MenuTab: String, CaseIterable {
        case macros = "Macros"
        case bots = "Bots"
        case zoom = "Zoom"
        case config = "Config"
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
                .background(isActive ? xrdPurple.opacity(0.3) : Color.clear)
                .cornerRadius(6)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            switch activeTab {
            case .macros:
                macrosTab
            case .bots:
                BotConfigPanel(settings: settings, botEngine: botEngine)
            case .zoom:
                zoomTab
            case .config:
                configTab
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Macros Tab

    private var macrosTab: some View {
        VStack(spacing: 8) {
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
                .background(settings.isAutoFeeding ? Color.red.opacity(0.8) : xrdPurple)
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("MACRO BUTTON")
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
                        Spacer()
                        if settings.isMacroActive {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text("ON")
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }

                    Toggle(isOn: $settings.macroDragMode) {
                        Text("Drag to move")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .tint(xrdPurple)
                }
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("MY UID")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(xrdCyan)
                    Spacer()
                    if !settings.detectedUID.isEmpty {
                        Text(settings.detectedUID)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }

                HStack(spacing: 4) {
                    Text("Name")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(width: 38, alignment: .leading)
                    TextField("Your IGN", text: $settings.playerName)
                        .textFieldStyle(XRDTextFieldStyle())
                }

                Button(action: {
                    if !settings.detectedUID.isEmpty {
                        UIPasteboard.general.string = settings.detectedUID
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text(settings.detectedUID.isEmpty ? "ENTER NAME TO DETECT" : "COPY UID")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(settings.detectedUID.isEmpty ? Color.gray.opacity(0.3) : xrdPurple)
                    .cornerRadius(6)
                }
                .disabled(settings.detectedUID.isEmpty)
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 3) {
                infoRow("MASS", "\(settings.ownMass)")
                infoRow("API", NetworkInterceptor.shared.hasDiscoveredAPI ? "Ready" : "Play 1 game")
                infoRow("PLAYERS", "\(settings.currentPlayers.count)")
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
                    Text("DISPLAY ZOOM")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(xrdCyan)
                    Spacer()
                    Text(String(format: "%.1fx", settings.zoomLevel))
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                }

                Slider(value: $settings.zoomLevel, in: 0.3...3.0, step: 0.1)
                    .accentColor(xrdPurple)

                HStack(spacing: 6) {
                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { val in
                        Button(action: { settings.zoomLevel = val }) {
                            Text(String(format: "%.1fx", val))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(abs(settings.zoomLevel - val) < 0.05 ? .white : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(abs(settings.zoomLevel - val) < 0.05 ? xrdPurple : Color.white.opacity(0.08))
                                .cornerRadius(5)
                        }
                    }
                }

                Button(action: { settings.zoomLevel = 1.0 }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                        Text("RESET")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 4) {
                Text("INFO")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Text("Display zoom scales the game view. Values below 1.0x zoom out, above 1.0x zoom in.")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .sectionStyle()

            Spacer(minLength: 8)
        }
    }

    // MARK: - Config Tab

    private var configTab: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SETTINGS")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(xrdCyan)
                    .tracking(1.5)

                Text("Save your macro, zoom, bot config so they load automatically next time.")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .sectionStyle()

            Button(action: {
                settings.save()
                showSaved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSaved = false }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 12))
                    Text("SAVE CHANGES")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
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
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                    Text("RESET ALL")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.7))
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                infoRow("LICENSE", settings.isLicenseValid ? "Active" : "Inactive")
                infoRow("MASS", "\(settings.ownMass)")
                infoRow("PLAYERS", "\(settings.currentPlayers.count)")
            }
            .sectionStyle()

            Spacer(minLength: 8)
        }
    }

    // MARK: - Helpers

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
                .fill(botEngine.isRunning ? Color.green : (NetworkInterceptor.shared.hasDiscoveredAPI ? Color.cyan : Color.gray.opacity(0.5)))
                .frame(width: 5, height: 5)
            Text(botEngine.isRunning ? botEngine.statusMessage : (NetworkInterceptor.shared.hasDiscoveredAPI ? "API ready" : "Play 1 game to setup"))
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(1)
            Spacer()
            Text("v1.1")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.gray.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.03))
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
