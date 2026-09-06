import Foundation
import Network

protocol AgarBotDelegate: AnyObject {
    func bot(_ bot: AgarBot, didUpdateState state: AgarBot.State)
    func bot(_ bot: AgarBot, didSpawnWithIDs ids: [UInt32])
    func bot(_ bot: AgarBot, didReceiveWorldUpdate players: [CellUpdate])
    func botDidDisconnect(_ bot: AgarBot)
}

class AgarBot: NSObject, Identifiable {
    let id = UUID()
    let name: String
    let serverIP: String
    let serverPort: Int
    let serverHostname: String
    let serverToken: String
    let action: BotAction
    var targetUID: String = ""

    weak var delegate: AgarBotDelegate?

    enum State {
        case idle, connecting, connected, spawning, alive, dead, disconnected
    }

    private(set) var state: State = .idle {
        didSet { delegate?.bot(self, didUpdateState: state) }
    }

    private(set) var connMode: String = ""
    private(set) var lastError: String = ""

    static var recentLog: [String] = []
    private static func log(_ msg: String) {
        DispatchQueue.main.async {
            if recentLog.count >= 30 { recentLog.removeFirst() }
            recentLog.append(msg)
        }
    }

    private var nwConnection: NWConnection?

    private var targetPosition: (x: Double, y: Double)?
    private var ownIDs: [UInt32] = []
    private var cells: [UInt32: CellUpdate] = [:]
    private var worldBorder: WorldBorder = .default
    private var moveTimer: Timer?
    private var isAlive: Bool = false
    private var respawnCount: Int = 0
    private var cancelled = false
    private var xorKey: [UInt8]?
    private(set) var serverPacketCount: Int = 0

    init(name: String, serverIP: String, serverPort: Int, serverHostname: String, serverToken: String, action: BotAction) {
        self.name = name
        self.serverIP = serverIP
        self.serverPort = serverPort
        self.serverHostname = serverHostname
        self.serverToken = serverToken
        self.action = action
        super.init()
    }

    deinit {
        cleanup()
    }

    // MARK: - TLS hostname for SNI

    private var tlsHostname: String {
        if !serverHostname.isEmpty {
            var sin = sockaddr_in()
            var sin6 = sockaddr_in6()
            let isIP = serverHostname.withCString { cs in
                inet_pton(AF_INET, cs, &sin.sin_addr) == 1 ||
                inet_pton(AF_INET6, cs, &sin6.sin6_addr) == 1
            }
            if !isIP { return serverHostname }
        }
        return "eu-west-3.mobile-live-v26.agario.miniclippt.com"
    }

    // MARK: - Connection (NWConnection — direct IP with proper TLS SNI)

    func connect() {
        state = .connecting
        lastError = ""
        cancelled = false
        xorKey = nil
        serverPacketCount = 0
        triedTLS = false
        triedPlain = false

        // Port 443 = standard TLS, try wss first
        // Dynamic ports (20982 etc) = likely plain WS, try ws first
        connectWithTLS(serverPort == 443)
    }

    private var triedTLS = false
    private var triedPlain = false

    private func connectWithTLS(_ useTLS: Bool) {
        guard !cancelled else { return }

        if useTLS { triedTLS = true } else { triedPlain = true }
        connMode = useTLS ? "wss" : "ws"

        guard let port = NWEndpoint.Port(rawValue: UInt16(serverPort)) else {
            AgarBot.log("[\(name)] invalid port: \(serverPort)")
            lastError = "invalid port"
            state = .disconnected
            return
        }

        let host = NWEndpoint.Host(serverIP)
        let sni = tlsHostname

        AgarBot.log("[\(name)] connecting \(connMode)://\(serverIP):\(serverPort) sni=\(sni)")

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.setAdditionalHeaders([("Host", sni)])

        let params: NWParameters
        if useTLS {
            let tlsOpts = NWProtocolTLS.Options()
            let secOpts = tlsOpts.securityProtocolOptions
            sec_protocol_options_set_tls_server_name(secOpts, sni)
            sec_protocol_options_set_verify_block(secOpts, { _, _, complete in
                complete(true)
            }, .main)
            params = NWParameters(tls: tlsOpts)
        } else {
            params = NWParameters.tcp
        }

        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let connection = NWConnection(host: host, port: port, using: params)
        self.nwConnection = connection

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self = self, !self.cancelled else { return }
            switch newState {
            case .ready:
                AgarBot.log("[\(self.name)] \(self.connMode) connected to \(self.serverIP):\(self.serverPort)")
                self.state = .connected
                self.sendGameHandshake()
                self.receiveLoop()
            case .failed(let error):
                AgarBot.log("[\(self.name)] \(self.connMode) failed: \(error)")
                self.nwConnection?.cancel()
                self.nwConnection = nil
                let canFallback = useTLS ? !self.triedPlain : !self.triedTLS
                if canFallback {
                    AgarBot.log("[\(self.name)] trying \(useTLS ? "ws" : "wss"):// fallback")
                    self.connectWithTLS(!useTLS)
                } else {
                    self.lastError = error.localizedDescription
                    self.disconnect()
                }
            case .waiting(let error):
                AgarBot.log("[\(self.name)] waiting: \(error)")
                self.nwConnection?.cancel()
                self.nwConnection = nil
                let canFallback = useTLS ? !self.triedPlain : !self.triedTLS
                if canFallback {
                    AgarBot.log("[\(self.name)] waiting, trying \(useTLS ? "ws" : "wss")://")
                    self.connectWithTLS(!useTLS)
                } else {
                    self.lastError = error.localizedDescription
                    self.disconnect()
                }
            default:
                break
            }
        }

        connection.start(queue: .main)

        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self, !self.cancelled, self.state == .connecting else { return }
            self.nwConnection?.cancel()
            self.nwConnection = nil
            let canFallback = useTLS ? !self.triedPlain : !self.triedTLS
            if canFallback {
                AgarBot.log("[\(self.name)] \(self.connMode) timeout, trying \(useTLS ? "ws" : "wss")://")
                self.connectWithTLS(!useTLS)
            } else {
                self.lastError = "connection timeout"
                self.disconnect()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, !self.cancelled else { return }
            if self.state == .connected {
                AgarBot.log("[\(self.name)] spawn timeout — forcing spawn")
                self.spawn()
            }
        }
    }

    private func receiveLoop() {
        nwConnection?.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self, !self.cancelled else { return }

            if let error = error {
                AgarBot.log("[\(self.name)] recv error: \(error)")
                if !self.cancelled {
                    self.lastError = error.localizedDescription
                    self.disconnect()
                }
                return
            }

            if let wsMetadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               wsMetadata.opcode == .close {
                AgarBot.log("[\(self.name)] WS closed by server pkts=\(self.serverPacketCount)")
                if !self.cancelled {
                    self.lastError = "WS closed pkts=\(self.serverPacketCount)"
                    self.disconnect()
                }
                return
            }

            if let data = content, !data.isEmpty {
                self.handlePacket(data)
            }
            self.receiveLoop()
        }
    }

    // MARK: - Game Protocol

    private func sendGameHandshake() {
        let hs = AgarProtocol.handshakePacket()
        let ck = AgarProtocol.connectionKeyPacket()
        gameSend(hs)
        gameSend(ck)
        let hsHex = hs.map { String(format: "%02x", $0) }.joined(separator: " ")
        let ckHex = ck.map { String(format: "%02x", $0) }.joined(separator: " ")
        AgarBot.log("[\(name)] handshake=[\(hsHex)] key=[\(ckHex)]")
        if !serverToken.isEmpty {
            gameSend(AgarProtocol.facebookTokenPacket(token: serverToken))
            AgarBot.log("[\(name)] token sent (\(serverToken.count) chars)")
        }
    }

    private func gameSend(_ data: Data) {
        guard !cancelled, let connection = nwConnection else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            if let error = error, let self = self, !self.cancelled {
                AgarBot.log("[\(self.name)] send error: \(error)")
            }
        })
    }

    // MARK: - Public API

    func disconnect() {
        cancelled = true
        cleanup()
        if state != .disconnected {
            AgarBot.log("[\(name)] disconnected: \(lastError)")
            state = .disconnected
            delegate?.botDidDisconnect(self)
        }
    }

    func setTarget(x: Double, y: Double) {
        targetPosition = (x, y)
    }

    func spawn() {
        state = .spawning
        gameSend(AgarProtocol.spawnPacket(name: name))
    }

    func findCellByName(_ name: String) -> CellUpdate? {
        cells.values.first { !ownIDs.contains($0.id) && !$0.isVirus && $0.name == name }
    }

    // MARK: - Packet Handling

    private func handlePacket(_ data: Data) {
        serverPacketCount += 1

        if data.first == 0xF1 && xorKey == nil {
            if data.count >= 5 {
                xorKey = [data[1], data[2], data[3], data[4]]
                let ver = data.count > 5 ? (String(data: data[5...], encoding: .utf8)?.replacingOccurrences(of: "\0", with: "") ?? "") : ""
                AgarBot.log("[\(name)] VERSION \"\(ver)\" xorKey=[\(xorKey!.map { String(format: "%02x", $0) }.joined())]")
            }
            return
        }

        let decoded: Data
        if let key = xorKey {
            decoded = AgarProtocol.xorApply(data, key: key)
        } else {
            decoded = data
        }

        guard let packet = AgarProtocol.parsePacket(decoded) else {
            if serverPacketCount <= 10 {
                let hex = decoded.prefix(20).map { String(format: "%02x", $0) }.joined()
                AgarBot.log("[\(name)] unparsed #\(serverPacketCount) op=0x\(String(format: "%02x", decoded.first ?? 0)) len=\(decoded.count) \(hex)")
            }
            return
        }

        switch packet {
        case .version(let key, let ver):
            xorKey = key
            AgarBot.log("[\(name)] VERSION(parsed) \"\(ver)\"")

        case .ack:
            AgarBot.log("[\(name)] ACK — spawning")
            if state == .connecting || state == .connected {
                state = .connected
                spawn()
            }

        case .worldUpdate(let eatRecords, let updates, let removals):
            for update in updates { cells[update.id] = update }
            for removal in removals { cells.removeValue(forKey: removal) }
            for record in eatRecords {
                cells.removeValue(forKey: record.eaten)
                ownIDs.removeAll { $0 == record.eaten }
            }
            if isAlive && ownIDs.isEmpty {
                isAlive = false
                state = .dead
                handleDeath()
            }
            if isAlive {
                updateUIDTarget()
                performAction()
            }
            delegate?.bot(self, didReceiveWorldUpdate: updates)

        case .ownIDs(let ids):
            ownIDs = ids
            if !ids.isEmpty {
                isAlive = true
                state = .alive
                AgarBot.log("[\(name)] ALIVE ids=\(ids)")
                delegate?.bot(self, didSpawnWithIDs: ids)
                startMovementLoop()
            }

        case .worldBorder(let border):
            worldBorder = border
            AgarBot.log("[\(name)] world border, spawning")
            if state == .connecting || state == .connected {
                state = .connected
                spawn()
            }

        case .clearAll:
            cells.removeAll()

        case .clearCell(let id):
            cells.removeValue(forKey: id)
            ownIDs.removeAll { $0 == id }
            if isAlive && ownIDs.isEmpty {
                isAlive = false
                state = .dead
                handleDeath()
            }

        case .unknown(let opcode, let raw):
            if serverPacketCount <= 15 {
                let hex = raw.prefix(20).map { String(format: "%02x", $0) }.joined()
                AgarBot.log("[\(name)] unknown op=0x\(String(format: "%02x", opcode)) len=\(raw.count) \(hex)")
            }
            if raw.count == 33 {
                let reader = BinaryReader(data: raw)
                reader.skip(1)
                let minX = reader.readFloat64()
                let minY = reader.readFloat64()
                let maxX = reader.readFloat64()
                let maxY = reader.readFloat64()
                if abs(minX) < 50000 && abs(maxX) < 50000 && maxX > minX && maxY > minY {
                    worldBorder = WorldBorder(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
                    AgarBot.log("[\(name)] heuristic world border \(worldBorder)")
                    if state == .connecting || state == .connected {
                        state = .connected
                        spawn()
                    }
                }
            }
            if raw.count >= 5 && raw.count <= 33 && (raw.count - 1) % 4 == 0 {
                let reader = BinaryReader(data: raw)
                reader.skip(1)
                var ids: [UInt32] = []
                while reader.hasMore { ids.append(reader.readUInt32()) }
                if !ids.isEmpty && ids.allSatisfy({ $0 > 0 && $0 < 0xFFFFFF }) {
                    ownIDs = ids
                    isAlive = true
                    state = .alive
                    AgarBot.log("[\(name)] heuristic ALIVE ids=\(ids)")
                    delegate?.bot(self, didSpawnWithIDs: ids)
                    startMovementLoop()
                }
            }

        default:
            break
        }
    }

    // MARK: - Movement

    private func updateUIDTarget() {
        guard !targetUID.isEmpty else { return }
        if let uid = UInt32(targetUID, radix: 16), let cell = cells[uid] {
            targetPosition = (Double(cell.x), Double(cell.y))
            return
        }
        if let cell = cells.values.first(where: {
            !ownIDs.contains($0.id) && !$0.isVirus && $0.name == targetUID
        }) {
            targetPosition = (Double(cell.x), Double(cell.y))
        }
    }

    private func startMovementLoop() {
        moveTimer?.invalidate()
        moveTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateUIDTarget()
            self?.performAction()
        }
    }

    private func performAction() {
        guard isAlive else { return }
        switch action {
        case .feedTarget:
            moveToTarget()
            gameSend(AgarProtocol.ejectMassPacket())
        case .suicide:
            moveToTarget()
            gameSend(AgarProtocol.splitPacket())
        case .feedEverywhere:
            let rx = Double.random(in: worldBorder.minX...worldBorder.maxX)
            let ry = Double.random(in: worldBorder.minY...worldBorder.maxY)
            gameSend(AgarProtocol.movePacket(x: rx, y: ry))
            gameSend(AgarProtocol.ejectMassPacket())
        }
    }

    private func moveToTarget() {
        guard let t = targetPosition else {
            gameSend(AgarProtocol.movePacket(x: worldBorder.centerX, y: worldBorder.centerY))
            return
        }
        gameSend(AgarProtocol.movePacket(x: t.x, y: t.y))
    }

    private var ownPosition: (x: Double, y: Double)? {
        let own = ownIDs.compactMap { cells[$0] }
        guard !own.isEmpty else { return nil }
        let x = own.map { Double($0.x) }.reduce(0, +) / Double(own.count)
        let y = own.map { Double($0.y) }.reduce(0, +) / Double(own.count)
        return (x, y)
    }

    private func handleDeath() {
        moveTimer?.invalidate()
        moveTimer = nil
        respawnCount += 1
        if respawnCount > 20 {
            AgarBot.log("[\(name)] max respawns reached, disconnecting")
            lastError = "max respawns"
            disconnect()
            return
        }
        let delay = respawnCount > 10 ? 3.0 : 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.cancelled else { return }
            self.spawn()
        }
    }

    private func cleanup() {
        moveTimer?.invalidate()
        moveTimer = nil
        nwConnection?.cancel()
        nwConnection = nil
    }
}
