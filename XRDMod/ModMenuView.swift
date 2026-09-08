import SwiftUI

struct ModMenuView: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine
    @ObservedObject var zoomEngine: ZoomEngine
    @ObservedObject var gameHooks: GameHooks
    @State private var activeTab: MenuTab = .bots
    @State private var showSaved = false
    @State private var manualServer: String = ""
    @State private var configCopiedUID = false
    @State private var debugCopied = false

    enum MenuTab: String, CaseIterable {
        case bots = "Bots"
        case mods = "Mods"
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
        .frame(width: 230, height: 380)
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
            case .bots: BotConfigPanel(settings: settings, botEngine: botEngine)
            case .mods: modsTab
            case .zoom: zoomTab
            case .config: configTab
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Mods Tab

    private var modsTab: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("GAMEPLAY")
                modToggle("Unlock FPS (120)", isOn: Binding(
                    get: { GameHooks.unlockFPS },
                    set: { GameHooks.unlockFPS = $0; gameHooks.applyFPSToExisting(); gameHooks.saveToggles() }
                ))
                modToggle("Auto Respawn", isOn: Binding(
                    get: { GameHooks.autoRespawn },
                    set: { GameHooks.autoRespawn = $0; gameHooks.saveToggles() }
                ))
                modToggle("Show Mass", isOn: Binding(
                    get: { GameHooks.showMass },
                    set: { GameHooks.showMass = $0; gameHooks.saveToggles() }
                ))
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("VISUALS")
                modToggle("Hide Grid", isOn: Binding(
                    get: { GameHooks.hideGrid },
                    set: { GameHooks.hideGrid = $0; gameHooks.saveToggles() }
                ))
                modToggle("Hide Borders", isOn: Binding(
                    get: { GameHooks.hideBorder },
                    set: { GameHooks.hideBorder = $0; gameHooks.saveToggles() }
                ))
                modToggle("No Skins", isOn: Binding(
                    get: { GameHooks.noSkins },
                    set: { GameHooks.noSkins = $0; gameHooks.saveToggles() }
                ))
                modToggle("No Animations", isOn: Binding(
                    get: { GameHooks.disableAnimations },
                    set: { GameHooks.disableAnimations = $0; gameHooks.saveToggles() }
                ))
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("UNLOCK")
                modToggle("All Skins", isOn: Binding(
                    get: { GameHooks.unlockSkins },
                    set: { GameHooks.unlockSkins = $0; gameHooks.saveToggles() }
                ))
                modToggle("All Emojis", isOn: Binding(
                    get: { GameHooks.unlockEmojis },
                    set: { GameHooks.unlockEmojis = $0; gameHooks.saveToggles() }
                ))
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("MACROS")
                HStack(spacing: 6) {
                    Button(action: {
                        GameHooks.feedMacroActive.toggle()
                        if GameHooks.feedMacroActive {
                            gameHooks.startFeedMacro(rate: settings.botConfig.feedMacroRate, size: settings.botConfig.feedMacroSize, invisible: settings.botConfig.invisibleFeed)
                        }
                    }) {
                        Text(GameHooks.feedMacroActive ? "FEED ON" : "FEED")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(GameHooks.feedMacroActive ? Color.green.opacity(0.7) : xrdPurple.opacity(0.6))
                            .cornerRadius(6)
                    }
                    Button(action: {
                        gameHooks.startSplitMacro(count: settings.botConfig.softMacroAmount, rate: settings.botConfig.splitMacroRate, invisible: settings.botConfig.invisibleSplit)
                    }) {
                        Text("SPLIT x\(settings.botConfig.softMacroAmount)")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(xrdPurple.opacity(0.6))
                            .cornerRadius(6)
                    }
                }

                macroSlider("Feed Rate", value: $settings.botConfig.feedMacroRate, range: 5...100, unit: "/s")
                macroSlider("Split Rate", value: $settings.botConfig.splitMacroRate, range: 5...100, unit: "/s")

                HStack(spacing: 4) {
                    Text("Feed Size")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                    ForEach([1, 3, 5, 7], id: \.self) { n in
                        Button("\(n)") {
                            settings.botConfig.feedMacroSize = n
                        }
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(settings.botConfig.feedMacroSize == n ? xrdPurple : Color.white.opacity(0.08))
                        .cornerRadius(4)
                    }
                }

                HStack(spacing: 4) {
                    Text("Split Amt")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                    ForEach([4, 8, 16, 32], id: \.self) { n in
                        Button("\(n)") {
                            settings.botConfig.softMacroAmount = n
                        }
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(settings.botConfig.softMacroAmount == n ? xrdPurple : Color.white.opacity(0.08))
                        .cornerRadius(4)
                    }
                }

                modToggle("Invisible Feed", isOn: $settings.botConfig.invisibleFeed)
                modToggle("Invisible Split", isOn: $settings.botConfig.invisibleSplit)
                modToggle("Center Self Feed", isOn: $settings.botConfig.centerSelfFeed)

                Button(action: { gameHooks.stopMacros() }) {
                    Text("STOP MACROS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("HOOKS STATUS")
                if gameHooks.hookedMethods.isEmpty {
                    Text("Aucun hook actif")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.7))
                } else {
                    ForEach(gameHooks.hookedMethods, id: \.self) { method in
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 4, height: 4)
                            Text(method)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.green.opacity(0.8))
                        }
                    }
                }
            }
            .sectionStyle()

            Spacer(minLength: 8)
        }
    }

    private func macroSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 55, alignment: .leading)
            Slider(value: value, in: range, step: 5)
                .accentColor(xrdPurple)
            Text("\(Int(value.wrappedValue))\(unit)")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(xrdCyan)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func modToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .scaleEffect(0.7)
                .tint(xrdPurple)
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
                if zoomEngine.activeMethod == .gameHook {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("Game hook actif")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.green.opacity(0.8))
                    }
                } else if zoomEngine.activeMethod == .engineHook || zoomEngine.activeMethod == .objcHook {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("Engine hook actif")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.green.opacity(0.8))
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                        Text("Zoom visuel (fallback)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.8))
                    }
                }
                Text("Pinch 2 doigts = zoom")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.6))
                Text("Double-tap 2 doigts = reset")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .sectionStyle()

            Spacer(minLength: 8)
        }
    }

    // MARK: - Config Tab

    private var configTab: some View {
        let jsStatus: String = XRDOverlay.shared.jsBridge.isConnected ? "Connected" : XRDOverlay.shared.jsBridge.statusInfo
        let zoomMethod: String = zoomEngine.activeMethod.rawValue
        let wsStatus: String = NetworkInterceptor.shared.gameWebSocket != nil ? "Captured" : "None"
        let intercepted: String = "\(NetworkInterceptor.shared.interceptedCount)"
        let licenseStatus: String = settings.isLicenseValid ? "Active" : "Inactive"

        return VStack(spacing: 8) {
            uidSection
            serverConfigSection
            configButtons
            configDebugSection(license: licenseStatus, ws: wsStatus, js: jsStatus, zoom: zoomMethod, intercepted: intercepted)
            copyDebugButton
            configVersionSection
            Spacer(minLength: 8)
        }
    }

    private var configButtons: some View {
        HStack(spacing: 6) {
            Button(action: {
                settings.save()
                showSaved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSaved = false }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.down.fill").font(.system(size: 10))
                    Text(showSaved ? "OK!" : "SAVE").font(.system(size: 9, weight: .black, design: .monospaced))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(showSaved ? Color.green.opacity(0.7) : xrdPurple)
                .cornerRadius(6)
            }

            Button(action: { settings.resetAll() }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 10))
                    Text("RESET").font(.system(size: 9, weight: .black, design: .monospaced))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.6))
                .cornerRadius(6)
            }
        }
    }

    private func configDebugSection(license: String, ws: String, js: String, zoom: String, intercepted: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionHeader("DEBUG")
            infoRow("License", license)
            infoRow("WS", ws)
            infoRow("JS", js)
            infoRow("Zoom", zoom)
            infoRow("Intercepted", intercepted)
        }
        .sectionStyle()
    }

    private var copyDebugButton: some View {
        Button(action: {
            let dump = XRDOverlay.shared.debugDump()
            UIPasteboard.general.string = dump
            debugCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { debugCopied = false }
        }) {
            HStack(spacing: 4) {
                Image(systemName: debugCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 10))
                Text(debugCopied ? "COPIED!" : "COPY DEBUG")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(debugCopied ? Color.green.opacity(0.7) : Color.orange.opacity(0.7))
            .cornerRadius(6)
        }
    }

    private var configVersionSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            infoRow("Version", "3.1")
            infoRow("Mod", "XRD Agar.io")
        }
        .sectionStyle()
    }

    // MARK: - Your UID (in Config)

    private var uidSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader("YOUR UID")
            Text("Ton ID en jeu (auto-detect via bots)")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.gray.opacity(0.5))
            HStack(spacing: 4) {
                Text("Pseudo")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 42, alignment: .leading)
                TextField("Ton nom in-game", text: $settings.playerName)
                    .textFieldStyle(XRDTextFieldStyle())
            }

            if !settings.detectedUID.isEmpty {
                HStack {
                    Text(settings.detectedUID)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(xrdCyan)
                    Spacer()
                }

                Button(action: {
                    UIPasteboard.general.string = settings.detectedUID
                    configCopiedUID = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { configCopiedUID = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: configCopiedUID ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .font(.system(size: 10))
                        Text(configCopiedUID ? "COPIED!" : "COPY UID")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(configCopiedUID ? Color.green.opacity(0.7) : xrdPurple)
                    .cornerRadius(6)
                }
            } else {
                Text("Mets ton pseudo, lance les bots = UID detect")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.7))
            }
        }
        .sectionStyle()
    }

    // MARK: - Server (in Config)

    private var serverConfigSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                sectionHeader("SERVER")
                Spacer()
                Circle()
                    .fill(NetworkInterceptor.shared.hasServer ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(NetworkInterceptor.shared.hasServer ? "AUTO" : "NONE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(NetworkInterceptor.shared.hasServer ? .green : .red)
            }
            Text("Auto-capturé quand tu joues")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.gray.opacity(0.5))

            if let url = NetworkInterceptor.shared.bestServerURL {
                Text(String(url.prefix(35)))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            if !NetworkInterceptor.shared.hasServer {
                Text("Joue une partie = serveur auto-detect")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.7))

                HStack(spacing: 4) {
                    TextField("wss://server...", text: $manualServer)
                        .textFieldStyle(XRDTextFieldStyle())
                    Button(action: {
                        if let s = UIPasteboard.general.string {
                            manualServer = s
                            NetworkInterceptor.shared.setManualServer(s)
                        }
                    }) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10))
                            .foregroundColor(xrdCyan)
                            .padding(5)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(5)
                    }
                    Button(action: {
                        guard !manualServer.isEmpty else { return }
                        NetworkInterceptor.shared.setManualServer(manualServer)
                    }) {
                        Text("SET")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(xrdPurple)
                            .cornerRadius(5)
                    }
                }
            }
        }
        .sectionStyle()
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
            Text("v3.0")
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
