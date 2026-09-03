import SwiftUI

struct PlayerListView: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine
    @State private var searchText: String = ""

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }
    private var xrdGradient: LinearGradient {
        LinearGradient(colors: [xrdPurple, xrdCyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var filteredPlayers: [PlayerInfo] {
        let players = settings.currentPlayers
            .filter { !settings.ownCellIDs.contains($0.id) }
            .sorted { $0.mass > $1.mass }

        if searchText.isEmpty { return players }
        return players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.uid.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))
                TextField("Search player or UID...", text: $searchText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)

            // Header
            HStack {
                Text("NAME")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("MASS")
                    .frame(width: 50, alignment: .trailing)
                Text("UID")
                    .frame(width: 70, alignment: .trailing)
                Text("")
                    .frame(width: 30)
            }
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundColor(.gray)
            .padding(.horizontal, 8)

            // Player List
            if filteredPlayers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No players found")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(filteredPlayers.prefix(20)) { player in
                    playerRow(player)
                }
            }

            // Current Target
            if let target = settings.targetPlayer {
                VStack(spacing: 6) {
                    HStack {
                        Text("CURRENT TARGET")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(xrdCyan)
                            .tracking(2)
                        Spacer()
                        Button(action: {
                            settings.targetPlayer = nil
                            settings.botConfig.targetUID = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.name)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("UID: \(target.uid)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Text("\(target.displayMass)")
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundStyle(xrdGradient)
                    }
                }
                .padding(10)
                .background(xrdPurple.opacity(0.15))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(xrdPurple.opacity(0.4), lineWidth: 1)
                )
            }

            Spacer(minLength: 20)
        }
    }

    private func playerRow(_ player: PlayerInfo) -> some View {
        let isTarget = settings.targetPlayer?.id == player.id

        return HStack(spacing: 6) {
            Text(player.name.isEmpty ? "???" : player.name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(isTarget ? xrdCyan : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(player.displayMass)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 50, alignment: .trailing)

            Button(action: {
                UIPasteboard.general.string = player.uid
            }) {
                Text(String(player.uid.prefix(6)))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(xrdCyan.opacity(0.8))
                    .frame(width: 70, alignment: .trailing)
            }

            Button(action: {
                settings.targetPlayer = player
                settings.botConfig.targetUID = player.uid
                botEngine.updateTargetFromPlayer(player)
            }) {
                Image(systemName: isTarget ? "target" : "scope")
                    .font(.system(size: 14))
                    .foregroundColor(isTarget ? xrdCyan : .gray)
            }
            .frame(width: 30)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isTarget ? xrdPurple.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}
