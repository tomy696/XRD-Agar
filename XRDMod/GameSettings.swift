import Foundation
import SwiftUI

class GameSettings: ObservableObject {
    @Published var zoomLevel: Double = 1.0
    @Published var isAutoFeeding: Bool = false
    @Published var isMacroActive: Bool = false
    @Published var isMacroEnabled: Bool = false
    @Published var macroDragMode: Bool = false
    @Published var macroButtonSize: Double = 50
    @Published var isMenuVisible: Bool = false
    @Published var currentPlayers: [PlayerInfo] = []
    @Published var targetPlayer: PlayerInfo? = nil
    @Published var ownCellIDs: [UInt32] = []
    @Published var serverURL: String = ""
    @Published var isConnected: Bool = false
    @Published var worldBorder: WorldBorder = .default
    @Published var licenseKey: String = ""
    @Published var isLicenseValid: Bool = false
    @Published var botConfig: BotConfiguration = BotConfiguration()
    @Published var playerName: String = ""
    @Published var detectedUID: String = ""

    private let defaults = UserDefaults.standard
    private let prefix = "XRD_"

    var ownPosition: (x: Double, y: Double)? {
        let ownCells = currentPlayers.filter { ownCellIDs.contains($0.id) }
        guard !ownCells.isEmpty else { return nil }
        let avgX = ownCells.map(\.x).reduce(0, +) / Double(ownCells.count)
        let avgY = ownCells.map(\.y).reduce(0, +) / Double(ownCells.count)
        return (avgX, avgY)
    }

    var ownMass: Int {
        currentPlayers
            .filter { ownCellIDs.contains($0.id) }
            .map(\.displayMass)
            .reduce(0, +)
    }

    func save() {
        defaults.set(zoomLevel, forKey: k("zoom"))
        defaults.set(isMacroEnabled, forKey: k("macroEnabled"))
        defaults.set(macroDragMode, forKey: k("macroDrag"))
        defaults.set(macroButtonSize, forKey: k("macroSize"))
        defaults.set(playerName, forKey: k("playerName"))

        defaults.set(botConfig.botCount, forKey: k("botCount"))
        defaults.set(botConfig.botNames, forKey: k("botNames"))
        defaults.set(botConfig.useRandomNames, forKey: k("randomNames"))
        defaults.set(botConfig.massBoost.rawValue, forKey: k("massBoost"))
        defaults.set(botConfig.region.rawValue, forKey: k("region"))
        defaults.set(botConfig.gameMode.rawValue, forKey: k("gameMode"))
        defaults.set(botConfig.partyCode, forKey: k("partyCode"))
        defaults.set(botConfig.targetUID, forKey: k("targetUID"))
        defaults.set(botConfig.shouldSplit, forKey: k("shouldSplit"))
        defaults.set(botConfig.botAction.rawValue, forKey: k("botAction"))

        defaults.synchronize()
    }

    func load() {
        guard defaults.object(forKey: k("zoom")) != nil else { return }

        zoomLevel = defaults.double(forKey: k("zoom"))
        if zoomLevel == 0 { zoomLevel = 1.0 }
        isMacroEnabled = defaults.bool(forKey: k("macroEnabled"))
        macroDragMode = defaults.bool(forKey: k("macroDrag"))
        macroButtonSize = defaults.double(forKey: k("macroSize"))
        if macroButtonSize < 30 { macroButtonSize = 50 }
        playerName = defaults.string(forKey: k("playerName")) ?? ""

        botConfig.botCount = defaults.integer(forKey: k("botCount"))
        if botConfig.botCount == 0 { botConfig.botCount = 10 }
        if let names = defaults.stringArray(forKey: k("botNames")), !names.isEmpty {
            botConfig.botNames = names
        }
        botConfig.useRandomNames = defaults.bool(forKey: k("randomNames"))
        if let raw = defaults.string(forKey: k("massBoost")), let v = MassBoost(rawValue: raw) {
            botConfig.massBoost = v
        }
        if let raw = defaults.string(forKey: k("region")), let v = ServerRegion(rawValue: raw) {
            botConfig.region = v
        }
        if let raw = defaults.string(forKey: k("gameMode")), let v = GameMode(rawValue: raw) {
            botConfig.gameMode = v
        }
        botConfig.partyCode = defaults.string(forKey: k("partyCode")) ?? ""
        botConfig.targetUID = defaults.string(forKey: k("targetUID")) ?? ""
        botConfig.shouldSplit = defaults.bool(forKey: k("shouldSplit"))
        if let raw = defaults.string(forKey: k("botAction")), let v = BotAction(rawValue: raw) {
            botConfig.botAction = v
        }
    }

    func resetAll() {
        zoomLevel = 1.0
        isMacroEnabled = false
        macroDragMode = false
        macroButtonSize = 50
        playerName = ""
        botConfig = BotConfiguration()

        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.synchronize()
    }

    private func k(_ name: String) -> String { prefix + name }
}
