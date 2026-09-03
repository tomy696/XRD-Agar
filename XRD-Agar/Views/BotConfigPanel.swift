import SwiftUI

struct BotConfigPanel: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine
    @State private var nameInput: String = "XRD Bot"
    @State private var customNames: String = ""
    @State private var botCountStr: String = "10"

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Connection Settings
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("CONNECTION")

                fieldRow("Region") {
                    Picker("", selection: $settings.botConfig.region) {
                        ForEach(ServerRegion.allCases) { region in
                            Text(region.rawValue).tag(region)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(xrdCyan)
                }

                fieldRow("Game Mode") {
                    Picker("", selection: $settings.botConfig.gameMode) {
                        ForEach(GameMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(xrdCyan)
                }

                if settings.botConfig.gameMode == .party {
                    fieldRow("Party Code") {
                        TextField("Enter code", text: $settings.botConfig.partyCode)
                            .textFieldStyle(XRDTextFieldStyle())
                    }
                }
            }
            .sectionStyle()

            // Target Settings
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("TARGET")

                fieldRow("Target UID") {
                    HStack(spacing: 4) {
                        TextField("Paste UID", text: $settings.botConfig.targetUID)
                            .textFieldStyle(XRDTextFieldStyle())

                        Button(action: {
                            if let clip = UIPasteboard.general.string {
                                settings.botConfig.targetUID = clip
                            }
                        }) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12))
                                .foregroundColor(xrdCyan)
                                .padding(6)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }

                if let target = settings.targetPlayer {
                    HStack {
                        Text("Target:")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                        Text(target.name)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(xrdCyan)
                        Spacer()
                        Text("\(target.displayMass) mass")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .sectionStyle()

            // Bot Settings
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("BOT CONFIG")

                fieldRow("Bot Count") {
                    HStack(spacing: 8) {
                        TextField("10", text: $botCountStr)
                            .textFieldStyle(XRDTextFieldStyle())
                            .frame(width: 60)
                            .onChange(of: botCountStr) { _, val in
                                settings.botConfig.botCount = Int(val) ?? 10
                            }
                        botCountButton(5)
                        botCountButton(10)
                        botCountButton(25)
                        botCountButton(50)
                    }
                }

                fieldRow("Bot Names") {
                    TextField("Name (comma separated)", text: $nameInput)
                        .textFieldStyle(XRDTextFieldStyle())
                        .onChange(of: nameInput) { _, val in
                            settings.botConfig.botNames = val.split(separator: ",").map {
                                String($0).trimmingCharacters(in: .whitespaces)
                            }
                            if settings.botConfig.botNames.isEmpty {
                                settings.botConfig.botNames = ["XRD Bot"]
                            }
                        }
                }

                Toggle(isOn: $settings.botConfig.useRandomNames) {
                    Text("Random Names")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
                .tint(xrdPurple)

                fieldRow("Mass Boost") {
                    Picker("", selection: $settings.botConfig.massBoost) {
                        ForEach(MassBoost.allCases) { boost in
                            Text(boost.rawValue).tag(boost)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                fieldRow("Action") {
                    Picker("", selection: $settings.botConfig.botAction) {
                        ForEach(BotAction.allCases) { action in
                            Text(action.rawValue).tag(action)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(xrdCyan)
                }

                Toggle(isOn: $settings.botConfig.shouldSplit) {
                    Text("Split into target")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
                .tint(xrdPurple)
            }
            .sectionStyle()

            // Launch / Stop
            HStack(spacing: 12) {
                Button(action: launchBots) {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("LAUNCH")
                    }
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(xrdGradient)
                    .cornerRadius(10)
                }
                .disabled(botEngine.isRunning)
                .opacity(botEngine.isRunning ? 0.5 : 1)

                Button(action: { botEngine.stopBots() }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("STOP")
                    }
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(10)
                }
                .disabled(!botEngine.isRunning)
                .opacity(!botEngine.isRunning ? 0.5 : 1)
            }

            // Stats
            if botEngine.isRunning {
                HStack {
                    statPill("Spawned", "\(botEngine.totalSpawned)")
                    statPill("Alive", "\(botEngine.totalAlive)")
                    statPill("Active", "\(botEngine.activeBotCount)")
                }
            }

            Spacer(minLength: 20)
        }
    }

    // MARK: - Actions

    private func launchBots() {
        if let target = settings.targetPlayer {
            botEngine.updateTargetFromPlayer(target)
        }
        botEngine.startBots(config: settings.botConfig)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundColor(xrdCyan)
            .tracking(2)
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            content()
        }
    }

    private func botCountButton(_ count: Int) -> some View {
        let isActive = settings.botConfig.botCount == count
        let bg: Color = isActive ? xrdPurple : Color.white.opacity(0.1)
        return Button("\(count)") {
            botCountStr = "\(count)"
            settings.botConfig.botCount = count
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(bg)
        .cornerRadius(6)
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(xrdCyan)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Custom TextField Style

struct XRDTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}
