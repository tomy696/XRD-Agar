import Foundation
import Combine

class BotServerClient: ObservableObject {
    static let shared = BotServerClient()

    @Published var isConnected = false
    @Published var sessionId: String?
    @Published var alive: Int = 0
    @Published var total: Int = 0
    @Published var paused: Bool = false
    @Published var statusMessage: String = "Idle"
    @Published var serverBotURL: String = ""

    private var pollTimer: Timer?
    private let session = URLSession(configuration: .ephemeral)
    private let defaultURL = "https://xrd-agar-production.up.railway.app"

    var baseURL: String {
        let url = serverBotURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? defaultURL : url
    }

    func startBots(count: Int, names: [String], mode: String, targetX: Double, targetY: Double, gameServerURL: String?, serverIP: String? = nil) {
        guard sessionId == nil else { return }

        statusMessage = "Starting..."

        var body: [String: Any] = [
            "count": count,
            "names": names,
            "mode": mode,
            "targetX": targetX,
            "targetY": targetY
        ]

        if let url = gameServerURL, !url.isEmpty {
            body["serverURL"] = url
        }
        if let ip = serverIP, !ip.isEmpty {
            body["serverIP"] = ip
        }

        post("/api/start", body: body) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    self?.sessionId = json["sessionId"] as? String
                    self?.total = json["botCount"] as? Int ?? count
                    self?.isConnected = true
                    self?.paused = false
                    self?.statusMessage = "Spawning \(count) bots..."
                    self?.startPolling()
                case .failure(let err):
                    self?.statusMessage = "Error: \(err.localizedDescription)"
                }
            }
        }
    }

    func stopBots() {
        guard let sid = sessionId else { return }
        post("/api/stop", body: ["sessionId": sid]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.cleanup()
                self?.statusMessage = "Stopped"
            }
        }
    }

    func pauseBots() {
        guard let sid = sessionId else { return }
        post("/api/pause", body: ["sessionId": sid]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.paused = true
                self?.statusMessage = "Paused (\(self?.alive ?? 0) alive)"
            }
        }
    }

    func resumeBots() {
        guard let sid = sessionId else { return }
        post("/api/resume", body: ["sessionId": sid]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.paused = false
                self?.statusMessage = "Resumed"
            }
        }
    }

    func updateTarget(x: Double, y: Double) {
        guard let sid = sessionId else { return }
        post("/api/target", body: ["sessionId": sid, "x": x, "y": y]) { _ in }
    }

    func updateMode(_ mode: String) {
        guard let sid = sessionId else { return }
        post("/api/mode", body: ["sessionId": sid, "mode": mode]) { _ in }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollStatus()
        }
    }

    private func pollStatus() {
        guard let sid = sessionId else { return }
        get("/api/status/\(sid)") { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    let a = json["alive"] as? Int ?? 0
                    let t = json["total"] as? Int ?? 0
                    self?.alive = a
                    self?.total = t
                    if !( self?.paused ?? false) {
                        if a > 0 {
                            self?.statusMessage = "\(a)/\(t) alive"
                        } else if t > 0 {
                            self?.statusMessage = "Spawning..."
                        }
                    }
                    if t == 0 && self?.sessionId != nil {
                        self?.cleanup()
                        self?.statusMessage = "All disconnected"
                    }
                case .failure:
                    break
                }
            }
        }
    }

    private func cleanup() {
        pollTimer?.invalidate()
        pollTimer = nil
        sessionId = nil
        isConnected = false
        alive = 0
        total = 0
        paused = false
    }

    // MARK: - HTTP

    private func post(_ path: String, body: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: baseURL + path) else {
            completion(.failure(ClientError.badURL))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: req) { data, _, error in
            if let error = error { return completion(.failure(error)) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return completion(.failure(ClientError.badResponse)) }
            completion(.success(json))
        }.resume()
    }

    private func get(_ path: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: baseURL + path) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10

        session.dataTask(with: req) { data, _, error in
            if let error = error { return completion(.failure(error)) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return completion(.failure(ClientError.badResponse)) }
            completion(.success(json))
        }.resume()
    }

    enum ClientError: LocalizedError {
        case badURL, badResponse
        var errorDescription: String? {
            switch self {
            case .badURL: return "Invalid server URL"
            case .badResponse: return "Bad response from bot server"
            }
        }
    }
}
