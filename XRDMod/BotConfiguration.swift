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

    var resolvedNames: [String] {
        (0..<botCount).map { i in
            botNames[i % botNames.count]
        }
    }
}
