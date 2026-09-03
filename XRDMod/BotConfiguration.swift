import Foundation

enum MassBoost: String, CaseIterable, Identifiable {
    case none = "x1"
    case double = "x2"
    case triple = "x3"

    var id: String { rawValue }

    var feedCycles: Int {
        switch self {
        case .none: return 0
        case .double: return 7
        case .triple: return 14
        }
    }
}

enum BotAction: String, CaseIterable, Identifiable {
    case suicide = "Suicide"
    case feedTarget = "Feed Target"
    case destroyViruses = "Destroy Viruses"
    case createCorpses = "Create Corpses"
    case feedEverywhere = "Feed Everywhere"

    var id: String { rawValue }
}

enum GameMode: String, CaseIterable, Identifiable {
    case ffa = "FFA"
    case teams = "Teams"
    case experimental = "Experimental"
    case party = "Party"

    var id: String { rawValue }

    var serverMode: String {
        switch self {
        case .ffa: return ":ffa"
        case .teams: return ":teams"
        case .experimental: return ":experimental"
        case .party: return ":party"
        }
    }
}

enum ServerRegion: String, CaseIterable, Identifiable {
    case euLondon = "EU-London"
    case euFrankfurt = "EU-Frankfurt"
    case usEast = "US-East"
    case usWest = "US-West"
    case usAtlanta = "US-Atlanta"
    case saBrazil = "SA-Brazil"
    case asiaChina = "Asia-China"
    case asiaSingapore = "Asia-Singapore"
    case jpTokyo = "JP-Tokyo"
    case oceania = "Oceania"
    case turkeyIstanbul = "Turkey-Istanbul"
    case ruRussia = "RU-Russia"

    var id: String { rawValue }
}

struct BotConfiguration: Identifiable {
    let id = UUID()
    var botCount: Int = 10
    var botNames: [String] = ["XRD Bot"]
    var useRandomNames: Bool = false
    var massBoost: MassBoost = .none
    var region: ServerRegion = .euLondon
    var gameMode: GameMode = .ffa
    var partyCode: String = ""
    var targetUID: String = ""
    var shouldSplit: Bool = true
    var botAction: BotAction = .suicide
    var isRunning: Bool = false

    var resolvedNames: [String] {
        if useRandomNames {
            let pool = [
                "XRD", "Shadow", "Phantom", "Ghost", "Void",
                "Null", "Zero", "Byte", "Pixel", "Glitch",
                "Nano", "Flux", "Drift", "Pulse", "Echo",
                "Nyx", "Apex", "Core", "Node", "Bit"
            ]
            return (0..<botCount).map { _ in pool.randomElement()! }
        }
        return (0..<botCount).map { i in
            botNames[i % botNames.count]
        }
    }
}
