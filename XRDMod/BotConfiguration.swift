import Foundation

enum BotAction: String, CaseIterable, Identifiable {
    case followPlayer = "Follow Player"
    case makeVirus = "Make Virus"
    case breakVirus = "Break Virus"
    case feedLeave = "Feed-leave"
    case smartAFK = "Smart AFK"

    var id: String { rawValue }
}

enum GameMode: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case teams = "Teams"
    case experimental = "Experimental"

    var id: String { rawValue }

    var serverCode: String {
        switch self {
        case .classic: return ":ffa"
        case .teams: return ":teams"
        case .experimental: return ":experimental"
        }
    }
}

struct BotConfiguration {
    var botCount: Int = 50
    var botNames: [String] = [""]
    var botSkin: String = ""
    var partyCode: String = ""
    var targetUIDs: [String] = [""]
    var botAction: BotAction = .followPlayer
    var gameMode: GameMode = .classic
    var feedMacroRate: Double = 50
    var splitMacroRate: Double = 40
    var feedMacroSize: Int = 1
    var centerSelfFeed: Bool = false
    var invisibleFeed: Bool = false
    var invisibleSplit: Bool = false
    var softMacroAmount: Int = 16
    var region: String = "EU-London"
    var botKey: String = ""
    var tripleMass: Bool = true
    var boosterMode: Bool = true
    var feedtrackMode: Bool = false

    var resolvedNames: [String] {
        let name = botNames.first(where: { !$0.isEmpty }) ?? ""
        return (0..<botCount).map { _ in name }
    }

    var feedInterval: TimeInterval {
        max(0.02, 1.0 / feedMacroRate)
    }

    var splitInterval: TimeInterval {
        max(0.02, 1.0 / splitMacroRate)
    }
}
