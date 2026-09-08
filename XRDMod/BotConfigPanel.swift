import SwiftUI

struct BotConfigPanel: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 8) {
            launchButtons
            if botEngine.isRunning { botStats }
            regionSection
            botCountSection
            partySection
            botKeySection
            Spacer(minLength: 8)
        }
    }

    // MARK: - Launch / Pause / Stop

    private var launchButtons: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button(action: { botEngine.startBots(config: settings.botConfig) }) {
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
        }
    }

    // MARK: - Region

    private var regionSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader("REGION")
            let regions = [
                "EU-London", "US-Atlanta", "US-Dallas", "US-San Jose",
                "East Asia", "South America", "China", "Oceania", "Turkey", "Russia"
            ]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                ForEach(regions, id: \.self) { r in
                    Button(action: { settings.botConfig.region = r }) {
                        Text(r)
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

    // MARK: - Bot Count

    private var botCountSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader("BOTS")
            HStack(spacing: 3) {
                ForEach([5, 10, 25, 50], id: \.self) { n in
                    Button("\(n)") {
                        settings.botConfig.botCount = n
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(settings.botConfig.botCount == n ? xrdPurple : Color.white.opacity(0.1))
                    .cornerRadius(5)
                }
            }
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

    // MARK: - Bot Key

    private var botKeySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader("BOT KEY")
            HStack(spacing: 4) {
                TextField("XRD-XXXX...", text: $settings.botConfig.botKey)
                    .textFieldStyle(XRDTextFieldStyle())
                Button(action: {
                    if let s = UIPasteboard.general.string {
                        settings.botConfig.botKey = s
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

    // MARK: - Helpers

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

// MARK: - Custom Dropdown

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
