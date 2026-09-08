import Foundation

class AgarProtocol {

    static let protocolVersion: UInt32 = 23
    static let clientVersion: String = "3.11.29"

    // MARK: - Client → Server Packets

    static func handshakePacket() -> Data {
        var data = Data()
        data.append(254)
        data.appendUInt32(protocolVersion)
        return data
    }

    static func versionIntPacket() -> Data {
        var data = Data()
        data.append(255)
        data.appendUInt32(versionStringToInt(clientVersion))
        return data
    }

    static func spawnPacket(name: String) -> Data {
        var data = Data()
        data.append(0)
        for byte in name.utf8 {
            data.append(byte)
        }
        data.append(0)
        return data
    }

    static func movePacket(x: Double, y: Double, movementKey: UInt32) -> Data {
        var data = Data()
        data.append(16)
        data.appendInt32(Int32(x))
        data.appendInt32(Int32(y))
        data.appendUInt32(movementKey)
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

    // MARK: - Version Helpers

    static func versionStringToInt(_ version: String) -> UInt32 {
        let parts = version.split(separator: ".").map { UInt32($0) ?? 0 }
        guard parts.count >= 3 else { return 0 }
        return parts[0] * 10000 + parts[1] * 100 + parts[2]
    }

    // MARK: - Crypto

    static func murmur2(_ str: String, seed: UInt32) -> UInt32 {
        let bytes = Array(str.utf8)
        var l = bytes.count
        var h: UInt32 = seed ^ UInt32(l)
        var i = 0
        while l >= 4 {
            var k: UInt32 = UInt32(bytes[i]) |
                (UInt32(bytes[i + 1]) << 8) |
                (UInt32(bytes[i + 2]) << 16) |
                (UInt32(bytes[i + 3]) << 24)
            k = k &* 0x5bd1e995
            k ^= k >> 24
            k = k &* 0x5bd1e995
            h = (h &* 0x5bd1e995) ^ k
            l -= 4
            i += 4
        }
        switch l {
        case 3: h ^= UInt32(bytes[i + 2]) << 16; fallthrough
        case 2: h ^= UInt32(bytes[i + 1]) << 8; fallthrough
        case 1: h ^= UInt32(bytes[i]); h = h &* 0x5bd1e995
        default: break
        }
        h ^= h >> 13
        h = h &* 0x5bd1e995
        h ^= h >> 15
        return h
    }

    static func rotateKey(_ key: UInt32) -> UInt32 {
        var k = key &* 1540483477
        k = (((k >> 24) ^ k) &* 1540483477) ^ 114296087
        k = ((k >> 13) ^ k) &* 1540483477
        k = (k >> 15) ^ k
        return k
    }

    static func xorWithKey(_ data: Data, key: UInt32) -> Data {
        guard key != 0 else { return data }
        let keyBytes: [UInt8] = [
            UInt8(key & 0xFF),
            UInt8((key >> 8) & 0xFF),
            UInt8((key >> 16) & 0xFF),
            UInt8((key >> 24) & 0xFF)
        ]
        var result = Data(count: data.count)
        for i in 0..<data.count {
            result[i] = data[i] ^ keyBytes[i % 4]
        }
        return result
    }

    // MARK: - LZ4 Decompression

    static func lz4Decompress(_ input: Data) -> Data? {
        let bytes = Array(input)
        var output: [UInt8] = []
        var i = 0
        let n = bytes.count
        while i < n {
            let token = bytes[i]; i += 1
            var litLen = Int(token >> 4)
            if litLen > 0 {
                if litLen == 15 {
                    repeat {
                        guard i < n else { return nil }
                        let ext = Int(bytes[i]); i += 1
                        litLen += ext
                        if ext != 255 { break }
                    } while true
                }
                guard i + litLen <= n else { return nil }
                output.append(contentsOf: bytes[i..<(i + litLen)])
                i += litLen
                if i >= n { break }
            }
            guard i + 1 < n else { return nil }
            let offset = Int(bytes[i]) | (Int(bytes[i + 1]) << 8)
            i += 2
            guard offset > 0, offset <= output.count else { return nil }
            var matchLen = Int(token & 0x0F) + 4
            if (token & 0x0F) == 15 {
                repeat {
                    guard i < n else { return nil }
                    let ext = Int(bytes[i]); i += 1
                    matchLen += ext
                    if ext != 255 { break }
                } while true
            }
            var pos = output.count - offset
            for _ in 0..<matchLen {
                output.append(output[pos])
                pos += 1
            }
        }
        guard !output.isEmpty else { return nil }
        return Data(output)
    }

    // MARK: - Server → Client Parsing

    static func parsePacket(_ data: Data) -> ServerPacket? {
        guard let firstByte = data.first else { return nil }

        switch firstByte {
        case 0xF1:
            return parseF1(data)
        case 0x80:
            return .outdatedVersion
        case 0x81:
            return .protocolError
        case 0xFF:
            if data.count > 5 {
                let compressed = Data(data[5...])
                if let decompressed = lz4Decompress(compressed) {
                    return parsePacket(decompressed)
                }
            }
            return nil
        default:
            break
        }

        let reader = BinaryReader(data: data)
        reader.skip(1)

        switch firstByte {
        case 0x55:
            return .captchaRequest
        case 0x6B:
            return .ack
        case 0x66:
            return parseWorldUpdate(reader)
        case 0xDC:
            return parseLeaderboardFFA(reader)
        case 16:
            return parseWorldUpdate(reader)
        case 17:
            return parseLeaderboardFFA(reader)
        case 20:
            return .clearAll
        case 32:
            return parseOwnIDs(reader)
        case 49:
            return parseLeaderboardTeams(reader)
        case 50:
            return parseOwnIDs(reader)
        case 64:
            return parseWorldBorder(reader)
        case 99:
            return parseChatMessage(reader)
        default:
            return .unknown(opcode: firstByte, data: data)
        }
    }

    private static func parseF1(_ data: Data) -> ServerPacket {
        guard data.count >= 5 else { return .version(movementKey: 0, versionString: "") }
        let reader = BinaryReader(data: data)
        reader.skip(1)
        let movementKey = reader.readUInt32()
        var verStr = ""
        if reader.hasMore {
            verStr = reader.readUTF8String()
        }
        return .version(movementKey: movementKey, versionString: verStr)
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

            let x = reader.readInt32()
            let y = reader.readInt32()
            let size = reader.readUInt16()

            let flags = reader.readUInt8()
            let isVirus = (flags & 0x01) != 0
            let hasColor = (flags & 0x02) != 0
            let hasSkin = (flags & 0x04) != 0
            let hasName = (flags & 0x08) != 0
            let hasExtFlags = (flags & 0x80) != 0

            var extFlags: UInt8 = 0
            if hasExtFlags {
                extFlags = reader.readUInt8()
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

            if (flags & 0x10) != 0 { /* isAgitated - no extra data */ }
            if (flags & 0x20) != 0 { /* isEjected - no extra data */ }
            if (flags & 0x40) != 0 { /* isEnemyEject - no extra data */ }

            if (extFlags & 0x04) != 0 {
                reader.skip(4)
            }

            let cell = CellUpdate(
                id: id, x: x, y: y, size: Int16(size),
                color: color, flags: flags, name: name,
                skin: skin, isVirus: isVirus
            )
            updates.append(cell)
        }

        let removeCount = reader.readUInt16()
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
    case version(movementKey: UInt32, versionString: String)
    case ack
    case worldUpdate(eatRecords: [(eater: UInt32, eaten: UInt32)], updates: [CellUpdate], removals: [UInt32])
    case ownIDs([UInt32])
    case worldBorder(WorldBorder)
    case clearAll
    case clearCell(UInt32)
    case leaderboard([(id: UInt32, name: String)])
    case chatMessage(name: String, message: String, color: UInt32)
    case outdatedVersion
    case protocolError
    case captchaRequest
    case unknown(opcode: UInt8, data: Data)
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

    func readInt32() -> Int32 {
        guard offset + 3 < data.count else { return 0 }
        let val = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
            $0.load(as: Int32.self)
        }
        offset += 4
        return Int32(littleEndian: val)
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

    mutating func appendInt32(_ value: Int32) {
        var val = value.littleEndian
        append(Data(bytes: &val, count: 4))
    }

    mutating func appendInt16(_ value: Int16) {
        var val = value.littleEndian
        append(Data(bytes: &val, count: 2))
    }

    mutating func appendUInt64(_ value: UInt64) {
        var val = value.littleEndian
        append(Data(bytes: &val, count: 8))
    }

    mutating func appendFloat64(_ value: Double) {
        var val = value
        append(Data(bytes: &val, count: 8))
    }
}
