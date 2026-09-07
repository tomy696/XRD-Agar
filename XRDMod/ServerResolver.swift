import Foundation

class ServerResolver {

    static let browserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    static let webBouncer = "webbouncer-live-v8-0.agario.miniclippt.com"

    struct ServerInfo {
        let url: String
        let token: String
        let ip: String
        let port: Int
        let hostname: String
    }

    static func resolveServer(
        partyCode: String = "",
        completion: @escaping (Result<ServerInfo, Error>) -> Void
    ) {
        // Strategy:
        // 1. API discovery (findServer) — returns a proper WebSocket game server
        // 2. Captured IP on port 443 — same IP might serve WebSocket on :443
        // 3. Webbouncer direct — guaranteed WebSocket endpoint

        discoverViaAPI(index: 0, partyCode: partyCode) { result in
            switch result {
            case .success(let info):
                AgarBot.log("[SR] API found: \(info.hostname):\(info.port)")
                completion(.success(info))

            case .failure:
                // Try captured IP on standard WebSocket port 443
                let interceptor = NetworkInterceptor.shared
                if let ip = interceptor.capturedServerIP, !ip.isEmpty {
                    AgarBot.log("[SR] Trying captured IP \(ip) on :443")
                    completion(.success(ServerInfo(
                        url: "wss://\(ip):443",
                        token: partyCode, ip: ip, port: 443, hostname: ip
                    )))
                    return
                }

                // Fallback: connect directly to webbouncer
                AgarBot.log("[SR] Using webbouncer direct")
                completion(.success(ServerInfo(
                    url: "wss://\(webBouncer):443",
                    token: partyCode, ip: webBouncer, port: 443, hostname: webBouncer
                )))
            }
        }
    }

    // MARK: - API Discovery

    private static let apiEndpoints = [
        "https://webbouncer-live-v8-0.agario.miniclippt.com/findServer",
        "https://web-arenas-live-v25-0.agario.miniclippt.com/findServer",
    ]

    private static func discoverViaAPI(
        index: Int, partyCode: String,
        completion: @escaping (Result<ServerInfo, Error>) -> Void
    ) {
        guard index < apiEndpoints.count else {
            completion(.failure(ServerError.noServerFound))
            return
        }

        guard let url = URL(string: apiEndpoints[index]) else {
            discoverViaAPI(index: index + 1, partyCode: partyCode, completion: completion)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://agar.io", forHTTPHeaderField: "Origin")
        request.setValue("https://agar.io/", forHTTPHeaderField: "Referer")
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.httpBody = "EU-London".data(using: .utf8)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

                if let error = error {
                    AgarBot.log("[SR] API[\(index)] err: \(error.localizedDescription)")
                    discoverViaAPI(index: index + 1, partyCode: partyCode, completion: completion)
                    return
                }

                guard let data = data else {
                    discoverViaAPI(index: index + 1, partyCode: partyCode, completion: completion)
                    return
                }

                let responseText = String(data: data, encoding: .utf8) ?? "(binary)"
                AgarBot.log("[SR] API[\(index)] HTTP \(httpStatus) len=\(data.count): \(responseText.prefix(200))")

                if let info = parseResponse(data: data, text: responseText, partyCode: partyCode) {
                    completion(.success(info))
                    return
                }

                discoverViaAPI(index: index + 1, partyCode: partyCode, completion: completion)
            }
        }.resume()
    }

    private static func parseResponse(data: Data, text: String, partyCode: String) -> ServerInfo? {
        // JSON: {"endpoints":[{"url":"wss://..."}],"token":"..."}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var serverURL: String?
            if let endpoints = json["endpoints"] as? [[String: Any]], let first = endpoints.first {
                serverURL = (first["url"] as? String) ?? (first["server"] as? String)
            }
            if serverURL == nil { serverURL = json["url"] as? String }
            if serverURL == nil { serverURL = json["server"] as? String }
            if serverURL == nil { serverURL = json["ip"] as? String }

            if let server = serverURL, !server.isEmpty {
                let wsURL = (server.hasPrefix("ws://") || server.hasPrefix("wss://")) ? server : "wss://\(server)"
                if let parsed = URLComponents(string: wsURL), let host = parsed.host {
                    let token = (json["token"] as? String) ?? partyCode
                    return ServerInfo(url: wsURL, token: token, ip: host, port: parsed.port ?? 443, hostname: host)
                }
            }
        }

        // Text: ip:port\ntoken
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n")
        if let first = lines.first {
            let server = String(first).trimmingCharacters(in: .whitespaces)
            if !server.isEmpty, !server.contains(" "), !server.contains("<"),
               server.contains(".") || server.contains(":") {
                let token = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespaces) : partyCode
                let wsURL = "wss://\(server)"
                if let parsed = URLComponents(string: wsURL), let host = parsed.host {
                    return ServerInfo(url: wsURL, token: token, ip: host, port: parsed.port ?? 443, hostname: host)
                }
            }
        }

        return nil
    }

    enum ServerError: LocalizedError {
        case noServerFound
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noServerFound: return "No game server found"
            case .invalidResponse: return "Bad response"
            }
        }
    }
}
