import Foundation
import Darwin.POSIX

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
    private(set) var lastError: String = ""

    // diagnostic log visible in dump even after disconnect
    static var recentLog: [String] = []
    private static func log(_ msg: String) {
        DispatchQueue.main.async {
            if recentLog.count >= 30 { recentLog.removeFirst() }
            recentLog.append(msg)
        }
    }

    private var sockfd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var recvBuffer = Data()
    private var wsReady = false
    private var upgradeTimer: Timer?

    private var targetPosition: (x: Double, y: Double)?
    private var ownIDs: [UInt32] = []
    private var cells: [UInt32: CellUpdate] = [:]
    private var worldBorder: WorldBorder = .default
    private var moveTimer: Timer?
    private var isAlive: Bool = false
    private var respawnCount: Int = 0
    private var cancelled = false

    init(name: String, serverIP: String, serverPort: Int, serverHostname: String, serverToken: String, action: BotAction) {
        self.name = name
        self.serverIP = serverIP
        self.serverPort = serverPort
        self.serverHostname = serverHostname
        self.serverToken = serverToken
        self.action = action
    }

    deinit {
        cleanup()
    }

    // MARK: - Connection (blocking connect on background queue)

    func connect() {
        state = .connecting
        lastError = ""
        connMode = "bsd"
        recvBuffer.removeAll()
        wsReady = false
        cancelled = false

        AgarBot.log("[\(name)] connecting to \(serverIP):\(serverPort)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, !self.cancelled else { return }

            let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else {
                let e = errno
                AgarBot.log("[\(self.name)] socket() failed errno=\(e)")
                DispatchQueue.main.async {
                    self.lastError = "socket errno=\(e)"
                    self.state = .disconnected
                }
                return
            }

            // prevent SIGPIPE crash
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            // 10s connect timeout via SO_SNDTIMEO
            var tv = timeval(tv_sec: 10, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(self.serverPort).bigEndian

            guard inet_pton(AF_INET, self.serverIP, &addr.sin_addr) == 1 else {
                AgarBot.log("[\(self.name)] bad IP \(self.serverIP)")
                Darwin.close(fd)
                DispatchQueue.main.async {
                    self.lastError = "bad IP"
                    self.state = .disconnected
                }
                return
            }

            AgarBot.log("[\(self.name)] calling connect() fd=\(fd)")

            let ret = withUnsafePointer(to: &addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    Darwin.connect(fd, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            let connectErrno = errno

            guard !self.cancelled else {
                Darwin.close(fd)
                return
            }

            if ret != 0 {
                AgarBot.log("[\(self.name)] connect() failed errno=\(connectErrno) (\(self.errnoName(connectErrno)))")
                Darwin.close(fd)
                DispatchQueue.main.async {
                    self.lastError = "connect errno=\(connectErrno) \(self.errnoName(connectErrno))"
                    self.state = .disconnected
                }
                return
            }

            AgarBot.log("[\(self.name)] TCP connected! fd=\(fd)")

            DispatchQueue.main.async {
                guard !self.cancelled else {
                    Darwin.close(fd)
                    return
                }
                self.sockfd = fd
                self.onTCPConnected()
            }
        }
    }

    private func errnoName(_ e: Int32) -> String {
        switch e {
        case 60: return "ETIMEDOUT"
        case 61: return "ECONNREFUSED"
        case 54: return "ECONNRESET"
        case 51: return "ENETUNREACH"
        case 50: return "ENETDOWN"
        case 65: return "EHOSTUNREACH"
        case 36: return "EINPROGRESS"
        case 48: return "EADDRINUSE"
        case 22: return "EINVAL"
        case 0: return "OK"
        default: return "E?\(e)"
        }
    }

    private func onTCPConnected() {
        connMode = "bsd-tcp"

        // switch to non-blocking for async reads
        let flags = fcntl(sockfd, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(sockfd, F_SETFL, flags | O_NONBLOCK) }

        let rs = DispatchSource.makeReadSource(fileDescriptor: sockfd, queue: .main)
        self.readSource = rs
        rs.setEventHandler { [weak self] in self?.onReadable() }
        rs.resume()

        sendWSUpgrade()

        upgradeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.wsReady else { return }
            AgarBot.log("[\(self.name)] WS upgrade timeout, trying raw binary")
            self.connMode = "bsd-raw"
            self.wsReady = true
            self.recvBuffer.removeAll()
            self.state = .connected
            self.sendGameHandshake()
        }
    }

    // MARK: - WebSocket Upgrade

    private func sendWSUpgrade() {
        var keyBytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { keyBytes[i] = UInt8.random(in: 0...255) }
        let wsKey = Data(keyBytes).base64EncodedString()

        let req = "GET / HTTP/1.1\r\n" +
            "Host: \(serverHostname):\(serverPort)\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Key: \(wsKey)\r\n" +
            "Sec-WebSocket-Version: 13\r\n" +
            "Origin: https://agar.io\r\n" +
            "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)\r\n" +
            "\r\n"
        AgarBot.log("[\(name)] sending WS upgrade")
        sockSend(Data(req.utf8))
    }

    private func processUpgradeResponse() {
        guard let end = recvBuffer.range(of: Data("\r\n\r\n".utf8)) else { return }
        upgradeTimer?.invalidate()
        upgradeTimer = nil

        let hdr = String(data: recvBuffer.subdata(in: 0..<end.lowerBound), encoding: .utf8) ?? ""
        let firstLine = hdr.components(separatedBy: "\r\n").first ?? ""
        recvBuffer.removeSubrange(0..<end.upperBound)

        AgarBot.log("[\(name)] upgrade response: \(firstLine)")

        if hdr.contains("101") {
            wsReady = true
            connMode = "bsd-ws"
            state = .connected
            AgarBot.log("[\(name)] WS connected, sending handshake")
            sendGameHandshake()
            if !recvBuffer.isEmpty { processWSFrames() }
        } else {
            wsReady = true
            connMode = "bsd-raw"
            recvBuffer.removeAll()
            state = .connected
            AgarBot.log("[\(name)] WS rejected, trying raw binary")
            sendGameHandshake()
        }
    }

    // MARK: - Data Reception

    private func onReadable() {
        var buf = [UInt8](repeating: 0, count: 65536)
        let n = recv(sockfd, &buf, buf.count, 0)

        if n == 0 {
            AgarBot.log("[\(name)] server closed connection")
            lastError = "Server closed"
            disconnect()
            return
        }
        if n < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            AgarBot.log("[\(name)] recv errno=\(errno)")
            lastError = "recv errno=\(errno)"
            disconnect()
            return
        }

        recvBuffer.append(contentsOf: buf[0..<n])

        if !wsReady {
            processUpgradeResponse()
        } else if connMode == "bsd-ws" {
            processWSFrames()
        } else {
            handlePacket(recvBuffer)
            recvBuffer.removeAll()
        }
    }

    // MARK: - WebSocket Frame I/O

    private func processWSFrames() {
        while recvBuffer.count >= 2 {
            let b0 = recvBuffer[0]
            let b1 = recvBuffer[1]
            let opcode = b0 & 0x0F
            let masked = (b1 & 0x80) != 0
            var payloadLen = Int(b1 & 0x7F)
            var headerLen = 2

            if payloadLen == 126 {
                guard recvBuffer.count >= 4 else { return }
                payloadLen = Int(recvBuffer[2]) << 8 | Int(recvBuffer[3])
                headerLen = 4
            } else if payloadLen == 127 {
                guard recvBuffer.count >= 10 else { return }
                payloadLen = 0
                for i in 0..<8 { payloadLen = (payloadLen << 8) | Int(recvBuffer[2 + i]) }
                headerLen = 10
            }

            let maskLen = masked ? 4 : 0
            let totalLen = headerLen + maskLen + payloadLen
            guard recvBuffer.count >= totalLen else { return }

            var payload = Data(recvBuffer[(headerLen + maskLen)..<totalLen])
            if masked {
                let mk = Array(recvBuffer[headerLen..<(headerLen + 4)])
                for i in 0..<payload.count { payload[i] ^= mk[i % 4] }
            }

            recvBuffer.removeSubrange(0..<totalLen)

            switch opcode {
            case 0x01, 0x02: handlePacket(payload)
            case 0x08: disconnect(); return
            case 0x09: sendWSPong(payload)
            default: break
            }
        }
    }

    private func wsSend(_ payload: Data) {
        var frame = Data()
        frame.append(0x82)

        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len) | 0x80)
        } else if len < 65536 {
            frame.append(126 | 0x80)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(127 | 0x80)
            for i in (0..<8).reversed() { frame.append(UInt8((len >> (i * 8)) & 0xFF)) }
        }

        var mask = [UInt8](repeating: 0, count: 4)
        for i in 0..<4 { mask[i] = UInt8.random(in: 0...255) }
        frame.append(contentsOf: mask)
        for i in 0..<len { frame.append(payload[i] ^ mask[i % 4]) }
        sockSend(frame)
    }

    private func sendWSPong(_ data: Data) {
        var frame = Data()
        frame.append(0x8A)
        let len = min(data.count, 125)
        frame.append(UInt8(len) | 0x80)
        var mask = [UInt8](repeating: 0, count: 4)
        for i in 0..<4 { mask[i] = UInt8.random(in: 0...255) }
        frame.append(contentsOf: mask)
        for i in 0..<len { frame.append(data[i] ^ mask[i % 4]) }
        sockSend(frame)
    }

    // MARK: - Socket I/O

    private func sockSend(_ data: Data) {
        guard sockfd >= 0 else { return }
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = Darwin.send(sockfd, base + sent, data.count - sent, 0)
                if n <= 0 { return }
                sent += n
            }
        }
    }

    private func closeSock() {
        if sockfd >= 0 {
            Darwin.close(sockfd)
            sockfd = -1
        }
    }

    private func cleanup() {
        moveTimer?.invalidate()
        moveTimer = nil
        upgradeTimer?.invalidate()
        upgradeTimer = nil
        readSource?.cancel()
        readSource = nil
        closeSock()
    }

    // MARK: - Game Protocol

    private func sendGameHandshake() {
        gameSend(AgarProtocol.handshakePacket())
        gameSend(AgarProtocol.connectionKeyPacket())
        if !serverToken.isEmpty {
            gameSend(AgarProtocol.facebookTokenPacket(token: serverToken))
        }
    }

    private func gameSend(_ data: Data) {
        if connMode == "bsd-ws" {
            wsSend(data)
        } else {
            sockSend(data)
        }
    }

    // MARK: - Public API

    func disconnect() {
        cancelled = true
        cleanup()
        recvBuffer.removeAll()
        wsReady = false
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
                AgarBot.log("[\(name)] ALIVE ids=\(ids)")
                delegate?.bot(self, didSpawnWithIDs: ids)
                startMovementLoop()
            }

        case .worldBorder(let border):
            worldBorder = border
            AgarBot.log("[\(name)] got world border, spawning")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.spawn()
        }
    }
}
