import Foundation

class ServerResolver {

    struct ServerInfo {
        let url: String
        let token: String
    }

    static func resolveServer(
        region: ServerRegion,
        gameMode: GameMode,
        partyCode: String = "",
        completion: @escaping (Result<ServerInfo, Error>) -> Void
    ) {
        guard let endpointStr = NetworkInterceptor.shared.discoveredAPIEndpoint,
              let endpoint = URL(string: endpointStr) else {
            completion(.failure(ServerError.noAPIDiscovered))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://agar.io", forHTTPHeaderField: "Origin")

        if let headers = NetworkInterceptor.shared.discoveredHeaders {
            for (key, value) in headers {
                if key.lowercased() != "content-length" {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
        }

        var body: [String: Any] = [
            "region": region.apiValue,
            "mode": (gameMode == .party && !partyCode.isEmpty) ? ":party" : gameMode.serverMode
        ]
        if gameMode == .party && !partyCode.isEmpty {
            body["token"] = partyCode
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(ServerError.invalidResponse))
                return
            }

            var serverURL: String?
            if let endpoints = json["endpoints"] as? [[String: Any]],
               let first = endpoints.first,
               let url = first["url"] as? String {
                serverURL = url
            } else if let url = json["url"] as? String {
                serverURL = url
            } else if let url = json["server"] as? String {
                serverURL = url
            }

            guard let server = serverURL else {
                completion(.failure(ServerError.noServerFound))
                return
            }

            let token = (json["token"] as? String) ?? ""
            let wsURL = server.hasPrefix("wss://") ? server : "wss://\(server)"
            completion(.success(ServerInfo(url: wsURL, token: token)))
        }.resume()
    }

    enum ServerError: LocalizedError {
        case noServerFound
        case invalidResponse
        case noAPIDiscovered

        var errorDescription: String? {
            switch self {
            case .noServerFound: return "No server found"
            case .invalidResponse: return "Invalid response"
            case .noAPIDiscovered: return "Play one game first so XRD can discover the API"
            }
        }
    }
}
