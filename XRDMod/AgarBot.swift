import Foundation

protocol AgarBotDelegate: AnyObject {
    func bot(_ bot: AgarBot, didUpdateState state: AgarBot.State)
    func bot(_ bot: AgarBot, didSpawnWithIDs ids: [UInt32])
    func bot(_ bot: AgarBot, didReceiveWorldUpdate players: [CellUpdate])
    func botDidDisconnect(_ bot: AgarBot)
}

class AgarBot: NSObject, Identifiable {
    let id = UUID()
    let name: String
    let serverURL: String
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

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var targetPosition: (x: Double, y: Double)?
    private var ownIDs: [UInt32] = []
    private var cells: [UInt32: CellUpdate] = [:]
    private var worldBorder: WorldBorder = .default
    private var moveTimer: Timer?
    private var isAlive: Bool = false
    private var respawnCount: Int = 0

    init(name: String, serverURL: String, serverToken: String, action: BotAction) {
        self.name = name
        self.serverURL = serverURL
        self.serverToken = serverToken
        self.action = action
        super.init()
    }

    private(set) var lastError: String = ""

    func connect() {
        state = .connecting
        lastError = ""
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Origin": "https://agar.io",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
        ]
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        if let s = session { NetworkInterceptor.shared.botSessions.add(s) }

        guard let url = URL(string: serverURL) else {
            lastError = "Bad URL"
            state = .disconnected
            return
        }

        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()
        receiveLoop()
    }

    func disconnect() {
        moveTimer?.invalidate()
        moveTimer = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        state = .disconnected
        delegate?.botDidDisconnect(self)
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
        webSocket?.send(.data(data)) { _ in }
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                if case .data(let data) = message {
                    self.handlePacket(data)
                }
                self.receiveLoop()
            case .failure:
                self.disconnect()
            }
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

extension AgarBot: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        state = .connected
        sendHandshake()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lastError = "Closed: \(closeCode.rawValue)"
        disconnect()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            lastError = String(error.localizedDescription.prefix(60))
            disconnect()
        }
    }
}
