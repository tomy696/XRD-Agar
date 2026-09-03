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
    case destroyViruses = "Destroy Virus"
    case createCorpses = "Corpses"
    case feedEverywhere = "Feed All"

    var id: String { rawValue }
}

enum GameMode: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case burst = "Burst"
    case teams = "Teams"
    case experimental = "Experimental"
    case party = "Party"

    var id: String { rawValue }

    var serverMode: String {
        switch self {
        case .classic: return ":ffa"
        case .burst: return ":rush"
        case .teams: return ":teams"
        case .experimental: return ":experimental"
        case .party: return ":party"
        }
    }
}

enum AutoTarget: String, CaseIterable, Identifiable {
    case off = "Off"
    case nearest = "Nearest"
    case biggest = "Biggest"
    case smallest = "Smallest"

    var id: String { rawValue }
}

enum ServerRegion: String, CaseIterable, Identifiable {
    case usEast = "US East"
    case usWest = "US West"
    case euWest = "EU West"
    case southAmerica = "South America"
    case russia = "Russia"
    case eastAsia = "East Asia"
    case china = "China"
    case japan = "Japan"
    case oceania = "Oceania"
    case turkey = "Turkey"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .usEast: return "US-Atlanta"
        case .usWest: return "US-Fremont"
        case .euWest: return "EU-London"
        case .southAmerica: return "BR-Brazil"
        case .russia: return "RU-Russia"
        case .eastAsia: return "SG-Singapore"
        case .china: return "CN-China"
        case .japan: return "JP-Tokyo"
        case .oceania: return "Oceania"
        case .turkey: return "TR-Turkey"
        }
    }
}

struct BotConfiguration: Identifiable {
    let id = UUID()
    var botCount: Int = 10
    var botNames: [String] = ["XRD Bot"]
    var useRandomNames: Bool = false
    var massBoost: MassBoost = .none
    var region: ServerRegion = .euWest
    var gameMode: GameMode = .classic
    var partyCode: String = ""
    var targetUID: String = ""
    var shouldSplit: Bool = true
    var botAction: BotAction = .suicide
    var autoTarget: AutoTarget = .off
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
