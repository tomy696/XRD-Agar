import Foundation

enum BotAction: String, CaseIterable, Identifiable {
    case feedTarget = "Feed Target"
    case suicide = "Suicide"
    case feedEverywhere = "Feed All"

    var id: String { rawValue }
}

struct BotConfiguration {
    var botCount: Int = 10
    var botNames: [String] = ["XRD Bot"]
    var partyCode: String = ""
    var targetUID: String = ""
    var botAction: BotAction = .feedTarget
    var feedMacroRate: Double = 50
    var splitMacroRate: Double = 40
    var feedMacroSize: Int = 1
    var centerSelfFeed: Bool = false
    var region: String = "EU-London"

    var resolvedNames: [String] {
        (0..<botCount).map { i in
            botNames[i % botNames.count]
        }
    }

    var feedInterval: TimeInterval {
        max(0.02, 1.0 / feedMacroRate)
    }

    var splitInterval: TimeInterval {
        max(0.02, 1.0 / splitMacroRate)
    }
}
