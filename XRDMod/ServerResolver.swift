import Foundation

class ServerResolver {

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
        let interceptor = NetworkInterceptor.shared

        if let wsURL = interceptor.bestServerURL,
           let parsed = URLComponents(string: wsURL),
           let host = parsed.host {
            let token = interceptor.capturedToken ?? partyCode
            let port = parsed.port ?? 443
            let ip = interceptor.capturedServerIP ?? host

            completion(.success(ServerInfo(url: wsURL, token: token, ip: ip, port: port, hostname: host)))
            return
        }

        if let bsdServer = UserDefaults.standard.string(forKey: "XRD_bsdServer"),
           !bsdServer.isEmpty,
           let parsed = URLComponents(string: bsdServer), let host = parsed.host {
            let p = parsed.port ?? 443
            completion(.success(ServerInfo(url: bsdServer, token: partyCode, ip: host, port: p, hostname: host)))
            return
        }

        guard let endpointStr = interceptor.discoveredAPIEndpoint,
              let endpoint = URL(string: endpointStr) else {
            completion(.failure(ServerError.noServer))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://agar.io", forHTTPHeaderField: "Origin")

        if let headers = interceptor.discoveredHeaders {
            for (key, value) in headers {
                if key.lowercased() != "content-length" {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
        }

        var body: [String: Any] = ["mode": partyCode.isEmpty ? ":ffa" : ":party"]
        if !partyCode.isEmpty {
            body["token"] = partyCode
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession.shared
        NetworkInterceptor.shared.botSessions.add(session)

        session.dataTask(with: request) { data, _, error in
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
            if let parsed = URLComponents(string: wsURL), let host = parsed.host {
                let p = parsed.port ?? 443
                completion(.success(ServerInfo(url: wsURL, token: token, ip: host, port: p, hostname: host)))
            } else {
                completion(.failure(ServerError.invalidResponse))
            }
        }.resume()
    }

    enum ServerError: LocalizedError {
        case noServerFound
        case invalidResponse
        case noServer

        var errorDescription: String? {
            switch self {
            case .noServerFound: return "No server in response"
            case .invalidResponse: return "Bad response"
            case .noServer: return "Play a game first so XRD can find your server"
            }
        }
    }
}
