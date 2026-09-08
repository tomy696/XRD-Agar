import Foundation
import SwiftUI

class GameSettings: ObservableObject {
    @Published var isMacroEnabled: Bool = false
    @Published var macroPower: Double = 5
    @Published var macroButtonSize: Double = 50
    @Published var playerName: String = ""
    @Published var detectedUID: String = ""
    @Published var isLicenseValid: Bool = false
    @Published var botConfig: BotConfiguration = BotConfiguration()

    @Published var currentPlayers: [PlayerInfo] = []
    @Published var targetPlayer: PlayerInfo? = nil
    @Published var ownCellIDs: [UInt32] = []
    @Published var worldBorder: WorldBorder = .default

    private let defaults = UserDefaults.standard
    private let prefix = "XRD_"

    var feedInterval: TimeInterval {
        max(0.015, 0.20 - macroPower * 0.02)
    }

    var ownMass: Int {
        currentPlayers
            .filter { ownCellIDs.contains($0.id) }
            .map(\.displayMass)
            .reduce(0, +)
    }

    func save() {
        defaults.set(isMacroEnabled, forKey: k("macroEnabled"))
        defaults.set(macroPower, forKey: k("macroPower"))
        defaults.set(macroButtonSize, forKey: k("macroSize"))
        defaults.set(playerName, forKey: k("playerName"))
        defaults.set(botConfig.botCount, forKey: k("botCount"))
        defaults.set(botConfig.botNames, forKey: k("botNames"))
        defaults.set(botConfig.partyCode, forKey: k("partyCode"))
        defaults.set(botConfig.targetUID, forKey: k("targetUID"))
        defaults.set(botConfig.botAction.rawValue, forKey: k("botAction"))
        defaults.set(botConfig.feedMacroRate, forKey: k("feedMacroRate"))
        defaults.set(botConfig.splitMacroRate, forKey: k("splitMacroRate"))
        defaults.set(botConfig.feedMacroSize, forKey: k("feedMacroSize"))
        defaults.set(botConfig.centerSelfFeed, forKey: k("centerSelfFeed"))
        defaults.set(botConfig.region, forKey: k("region"))
        defaults.synchronize()
    }

    func load() {
        guard defaults.object(forKey: k("macroEnabled")) != nil else { return }
        isMacroEnabled = defaults.bool(forKey: k("macroEnabled"))
        macroPower = defaults.double(forKey: k("macroPower"))
        if macroPower < 1 { macroPower = 5 }
        macroButtonSize = defaults.double(forKey: k("macroSize"))
        if macroButtonSize < 30 { macroButtonSize = 50 }
        playerName = defaults.string(forKey: k("playerName")) ?? ""
        botConfig.botCount = defaults.integer(forKey: k("botCount"))
        if botConfig.botCount == 0 { botConfig.botCount = 10 }
        if let names = defaults.stringArray(forKey: k("botNames")), !names.isEmpty {
            botConfig.botNames = names
        }
        botConfig.partyCode = defaults.string(forKey: k("partyCode")) ?? ""
        botConfig.targetUID = defaults.string(forKey: k("targetUID")) ?? ""
        if let raw = defaults.string(forKey: k("botAction")), let v = BotAction(rawValue: raw) {
            botConfig.botAction = v
        }
        let fr = defaults.double(forKey: k("feedMacroRate"))
        botConfig.feedMacroRate = fr > 0 ? fr : 50
        let sr = defaults.double(forKey: k("splitMacroRate"))
        botConfig.splitMacroRate = sr > 0 ? sr : 40
        let fs = defaults.integer(forKey: k("feedMacroSize"))
        botConfig.feedMacroSize = fs > 0 ? fs : 1
        botConfig.centerSelfFeed = defaults.bool(forKey: k("centerSelfFeed"))
        botConfig.region = defaults.string(forKey: k("region")) ?? "EU-London"
    }

    func resetAll() {
        isMacroEnabled = false
        macroPower = 5
        macroButtonSize = 50
        playerName = ""
        botConfig = BotConfiguration()
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.synchronize()
    }

    private func k(_ name: String) -> String { prefix + name }
}
