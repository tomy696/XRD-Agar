import SwiftUI

struct BotConfigPanel: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine

    @State private var hideKey: Bool = true
    @State private var keyStatus: String = ""
    @State private var isVerifying: Bool = false

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var darkBg: Color { Color.white.opacity(0.06) }
    private var sectionBg: Color { Color.white.opacity(0.04) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                skinKeySection
                botSettingsSection
                botModeSection
                botSetupSection
                actionButtons
                if botEngine.isRunning { botStats }
                if !botEngine.client.activePartyCode.isEmpty { partyCodeBanner }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Skin Key

    private var skinKeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("SKIN KEY")

            HStack(spacing: 4) {
                if hideKey {
                    SecureField("Bot Key...", text: $settings.botConfig.botKey)
                        .textFieldStyle(XRDTextFieldStyle())
                } else {
                    TextField("Bot Key...", text: $settings.botConfig.botKey)
                        .textFieldStyle(XRDTextFieldStyle())
                }
                Button("Verify") {
                    verifyKey()
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(xrdCyan)
                .cornerRadius(5)
                .disabled(isVerifying)
            }

            if !keyStatus.isEmpty {
                Text(keyStatus)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(keyStatus.contains("Valid") ? .green : .red)
            }

            HStack(spacing: 8) {
                Toggle(isOn: $hideKey) {
                    Text("Hide Secret Key")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .toggleStyle(XRDCheckboxStyle())
            }
        }
        .sectionStyle()
    }

    // MARK: - Bot Settings

    private var botSettingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("BOT SETTINGS")

            // Region
            VStack(alignment: .leading, spacing: 3) {
                Text("Region")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                let regions = [
                    "EU West 2", "EU West 3", "EU Central 1",
                    "US East 1", "US East 2", "US West 1",
                    "AP South 1", "AP Southeast 1", "AP Northeast 1",
                    "ME South 1", "SA East 1"
                ]
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                    ForEach(regions, id: \.self) { r in
                        Button(action: { settings.botConfig.region = r }) {
                            Text(r)
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(settings.botConfig.region == r ? xrdPurple : darkBg)
                                .cornerRadius(4)
                        }
                    }
                }
            }

            // Game Mode
            VStack(alignment: .leading, spacing: 3) {
                Text("Game Mode")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                HStack(spacing: 3) {
                    ForEach(GameMode.allCases) { mode in
                        Button(action: { settings.botConfig.gameMode = mode }) {
                            Text(mode.rawValue)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(settings.botConfig.gameMode == mode ? xrdPurple : darkBg)
                                .cornerRadius(4)
                        }
                    }
                }
            }

            // Bot Name
            VStack(alignment: .leading, spacing: 3) {
                Text("Bot Name")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                TextField("Bot name...", text: Binding(
                    get: { settings.botConfig.botNames.first ?? "" },
                    set: { settings.botConfig.botNames = [$0] }
                ))
                .textFieldStyle(XRDTextFieldStyle())
            }

            // Party Code
            VStack(alignment: .leading, spacing: 3) {
                Text("Party Code")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                HStack(spacing: 4) {
                    TextField("Party code...", text: $settings.botConfig.partyCode)
                        .textFieldStyle(XRDTextFieldStyle())
                    Button(action: {
                        if let s = UIPasteboard.general.string {
                            settings.botConfig.partyCode = s
                        }
                    }) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10))
                            .foregroundColor(xrdCyan)
                            .padding(5)
                            .background(darkBg)
                            .cornerRadius(5)
                    }
                }
            }
        }
        .sectionStyle()
    }

    // MARK: - Bot Mode

    private var botModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("BOT MODE")

            // Mode buttons
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                ForEach(BotAction.allCases) { action in
                    Button(action: { settings.botConfig.botAction = action }) {
                        Text(action.rawValue)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(settings.botConfig.botAction == action ? xrdPurple : darkBg)
                            .cornerRadius(4)
                    }
                }
            }

            // Target UID
            VStack(alignment: .leading, spacing: 3) {
                Text("Target UID")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                TextField("UID...", text: Binding(
                    get: { settings.botConfig.targetUIDs.first ?? "" },
                    set: { settings.botConfig.targetUIDs = [$0] }
                ))
                .textFieldStyle(XRDTextFieldStyle())
            }

            // Options
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $settings.botConfig.tripleMass) {
                    Text("3x Mass Bots")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white)
                }
                .toggleStyle(XRDCheckboxStyle())

                Toggle(isOn: $settings.botConfig.boosterMode) {
                    Text("Booster Mode")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white)
                }
                .toggleStyle(XRDCheckboxStyle())

                Toggle(isOn: $settings.botConfig.feedtrackMode) {
                    Text("Start Feedtrack Mode")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white)
                }
                .toggleStyle(XRDCheckboxStyle())
            }
        }
        .sectionStyle()
    }

    // MARK: - Bot Setup

    private var botSetupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("BOT SETUP")

            // Bot Count
            VStack(alignment: .leading, spacing: 3) {
                Text("Bot Count: \(settings.botConfig.botCount)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                HStack(spacing: 3) {
                    ForEach([5, 10, 25, 50], id: \.self) { n in
                        Button("\(n)") {
                            settings.botConfig.botCount = n
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(settings.botConfig.botCount == n ? xrdPurple : darkBg)
                        .cornerRadius(5)
                    }
                }
            }

            // Bot Skin
            VStack(alignment: .leading, spacing: 3) {
                Text("Bot Skin")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                TextField("Skin name...", text: $settings.botConfig.botSkin)
                    .textFieldStyle(XRDTextFieldStyle())
            }
        }
        .sectionStyle()
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button(action: { botEngine.startBots(config: settings.botConfig) }) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text("Start Bots").font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(8)
                }
                .disabled(botEngine.isRunning)
                .opacity(botEngine.isRunning ? 0.5 : 1)

                Button(action: { botEngine.stopBots() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill").font(.system(size: 10))
                        Text("Stop Bots").font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                }
                .disabled(!botEngine.isRunning)
                .opacity(!botEngine.isRunning ? 0.5 : 1)
            }

            Text(botEngine.statusMessage)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(botEngine.isRunning ? xrdCyan : .gray)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Bot Stats

    private var botStats: some View {
        HStack {
            statPill("Total", "\(botEngine.totalSpawned)")
            statPill("Alive", "\(botEngine.totalAlive)")
        }
    }

    // MARK: - Party Code Banner

    private var partyCodeBanner: some View {
        VStack(spacing: 4) {
            Text("JOIN THIS PARTY")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.green)
                .tracking(1.5)
            Text(botEngine.client.activePartyCode)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundColor(.white)
            Button(action: {
                UIPasteboard.general.string = botEngine.client.activePartyCode
            }) {
                Text("COPY CODE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(xrdCyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func verifyKey() {
        guard !settings.botConfig.botKey.isEmpty else {
            keyStatus = "Enter a key first"
            return
        }
        isVerifying = true
        keyStatus = "Verifying..."
        botEngine.client.validateKey(settings.botConfig.botKey) { valid, maxBots in
            DispatchQueue.main.async {
                isVerifying = false
                if valid {
                    keyStatus = "Valid! Max \(maxBots ?? 50) bots"
                } else {
                    keyStatus = "Invalid or expired key"
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundColor(xrdCyan)
            .tracking(1.5)
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(xrdCyan)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.05))
        .cornerRadius(6)
    }
}

// MARK: - Checkbox Toggle Style

struct XRDCheckboxStyle: ToggleStyle {
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 12))
                .foregroundColor(configuration.isOn ? xrdCyan : .gray)
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}

// MARK: - Custom TextField Style

struct XRDTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}
