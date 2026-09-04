import Foundation
import Combine

class BotEngine: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var statusMessage: String = "Idle"
    @Published var totalSpawned: Int = 0
    @Published var totalAlive: Int = 0

    weak var settings: GameSettings?
    var bots: [AgarBot] = []

    private var targetX: Double = 0
    private var targetY: Double = 0
    private var uidTimer: Timer?

    func startBots(config: BotConfiguration) {
        guard !isRunning else { return }

        guard NetworkInterceptor.shared.hasServer else {
            statusMessage = "No server - play a game first"
            return
        }

        isRunning = true
        statusMessage = "Resolving..."

        ServerResolver.resolveServer(partyCode: config.partyCode) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    self?.statusMessage = "Spawning..."
                    self?.spawnBots(config: config, serverInfo: info)
                    self?.startUIDDetection()
                case .failure(let error):
                    self?.statusMessage = error.localizedDescription
                    self?.isRunning = false
                }
            }
        }
    }

    func stopBots() {
        uidTimer?.invalidate()
        uidTimer = nil
        for bot in bots { bot.disconnect() }
        bots.removeAll()
        totalAlive = 0
        totalSpawned = 0
        isRunning = false
        statusMessage = "Stopped"
    }

    func updateTarget(x: Double, y: Double) {
        targetX = x
        targetY = y
        for bot in bots { bot.setTarget(x: x, y: y) }
    }

    private func startUIDDetection() {
        uidTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let settings = self.settings else { return }
            guard !settings.playerName.isEmpty else {
                if !settings.detectedUID.isEmpty {
                    DispatchQueue.main.async { settings.detectedUID = "" }
                }
                return
            }
            for bot in self.bots {
                if let cell = bot.findCellByName(settings.playerName) {
                    let uid = String(format: "%08X", cell.id)
                    if settings.detectedUID != uid {
                        DispatchQueue.main.async { settings.detectedUID = uid }
                    }
                    return
                }
            }
        }
    }

    private func spawnBots(config: BotConfiguration, serverInfo: ServerResolver.ServerInfo) {
        let names = config.resolvedNames
        let count = min(config.botCount, 50)

        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) { [weak self] in
                guard let self = self, self.isRunning else { return }

                let bot = AgarBot(
                    name: names[i % names.count],
                    serverURL: serverInfo.url,
                    serverToken: serverInfo.token,
                    action: config.botAction
                )
                bot.targetUID = config.targetUID
                bot.delegate = self
                bot.setTarget(x: self.targetX, y: self.targetY)
                bot.connect()

                self.bots.append(bot)
                self.totalSpawned += 1
                self.statusMessage = "Spawning \(self.totalSpawned)/\(config.botCount)"
            }
        }
    }

    private func recountAlive() {
        totalAlive = bots.filter { $0.state == .alive }.count
    }
}

extension BotEngine: AgarBotDelegate {
    func bot(_ bot: AgarBot, didUpdateState state: AgarBot.State) {
        DispatchQueue.main.async { [weak self] in
            self?.recountAlive()
            switch state {
            case .alive:
                self?.statusMessage = "Alive: \(self?.totalAlive ?? 0)"
            case .dead:
                self?.statusMessage = "Respawning..."
            case .disconnected:
                let err = bot.lastError
                self?.bots.removeAll { $0.id == bot.id }
                self?.recountAlive()
                if self?.bots.isEmpty == true {
                    self?.isRunning = false
                    self?.statusMessage = err.isEmpty ? "All disconnected" : "Error: \(err)"
                }
            default: break
            }
        }
    }

    func bot(_ bot: AgarBot, didSpawnWithIDs ids: [UInt32]) {}

    func bot(_ bot: AgarBot, didReceiveWorldUpdate updates: [CellUpdate]) {
        DispatchQueue.main.async { [weak self] in
            guard let settings = self?.settings else { return }
            for cell in updates {
                guard !cell.name.isEmpty, !cell.isVirus else { continue }
                let info = PlayerInfo(
                    id: cell.id, name: cell.name,
                    x: Double(cell.x), y: Double(cell.y),
                    mass: Double(cell.size) * Double(cell.size) / 100.0,
                    color: cell.color, isVirus: false
                )
                if let idx = settings.currentPlayers.firstIndex(where: { $0.id == info.id }) {
                    settings.currentPlayers[idx] = info
                } else {
                    settings.currentPlayers.append(info)
                }
            }
            if settings.currentPlayers.count > 80 {
                settings.currentPlayers = settings.currentPlayers
                    .sorted { $0.mass > $1.mass }
                    .prefix(60).map { $0 }
            }
        }
    }

    func botDidDisconnect(_ bot: AgarBot) {}
}
