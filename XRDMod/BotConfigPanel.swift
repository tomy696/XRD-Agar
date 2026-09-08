import SwiftUI

struct BotConfigPanel: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine
    @State private var nameInput: String = ""
    @State private var copiedUID: String = ""
    @State private var didInit = false

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 8) {
            launchButtons
            if botEngine.isRunning { botStats }
            partySection
            regionSection
            playerList
            targetSection
            botSettings
            Spacer(minLength: 8)
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            nameInput = settings.botConfig.botNames.joined(separator: ", ")
        }
    }

    // MARK: - Launch / Pause / Stop (TOP)

    private var launchButtons: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button(action: launchBots) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").font(.system(size: 10))
                        Text("LAUNCH").font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(xrdGradient)
                    .cornerRadius(8)
                }
                .disabled(botEngine.isRunning)
                .opacity(botEngine.isRunning ? 0.5 : 1)

                Button(action: {
                    if botEngine.isPaused { botEngine.resumeBots() }
                    else { botEngine.pauseBots() }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: botEngine.isPaused ? "play.fill" : "pause.fill").font(.system(size: 10))
                        Text(botEngine.isPaused ? "RESUME" : "PAUSE").font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(botEngine.isPaused ? Color.green.opacity(0.7) : Color.orange.opacity(0.8))
                    .cornerRadius(8)
                }
                .disabled(!botEngine.isRunning)
                .opacity(!botEngine.isRunning ? 0.5 : 1)

                Button(action: { botEngine.stopBots() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill").font(.system(size: 10))
                        Text("STOP").font(.system(size: 10, weight: .black, design: .monospaced))
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

    private var botStats: some View {
        HStack {
            statPill("Total", "\(botEngine.totalSpawned)")
            statPill("Alive", "\(botEngine.totalAlive)")
            if botEngine.isPaused {
                statPill("Status", "PAUSED")
            }
        }
    }

    // MARK: - Player List (grab UID)

    @ViewBuilder
    private var playerList: some View {
        let players = settings.currentPlayers
            .filter { !settings.ownCellIDs.contains($0.id) && !$0.name.isEmpty }
            .sorted { $0.mass > $1.mass }

        if !players.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("PLAYERS (\(players.count))")

                ForEach(players.prefix(15)) { player in
                    HStack(spacing: 4) {
                        Text(player.name)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(player.displayMass)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                            .frame(width: 30, alignment: .trailing)

                        Button(action: {
                            UIPasteboard.general.string = player.uid
                            copiedUID = player.uid
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedUID = "" }
                        }) {
                            Text(copiedUID == player.uid ? "OK!" : String(player.uid.prefix(6)))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(copiedUID == player.uid ? .green : xrdCyan)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(3)
                        }

                        Button(action: {
                            settings.botConfig.targetUID = player.uid
                            settings.targetPlayer = player
                            botEngine.updateTarget(x: player.x, y: player.y)
                        }) {
                            Image(systemName: settings.targetPlayer?.id == player.id ? "target" : "scope")
                                .font(.system(size: 11))
                                .foregroundColor(settings.targetPlayer?.id == player.id ? xrdCyan : .gray)
                        }
                        .frame(width: 20)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(settings.targetPlayer?.id == player.id ? xrdPurple.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                }
            }
            .sectionStyle()
        } else if botEngine.isRunning {
            VStack(alignment: .leading, spacing: 3) {
                sectionHeader("PLAYERS")
                Text("Waiting for world data...")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .sectionStyle()
        }
    }

    // MARK: - Target

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader("TARGET")
            HStack(spacing: 4) {
                TextField("UID or name", text: $settings.botConfig.targetUID)
                    .textFieldStyle(XRDTextFieldStyle())
                Button(action: {
                    if let s = UIPasteboard.general.string { settings.botConfig.targetUID = s }
                }) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10))
                        .foregroundColor(xrdCyan)
                        .padding(5)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(5)
                }
            }

            serverStatus
        }
        .sectionStyle()
    }

    private var serverStatus: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(NetworkInterceptor.shared.hasServer ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(NetworkInterceptor.shared.hasServer ? "Server detected" : "Play a game first")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(NetworkInterceptor.shared.hasServer ? .green.opacity(0.8) : .red.opacity(0.8))
            Spacer()
        }
    }

    // MARK: - Bot Settings

    private var botSettings: some View {
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
    }

    // MARK: - Party Code

    private var partySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader("PARTY CODE")
            Text("Bots join your party server")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.gray.opacity(0.5))
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
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(5)
                }
            }
        }
        .sectionStyle()
    }

    // MARK: - Region Selector

    private var regionSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader("REGION")
            let regions = ["EU-London", "US-Atlanta", "US-Dallas", "US-San Jose",
                           "East Asia", "South America", "China", "Oceania", "Turkey", "Russia"]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                ForEach(regions, id: \.self) { r in
                    Button(action: { settings.botConfig.region = r }) {
                        Text(r.replacingOccurrences(of: "US-", with: "").prefix(10))
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(settings.botConfig.region == r ? xrdPurple : Color.white.opacity(0.08))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .sectionStyle()
    }

    // MARK: - Actions

    private func launchBots() {
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
