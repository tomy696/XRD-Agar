import Foundation

protocol AgarBotDelegate: AnyObject {
    func bot(_ bot: AgarBot, didUpdateState state: AgarBot.State)
    func bot(_ bot: AgarBot, didSpawnWithIDs ids: [UInt32])
    func bot(_ bot: AgarBot, didReceiveWorldUpdate players: [CellUpdate])
    func botDidDisconnect(_ bot: AgarBot)
}

class AgarBot: NSObject, Identifiable, URLSessionWebSocketDelegate {
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

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    private var targetPosition: (x: Double, y: Double)?
    private var ownIDs: [UInt32] = []
    private var cells: [UInt32: CellUpdate] = [:]
    private var worldBorder: WorldBorder = .default
    private var moveTimer: Timer?
    private var isAlive: Bool = false
    private var respawnCount: Int = 0
    private var cancelled = false
    private(set) var serverPacketCount: Int = 0

    private var encryptionKey: UInt32 = 0
    private var decryptionKey: UInt32 = 0
    private var movementKey: UInt32 = 0
    private var serverVersion: String = ""
    private var handshakeComplete = false

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

    private var connectHost: String {
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

    // MARK: - Connection

    func connect() {
        state = .connecting
        lastError = ""
        cancelled = false
        encryptionKey = 0
        decryptionKey = 0
        movementKey = 0
        serverVersion = ""
        handshakeComplete = false
        serverPacketCount = 0
        triedTLS = false
        triedPlain = false

        connectWebSocket(useTLS: true)
    }

    private var triedTLS = false
    private var triedPlain = false

    private func connectWebSocket(useTLS: Bool) {
        guard !cancelled else { return }

        if useTLS { triedTLS = true } else { triedPlain = true }
        connMode = useTLS ? "wss" : "ws"

        let scheme = useTLS ? "wss" : "ws"
        let host = connectHost

        guard let url = URL(string: "\(scheme)://\(host):\(serverPort)") else {
            AgarBot.log("[\(name)] invalid URL")
            lastError = "invalid URL"
            state = .disconnected
            return
        }

        AgarBot.log("[\(name)] connecting \(url.absoluteString)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        var request = URLRequest(url: url)
        request.setValue("https://agar.io", forHTTPHeaderField: "Origin")
        let task = urlSession!.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        receiveLoop()

        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self, !self.cancelled, self.state == .connecting else { return }
            AgarBot.log("[\(self.name)] \(self.connMode) timeout")
            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.webSocketTask = nil
            self.urlSession?.invalidateAndCancel()
            self.urlSession = nil
            let canFallback = useTLS ? !self.triedPlain : !self.triedTLS
            if canFallback {
                AgarBot.log("[\(self.name)] trying \(useTLS ? "ws" : "wss")://")
                self.connectWebSocket(useTLS: !useTLS)
            } else {
                self.lastError = "connection timeout"
                self.disconnect()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 14.0) { [weak self] in
            guard let self = self, !self.cancelled else { return }
            if self.state == .connected && !self.handshakeComplete {
                AgarBot.log("[\(self.name)] no F1 after 14s — forcing spawn")
                self.spawn()
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol proto: String?) {
        guard !cancelled else { return }
        AgarBot.log("[\(name)] \(connMode) connected to \(connectHost):\(serverPort)")
        state = .connected
        sendGameHandshake()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard !cancelled else { return }
        AgarBot.log("[\(name)] WS closed code=\(closeCode.rawValue) pkts=\(serverPacketCount)")
        lastError = "WS closed code=\(closeCode.rawValue) pkts=\(serverPacketCount)"
        disconnect()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard !cancelled else { return }
        guard let error = error else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }

        AgarBot.log("[\(name)] \(connMode) error: \(error.localizedDescription)")
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        let usedTLS = connMode == "wss"
        let canFallback = usedTLS ? !triedPlain : !triedTLS
        if canFallback && state == .connecting {
            AgarBot.log("[\(name)] trying \(usedTLS ? "ws" : "wss")://")
            connectWebSocket(useTLS: !usedTLS)
        } else if state != .disconnected {
            lastError = error.localizedDescription
            disconnect()
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self, !self.cancelled else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handlePacket(data)
                case .string(let str):
                    if let data = str.data(using: .utf8) {
                        self.handlePacket(data)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure(let error):
                let nsError = error as NSError
                if nsError.code == NSURLErrorCancelled { return }
                if !self.cancelled {
                    AgarBot.log("[\(self.name)] recv error: \(error.localizedDescription)")
                    self.lastError = error.localizedDescription
                    self.disconnect()
                }
            }
        }
    }

    // MARK: - Game Protocol

    private func sendGameHandshake() {
        let hs = AgarProtocol.handshakePacket()
        let vi = AgarProtocol.versionIntPacket()
        gameSend(hs)
        gameSend(vi)
        let hsHex = hs.map { String(format: "%02x", $0) }.joined(separator: " ")
        let viHex = vi.map { String(format: "%02x", $0) }.joined(separator: " ")
        let vInt = AgarProtocol.versionStringToInt(AgarProtocol.clientVersion)
        AgarBot.log("[\(name)] handshake=[\(hsHex)] verInt=[\(viHex)] (\(vInt))")
        if !serverToken.isEmpty {
            gameSend(AgarProtocol.facebookTokenPacket(token: serverToken))
            AgarBot.log("[\(name)] token sent (\(serverToken.count) chars)")
        }
    }

    private func gameSend(_ data: Data) {
        guard !cancelled, let task = webSocketTask else { return }
        let sendData: Data
        if handshakeComplete {
            sendData = AgarProtocol.xorWithKey(data, key: encryptionKey)
            encryptionKey = AgarProtocol.rotateKey(encryptionKey)
        } else {
            sendData = data
        }
        task.send(.data(sendData)) { [weak self] error in
            if let error = error, let self = self, !self.cancelled {
                AgarBot.log("[\(self.name)] send error: \(error)")
            }
        }
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

        if serverPacketCount <= 3 {
            let rawHex = data.prefix(30).map { String(format: "%02x", $0) }.joined(separator: " ")
            AgarBot.log("[\(name)] raw#\(serverPacketCount) len=\(data.count) [\(rawHex)]")
        }

        let decoded: Data
        if handshakeComplete {
            decoded = AgarProtocol.xorWithKey(data, key: decryptionKey)
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
        case .version(let mk, let ver):
            movementKey = mk
            serverVersion = ver
            let versionInt = AgarProtocol.versionStringToInt(AgarProtocol.clientVersion)
            decryptionKey = mk ^ versionInt
            let host = connectHost
            encryptionKey = AgarProtocol.murmur2("\(host)\(ver)", seed: 255)
            handshakeComplete = true
            AgarBot.log("[\(name)] F1 mk=\(mk) dk=\(decryptionKey) ek=\(encryptionKey) ver=\"\(ver)\" host=\(host)")
            spawn()

        case .outdatedVersion:
            AgarBot.log("[\(name)] OUTDATED 0x80 — client version \(AgarProtocol.clientVersion) rejected")
            lastError = "client version outdated"
            disconnect()

        case .protocolError:
            AgarBot.log("[\(name)] PROTO_ERROR 0x81 — protocol version \(AgarProtocol.protocolVersion) rejected")
            lastError = "protocol version rejected"
            disconnect()

        case .captchaRequest:
            AgarBot.log("[\(name)] CAPTCHA 0x55 — server wants reCAPTCHA")
            lastError = "captcha requested"
            disconnect()

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
            for newId in ids {
                if !ownIDs.contains(newId) {
                    ownIDs.append(newId)
                }
            }
            if !ownIDs.isEmpty && !isAlive {
                isAlive = true
                state = .alive
                AgarBot.log("[\(name)] ALIVE ids=\(ownIDs)")
                delegate?.bot(self, didSpawnWithIDs: ownIDs)
                startMovementLoop()
            }

        case .worldBorder(let border):
            worldBorder = border
            AgarBot.log("[\(name)] world border")
            if !isAlive && (state == .connecting || state == .connected || state == .spawning) {
                spawn()
            }

        case .clearAll:
            cells.removeAll()

        case .clearCell(let cid):
            cells.removeValue(forKey: cid)
            ownIDs.removeAll { $0 == cid }
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
                    if !isAlive && (state == .connecting || state == .connected || state == .spawning) {
                        spawn()
                    }
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
            gameSend(AgarProtocol.movePacket(x: rx, y: ry, movementKey: movementKey))
            gameSend(AgarProtocol.ejectMassPacket())
        }
    }

    private func moveToTarget() {
        guard let t = targetPosition else {
            gameSend(AgarProtocol.movePacket(x: worldBorder.centerX, y: worldBorder.centerY, movementKey: movementKey))
            return
        }
        gameSend(AgarProtocol.movePacket(x: t.x, y: t.y, movementKey: movementKey))
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
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }
}
