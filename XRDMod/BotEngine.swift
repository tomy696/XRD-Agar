import Foundation
import Combine

class BotEngine: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var statusMessage: String = "Idle"
    @Published var totalSpawned: Int = 0
    @Published var totalAlive: Int = 0

    let client = BotServerClient.shared

    private var cancellables = Set<AnyCancellable>()
    private var targetX: Double = 0
    private var targetY: Double = 0

    init() {
        client.$isConnected.sink { [weak self] connected in
            DispatchQueue.main.async { self?.isRunning = connected }
        }.store(in: &cancellables)

        client.$alive.sink { [weak self] alive in
            DispatchQueue.main.async { self?.totalAlive = alive }
        }.store(in: &cancellables)

        client.$total.sink { [weak self] total in
            DispatchQueue.main.async { self?.totalSpawned = total }
        }.store(in: &cancellables)

        client.$statusMessage.sink { [weak self] msg in
            DispatchQueue.main.async { self?.statusMessage = msg }
        }.store(in: &cancellables)

        client.$paused.sink { [weak self] p in
            DispatchQueue.main.async { self?.isPaused = p }
        }.store(in: &cancellables)
    }

    func startBots(config: BotConfiguration) {
        guard !isRunning else { return }

        let interceptor = NetworkInterceptor.shared
        let capturedURL = interceptor.bestServerURL
        let capturedToken = interceptor.capturedToken

        client.startBots(
            count: config.botCount,
            names: config.resolvedNames,
            mode: config.botAction.serverMode,
            targetX: targetX,
            targetY: targetY,
            partyCode: config.partyCode.isEmpty ? nil : config.partyCode,
            region: config.region,
            botKey: config.botKey.isEmpty ? nil : config.botKey,
            gameMode: config.gameMode.serverCode,
            targetUID: config.targetUIDs.first ?? "",
            tripleMass: config.tripleMass,
            boosterMode: config.boosterMode,
            feedtrackMode: config.feedtrackMode,
            botSkin: config.botSkin,
            serverURL: capturedURL,
            serverToken: capturedToken
        )
    }

    func stopBots() {
        client.stopBots()
    }

    func pauseBots() {
        client.pauseBots()
    }

    func resumeBots() {
        client.resumeBots()
    }

    func updateTarget(x: Double, y: Double) {
        targetX = x
        targetY = y
        client.updateTarget(x: x, y: y)
    }
}
