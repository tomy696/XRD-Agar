import Foundation
import Combine

class BotEngine: ObservableObject {
    @Published var bots: [AgarBot] = []
    @Published var activeBotCount: Int = 0
    @Published var isRunning: Bool = false
    @Published var statusMessage: String = "Idle"
    @Published var totalSpawned: Int = 0
    @Published var totalAlive: Int = 0

    weak var settings: GameSettings?

    private var targetX: Double = 0
    private var targetY: Double = 0
    private var serverInfo: ServerResolver.ServerInfo?
    private var uidTimer: Timer?

    func startBots(config: BotConfiguration) {
        guard !isRunning else { return }
        isRunning = true
        statusMessage = "Resolving server..."

        let region = config.region
        let mode = config.gameMode
        let partyCode = config.partyCode

        ServerResolver.resolveServer(region: region, gameMode: mode, partyCode: partyCode) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    self?.serverInfo = info
                    self?.statusMessage = "Server found. Spawning bots..."
                    self?.spawnBots(config: config, serverInfo: info)
                    self?.startUIDDetection()
                case .failure(let error):
                    self?.statusMessage = "Error: \(error.localizedDescription)"
                    self?.isRunning = false
                }
            }
        }
    }

    func stopBots() {
        uidTimer?.invalidate()
        uidTimer = nil
        for bot in bots {
            bot.disconnect()
        }
        bots.removeAll()
        activeBotCount = 0
        totalAlive = 0
        totalSpawned = 0
        isRunning = false
        statusMessage = "Stopped"
    }

    func updateTarget(x: Double, y: Double) {
        targetX = x
        targetY = y
        for bot in bots {
            bot.setTarget(x: x, y: y)
        }
    }

    func updateTargetFromPlayer(_ player: PlayerInfo) {
        updateTarget(x: player.x, y: player.y)
    }

    // MARK: - UID Detection

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

    // MARK: - Spawning

    private func spawnBots(config: BotConfiguration, serverInfo: ServerResolver.ServerInfo) {
        let names = config.resolvedNames
        let batchSize = min(config.botCount, 50)

        for i in 0..<batchSize {
            let delay = Double(i) * 0.15

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.isRunning else { return }

                let bot = AgarBot(
                    name: names[i % names.count],
                    serverURL: serverInfo.url,
                    serverToken: serverInfo.token,
                    massBoost: config.massBoost,
                    action: config.botAction,
                    shouldSplit: config.shouldSplit
                )
                bot.targetUID = config.targetUID
                bot.delegate = self
                bot.setTarget(x: self.targetX, y: self.targetY)
                bot.connect()

                self.bots.append(bot)
                self.totalSpawned += 1
                self.activeBotCount = self.bots.count
                self.statusMessage = "Spawning... \(self.totalSpawned)/\(config.botCount)"
            }
        }

        if config.botCount > 50 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(50) * 0.15 + 1.0) { [weak self] in
                guard let self = self, self.isRunning else { return }
                var remainingConfig = config
                remainingConfig.botCount = config.botCount - 50
                self.spawnBots(config: remainingConfig, serverInfo: serverInfo)
            }
        }
    }

    private func recountAlive() {
        totalAlive = bots.filter { bot in
            switch bot.state {
            case .alive, .feeding: return true
            default: return false
            }
        }.count
    }
}

extension BotEngine: AgarBotDelegate {
    func bot(_ bot: AgarBot, didUpdateState state: AgarBot.State) {
        DispatchQueue.main.async { [weak self] in
            self?.recountAlive()
            switch state {
            case .alive:
                self?.statusMessage = "Bots alive: \(self?.totalAlive ?? 0)"
            case .dead:
                self?.statusMessage = "Bot died, respawning..."
            case .disconnected:
                self?.bots.removeAll { $0.id == bot.id }
                self?.activeBotCount = self?.bots.count ?? 0
                self?.recountAlive()
                if self?.bots.isEmpty == true {
                    self?.isRunning = false
                    self?.statusMessage = "All bots disconnected"
                }
            default:
                break
            }
        }
    }

    func bot(_ bot: AgarBot, didSpawnWithIDs ids: [UInt32]) {}

    func bot(_ bot: AgarBot, didReceiveWorldUpdate players: [CellUpdate]) {}

    func botDidDisconnect(_ bot: AgarBot) {}
}
