import SwiftUI

struct BotConfigPanel: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine
    @State private var nameInput: String = "XRD Bot"
    @State private var botCountStr: String = "10"

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                sectionHeader("CONNECTION")

                fieldRow("Region") {
                    Picker("", selection: $settings.botConfig.region) {
                        ForEach(ServerRegion.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(xrdCyan)
                }

                fieldRow("Mode") {
                    Picker("", selection: $settings.botConfig.gameMode) {
                        ForEach(GameMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(xrdCyan)
                }

                if settings.botConfig.gameMode == .party {
                    fieldRow("Party") {
                        TextField("Code", text: $settings.botConfig.partyCode)
                            .textFieldStyle(XRDTextFieldStyle())
                    }
                }
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 5) {
                sectionHeader("TARGET")

                fieldRow("Auto") {
                    Picker("", selection: $settings.botConfig.autoTarget) {
                        ForEach(AutoTarget.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(xrdCyan)
                }

                fieldRow("UID") {
                    HStack(spacing: 4) {
                        TextField("Paste UID", text: $settings.botConfig.targetUID)
                            .textFieldStyle(XRDTextFieldStyle())

                        Button(action: {
                            if let s = UIPasteboard.general.string {
                                settings.botConfig.targetUID = s
                            }
                        }) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 10))
                                .foregroundColor(xrdCyan)
                                .padding(5)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(5)
                        }
                    }
                }

                if let target = settings.targetPlayer {
                    HStack {
                        Text(target.name)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(xrdCyan)
                        Spacer()
                        Text("\(target.displayMass)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .sectionStyle()

            VStack(alignment: .leading, spacing: 5) {
                sectionHeader("BOTS")

                fieldRow("Count") {
                    HStack(spacing: 4) {
                        TextField("10", text: $botCountStr)
                            .textFieldStyle(XRDTextFieldStyle())
                            .frame(width: 40)
                            .onChange(of: botCountStr) { v in
                                settings.botConfig.botCount = Int(v) ?? 10
                            }
                        ForEach([5, 10, 25, 50], id: \.self) { n in
                            cntBtn(n)
                        }
                    }
                }

                fieldRow("Names") {
                    TextField("Comma sep.", text: $nameInput)
                        .textFieldStyle(XRDTextFieldStyle())
                        .onChange(of: nameInput) { v in
                            settings.botConfig.botNames = v.split(separator: ",")
                                .map { String($0).trimmingCharacters(in: .whitespaces) }
                            if settings.botConfig.botNames.isEmpty {
                                settings.botConfig.botNames = ["XRD Bot"]
                            }
                        }
                }

                Toggle(isOn: $settings.botConfig.useRandomNames) {
                    Text("Random")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
                .tint(xrdPurple)

                fieldRow("Boost") {
                    Picker("", selection: $settings.botConfig.massBoost) {
                        ForEach(MassBoost.allCases) { b in
                            Text(b.rawValue).tag(b)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                fieldRow("Action") {
                    Picker("", selection: $settings.botConfig.botAction) {
                        ForEach(BotAction.allCases) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(xrdCyan)
                }

                Toggle(isOn: $settings.botConfig.shouldSplit) {
                    Text("Split into target")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
                .tint(xrdPurple)
            }
            .sectionStyle()

            HStack(spacing: 8) {
                Button(action: launchBots) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text("LAUNCH")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(xrdGradient)
                    .cornerRadius(8)
                }
                .disabled(botEngine.isRunning)
                .opacity(botEngine.isRunning ? 0.5 : 1)

                Button(action: { botEngine.stopBots() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                        Text("STOP")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
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

            if botEngine.isRunning {
                HStack {
                    statPill("Spawned", "\(botEngine.totalSpawned)")
                    statPill("Alive", "\(botEngine.totalAlive)")
                    statPill("Active", "\(botEngine.activeBotCount)")
                }
            }

            Spacer(minLength: 8)
        }
    }

    // MARK: - Actions

    private func launchBots() {
        if let t = settings.targetPlayer {
            botEngine.updateTargetFromPlayer(t)
        }
        botEngine.startBots(config: settings.botConfig)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundColor(xrdCyan)
            .tracking(1.5)
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            content()
        }
    }

    private func cntBtn(_ count: Int) -> some View {
        let isActive = settings.botConfig.botCount == count
        return Button("\(count)") {
            botCountStr = "\(count)"
            settings.botConfig.botCount = count
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isActive ? xrdPurple : Color.white.opacity(0.1))
        .cornerRadius(5)
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
