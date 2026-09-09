import Foundation

enum BotAction: String, CaseIterable, Identifiable {
    case move = "Move"
    case feed = "Feed"
    case farm = "Farm"
    case makevirus = "Make Virus"
    case breakvirus = "Break Virus"
    case teamer = "Teamer"

    var id: String { rawValue }

    var serverMode: String {
        switch self {
        case .move: return "move"
        case .feed: return "feed"
        case .farm: return "farm"
        case .makevirus: return "makevirus"
        case .breakvirus: return "breakvirus"
        case .teamer: return "teamer"
        }
    }
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
    var botAction: BotAction = .feed
    var gameMode: GameMode = .classic
    var feedMacroRate: Double = 50
    var splitMacroRate: Double = 40
    var feedMacroSize: Int = 1
    var centerSelfFeed: Bool = false
    var invisibleFeed: Bool = false
    var invisibleSplit: Bool = false
    var softMacroAmount: Int = 16
    var region: String = "EU West 2"
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
