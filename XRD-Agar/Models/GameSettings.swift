import Foundation
import SwiftUI

class GameSettings: ObservableObject {
    @Published var zoomLevel: Double = 1.0
    @Published var isAutoFeeding: Bool = false
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
}
