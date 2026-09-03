import Foundation

class AgarProtocol {

    // MARK: - Client → Server Packets

    static func handshakePacket(protocolVersion: UInt32 = 22) -> Data {
        var data = Data()
        data.append(254)
        data.appendUInt32(protocolVersion)
        return data
    }

    static func connectionKeyPacket(key: UInt32 = 0) -> Data {
        var data = Data()
        data.append(255)
        data.appendUInt32(key)
        return data
    }

    static func spawnPacket(name: String) -> Data {
        var data = Data()
        data.append(0)
        for char in name.utf8 {
            data.append(char)
        }
        data.append(0)
        return data
    }

    static func movePacket(x: Double, y: Double) -> Data {
        var data = Data()
        data.append(16)
        data.appendFloat64(x)
        data.appendFloat64(y)
        data.appendUInt32(0)
        return data
    }

    static func splitPacket() -> Data {
        return Data([17])
    }

    static func ejectMassPacket() -> Data {
        return Data([21])
    }

    static func spectatePacket() -> Data {
        return Data([1])
    }

    static func facebookTokenPacket(token: String) -> Data {
        var data = Data()
        data.append(81)
        for byte in token.utf8 {
            data.append(byte)
        }
        data.append(0)
        return data
    }

    // MARK: - Server → Client Parsing

    static func parsePacket(_ data: Data) -> ServerPacket? {
        guard let firstByte = data.first else { return nil }
        let reader = BinaryReader(data: data)
        reader.skip(1)

        switch firstByte {
        case 16:
            return parseWorldUpdate(reader)
        case 17:
            return parseLeaderboardFFA(reader)
        case 20:
            return .clearAll
        case 32:
            return parseClearCell(reader)
        case 49:
            return parseLeaderboardTeams(reader)
        case 50:
            return parseOwnIDs(reader)
        case 64:
            return parseWorldBorder(reader)
        case 99:
            return parseChatMessage(reader)
        default:
            return nil
        }
    }

    private static func parseWorldUpdate(_ reader: BinaryReader) -> ServerPacket {
        var eatRecords: [(eater: UInt32, eaten: UInt32)] = []
        var updates: [CellUpdate] = []
        var removals: [UInt32] = []

        let eatCount = reader.readUInt16()
        for _ in 0..<eatCount {
            let eater = reader.readUInt32()
            let eaten = reader.readUInt32()
            eatRecords.append((eater, eaten))
        }

        while true {
            let id = reader.readUInt32()
            if id == 0 { break }

            let x = reader.readInt16()
            let y = reader.readInt16()
            let size = reader.readInt16()

            let flags = reader.readUInt8()
            let isVirus = (flags & 0x01) != 0
            let hasColor = (flags & 0x02) != 0
            let hasSkin = (flags & 0x04) != 0
            let hasName = (flags & 0x08) != 0
            let hasExtFlags = (flags & 0x80) != 0

            if hasExtFlags {
                _ = reader.readUInt8()
            }

            var color: UInt32 = 0
            if hasColor {
                let r = UInt32(reader.readUInt8())
                let g = UInt32(reader.readUInt8())
                let b = UInt32(reader.readUInt8())
                color = (r << 16) | (g << 8) | b
            }

            var skin = ""
            if hasSkin {
                skin = reader.readUTF8String()
            }

            var name = ""
            if hasName {
                name = reader.readUTF8String()
            }

            let cell = CellUpdate(
                id: id, x: x, y: y, size: size,
                color: color, flags: flags, name: name,
                skin: skin, isVirus: isVirus
            )
            updates.append(cell)
        }

        let removeCount = reader.readUInt32()
        for _ in 0..<removeCount {
            removals.append(reader.readUInt32())
        }

        return .worldUpdate(eatRecords: eatRecords, updates: updates, removals: removals)
    }

    private static func parseOwnIDs(_ reader: BinaryReader) -> ServerPacket {
        var ids: [UInt32] = []
        while reader.hasMore {
            ids.append(reader.readUInt32())
        }
        return .ownIDs(ids)
    }

    private static func parseWorldBorder(_ reader: BinaryReader) -> ServerPacket {
        let minX = reader.readFloat64()
        let minY = reader.readFloat64()
        let maxX = reader.readFloat64()
        let maxY = reader.readFloat64()
        return .worldBorder(WorldBorder(minX: minX, minY: minY, maxX: maxX, maxY: maxY))
    }

    private static func parseClearCell(_ reader: BinaryReader) -> ServerPacket {
        return .clearCell(reader.readUInt32())
    }

    private static func parseLeaderboardFFA(_ reader: BinaryReader) -> ServerPacket {
        var entries: [(id: UInt32, name: String)] = []
        let count = reader.readUInt32()
        for _ in 0..<count {
            let id = reader.readUInt32()
            let name = reader.readUTF8String()
            entries.append((id, name))
        }
        return .leaderboard(entries)
    }

    private static func parseLeaderboardTeams(_ reader: BinaryReader) -> ServerPacket {
        return .leaderboard([])
    }

    private static func parseChatMessage(_ reader: BinaryReader) -> ServerPacket {
        let flags = reader.readUInt8()
        _ = flags
        let r = reader.readUInt8()
        let g = reader.readUInt8()
        let b = reader.readUInt8()
        let color = (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
        let name = reader.readUTF8String()
        let message = reader.readUTF8String()
        return .chatMessage(name: name, message: message, color: color)
    }
}

// MARK: - Packet Types

enum ServerPacket {
    case worldUpdate(eatRecords: [(eater: UInt32, eaten: UInt32)], updates: [CellUpdate], removals: [UInt32])
    case ownIDs([UInt32])
    case worldBorder(WorldBorder)
    case clearAll
    case clearCell(UInt32)
    case leaderboard([(id: UInt32, name: String)])
    case chatMessage(name: String, message: String, color: UInt32)
}

// MARK: - Binary Reader

class BinaryReader {
    private let data: Data
    private var offset: Int = 0

    var hasMore: Bool { offset < data.count }

    init(data: Data) {
        self.data = data
    }

    func skip(_ count: Int) {
        offset += count
    }

    func readUInt8() -> UInt8 {
        guard offset < data.count else { return 0 }
        let val = data[offset]
        offset += 1
        return val
    }

    func readInt16() -> Int16 {
        guard offset + 1 < data.count else { return 0 }
        let val = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes {
            $0.load(as: Int16.self)
        }
        offset += 2
        return Int16(littleEndian: val)
    }

    func readUInt16() -> UInt16 {
        guard offset + 1 < data.count else { return 0 }
        let val = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes {
            $0.load(as: UInt16.self)
        }
        offset += 2
        return UInt16(littleEndian: val)
    }

    func readUInt32() -> UInt32 {
        guard offset + 3 < data.count else { return 0 }
        let val = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
            $0.load(as: UInt32.self)
        }
        offset += 4
        return UInt32(littleEndian: val)
    }

    func readFloat64() -> Double {
        guard offset + 7 < data.count else { return 0 }
        let val = data.subdata(in: offset..<(offset + 8)).withUnsafeBytes {
            $0.load(as: Double.self)
        }
        offset += 8
        return val
    }

    func readUTF8String() -> String {
        var bytes: [UInt8] = []
        while offset < data.count {
            let byte = data[offset]
            offset += 1
            if byte == 0 { break }
            bytes.append(byte)
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }
}

// MARK: - Data Extensions

extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        var val = value.littleEndian
        append(Data(bytes: &val, count: 4))
    }

    mutating func appendInt16(_ value: Int16) {
        var val = value.littleEndian
        append(Data(bytes: &val, count: 2))
    }

    mutating func appendFloat64(_ value: Double) {
        var val = value
        append(Data(bytes: &val, count: 8))
    }
}
