import SwiftUI

struct PlayerListView: View {
    @ObservedObject var settings: GameSettings
    @ObservedObject var botEngine: BotEngine

    private var xrdPurple: Color { Color(red: 0.459, green: 0.318, blue: 0.957) }
    private var xrdCyan: Color { Color(red: 0.2, green: 0.8, blue: 0.9) }

    private var filteredPlayers: [PlayerInfo] {
        settings.currentPlayers
            .filter { !settings.ownCellIDs.contains($0.id) }
            .sorted { $0.mass > $1.mass }
    }

    var body: some View {
        VStack(spacing: 6) {
            if filteredPlayers.isEmpty {
                Text("No players")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
            } else {
                ForEach(filteredPlayers.prefix(15)) { player in
                    HStack {
                        Text(player.name.isEmpty ? "???" : player.name)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(player.displayMass)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Button(action: {
                            settings.botConfig.targetUID = player.uid
                            settings.targetPlayer = player
                            botEngine.updateTarget(x: Double(player.x), y: Double(player.y))
                        }) {
                            Image(systemName: settings.targetPlayer?.id == player.id ? "target" : "scope")
                                .font(.system(size: 12))
                                .foregroundColor(settings.targetPlayer?.id == player.id ? xrdCyan : .gray)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
            }
        }
    }
}
