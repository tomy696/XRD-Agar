import Foundation

class ServerResolver {

    static let browserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    static let webBouncer = "webbouncer-live-v8-0.agario.miniclippt.com"
    static let clientVersionString = "3.11.29"
    static let clientVersionInt = "31129"
    static let protoVersion = "15.0.3"

    struct ServerInfo {
        let url: String
        let token: String
        let hostname: String
    }

    static func resolveServer(
        region: String = "EU-London",
        gameMode: String = ":ffa",
        completion: @escaping (Result<ServerInfo, Error>) -> Void
    ) {
        let apiURL = "https://\(webBouncer)/v4/findServer"
        guard let url = URL(string: apiURL) else {
            completion(.failure(ServerError.noServerFound))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("q=0.01", forHTTPHeaderField: "Accept")
        request.setValue(protoVersion, forHTTPHeaderField: "x-support-proto-version")
        request.setValue(clientVersionInt, forHTTPHeaderField: "x-client-version")
        request.setValue("https://agar.io", forHTTPHeaderField: "Origin")
        request.setValue("https://agar.io/", forHTTPHeaderField: "Referer")
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.httpBody = encodeBouncerRequest(region: region, gamemode: gameMode)
        request.timeoutInterval = 8

        AgarBot.log("[SR] POST \(apiURL) region=\(region) mode=\(gameMode)")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

                if let error = error {
                    AgarBot.log("[SR] err: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                guard let data = data, !data.isEmpty else {
                    AgarBot.log("[SR] empty response HTTP \(httpStatus)")
                    completion(.failure(ServerError.noServerFound))
                    return
                }

                let responseText = String(data: data, encoding: .utf8) ?? "(binary)"
                AgarBot.log("[SR] HTTP \(httpStatus): \(responseText.prefix(300))")

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let endpoints = json["endpoints"] as? [String: Any],
                      let serverPath = (endpoints["https"] as? String) ?? (endpoints["http"] as? String),
                      !serverPath.isEmpty
                else {
                    AgarBot.log("[SR] bad response format")
                    completion(.failure(ServerError.invalidResponse))
                    return
                }

                let wsURL = "wss://\(serverPath)"
                let hostname: String
                if let slashIdx = serverPath.firstIndex(of: "/") {
                    hostname = String(serverPath[serverPath.startIndex..<slashIdx])
                } else {
                    hostname = serverPath
                }

                let token = (json["token"] as? String) ?? ""

                AgarBot.log("[SR] server=\(wsURL) host=\(hostname) token=\(token.prefix(8))")
                completion(.success(ServerInfo(url: wsURL, token: token, hostname: hostname)))
            }
        }.resume()
    }

    // MARK: - Protobuf Encoding

    private static func encodeBouncerRequest(region: String, gamemode: String) -> Data {
        var inner = Data()
        let regionBytes = Array(region.utf8)
        inner.append(0x0A)
        inner.append(UInt8(regionBytes.count))
        inner.append(contentsOf: regionBytes)
        let modeBytes = Array(gamemode.utf8)
        inner.append(0x12)
        inner.append(UInt8(modeBytes.count))
        inner.append(contentsOf: modeBytes)

        var outer = Data()
        outer.append(0x0A)
        outer.append(UInt8(inner.count))
        outer.append(inner)
        return outer
    }

    enum ServerError: LocalizedError {
        case noServerFound
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noServerFound: return "No game server found"
            case .invalidResponse: return "Bad response from bouncer"
            }
        }
    }
}
