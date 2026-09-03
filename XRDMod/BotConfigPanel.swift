import SwiftUI

struct BotConfigPanel: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine
    @State private var nameInput: String = "XRD Bot"
    @State private var botCountStr: String = "10"
    @State private var groupCode: String = ""

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 8) {
            // GROUP CODE
            VStack(alignment: .leading, spacing: 5) {
                sectionHeader("GROUP CODE")
                Text("Enter your agar.io party code so bots join your game")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
                HStack(spacing: 4) {
                    TextField("Party code", text: $groupCode)
                        .textFieldStyle(XRDTextFieldStyle())
                    Button(action: {
                        if let s = UIPasteboard.general.string { groupCode = s }
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
            .sectionStyle()

            // TARGET UID
            VStack(alignment: .leading, spacing: 5) {
                sectionHeader("TARGET UID")
                Text("Bots will move toward this player")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
                HStack(spacing: 4) {
                    TextField("Player UID", text: $settings.botConfig.targetUID)
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
            .sectionStyle()

            // BOT SETTINGS
            VStack(alignment: .leading, spacing: 5) {
                sectionHeader("BOTS")

                fieldRow("Count") {
                    HStack(spacing: 3) {
                        ForEach([5, 10, 25, 50], id: \.self) { n in cntBtn(n) }
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

                XRDDropdown(label: "Action", selection: $settings.botConfig.botAction)
            }
            .sectionStyle()

            // LAUNCH / STOP
            HStack(spacing: 8) {
                Button(action: launchBots) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").font(.system(size: 10))
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
                        Image(systemName: "stop.fill").font(.system(size: 10))
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
                }
            }

            Spacer(minLength: 8)
        }
    }

    // MARK: - Actions

    private func launchBots() {
        settings.botConfig.partyCode = groupCode
        settings.botConfig.gameMode = groupCode.isEmpty ? .classic : .party
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
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 38, alignment: .leading)
            content()
        }
    }

    private func cntBtn(_ count: Int) -> some View {
        let isActive = settings.botConfig.botCount == count
        return Button("\(count)") {
            botCountStr = "\(count)"
            settings.botConfig.botCount = count
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
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

// MARK: - Custom Dropdown (no rotation bug)

struct XRDDropdown<T: CaseIterable & RawRepresentable & Hashable>: View where T.RawValue == String, T.AllCases == [T] {
    let label: String
    @Binding var selection: T
    @State private var isExpanded = false

    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }) {
                HStack {
                    Text(label)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(width: 42, alignment: .leading)
                    Text(selection.rawValue)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(xrdCyan)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            }

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(T.allCases), id: \.self) { option in
                        Button(action: {
                            selection = option
                            withAnimation(.easeInOut(duration: 0.15)) { isExpanded = false }
                        }) {
                            HStack {
                                Text(option.rawValue)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(option == selection ? xrdCyan : .white.opacity(0.7))
                                Spacer()
                                if option == selection {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(xrdCyan)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(option == selection ? Color.white.opacity(0.06) : Color.clear)
                        }
                    }
                }
                .background(Color.black.opacity(0.95))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.top, 2)
            }
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
