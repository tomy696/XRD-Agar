import Foundation

class ServerResolver {

    static let browserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    static let wsServers = [
        "webbouncer-live-v8-0.agario.miniclippt.com",
    ]

    private static let apiEndpoints = [
        "https://web-arenas-live-v25-0.agario.miniclippt.com/findServer",
        "https://web-arenas-live-v25-1.agario.miniclippt.com/findServer",
        "https://webbouncer-live-v8-0.agario.miniclippt.com/findServer",
    ]

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
        discoverViaAPI(index: 0, partyCode: partyCode) { result in
            switch result {
            case .success(let info):
                AgarBot.log("[SR] API found: \(info.hostname)")
                completion(.success(info))
            case .failure:
                let capturedIP = NetworkInterceptor.shared.capturedServerIP ?? ""
                if !capturedIP.isEmpty {
                    AgarBot.log("[SR] Trying captured IP \(capturedIP):443")
                    completion(.success(ServerInfo(
                        url: "wss://\(capturedIP):443",
                        token: partyCode, ip: capturedIP, port: 443, hostname: capturedIP
                    )))
                    return
                }

                let host = wsServers[0]
                AgarBot.log("[SR] Fallback to \(host)")
                completion(.success(ServerInfo(
                    url: "wss://\(host)", token: partyCode, ip: host, port: 443, hostname: host
                )))
            }
        }
    }

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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://agar.io", forHTTPHeaderField: "Origin")
        request.setValue("https://agar.io/", forHTTPHeaderField: "Referer")
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")

        var body: [String: Any] = ["mode": partyCode.isEmpty ? ":ffa" : ":party"]
        if !partyCode.isEmpty { body["token"] = partyCode }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
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
                    AgarBot.log("[SR] API[\(index)] no data (HTTP \(httpStatus))")
                    discoverViaAPI(index: index + 1, partyCode: partyCode, completion: completion)
                    return
                }

                let responseText = String(data: data, encoding: .utf8) ?? "(binary)"
                AgarBot.log("[SR] API[\(index)] HTTP \(httpStatus) len=\(data.count): \(responseText.prefix(120))")

                if let info = parseJSONResponse(data: data, partyCode: partyCode) {
                    completion(.success(info))
                    return
                }

                if let info = parseTextResponse(text: responseText, partyCode: partyCode) {
                    completion(.success(info))
                    return
                }

                discoverViaAPI(index: index + 1, partyCode: partyCode, completion: completion)
            }
        }.resume()
    }

    private static func parseJSONResponse(data: Data, partyCode: String) -> ServerInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var serverURL: String?
        if let endpoints = json["endpoints"] as? [[String: Any]], let first = endpoints.first {
            serverURL = (first["url"] as? String) ?? (first["server"] as? String)
        }
        if serverURL == nil { serverURL = json["url"] as? String }
        if serverURL == nil { serverURL = json["server"] as? String }
        if serverURL == nil { serverURL = json["ip"] as? String }

        guard let server = serverURL, !server.isEmpty else { return nil }
        let wsURL = (server.hasPrefix("ws://") || server.hasPrefix("wss://")) ? server : "wss://\(server)"
        guard let parsed = URLComponents(string: wsURL), let host = parsed.host else { return nil }

        let token = (json["token"] as? String) ?? partyCode
        let port = parsed.port ?? 443
        return ServerInfo(url: wsURL, token: token, ip: host, port: port, hostname: host)
    }

    private static func parseTextResponse(text: String, partyCode: String) -> ServerInfo? {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n")
        guard let first = lines.first else { return nil }
        let server = String(first).trimmingCharacters(in: .whitespaces)
        guard !server.isEmpty, !server.contains(" "), !server.contains("<"),
              server.contains(".") || server.contains(":") else { return nil }

        let token = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespaces) : partyCode
        let wsURL = (server.hasPrefix("ws://") || server.hasPrefix("wss://")) ? server : "wss://\(server)"
        guard let parsed = URLComponents(string: wsURL), let host = parsed.host else { return nil }
        let port = parsed.port ?? 443
        return ServerInfo(url: wsURL, token: token, ip: host, port: port, hostname: host)
    }

    enum ServerError: LocalizedError {
        case noServerFound
        case invalidResponse
        case noServer

        var errorDescription: String? {
            switch self {
            case .noServerFound: return "No game server found"
            case .invalidResponse: return "Bad response"
            case .noServer: return "No server available"
            }
        }
    }
}
