import Foundation

struct PlayerInfo: Identifiable, Hashable {
    let id: UInt32
    var name: String
    var x: Double
    var y: Double
    var mass: Double
    var color: UInt32
    var isVirus: Bool

    var displayMass: Int { Int(mass) }

    var uid: String {
        String(format: "%08X", id)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PlayerInfo, rhs: PlayerInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct CellUpdate {
    var id: UInt32
    var x: Int16
    var y: Int16
    var size: Int16
    var color: UInt32
    var flags: UInt8
    var name: String
    var skin: String
    var isVirus: Bool
}

struct WorldBorder {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var centerX: Double { (minX + maxX) / 2.0 }
    var centerY: Double { (minY + maxY) / 2.0 }
    var width: Double { maxX - minX }
    var height: Double { maxY - minY }

    static let `default` = WorldBorder(minX: -7071, minY: -7071, maxX: 7071, maxY: 7071)
}
