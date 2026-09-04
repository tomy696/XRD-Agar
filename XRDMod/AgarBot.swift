import Foundation
import Network

protocol AgarBotDelegate: AnyObject {
    func bot(_ bot: AgarBot, didUpdateState state: AgarBot.State)
    func bot(_ bot: AgarBot, didSpawnWithIDs ids: [UInt32])
    func bot(_ bot: AgarBot, didReceiveWorldUpdate players: [CellUpdate])
    func botDidDisconnect(_ bot: AgarBot)
}

class AgarBot: Identifiable {
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
    private var connection: NWConnection?
    private var targetPosition: (x: Double, y: Double)?
    private var ownIDs: [UInt32] = []
    private var cells: [UInt32: CellUpdate] = [:]
    private var worldBorder: WorldBorder = .default
    private var moveTimer: Timer?
    private var isAlive: Bool = false
    private var respawnCount: Int = 0
    private var fallbackTimer: Timer?

    init(name: String, serverIP: String, serverPort: Int, serverHostname: String, serverToken: String, action: BotAction) {
        self.name = name
        self.serverIP = serverIP
        self.serverPort = serverPort
        self.serverHostname = serverHostname
        self.serverToken = serverToken
        self.action = action
    }

    private(set) var lastError: String = ""

    func connect() {
        state = .connecting
        lastError = ""
        tryConnect(mode: "wss")
    }

    private func tryConnect(mode: String) {
        connection?.cancel()
        connection = nil
        fallbackTimer?.invalidate()
        connMode = mode

        guard let host = NWEndpoint.Host(serverIP) as NWEndpoint.Host?,
              let port = NWEndpoint.Port(rawValue: UInt16(serverPort)) else {
            lastError = "Bad IP/port"
            state = .disconnected
            return
        }

        let params: NWParameters
        switch mode {
        case "wss":
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, serverHostname)
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, cb in
                cb(true)
            }, DispatchQueue.main)
            let wsOpts = NWProtocolWebSocket.Options()
            wsOpts.autoReplyPing = true
            wsOpts.setAdditionalHeaders([
                ("Origin", "https://agar.io"),
                ("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)")
            ])
            params = NWParameters(tls: tlsOptions)
            params.defaultProtocolStack.applicationProtocols.insert(wsOpts, at: 0)

        case "ws":
            let wsOpts = NWProtocolWebSocket.Options()
            wsOpts.autoReplyPing = true
            wsOpts.setAdditionalHeaders([
                ("Origin", "https://agar.io"),
                ("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)")
            ])
            params = NWParameters.tcp
            params.defaultProtocolStack.applicationProtocols.insert(wsOpts, at: 0)

        default: // "tcp"
            params = NWParameters.tcp
        }

        let conn = NWConnection(host: host, port: port, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            switch newState {
            case .ready:
                self.fallbackTimer?.invalidate()
                self.fallbackTimer = nil
                self.state = .connected
                if mode == "tcp" {
                    self.sendBinaryRaw(AgarProtocol.handshakePacket())
                    self.sendBinaryRaw(AgarProtocol.connectionKeyPacket())
                    if !self.serverToken.isEmpty {
                        self.sendBinaryRaw(AgarProtocol.facebookTokenPacket(token: self.serverToken))
                    }
                    self.receiveLoopRaw()
                } else {
                    self.sendHandshake()
                    self.receiveLoop()
                }
            case .failed(let error):
                self.fallbackTimer?.invalidate()
                self.lastError = "\(mode): \(error.localizedDescription)"
                self.tryNextMode(current: mode)
            case .waiting(let error):
                self.lastError = "\(mode) waiting: \(error.localizedDescription)"
            default:
                break
            }
        }

        conn.start(queue: .main)

        let nextMode: String? = mode == "wss" ? "ws" : (mode == "ws" ? "tcp" : nil)
        if let next = nextMode {
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                guard let self = self, self.state == .connecting else { return }
                self.lastError = "\(mode) timeout, trying \(next)..."
                self.tryNextMode(current: mode)
            }
        }
    }

    private func tryNextMode(current: String) {
        connection?.cancel()
        connection = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil

        switch current {
        case "wss": tryConnect(mode: "ws")
        case "ws": tryConnect(mode: "tcp")
        default: disconnect()
        }
    }

    func disconnect() {
        moveTimer?.invalidate()
        moveTimer = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        connection?.cancel()
        connection = nil
        if state != .disconnected {
            state = .disconnected
            delegate?.botDidDisconnect(self)
        }
    }

    func setTarget(x: Double, y: Double) {
        targetPosition = (x, y)
    }

    private func sendHandshake() {
        sendBinary(AgarProtocol.handshakePacket())
        sendBinary(AgarProtocol.connectionKeyPacket())
        if !serverToken.isEmpty {
            sendBinary(AgarProtocol.facebookTokenPacket(token: serverToken))
        }
    }

    func spawn() {
        state = .spawning
        sendBinary(AgarProtocol.spawnPacket(name: name))
    }

    private func sendMove(x: Double, y: Double) {
        sendBinary(AgarProtocol.movePacket(x: x, y: y))
    }

    private func sendBinary(_ data: Data) {
        if connMode == "tcp" {
            sendBinaryRaw(data)
        } else {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
            connection?.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ _ in }))
        }
    }

    private func sendBinaryRaw(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed({ _ in }))
    }

    private func receiveLoop() {
        connection?.receiveMessage { [weak self] data, context, _, error in
            guard let self = self else { return }
            if let error = error {
                self.lastError = error.localizedDescription
                self.disconnect()
                return
            }
            if let data = data, !data.isEmpty,
               let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .binary {
                self.handlePacket(data)
            }
            self.receiveLoop()
        }
    }

    private func receiveLoopRaw() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self else { return }
            if let error = error {
                self.lastError = error.localizedDescription
                self.disconnect()
                return
            }
            if let data = data, !data.isEmpty {
                self.handlePacket(data)
            }
            self.receiveLoopRaw()
        }
    }

    private func handlePacket(_ data: Data) {
        guard let packet = AgarProtocol.parsePacket(data) else { return }

        switch packet {
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
                delegate?.bot(self, didSpawnWithIDs: ids)
                startMovementLoop()
            }

        case .worldBorder(let border):
            worldBorder = border
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

        default:
            break
        }
    }

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

    func findCellByName(_ name: String) -> CellUpdate? {
        cells.values.first { !ownIDs.contains($0.id) && !$0.isVirus && $0.name == name }
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
            sendBinary(AgarProtocol.ejectMassPacket())
        case .suicide:
            moveToTarget()
            sendBinary(AgarProtocol.splitPacket())
        case .feedEverywhere:
            let rx = Double.random(in: worldBorder.minX...worldBorder.maxX)
            let ry = Double.random(in: worldBorder.minY...worldBorder.maxY)
            sendMove(x: rx, y: ry)
            sendBinary(AgarProtocol.ejectMassPacket())
        }
    }

    private func moveToTarget() {
        guard let t = targetPosition else {
            sendMove(x: worldBorder.centerX, y: worldBorder.centerY)
            return
        }
        sendMove(x: t.x, y: t.y)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.spawn()
        }
    }
}
