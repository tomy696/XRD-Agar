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
    let massBoost: MassBoost
    let action: BotAction
    let shouldSplit: Bool

    weak var delegate: AgarBotDelegate?

    enum State {
        case idle
        case connecting
        case connected
        case spawning
        case alive
        case feeding
        case dead
        case disconnected
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
    private var feedCyclesRemaining: Int = 0
    private var isAlive: Bool = false
    private var respawnCount: Int = 0
    private let maxRespawns: Int = 50

    init(name: String, serverURL: String, serverToken: String,
         massBoost: MassBoost, action: BotAction, shouldSplit: Bool) {
        self.name = name
        self.serverURL = serverURL
        self.serverToken = serverToken
        self.massBoost = massBoost
        self.action = action
        self.shouldSplit = shouldSplit
        super.init()
    }

    func connect() {
        state = .connecting
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Origin": "https://agar.io",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
        ]
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        guard let url = URL(string: serverURL) else {
            state = .disconnected
            return
        }

        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        sendHandshake()
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

    // MARK: - Packet Sending

    private func sendHandshake() {
        sendBinary(AgarProtocol.handshakePacket())
        sendBinary(AgarProtocol.connectionKeyPacket())

        if !serverToken.isEmpty {
            sendBinary(AgarProtocol.facebookTokenPacket(token: serverToken))
        }
    }

    func spawn() {
        state = .spawning
        feedCyclesRemaining = massBoost.feedCycles
        sendBinary(AgarProtocol.spawnPacket(name: name))
    }

    private func sendMove(x: Double, y: Double) {
        sendBinary(AgarProtocol.movePacket(x: x, y: y))
    }

    private func sendSplit() {
        sendBinary(AgarProtocol.splitPacket())
    }

    private func sendEjectMass() {
        sendBinary(AgarProtocol.ejectMassPacket())
    }

    private func sendBinary(_ data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocket?.send(message) { _ in }
    }

    // MARK: - Receive Loop

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handlePacket(data)
                case .string:
                    break
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure:
                self.disconnect()
            }
        }
    }

    // MARK: - Packet Handling

    private func handlePacket(_ data: Data) {
        guard let packet = AgarProtocol.parsePacket(data) else { return }

        switch packet {
        case .worldUpdate(let eatRecords, let updates, let removals):
            for update in updates {
                cells[update.id] = update
            }
            for removal in removals {
                cells.removeValue(forKey: removal)
            }
            for record in eatRecords {
                cells.removeValue(forKey: record.eaten)
                if ownIDs.contains(record.eaten) {
                    ownIDs.removeAll { $0 == record.eaten }
                }
            }

            if isAlive && ownIDs.isEmpty {
                isAlive = false
                state = .dead
                handleDeath()
            }

            if isAlive {
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
            if state == .connecting {
                state = .connected
                spawn()
            }

        case .clearAll:
            cells.removeAll()

        case .clearCell(let id):
            cells.removeValue(forKey: id)
            if ownIDs.contains(id) {
                ownIDs.removeAll { $0 == id }
                if ownIDs.isEmpty {
                    isAlive = false
                    state = .dead
                    handleDeath()
                }
            }

        default:
            break
        }
    }

    // MARK: - AI / Actions

    private func startMovementLoop() {
        moveTimer?.invalidate()
        moveTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.performAction()
        }
    }

    private func performAction() {
        guard isAlive else { return }

        switch action {
        case .suicide:
            moveToTarget()
            if shouldSplit {
                sendSplit()
            }

        case .feedTarget:
            moveToTarget()
            sendEjectMass()

        case .destroyViruses:
            if let virus = findNearestVirus() {
                sendMove(x: Double(virus.x), y: Double(virus.y))
                sendSplit()
            } else {
                moveToTarget()
            }

        case .createCorpses:
            let rx = Double.random(in: worldBorder.minX...worldBorder.maxX)
            let ry = Double.random(in: worldBorder.minY...worldBorder.maxY)
            sendMove(x: rx, y: ry)
            for _ in 0..<5 { sendEjectMass() }

        case .feedEverywhere:
            let rx = Double.random(in: worldBorder.minX...worldBorder.maxX)
            let ry = Double.random(in: worldBorder.minY...worldBorder.maxY)
            sendMove(x: rx, y: ry)
            sendEjectMass()
        }
    }

    private func moveToTarget() {
        guard let target = targetPosition else {
            let cx = worldBorder.centerX
            let cy = worldBorder.centerY
            sendMove(x: cx, y: cy)
            return
        }
        sendMove(x: target.x, y: target.y)
    }

    private func findNearestVirus() -> CellUpdate? {
        guard let ownPos = ownPosition else { return nil }
        return cells.values
            .filter { $0.isVirus }
            .min { a, b in
                let distA = pow(Double(a.x) - ownPos.x, 2) + pow(Double(a.y) - ownPos.y, 2)
                let distB = pow(Double(b.x) - ownPos.x, 2) + pow(Double(b.y) - ownPos.y, 2)
                return distA < distB
            }
    }

    private var ownPosition: (x: Double, y: Double)? {
        let ownCells = ownIDs.compactMap { cells[$0] }
        guard !ownCells.isEmpty else { return nil }
        let x = ownCells.map { Double($0.x) }.reduce(0, +) / Double(ownCells.count)
        let y = ownCells.map { Double($0.y) }.reduce(0, +) / Double(ownCells.count)
        return (x, y)
    }

    private func handleDeath() {
        moveTimer?.invalidate()
        moveTimer = nil
        respawnCount += 1
        guard respawnCount < maxRespawns else {
            disconnect()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.spawn()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension AgarBot: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        state = .connected
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        disconnect()
    }
}
